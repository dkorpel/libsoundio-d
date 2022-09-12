/// Translated from C to D
module soundio.alsa;

version(SOUNDIO_HAVE_ALSA):
@nogc nothrow:
extern(C): __gshared:


import soundio.api;
import soundio.soundio_private;
import soundio.os;
import soundio.list;
import soundio.atomics;
import soundio.headers.alsaheader;

import core.sys.linux.sys.inotify;
import core.sys.posix.fcntl;
import core.sys.posix.unistd;
import core.sys.posix.poll; //pollfd, POLLERR etc.
import core.stdc.errno;
import core.stdc.string: strcmp, strncmp, strlen, strstr, strdup;
import core.stdc.stdlib: free;

private:

static if (__VERSION__ < 2094) {
    // @nogc inotify headers
    int inotify_init();
    int inotify_init1(int flags);
    int inotify_add_watch(int fd, const(char)* name, uint mask);
    int inotify_rm_watch(int fd, uint wd);
}
// in unistd.h, missing from core.sys.posix.unistd
int pipe2(int* __pipedes, int __flags);

package struct SoundIoDeviceAlsa { int make_the_struct_not_empty; }

enum SOUNDIO_MAX_ALSA_SND_FILE_LEN = 16;
struct SoundIoAlsaPendingFile {
    char[SOUNDIO_MAX_ALSA_SND_FILE_LEN] name;
}

alias SoundIoListAlsaPendingFile = SOUNDIO_LIST!SoundIoAlsaPendingFile;

package struct SoundIoAlsa {
    SoundIoOsMutex* mutex;
    SoundIoOsCond* cond;

    SoundIoOsThread* thread;
    SoundIoAtomicFlag abort_flag;
    int notify_fd;
    int notify_wd;
    bool have_devices_flag;
    int[2] notify_pipe_fd;
    SoundIoListAlsaPendingFile pending_files;

    // this one is ready to be read with flush_events. protected by mutex
    SoundIoDevicesInfo* ready_devices_info;

    int shutdown_err;
    bool emitted_shutdown_cb;
}

package struct SoundIoOutStreamAlsa {
    snd_pcm_t* handle;
    snd_pcm_chmap_t* chmap;
    int chmap_size;
    snd_pcm_uframes_t offset;
    snd_pcm_access_t access;
    snd_pcm_uframes_t buffer_size_frames;
    int sample_buffer_size;
    char* sample_buffer;
    int poll_fd_count;
    int poll_fd_count_with_extra;
    pollfd* poll_fds;
    int[2] poll_exit_pipe_fd;
    SoundIoOsThread* thread;
    SoundIoAtomicFlag thread_exit_flag;
    snd_pcm_uframes_t period_size;
    int write_frame_count;
    bool is_paused;
    SoundIoAtomicFlag clear_buffer_flag;
    SoundIoChannelArea[SOUNDIO_MAX_CHANNELS] areas;
}

package struct SoundIoInStreamAlsa {
    snd_pcm_t* handle;
    snd_pcm_chmap_t* chmap;
    int chmap_size;
    snd_pcm_uframes_t offset;
    snd_pcm_access_t access;
    int sample_buffer_size;
    char* sample_buffer;
    int poll_fd_count;
    pollfd* poll_fds;
    SoundIoOsThread* thread;
    SoundIoAtomicFlag thread_exit_flag;
    int period_size;
    int read_frame_count;
    bool is_paused;
    SoundIoChannelArea[SOUNDIO_MAX_CHANNELS] areas;
}

immutable snd_pcm_stream_t[2] stream_types = [SND_PCM_STREAM_PLAYBACK, SND_PCM_STREAM_CAPTURE];

static snd_pcm_access_t[5] prioritized_access_types = [
    SND_PCM_ACCESS_MMAP_INTERLEAVED,
    SND_PCM_ACCESS_MMAP_NONINTERLEAVED,
    SND_PCM_ACCESS_MMAP_COMPLEX,
    SND_PCM_ACCESS_RW_INTERLEAVED,
    SND_PCM_ACCESS_RW_NONINTERLEAVED,
];

static void wakeup_device_poll(SoundIoAlsa* sia) {
    ssize_t amt = write(sia.notify_pipe_fd[1], "a".ptr, 1);
    if (amt == -1) {
        assert(errno != EBADF);
        assert(errno != EIO);
        assert(errno != ENOSPC);
        assert(errno != EPERM);
        assert(errno != EPIPE);
    }
}

static void wakeup_outstream_poll(SoundIoOutStreamAlsa* osa) {
    ssize_t amt = write(osa.poll_exit_pipe_fd[1], "a".ptr, 1);
    if (amt == -1) {
        assert(errno != EBADF);
        assert(errno != EIO);
        assert(errno != ENOSPC);
        assert(errno != EPERM);
        assert(errno != EPIPE);
    }
}

static void destroy_alsa(SoundIoPrivate* si) {
    SoundIoAlsa* sia = &si.backend_data.alsa;

    if (sia.thread) {
        SOUNDIO_ATOMIC_FLAG_CLEAR(sia.abort_flag);
        wakeup_device_poll(sia);
        soundio_os_thread_destroy(sia.thread);
    }

    sia.pending_files.deinit();

    if (sia.cond)
        soundio_os_cond_destroy(sia.cond);

    if (sia.mutex)
        soundio_os_mutex_destroy(sia.mutex);

    soundio_destroy_devices_info(sia.ready_devices_info);



    close(sia.notify_pipe_fd[0]);
    close(sia.notify_pipe_fd[1]);
    close(sia.notify_fd);
}

pragma(inline, true) static snd_pcm_uframes_t ceil_dbl_to_uframes(double x) {
    const(double) truncation = cast(snd_pcm_uframes_t)x;
    return cast(snd_pcm_uframes_t) (truncation + (truncation < x));
}

static char* str_partition_on_char(char* str, char c) {
    if (!str)
        return null;
    while (*str) {
        if (*str == c) {
            *str = 0;
            return str + 1;
        }
        str += 1;
    }
    return null;
}

static snd_pcm_stream_t aim_to_stream(SoundIoDeviceAim aim) {
    final switch (aim) {
        case SoundIoDeviceAim.Output: return SND_PCM_STREAM_PLAYBACK;
        case SoundIoDeviceAim.Input: return SND_PCM_STREAM_CAPTURE;
    }
    //assert(0); // Invalid aim
    //return SND_PCM_STREAM_PLAYBACK;
}

static SoundIoChannelId from_alsa_chmap_pos(uint pos) {
    switch (/*cast(snd_pcm_chmap_position)*/ pos) {
        case SND_CHMAP_UNKNOWN: return SoundIoChannelId.Invalid;
        case SND_CHMAP_NA:      return SoundIoChannelId.Invalid;
        case SND_CHMAP_MONO:    return SoundIoChannelId.FrontCenter;
        case SND_CHMAP_FL:      return SoundIoChannelId.FrontLeft; // front left
        case SND_CHMAP_FR:      return SoundIoChannelId.FrontRight; // front right
        case SND_CHMAP_RL:      return SoundIoChannelId.BackLeft; // rear left
        case SND_CHMAP_RR:      return SoundIoChannelId.BackRight; // rear right
        case SND_CHMAP_FC:      return SoundIoChannelId.FrontCenter; // front center
        case SND_CHMAP_LFE:     return SoundIoChannelId.Lfe; // LFE
        case SND_CHMAP_SL:      return SoundIoChannelId.SideLeft; // side left
        case SND_CHMAP_SR:      return SoundIoChannelId.SideRight; // side right
        case SND_CHMAP_RC:      return SoundIoChannelId.BackCenter; // rear center
        case SND_CHMAP_FLC:     return SoundIoChannelId.FrontLeftCenter; // front left center
        case SND_CHMAP_FRC:     return SoundIoChannelId.FrontRightCenter; // front right center
        case SND_CHMAP_RLC:     return SoundIoChannelId.BackLeftCenter; // rear left center
        case SND_CHMAP_RRC:     return SoundIoChannelId.BackRightCenter; // rear right center
        case SND_CHMAP_FLW:     return SoundIoChannelId.FrontLeftWide; // front left wide
        case SND_CHMAP_FRW:     return SoundIoChannelId.FrontRightWide; // front right wide
        case SND_CHMAP_FLH:     return SoundIoChannelId.FrontLeftHigh; // front left high
        case SND_CHMAP_FCH:     return SoundIoChannelId.FrontCenterHigh; // front center high
        case SND_CHMAP_FRH:     return SoundIoChannelId.FrontRightHigh; // front right high
        case SND_CHMAP_TC:      return SoundIoChannelId.TopCenter; // top center
        case SND_CHMAP_TFL:     return SoundIoChannelId.TopFrontLeft; // top front left
        case SND_CHMAP_TFR:     return SoundIoChannelId.TopFrontRight; // top front right
        case SND_CHMAP_TFC:     return SoundIoChannelId.TopFrontCenter; // top front center
        case SND_CHMAP_TRL:     return SoundIoChannelId.TopBackLeft; // top rear left
        case SND_CHMAP_TRR:     return SoundIoChannelId.TopBackRight; // top rear right
        case SND_CHMAP_TRC:     return SoundIoChannelId.TopBackCenter; // top rear center
        case SND_CHMAP_TFLC:    return SoundIoChannelId.TopFrontLeftCenter; // top front left center
        case SND_CHMAP_TFRC:    return SoundIoChannelId.TopFrontRightCenter; // top front right center
        case SND_CHMAP_TSL:     return SoundIoChannelId.TopSideLeft; // top side left
        case SND_CHMAP_TSR:     return SoundIoChannelId.TopSideRight; // top side right
        case SND_CHMAP_LLFE:    return SoundIoChannelId.LeftLfe; // left LFE
        case SND_CHMAP_RLFE:    return SoundIoChannelId.RightLfe; // right LFE
        case SND_CHMAP_BC:      return SoundIoChannelId.BottomCenter; // bottom center
        case SND_CHMAP_BLC:     return SoundIoChannelId.BottomLeftCenter; // bottom left center
        case SND_CHMAP_BRC:     return SoundIoChannelId.BottomRightCenter; // bottom right center
        default: break;
    }
    return SoundIoChannelId.Invalid;
}

static int to_alsa_chmap_pos(SoundIoChannelId channel_id) {
    switch (channel_id) {
        case SoundIoChannelId.FrontLeft:             return SND_CHMAP_FL;
        case SoundIoChannelId.FrontRight:            return SND_CHMAP_FR;
        case SoundIoChannelId.BackLeft:              return SND_CHMAP_RL;
        case SoundIoChannelId.BackRight:             return SND_CHMAP_RR;
        case SoundIoChannelId.FrontCenter:           return SND_CHMAP_FC;
        case SoundIoChannelId.Lfe:                   return SND_CHMAP_LFE;
        case SoundIoChannelId.SideLeft:              return SND_CHMAP_SL;
        case SoundIoChannelId.SideRight:             return SND_CHMAP_SR;
        case SoundIoChannelId.BackCenter:            return SND_CHMAP_RC;
        case SoundIoChannelId.FrontLeftCenter:       return SND_CHMAP_FLC;
        case SoundIoChannelId.FrontRightCenter:      return SND_CHMAP_FRC;
        case SoundIoChannelId.BackLeftCenter:        return SND_CHMAP_RLC;
        case SoundIoChannelId.BackRightCenter:       return SND_CHMAP_RRC;
        case SoundIoChannelId.FrontLeftWide:         return SND_CHMAP_FLW;
        case SoundIoChannelId.FrontRightWide:        return SND_CHMAP_FRW;
        case SoundIoChannelId.FrontLeftHigh:         return SND_CHMAP_FLH;
        case SoundIoChannelId.FrontCenterHigh:       return SND_CHMAP_FCH;
        case SoundIoChannelId.FrontRightHigh:        return SND_CHMAP_FRH;
        case SoundIoChannelId.TopCenter:             return SND_CHMAP_TC;
        case SoundIoChannelId.TopFrontLeft:          return SND_CHMAP_TFL;
        case SoundIoChannelId.TopFrontRight:         return SND_CHMAP_TFR;
        case SoundIoChannelId.TopFrontCenter:        return SND_CHMAP_TFC;
        case SoundIoChannelId.TopBackLeft:           return SND_CHMAP_TRL;
        case SoundIoChannelId.TopBackRight:          return SND_CHMAP_TRR;
        case SoundIoChannelId.TopBackCenter:         return SND_CHMAP_TRC;
        case SoundIoChannelId.TopFrontLeftCenter:    return SND_CHMAP_TFLC;
        case SoundIoChannelId.TopFrontRightCenter:   return SND_CHMAP_TFRC;
        case SoundIoChannelId.TopSideLeft:           return SND_CHMAP_TSL;
        case SoundIoChannelId.TopSideRight:          return SND_CHMAP_TSR;
        case SoundIoChannelId.LeftLfe:               return SND_CHMAP_LLFE;
        case SoundIoChannelId.RightLfe:              return SND_CHMAP_RLFE;
        case SoundIoChannelId.BottomCenter:          return SND_CHMAP_BC;
        case SoundIoChannelId.BottomLeftCenter:      return SND_CHMAP_BLC;
        case SoundIoChannelId.BottomRightCenter:     return SND_CHMAP_BRC;

        default:
            return SND_CHMAP_UNKNOWN;
    }
}

static void get_channel_layout(SoundIoChannelLayout* dest, snd_pcm_chmap_t* chmap) {
    int channel_count = soundio_int_min(SOUNDIO_MAX_CHANNELS, chmap.channels);
    dest.channel_count = channel_count;
    for (int i = 0; i < channel_count; i += 1) {
        // chmap.pos is a variable length array, typed as a `uint[0]`.
        // The `.ptr` is needed to avoid a range violation with array bounds checks
        dest.channels[i] = from_alsa_chmap_pos(chmap.pos.ptr[i]);
    }
    soundio_channel_layout_detect_builtin(dest);
}

static int handle_channel_maps(SoundIoDevice* device, snd_pcm_chmap_query_t** maps) {
    if (!maps)
        return 0;

    snd_pcm_chmap_query_t** p;
    snd_pcm_chmap_query_t* v;

    // one iteration to count
    int layout_count = 0;
    for (p = maps; cast(bool) (v = *p) && layout_count < SOUNDIO_MAX_CHANNELS; p += 1, layout_count += 1) { }
    device.layouts = ALLOCATE!SoundIoChannelLayout(layout_count);
    if (!device.layouts) {
        snd_pcm_free_chmaps(maps);
        return SoundIoError.NoMem;
    }
    device.layout_count = layout_count;

    // iterate again to collect data
    int layout_index;
    for (p = maps, layout_index = 0;
        cast(bool) (v = *p) && layout_index < layout_count;
        p += 1, layout_index += 1)
    {
        get_channel_layout(&device.layouts[layout_index], &v.map);
    }
    snd_pcm_free_chmaps(maps);

    return 0;
}

static snd_pcm_format_t to_alsa_fmt(SoundIoFormat fmt) {
    switch (fmt) {
    case SoundIoFormat.S8:           return SND_PCM_FORMAT_S8;
    case SoundIoFormat.U8:           return SND_PCM_FORMAT_U8;
    case SoundIoFormat.S16LE:        return SND_PCM_FORMAT_S16_LE;
    case SoundIoFormat.S16BE:        return SND_PCM_FORMAT_S16_BE;
    case SoundIoFormat.U16LE:        return SND_PCM_FORMAT_U16_LE;
    case SoundIoFormat.U16BE:        return SND_PCM_FORMAT_U16_BE;
    case SoundIoFormat.S24LE:        return SND_PCM_FORMAT_S24_LE;
    case SoundIoFormat.S24BE:        return SND_PCM_FORMAT_S24_BE;
    case SoundIoFormat.U24LE:        return SND_PCM_FORMAT_U24_LE;
    case SoundIoFormat.U24BE:        return SND_PCM_FORMAT_U24_BE;
    case SoundIoFormat.S32LE:        return SND_PCM_FORMAT_S32_LE;
    case SoundIoFormat.S32BE:        return SND_PCM_FORMAT_S32_BE;
    case SoundIoFormat.U32LE:        return SND_PCM_FORMAT_U32_LE;
    case SoundIoFormat.U32BE:        return SND_PCM_FORMAT_U32_BE;
    case SoundIoFormat.Float32LE:    return SND_PCM_FORMAT_FLOAT_LE;
    case SoundIoFormat.Float32BE:    return SND_PCM_FORMAT_FLOAT_BE;
    case SoundIoFormat.Float64LE:    return SND_PCM_FORMAT_FLOAT64_LE;
    case SoundIoFormat.Float64BE:    return SND_PCM_FORMAT_FLOAT64_BE;
    case SoundIoFormat.Invalid:
    default: break;
    }
    return SND_PCM_FORMAT_UNKNOWN;
}

static void test_fmt_mask(SoundIoDevice* device, const(snd_pcm_format_mask_t)* fmt_mask, SoundIoFormat fmt) {
    if (snd_pcm_format_mask_test(fmt_mask, to_alsa_fmt(fmt))) {
        device.formats[device.format_count] = fmt;
        device.format_count += 1;
    }
}

static int set_access(snd_pcm_t* handle, snd_pcm_hw_params_t* hwparams, snd_pcm_access_t* out_access) {
    for (int i = 0; i < prioritized_access_types.length; i += 1) {
        snd_pcm_access_t access = prioritized_access_types[i];
        int err = snd_pcm_hw_params_set_access(handle, hwparams, access);
        if (err >= 0) {
            if (out_access)
                *out_access = access;
            return 0;
        }
    }
    return SoundIoError.OpeningDevice;
}

// this function does not override device->formats, so if you want it to, deallocate and set it to NULL
static int probe_open_device(SoundIoDevice* device, snd_pcm_t* handle, int resample, int* out_channels_min, int* out_channels_max) {
    SoundIoDevicePrivate* dev = cast(SoundIoDevicePrivate*)device;
    int err;

    snd_pcm_hw_params_t* hwparams;
    snd_pcm_hw_params_malloc(&hwparams);
    if (!hwparams)
        return SoundIoError.NoMem;
    scope(exit) snd_pcm_hw_params_free(hwparams);

    err = snd_pcm_hw_params_any(handle, hwparams);
    if (err < 0)
        return SoundIoError.OpeningDevice;

    err = snd_pcm_hw_params_set_rate_resample(handle, hwparams, resample);
    if (err < 0)
        return SoundIoError.OpeningDevice;

    if (auto err1 = set_access(handle, hwparams, null))
        return err1;

    uint channels_min;
    uint channels_max;

    err = snd_pcm_hw_params_get_channels_min(hwparams, &channels_min);
    if (err < 0)
        return SoundIoError.OpeningDevice;
    err = snd_pcm_hw_params_set_channels_last(handle, hwparams, &channels_max);
    if (err < 0)
        return SoundIoError.OpeningDevice;

    *out_channels_min = channels_min;
    *out_channels_max = channels_max;

    uint rate_min;
    uint rate_max;

    err = snd_pcm_hw_params_get_rate_min(hwparams, &rate_min, null);
    if (err < 0)
        return SoundIoError.OpeningDevice;

    err = snd_pcm_hw_params_set_rate_last(handle, hwparams, &rate_max, null);
    if (err < 0)
        return SoundIoError.OpeningDevice;

    device.sample_rate_count = 1;
    device.sample_rates = &dev.prealloc_sample_rate_range;
    device.sample_rates[0].min = rate_min;
    device.sample_rates[0].max = rate_max;

    double one_over_actual_rate = 1.0 / cast(double)rate_max;

    // Purposefully leave the parameters with the highest rate, highest channel count.

    snd_pcm_uframes_t min_frames;
    snd_pcm_uframes_t max_frames;


    err = snd_pcm_hw_params_get_buffer_size_min(hwparams, &min_frames);
    if (err < 0)
        return SoundIoError.OpeningDevice;
    err = snd_pcm_hw_params_get_buffer_size_max(hwparams, &max_frames);
    if (err < 0)
        return SoundIoError.OpeningDevice;

    device.software_latency_min = min_frames * one_over_actual_rate;
    device.software_latency_max = max_frames * one_over_actual_rate;

    err = snd_pcm_hw_params_set_buffer_size_first(handle, hwparams, &min_frames);
    if (err < 0)
        return SoundIoError.OpeningDevice;


    snd_pcm_format_mask_t* fmt_mask;
    snd_pcm_format_mask_malloc(&fmt_mask);
    if (!fmt_mask)
        return SoundIoError.NoMem;
    scope(exit) snd_pcm_format_mask_free(fmt_mask);
    snd_pcm_format_mask_none(fmt_mask);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_S8);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_U8);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_S16_LE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_S16_BE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_U16_LE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_U16_BE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_S24_LE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_S24_BE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_U24_LE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_U24_BE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_S32_LE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_S32_BE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_U32_LE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_U32_BE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_FLOAT_LE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_FLOAT_BE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_FLOAT64_LE);
    snd_pcm_format_mask_set(fmt_mask, SND_PCM_FORMAT_FLOAT64_BE);

    err = snd_pcm_hw_params_set_format_mask(handle, hwparams, fmt_mask);
    if (err < 0)
        return SoundIoError.OpeningDevice;

    if (!device.formats) {
        snd_pcm_hw_params_get_format_mask(hwparams, fmt_mask);
        device.formats = ALLOCATE!SoundIoFormat(18);
        if (!device.formats)
            return SoundIoError.NoMem;

        device.format_count = 0;
        test_fmt_mask(device, fmt_mask, SoundIoFormat.S8);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.U8);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.S16LE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.S16BE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.U16LE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.U16BE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.S24LE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.S24BE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.U24LE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.U24BE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.S32LE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.S32BE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.U32LE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.U32BE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.Float32LE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.Float32BE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.Float64LE);
        test_fmt_mask(device, fmt_mask, SoundIoFormat.Float64BE);
    }

    return 0;
}

extern(D) int probe_device(SoundIoDevice* device, snd_pcm_chmap_query_t** maps) {
    int err;
    snd_pcm_t* handle;

    snd_pcm_stream_t stream = aim_to_stream(device.aim);

    err = snd_pcm_open(&handle, device.id, stream, 0);
    if (err < 0) {
        handle_channel_maps(device, maps);
        return SoundIoError.OpeningDevice;
    }

    int channels_min;
    int channels_max;
    err = probe_open_device(device, handle, 0, &channels_min, &channels_max);
    if (err) {
        handle_channel_maps(device, maps);
        snd_pcm_close(handle);
        return err;
    }

    if (!maps) {
        maps = snd_pcm_query_chmaps(handle);
        if (!maps) {
            // device gave us no channel maps. we're forced to conclude that
            // the min and max channel counts are correct.
            int layout_count = 0;
            for (int i = 0; i < soundio_channel_layout_builtin_count(); i += 1) {
                const(SoundIoChannelLayout)* layout = soundio_channel_layout_get_builtin(i);
                if (layout.channel_count >= channels_min && layout.channel_count <= channels_max) {
                    layout_count += 1;
                }
            }
            device.layout_count = layout_count;
            device.layouts = ALLOCATE!SoundIoChannelLayout( device.layout_count);
            if (!device.layouts) {
                snd_pcm_close(handle);
                return SoundIoError.NoMem;
            }
            int layout_index = 0;
            for (int i = 0; i < soundio_channel_layout_builtin_count(); i += 1) {
                const(SoundIoChannelLayout)* layout = soundio_channel_layout_get_builtin(i);
                if (layout.channel_count >= channels_min && layout.channel_count <= channels_max) {
                    device.layouts[layout_index++] = *soundio_channel_layout_get_builtin(i);
                }
            }
        }
    }

    snd_pcm_chmap_t* chmap = snd_pcm_get_chmap(handle);
    if (chmap) {
        get_channel_layout(&device.current_layout, chmap);
        free(chmap);
    }
    err = handle_channel_maps(device, maps);
    if (err) {
        snd_pcm_close(handle);
        return err;
    }
    maps = null;

    if (!device.is_raw) {
        if (device.sample_rates[0].min == device.sample_rates[0].max)
            device.sample_rate_current = device.sample_rates[0].min;

        if (device.software_latency_min == device.software_latency_max)
            device.software_latency_current = device.software_latency_min;

        // now say that resampling is OK and see what the real min and max is.
        err = probe_open_device(device, handle, 1, &channels_min, &channels_max);
        if (err < 0) {
            snd_pcm_close(handle);
            return SoundIoError.OpeningDevice;
        }
    }

    snd_pcm_close(handle);
    return 0;
}

pragma(inline, true) static bool str_has_prefix(const(char)* big_str, const(char)* prefix) {
    return strncmp(big_str, prefix, strlen(prefix)) == 0;
}

extern(D) int refresh_devices(SoundIoPrivate* si) {
    SoundIo* soundio = &si.pub;
    SoundIoAlsa* sia = &si.backend_data.alsa;

    int err;
    err = snd_config_update_free_global();
    if (err < 0)
        return SoundIoError.SystemResources;
    err = snd_config_update();
    if (err < 0)
        return SoundIoError.SystemResources;

    SoundIoDevicesInfo* devices_info = ALLOCATE!SoundIoDevicesInfo(1);
    if (!devices_info)
        return SoundIoError.NoMem;
    devices_info.default_output_index = -1;
    devices_info.default_input_index = -1;

    void** hints;
    if (snd_device_name_hint(-1, "pcm", &hints) < 0) {
        soundio_destroy_devices_info(devices_info);
        return SoundIoError.NoMem;
    }

    int default_output_index = -1;
    int sysdefault_output_index = -1;
    int default_input_index = -1;
    int sysdefault_input_index = -1;

    for (void** hint_ptr = hints; *hint_ptr; hint_ptr += 1) {
        char* name = snd_device_name_get_hint(*hint_ptr, "NAME");
        // null - libsoundio has its own dummy backend. API clients should use
        // that instead of alsa null device.
        if (strcmp(name, "null") == 0 ||
            // all these surround devices are clutter
            str_has_prefix(name, "front:") ||
            str_has_prefix(name, "surround21:") ||
            str_has_prefix(name, "surround40:") ||
            str_has_prefix(name, "surround41:") ||
            str_has_prefix(name, "surround50:") ||
            str_has_prefix(name, "surround51:") ||
            str_has_prefix(name, "surround71:"))
        {
            free(name);
            continue;
        }

        // One or both of descr and descr1 can be NULL.
        char* descr = snd_device_name_get_hint(*hint_ptr, "DESC");
        char* descr1 = str_partition_on_char(descr, '\n');

        char* io = snd_device_name_get_hint(*hint_ptr, "IOID");
        bool is_playback;
        bool is_capture;

        // Workaround for Raspberry Pi driver bug, reporting itself as output
        // when really it is input.
        if (descr && strcmp(descr, "bcm2835 ALSA, bcm2835 ALSA") == 0 &&
            descr1 && strcmp(descr1, "Direct sample snooping device") == 0)
        {
            is_playback = false;
            is_capture = true;
        } else if (descr && strcmp(descr, "bcm2835 ALSA, bcm2835 IEC958/HDMI") == 0 &&
                   descr1 && strcmp(descr1, "Direct sample snooping device") == 0)
        {
            is_playback = false;
            is_capture = true;
        } else if (io) {
            if (strcmp(io, "Input") == 0) {
                is_playback = false;
                is_capture = true;
            } else {
                assert(strcmp(io, "Output") == 0);
                is_playback = true;
                is_capture = false;
            }
            free(io);
        } else {
            is_playback = true;
            is_capture = true;
        }

        for (int stream_type_i = 0; stream_type_i < stream_types.length; stream_type_i += 1) {
            snd_pcm_stream_t stream = stream_types[stream_type_i];
            if (stream == SND_PCM_STREAM_PLAYBACK && !is_playback) continue;
            if (stream == SND_PCM_STREAM_CAPTURE && !is_capture) continue;
            if (stream == SND_PCM_STREAM_CAPTURE && descr1 &&
                (strstr(descr1, "Output") || strstr(descr1, "output")))
            {
                continue;
            }


            SoundIoDevicePrivate* dev = ALLOCATE!SoundIoDevicePrivate(1);
            if (!dev) {
                free(name);
                free(descr);
                soundio_destroy_devices_info(devices_info);
                snd_device_name_free_hint(hints);
                return SoundIoError.NoMem;
            }
            SoundIoDevice* device = &dev.pub;
            device.ref_count = 1;
            device.soundio = soundio;
            device.is_raw = false;
            device.id = strdup(name);
            if (descr1) {
                device.name = soundio_alloc_sprintf(null, "%s: %s", descr, descr1);
            } else if (descr) {
                device.name = strdup(descr);
            } else {
                device.name = strdup(name);
            }

            if (!device.id || !device.name) {
                soundio_device_unref(device);
                free(name);
                free(descr);
                soundio_destroy_devices_info(devices_info);
                snd_device_name_free_hint(hints);
                return SoundIoError.NoMem;
            }

            SoundIoListDevicePtr* device_list;
            bool is_default = str_has_prefix(name, "default:") || strcmp(name, "default") == 0;
            bool is_sysdefault = str_has_prefix(name, "sysdefault:") || strcmp(name, "sysdefault") == 0;

            if (stream == SND_PCM_STREAM_PLAYBACK) {
                device.aim = SoundIoDeviceAim.Output;
                device_list = &devices_info.output_devices;
                if (is_default)
                    default_output_index = device_list.length;
                if (is_sysdefault)
                    sysdefault_output_index = device_list.length;
                if (devices_info.default_output_index == -1)
                    devices_info.default_output_index = device_list.length;
            } else {
                assert(stream == SND_PCM_STREAM_CAPTURE);
                device.aim = SoundIoDeviceAim.Input;
                device_list = &devices_info.input_devices;
                if (is_default)
                    default_input_index = device_list.length;
                if (is_sysdefault)
                    sysdefault_input_index = device_list.length;
                if (devices_info.default_input_index == -1)
                    devices_info.default_input_index = device_list.length;
            }

            device.probe_error = probe_device(device, null);

            if (device_list.append(device)) {
                soundio_device_unref(device);
                free(name);
                free(descr);
                soundio_destroy_devices_info(devices_info);
                snd_device_name_free_hint(hints);
                return SoundIoError.NoMem;
            }
        }

        free(name);
        free(descr);
    }

    if (default_input_index >= 0) {
        devices_info.default_input_index = default_input_index;
    } else if (sysdefault_input_index >= 0) {
        devices_info.default_input_index = sysdefault_input_index;
    }

    if (default_output_index >= 0) {
        devices_info.default_output_index = default_output_index;
    } else if (sysdefault_output_index >= 0) {
        devices_info.default_output_index = sysdefault_output_index;
    }

    snd_device_name_free_hint(hints);

    int card_index = -1;

    if (snd_card_next(&card_index) < 0)
        return SoundIoError.SystemResources;

    snd_ctl_card_info_t* card_info;
    snd_ctl_card_info_malloc(&card_info);
    if (!card_info)
        return SoundIoError.NoMem;
    scope(exit) snd_ctl_card_info_free(card_info);

    snd_pcm_info_t* pcm_info;
    snd_pcm_info_malloc(&pcm_info);
    if (!pcm_info)
        return SoundIoError.NoMem;
    scope(exit) snd_pcm_info_free(pcm_info);

    while (card_index >= 0) {
        snd_ctl_t* handle;
        char[32] name;
        import core.stdc.stdio: sprintf;
        sprintf(name.ptr, "hw:%d", card_index);
        err = snd_ctl_open(&handle, name.ptr, 0);
        if (err < 0) {
            if (err == -ENOENT) {
                break;
            } else {
                soundio_destroy_devices_info(devices_info);
                return SoundIoError.OpeningDevice;
            }
        }

        err = snd_ctl_card_info(handle, card_info);
        if (err < 0) {
            snd_ctl_close(handle);
            soundio_destroy_devices_info(devices_info);
            return SoundIoError.SystemResources;
        }
        const(char)* card_name = snd_ctl_card_info_get_name(card_info);

        int device_index = -1;
        for (;;) {
            if (snd_ctl_pcm_next_device(handle, &device_index) < 0) {
                snd_ctl_close(handle);
                soundio_destroy_devices_info(devices_info);
                return SoundIoError.SystemResources;
            }
            if (device_index < 0)
                break;

            snd_pcm_info_set_device(pcm_info, device_index);
            snd_pcm_info_set_subdevice(pcm_info, 0);

            for (int stream_type_i = 0; stream_type_i < stream_types.length; stream_type_i += 1) {
                snd_pcm_stream_t stream = stream_types[stream_type_i];
                snd_pcm_info_set_stream(pcm_info, stream);

                err = snd_ctl_pcm_info(handle, pcm_info);
                if (err < 0) {
                    if (err == -ENOENT) {
                        continue;
                    } else {
                        snd_ctl_close(handle);
                        soundio_destroy_devices_info(devices_info);
                        return SoundIoError.SystemResources;
                    }
                }

                const(char)* device_name = snd_pcm_info_get_name(pcm_info);

                SoundIoDevicePrivate* dev = ALLOCATE!SoundIoDevicePrivate(1);
                if (!dev) {
                    snd_ctl_close(handle);
                    soundio_destroy_devices_info(devices_info);
                    return SoundIoError.NoMem;
                }
                SoundIoDevice* device = &dev.pub;
                device.ref_count = 1;
                device.soundio = soundio;
                device.id = soundio_alloc_sprintf(null, "hw:%d,%d", card_index, device_index);
                device.name = soundio_alloc_sprintf(null, "%s %s", card_name, device_name);
                device.is_raw = true;

                if (!device.id || !device.name) {
                    soundio_device_unref(device);
                    snd_ctl_close(handle);
                    soundio_destroy_devices_info(devices_info);
                    return SoundIoError.NoMem;
                }

                SoundIoListDevicePtr* device_list;
                if (stream == SND_PCM_STREAM_PLAYBACK) {
                    device.aim = SoundIoDeviceAim.Output;
                    device_list = &devices_info.output_devices;
                } else {
                    assert(stream == SND_PCM_STREAM_CAPTURE);
                    device.aim = SoundIoDeviceAim.Input;
                    device_list = &devices_info.input_devices;
                }

                snd_pcm_chmap_query_t** maps = snd_pcm_query_chmaps_from_hw(card_index, device_index, -1, stream);
                device.probe_error = probe_device(device, maps);

                if (device_list.append(device)) {
                    soundio_device_unref(device);
                    soundio_destroy_devices_info(devices_info);
                    return SoundIoError.NoMem;
                }
            }
        }
        snd_ctl_close(handle);
        if (snd_card_next(&card_index) < 0) {
            soundio_destroy_devices_info(devices_info);
            return SoundIoError.SystemResources;
        }
    }

    soundio_os_mutex_lock(sia.mutex);
    soundio_destroy_devices_info(sia.ready_devices_info);
    sia.ready_devices_info = devices_info;
    sia.have_devices_flag = true;
    soundio_os_cond_signal(sia.cond, sia.mutex);
    soundio.on_events_signal(soundio);
    soundio_os_mutex_unlock(sia.mutex);
    return 0;
}

static void shutdown_backend(SoundIoPrivate* si, int err) {
    SoundIo* soundio = &si.pub;
    SoundIoAlsa* sia = &si.backend_data.alsa;
    soundio_os_mutex_lock(sia.mutex);
    sia.shutdown_err = err;
    soundio_os_cond_signal(sia.cond, sia.mutex);
    soundio.on_events_signal(soundio);
    soundio_os_mutex_unlock(sia.mutex);
}

static bool copy_str(char* dest, const(char)* src, int buf_len) {
    for (;;) {
        buf_len -= 1;
        if (buf_len <= 0)
            return false;
        *dest = *src;
        dest += 1;
        src += 1;
        if (!*src)
            break;
    }
    *dest = '\0';
    return true;
}

static void device_thread_run(void* arg) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)arg;
    SoundIoAlsa* sia = &si.backend_data.alsa;

    // Some systems cannot read integer variables if they are not
    // properly aligned. On other systems, incorrect alignment may
    // decrease performance. Hence, the buffer used for reading from
    // the inotify file descriptor should have the same alignment as
    // struct inotify_event.
    char[4096] buf; const(inotify_event)* event;

    pollfd[2] fds;
    fds[0].fd = sia.notify_fd;
    fds[0].events = POLLIN;

    fds[1].fd = sia.notify_pipe_fd[0];
    fds[1].events = POLLIN;

    int err;
    for (;;) {
        int poll_num = poll(fds.ptr, 2, -1);
        if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(sia.abort_flag))
            break;
        if (poll_num == -1) {
            if (errno == EINTR)
                continue;
            assert(errno != EFAULT);
            assert(errno != EINVAL);
            assert(errno == ENOMEM);
            // Kernel ran out of polling memory.
            shutdown_backend(si, SoundIoError.SystemResources);
            return;
        }
        if (poll_num <= 0)
            continue;
        bool got_rescan_event = false;
        if (fds[0].revents & POLLIN) {
            for (;;) {
                ssize_t len = read(sia.notify_fd, buf.ptr, buf.sizeof);
                if (len == -1) {
                    assert(errno != EBADF);
                    assert(errno != EFAULT);
                    assert(errno != EINVAL);
                    assert(errno != EIO);
                    assert(errno != EISDIR);
                    if (errno == EBADF || errno == EFAULT || errno == EINVAL ||
                        errno == EIO || errno == EISDIR)
                    {
                        shutdown_backend(si, SoundIoError.SystemResources);
                        return;
                    }
                }

                // catches EINTR and EAGAIN
                if (len <= 0)
                    break;

                // loop over all events in the buffer
                for (char* ptr = buf.ptr; ptr < buf.ptr + len; ptr += inotify_event.sizeof + event.len) {
                    event = cast(const(inotify_event)*) ptr;

                    if (!((event.mask & IN_CLOSE_WRITE) || (event.mask & IN_DELETE) || (event.mask & IN_CREATE)))
                        continue;
                    if (event.mask & IN_ISDIR)
                        continue;
                    if (!event.len || event.len < 8)
                        continue;
                    if (strncmp(event.name.ptr, "controlC", 8) != 0) {
                        continue;
                    }
                    if (event.mask & IN_CREATE) {
                        err = sia.pending_files.add_one();
                        if (err) {
                            shutdown_backend(si, SoundIoError.NoMem);
                            return;
                        }
                        SoundIoAlsaPendingFile* pending_file = sia.pending_files.last_ptr();
                        if (!copy_str(pending_file.name.ptr, event.name.ptr, SOUNDIO_MAX_ALSA_SND_FILE_LEN)) {
                            sia.pending_files.pop();
                        }
                        continue;
                    }
                    if (sia.pending_files.length > 0) {
                        // At this point ignore IN_DELETE in favor of waiting until the files
                        // opened with IN_CREATE have their IN_CLOSE_WRITE event.
                        if (!(event.mask & IN_CLOSE_WRITE))
                            continue;
                        for (int i = 0; i < sia.pending_files.length; i += 1) {
                            SoundIoAlsaPendingFile* pending_file = sia.pending_files.ptr_at(i);
                            if (strcmp(pending_file.name.ptr, event.name.ptr) == 0) {
                                sia.pending_files.swap_remove(i);
                                if (sia.pending_files.length == 0) {
                                    got_rescan_event = true;
                                }
                                break;
                            }
                        }
                    } else if (event.mask & IN_DELETE) {
                        // We are not waiting on created files to be closed, so when
                        // a delete happens we act on it.
                        got_rescan_event = true;
                    }
                }
            }
        }
        if (fds[1].revents & POLLIN) {
            got_rescan_event = true;
            for (;;) {
                ssize_t len = read(sia.notify_pipe_fd[0], buf.ptr, buf.sizeof);
                if (len == -1) {
                    assert(errno != EBADF);
                    assert(errno != EFAULT);
                    assert(errno != EINVAL);
                    assert(errno != EIO);
                    assert(errno != EISDIR);
                    if (errno == EBADF || errno == EFAULT || errno == EINVAL ||
                        errno == EIO || errno == EISDIR)
                    {
                        shutdown_backend(si, SoundIoError.SystemResources);
                        return;
                    }
                }
                if (len <= 0)
                    break;
            }
        }
        if (got_rescan_event) {
            err = refresh_devices(si);
            if (err) {
                shutdown_backend(si, err);
                return;
            }
        }
    }
}

extern(D) void my_flush_events(SoundIoPrivate* si, bool wait) {
    SoundIo* soundio = &si.pub;
    SoundIoAlsa* sia = &si.backend_data.alsa;

    bool change = false;
    bool cb_shutdown = false;
    SoundIoDevicesInfo* old_devices_info = null;

    soundio_os_mutex_lock(sia.mutex);

    // block until have devices
    while (wait || (!sia.have_devices_flag && !sia.shutdown_err)) {
        soundio_os_cond_wait(sia.cond, sia.mutex);
        wait = false;
    }

    if (sia.shutdown_err && !sia.emitted_shutdown_cb) {
        sia.emitted_shutdown_cb = true;
        cb_shutdown = true;
    } else if (sia.ready_devices_info) {
        old_devices_info = si.safe_devices_info;
        si.safe_devices_info = sia.ready_devices_info;
        sia.ready_devices_info = null;
        change = true;
    }

    soundio_os_mutex_unlock(sia.mutex);

    if (cb_shutdown)
        soundio.on_backend_disconnect(soundio, sia.shutdown_err);
    else if (change)
        soundio.on_devices_change(soundio);

    soundio_destroy_devices_info(old_devices_info);
}

void flush_events_alsa(SoundIoPrivate* si) {
    my_flush_events(si, false);
}

void wait_events_alsa(SoundIoPrivate* si) {
    my_flush_events(si, false);
    my_flush_events(si, true);
}

void wakeup_alsa(SoundIoPrivate* si) {
    SoundIoAlsa* sia = &si.backend_data.alsa;
    soundio_os_mutex_lock(sia.mutex);
    soundio_os_cond_signal(sia.cond, sia.mutex);
    soundio_os_mutex_unlock(sia.mutex);
}

void force_device_scan_alsa(SoundIoPrivate* si) {
    SoundIoAlsa* sia = &si.backend_data.alsa;
    wakeup_device_poll(sia);
}

void outstream_destroy_alsa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamAlsa* osa = &os.backend_data.alsa;

    if (osa.thread) {
        SOUNDIO_ATOMIC_FLAG_CLEAR(osa.thread_exit_flag);
        wakeup_outstream_poll(osa);
        soundio_os_thread_destroy(osa.thread);
        osa.thread = null;
    }

    if (osa.handle) {
        snd_pcm_close(osa.handle);
        osa.handle = null;
    }

    free(osa.poll_fds);
    osa.poll_fds = null;

    free(osa.chmap);
    osa.chmap = null;

    free(osa.sample_buffer);
    osa.sample_buffer = null;
}

int outstream_xrun_recovery(SoundIoOutStreamPrivate* os, int err) {
    SoundIoOutStream* outstream = &os.pub;
    SoundIoOutStreamAlsa* osa = &os.backend_data.alsa;
    if (err == -EPIPE) {
        err = snd_pcm_prepare(osa.handle);
        if (err >= 0)
            outstream.underflow_callback(outstream);
    } else if (err == -ESTRPIPE) {
        while ((err = snd_pcm_resume(osa.handle)) == -EAGAIN) {
            // wait until suspend flag is released
            poll(null, 0, 1);
        }
        if (err < 0)
            err = snd_pcm_prepare(osa.handle);
        if (err >= 0)
            outstream.underflow_callback(outstream);
    }
    return err;
}

int instream_xrun_recovery(SoundIoInStreamPrivate* is_, int err) {
    SoundIoInStream* instream = &is_.pub;
    SoundIoInStreamAlsa* isa = &is_.backend_data.alsa;
    if (err == -EPIPE) {
        err = snd_pcm_prepare(isa.handle);
        if (err >= 0)
            instream.overflow_callback(instream);
    } else if (err == -ESTRPIPE) {
        while ((err = snd_pcm_resume(isa.handle)) == -EAGAIN) {
            // wait until suspend flag is released
            poll(null, 0, 1);
        }
        if (err < 0)
            err = snd_pcm_prepare(isa.handle);
        if (err >= 0)
            instream.overflow_callback(instream);
    }
    return err;
}

int outstream_wait_for_poll(SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamAlsa* osa = &os.backend_data.alsa;
    int err;
    ushort revents;
    for (;;) {
        err = poll(osa.poll_fds, osa.poll_fd_count_with_extra, -1);
        if (err < 0) {
            return SoundIoError.Streaming;
        }
        if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osa.thread_exit_flag))
            return SoundIoError.Interrupted;
        if ((err = snd_pcm_poll_descriptors_revents(osa.handle,
                        osa.poll_fds, osa.poll_fd_count, &revents)) < 0)
        {
            return SoundIoError.Streaming;
        }
        if (revents & (POLLERR|POLLNVAL|POLLHUP)) {
            return 0;
        }
        if (revents & POLLOUT)
            return 0;
    }
}

int instream_wait_for_poll(SoundIoInStreamPrivate* is_) {
    SoundIoInStreamAlsa* isa = &is_.backend_data.alsa;
    int err;
    ushort revents;
    for (;;) {
        err = poll(isa.poll_fds, isa.poll_fd_count, -1);
        if (err < 0) {
            return err;
        }
        if ((err = snd_pcm_poll_descriptors_revents(isa.handle,
                        isa.poll_fds, isa.poll_fd_count, &revents)) < 0)
        {
            return err;
        }
        if (revents & (POLLERR|POLLNVAL|POLLHUP)) {
            return 0;
        }
        if (revents & POLLIN)
            return 0;
    }
}

void outstream_thread_run(void* arg) {
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*) arg;
    SoundIoOutStream* outstream = &os.pub;
    SoundIoOutStreamAlsa* osa = &os.backend_data.alsa;

    int err;

    for (;;) {
        snd_pcm_state_t state = snd_pcm_state(osa.handle);
        switch (state) {
            case SND_PCM_STATE_SETUP:
            {
                err = snd_pcm_prepare(osa.handle);
                if (err < 0) {
                    outstream.error_callback(outstream, SoundIoError.Streaming);
                    return;
                }
                continue;
            }
            case SND_PCM_STATE_PREPARED:
            {
                snd_pcm_sframes_t avail = snd_pcm_avail(osa.handle);
                if (avail < 0) {
                    outstream.error_callback(outstream, SoundIoError.Streaming);
                    return;
                }

                if (cast(snd_pcm_uframes_t)avail == osa.buffer_size_frames) {
                    outstream.write_callback(outstream, 0, cast(int) avail);
                    if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osa.thread_exit_flag))
                        return;
                    continue;
                }

                err = snd_pcm_start(osa.handle);
                if (err < 0) {
                    outstream.error_callback(outstream, SoundIoError.Streaming);
                    return;
                }
                continue;
            }
            case SND_PCM_STATE_RUNNING:
            case SND_PCM_STATE_PAUSED:
            {
                err = outstream_wait_for_poll(os);
                if (err) {
                    if (err == SoundIoError.Interrupted)
                        return;
                    outstream.error_callback(outstream, err);
                    return;
                }
                if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osa.thread_exit_flag))
                    return;
                if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osa.clear_buffer_flag)) {
                    err = snd_pcm_drop(osa.handle);
                    if (err < 0) {
                        outstream.error_callback(outstream, SoundIoError.Streaming);
                        return;
                    }
                    err = snd_pcm_reset(osa.handle);
                    if (err < 0) {
                        if (err == -EBADFD) {
                            // If this happens the snd_pcm_drop will have done
                            // the function of the reset so it's ok that this
                            // did not work.
                        } else {
                            outstream.error_callback(outstream, SoundIoError.Streaming);
                            return;
                        }
                    }
                    continue;
                }

                snd_pcm_sframes_t avail = snd_pcm_avail_update(osa.handle);
                if (avail < 0) {
                    err = outstream_xrun_recovery(os, cast(int) avail);
                    if (err < 0) {
                        outstream.error_callback(outstream, SoundIoError.Streaming);
                        return;
                    }
                    continue;
                }

                if (avail > 0)
                    outstream.write_callback(outstream, 0, cast(int) avail);
                continue;
            }
            case SND_PCM_STATE_XRUN:
                err = outstream_xrun_recovery(os, -EPIPE);
                if (err < 0) {
                    outstream.error_callback(outstream, SoundIoError.Streaming);
                    return;
                }
                continue;
            case SND_PCM_STATE_SUSPENDED:
                err = outstream_xrun_recovery(os, -ESTRPIPE);
                if (err < 0) {
                    outstream.error_callback(outstream, SoundIoError.Streaming);
                    return;
                }
                continue;
            case SND_PCM_STATE_OPEN:
            case SND_PCM_STATE_DRAINING:
            case SND_PCM_STATE_DISCONNECTED:
                outstream.error_callback(outstream, SoundIoError.Streaming);
                return;
            default:
                continue;
        }
    }
}

static void instream_thread_run(void* arg) {
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*) arg;
    SoundIoInStream* instream = &is_.pub;
    SoundIoInStreamAlsa* isa = &is_.backend_data.alsa;

    int err;

    for (;;) {
        snd_pcm_state_t state = snd_pcm_state(isa.handle);
        switch (state) {
            case SND_PCM_STATE_SETUP:
                err = snd_pcm_prepare(isa.handle);
                if (err < 0) {
                    instream.error_callback(instream, SoundIoError.Streaming);
                    return;
                }
                continue;
            case SND_PCM_STATE_PREPARED:
                err = snd_pcm_start(isa.handle);
                if (err < 0) {
                    instream.error_callback(instream, SoundIoError.Streaming);
                    return;
                }
                continue;
            case SND_PCM_STATE_RUNNING:
            case SND_PCM_STATE_PAUSED:
            {
                err = instream_wait_for_poll(is_);
                if (err < 0) {
                    if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(isa.thread_exit_flag))
                        return;
                    instream.error_callback(instream, SoundIoError.Streaming);
                    return;
                }
                if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(isa.thread_exit_flag))
                    return;

                snd_pcm_sframes_t avail = snd_pcm_avail_update(isa.handle);

                if (avail < 0) {
                    err = instream_xrun_recovery(is_, cast(int) avail);
                    if (err < 0) {
                        instream.error_callback(instream, SoundIoError.Streaming);
                        return;
                    }
                    continue;
                }

                if (avail > 0)
                    instream.read_callback(instream, 0, cast(int) avail);
                continue;
            }
            case SND_PCM_STATE_XRUN:
                err = instream_xrun_recovery(is_, -EPIPE);
                if (err < 0) {
                    instream.error_callback(instream, SoundIoError.Streaming);
                    return;
                }
                continue;
            case SND_PCM_STATE_SUSPENDED:
                err = instream_xrun_recovery(is_, -ESTRPIPE);
                if (err < 0) {
                    instream.error_callback(instream, SoundIoError.Streaming);
                    return;
                }
                continue;
            case SND_PCM_STATE_OPEN:
            case SND_PCM_STATE_DRAINING:
            case SND_PCM_STATE_DISCONNECTED:
                instream.error_callback(instream, SoundIoError.Streaming);
                return;
            default:
                continue;
        }
    }
}

static int outstream_open_alsa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamAlsa* osa = &os.backend_data.alsa;
    SoundIoOutStream* outstream = &os.pub;
    SoundIoDevice* device = outstream.device;

    SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osa.clear_buffer_flag);

    if (outstream.software_latency == 0.0)
        outstream.software_latency = 1.0;
    outstream.software_latency = soundio_double_clamp(device.software_latency_min, outstream.software_latency, device.software_latency_max);

    int ch_count = outstream.layout.channel_count;

    osa.chmap_size = cast(int) (int.sizeof + int.sizeof * ch_count);
    osa.chmap = cast(snd_pcm_chmap_t*)ALLOCATE!char(osa.chmap_size);
    if (!osa.chmap) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.NoMem;
    }

    int err;

    snd_pcm_hw_params_t* hwparams;
    snd_pcm_hw_params_malloc(&hwparams);
    if (!hwparams)
        return SoundIoError.NoMem;
    scope(exit) snd_pcm_hw_params_free(hwparams);

    snd_pcm_stream_t stream = aim_to_stream(outstream.device.aim);

    err = snd_pcm_open(&osa.handle, outstream.device.id, stream, 0);
    if (err < 0) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.OpeningDevice;
    }

    err = snd_pcm_hw_params_any(osa.handle, hwparams);
    if (err < 0) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.OpeningDevice;
    }

    int want_resample = !outstream.device.is_raw;
    err = snd_pcm_hw_params_set_rate_resample(osa.handle, hwparams, want_resample);
    if (err < 0) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.OpeningDevice;
    }

    err = set_access(osa.handle, hwparams, &osa.access);
    if (err) {
        outstream_destroy_alsa(si, os);
        return err;
    }

    err = snd_pcm_hw_params_set_channels(osa.handle, hwparams, ch_count);
    if (err < 0) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.OpeningDevice;
    }

    err = snd_pcm_hw_params_set_rate(osa.handle, hwparams, outstream.sample_rate, 0);
    if (err < 0) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.OpeningDevice;
    }

    snd_pcm_format_t format = to_alsa_fmt(outstream.format);
    int phys_bits_per_sample = snd_pcm_format_physical_width(format);
    if (phys_bits_per_sample % 8 != 0) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.IncompatibleDevice;
    }
    int phys_bytes_per_sample = phys_bits_per_sample / 8;
    err = snd_pcm_hw_params_set_format(osa.handle, hwparams, format);
    if (err < 0) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.OpeningDevice;
    }

    osa.buffer_size_frames = cast(ulong) (outstream.software_latency * outstream.sample_rate);
    err = snd_pcm_hw_params_set_buffer_size_near(osa.handle, hwparams, &osa.buffer_size_frames);
    if (err < 0) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.OpeningDevice;
    }
    outstream.software_latency = (cast(double)osa.buffer_size_frames) / cast(double)outstream.sample_rate;

    // write the hardware parameters to device
    err = snd_pcm_hw_params(osa.handle, hwparams);
    if (err < 0) {
        outstream_destroy_alsa(si, os);
        return (err == -EINVAL) ? SoundIoError.IncompatibleDevice : SoundIoError.OpeningDevice;
    }

    if ((snd_pcm_hw_params_get_period_size(hwparams, &osa.period_size, null)) < 0) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.OpeningDevice;
    }


    // set channel map
    osa.chmap.channels = ch_count;
    for (int i = 0; i < ch_count; i += 1) {
        // `pos` is variable length array typed `uint[0]`, .ptr to avoid range violation
        osa.chmap.pos.ptr[i] = to_alsa_chmap_pos(outstream.layout.channels[i]);
    }
    err = snd_pcm_set_chmap(osa.handle, osa.chmap);
    if (err < 0)
        outstream.layout_error = SoundIoError.IncompatibleDevice;

    // get current swparams
    snd_pcm_sw_params_t* swparams;
    snd_pcm_sw_params_malloc(&swparams);
    if (!swparams)
        return SoundIoError.NoMem;
    scope(exit) snd_pcm_sw_params_free(swparams);

    err = snd_pcm_sw_params_current(osa.handle, swparams);
    if (err < 0) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.OpeningDevice;
    }

    err = snd_pcm_sw_params_set_start_threshold(osa.handle, swparams, 0);
    if (err < 0) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.OpeningDevice;
    }

    err = snd_pcm_sw_params_set_avail_min(osa.handle, swparams, osa.period_size);
    if (err < 0) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.OpeningDevice;
    }

    // write the software parameters to device
    err = snd_pcm_sw_params(osa.handle, swparams);
    if (err < 0) {
        outstream_destroy_alsa(si, os);
        return (err == -EINVAL) ? SoundIoError.IncompatibleDevice : SoundIoError.OpeningDevice;
    }

    if (osa.access == SND_PCM_ACCESS_RW_INTERLEAVED || osa.access == SND_PCM_ACCESS_RW_NONINTERLEAVED) {
        osa.sample_buffer_size = cast(int) (ch_count * osa.period_size * phys_bytes_per_sample);
        osa.sample_buffer = ALLOCATE_NONZERO!(char)(osa.sample_buffer_size);
        if (!osa.sample_buffer) {
            outstream_destroy_alsa(si, os);
            return SoundIoError.NoMem;
        }
    }

    osa.poll_fd_count = snd_pcm_poll_descriptors_count(osa.handle);
    if (osa.poll_fd_count <= 0) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.OpeningDevice;
    }

    osa.poll_fd_count_with_extra = osa.poll_fd_count + 1;
    osa.poll_fds = ALLOCATE!pollfd( osa.poll_fd_count_with_extra);
    if (!osa.poll_fds) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.NoMem;
    }

    err = snd_pcm_poll_descriptors(osa.handle, osa.poll_fds, osa.poll_fd_count);
    if (err < 0) {
        outstream_destroy_alsa(si, os);
        return SoundIoError.OpeningDevice;
    }

    pollfd* extra_fd = &osa.poll_fds[osa.poll_fd_count];
    if (pipe2(osa.poll_exit_pipe_fd.ptr, O_NONBLOCK)) {
        assert(errno != EFAULT);
        assert(errno != EINVAL);
        assert(errno == EMFILE || errno == ENFILE);
        outstream_destroy_alsa(si, os);
        return SoundIoError.SystemResources;
    }
    extra_fd.fd = osa.poll_exit_pipe_fd[0];
    extra_fd.events = POLLIN;

    return 0;
}

static int outstream_start_alsa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamAlsa* osa = &os.backend_data.alsa;
    SoundIo* soundio = &si.pub;

    assert(!osa.thread);

    SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osa.thread_exit_flag);
    if (auto err = soundio_os_thread_create(&outstream_thread_run, os, soundio.emit_rtprio_warning, &osa.thread))
        return err;

    return 0;
}

static int outstream_begin_write_alsa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os, SoundIoChannelArea** out_areas, int* frame_count) {
    *out_areas = null;
    SoundIoOutStreamAlsa* osa = &os.backend_data.alsa;
    SoundIoOutStream* outstream = &os.pub;

    if (osa.access == SND_PCM_ACCESS_RW_INTERLEAVED) {
        for (int ch = 0; ch < outstream.layout.channel_count; ch += 1) {
            osa.areas[ch].ptr = osa.sample_buffer + ch * outstream.bytes_per_sample;
            osa.areas[ch].step = outstream.bytes_per_frame;
        }

        osa.write_frame_count = soundio_int_min(*frame_count, cast(int) osa.period_size);
        *frame_count = osa.write_frame_count;
    } else if (osa.access == SND_PCM_ACCESS_RW_NONINTERLEAVED) {
        for (int ch = 0; ch < outstream.layout.channel_count; ch += 1) {
            osa.areas[ch].ptr = osa.sample_buffer + ch * outstream.bytes_per_sample * osa.period_size;
            osa.areas[ch].step = outstream.bytes_per_sample;
        }

        osa.write_frame_count = soundio_int_min(*frame_count, cast(int) osa.period_size);
        *frame_count = osa.write_frame_count;
    } else {
        const(snd_pcm_channel_area_t)* areas;
        snd_pcm_uframes_t frames = *frame_count;
        int err;

        err = snd_pcm_mmap_begin(osa.handle, &areas, &osa.offset, &frames);
        if (err < 0) {
            if (err == -EPIPE || err == -ESTRPIPE)
                return SoundIoError.Underflow;
            else
                return SoundIoError.Streaming;
        }

        for (int ch = 0; ch < outstream.layout.channel_count; ch += 1) {
            if ((areas[ch].first % 8 != 0) || (areas[ch].step % 8 != 0))
                return SoundIoError.IncompatibleDevice;
            osa.areas[ch].step = areas[ch].step / 8;
            osa.areas[ch].ptr = (cast(char*)areas[ch].addr) + (areas[ch].first / 8) +
                (osa.areas[ch].step * osa.offset);
        }

        osa.write_frame_count = cast(int) frames;
        *frame_count = osa.write_frame_count;
    }

    *out_areas = osa.areas.ptr;
    return 0;
}

static int outstream_end_write_alsa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamAlsa* osa = &os.backend_data.alsa;
    SoundIoOutStream* outstream = &os.pub;

    snd_pcm_sframes_t commitres;
    if (osa.access == SND_PCM_ACCESS_RW_INTERLEAVED) {
        commitres = snd_pcm_writei(osa.handle, osa.sample_buffer, osa.write_frame_count);
    } else if (osa.access == SND_PCM_ACCESS_RW_NONINTERLEAVED) {
        char*[SOUNDIO_MAX_CHANNELS] ptrs;
        for (int ch = 0; ch < outstream.layout.channel_count; ch += 1) {
            ptrs[ch] = osa.sample_buffer + ch * outstream.bytes_per_sample * osa.period_size;
        }
        commitres = snd_pcm_writen(osa.handle, cast(void**)ptrs, osa.write_frame_count);
    } else {
        commitres = snd_pcm_mmap_commit(osa.handle, osa.offset, osa.write_frame_count);
    }

    if (commitres < 0 || commitres != osa.write_frame_count) {
        int err = cast(int) ((commitres >= 0) ? -EPIPE : commitres);
        if (err == -EPIPE || err == -ESTRPIPE)
            return SoundIoError.Underflow;
        else
            return SoundIoError.Streaming;
    }
    return 0;
}

static int outstream_clear_buffer_alsa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamAlsa* osa = &os.backend_data.alsa;
    SOUNDIO_ATOMIC_FLAG_CLEAR(osa.clear_buffer_flag);
    return 0;
}

static int outstream_pause_alsa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os, bool pause) {
    if (!si)
        return SoundIoError.Invalid;

    SoundIoOutStreamAlsa* osa = &os.backend_data.alsa;

    if (!osa.handle)
        return SoundIoError.Invalid;

    if (osa.is_paused == pause)
        return 0;

    int err;
    err = snd_pcm_pause(osa.handle, pause);
    if (err < 0) {
        return SoundIoError.IncompatibleDevice;
    }

    osa.is_paused = pause;
    return 0;
}

static int outstream_get_latency_alsa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os, double* out_latency) {
    SoundIoOutStream* outstream = &os.pub;
    SoundIoOutStreamAlsa* osa = &os.backend_data.alsa;
    int err;

    snd_pcm_sframes_t delay;
    err = snd_pcm_delay(osa.handle, &delay);
    if (err < 0) {
        return SoundIoError.Streaming;
    }

    *out_latency = delay / cast(double)outstream.sample_rate;
    return 0;
}

static void instream_destroy_alsa(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamAlsa* isa = &is_.backend_data.alsa;

    if (isa.thread) {
        SOUNDIO_ATOMIC_FLAG_CLEAR(isa.thread_exit_flag);
        soundio_os_thread_destroy(isa.thread);
        isa.thread = null;
    }

    if (isa.handle) {
        snd_pcm_close(isa.handle);
        isa.handle = null;
    }

    free(isa.poll_fds);
    isa.poll_fds = null;

    free(isa.chmap);
    isa.chmap = null;

    free(isa.sample_buffer);
    isa.sample_buffer = null;
}

static int instream_open_alsa(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamAlsa* isa = &is_.backend_data.alsa;
    SoundIoInStream* instream = &is_.pub;
    SoundIoDevice* device = instream.device;

    if (instream.software_latency == 0.0)
        instream.software_latency = 1.0;
    instream.software_latency = soundio_double_clamp(device.software_latency_min, instream.software_latency, device.software_latency_max);

    int ch_count = instream.layout.channel_count;

    isa.chmap_size = cast(int) (int.sizeof + int.sizeof * ch_count);
    isa.chmap = cast(snd_pcm_chmap_t*) ALLOCATE!char(isa.chmap_size);
    if (!isa.chmap) {
        instream_destroy_alsa(si, is_);
        return SoundIoError.NoMem;
    }

    int err;

    snd_pcm_hw_params_t* hwparams;
    snd_pcm_hw_params_malloc(&hwparams);
    if (!hwparams)
        return SoundIoError.NoMem;
    scope(exit) snd_pcm_hw_params_free(hwparams);

    snd_pcm_stream_t stream = aim_to_stream(instream.device.aim);

    err = snd_pcm_open(&isa.handle, instream.device.id, stream, 0);
    if (err < 0) {
        instream_destroy_alsa(si, is_);
        return SoundIoError.OpeningDevice;
    }

    err = snd_pcm_hw_params_any(isa.handle, hwparams);
    if (err < 0) {
        instream_destroy_alsa(si, is_);
        return SoundIoError.OpeningDevice;
    }

    int want_resample = !instream.device.is_raw;
    err = snd_pcm_hw_params_set_rate_resample(isa.handle, hwparams, want_resample);
    if (err < 0) {
        instream_destroy_alsa(si, is_);
        return SoundIoError.OpeningDevice;
    }

    err = set_access(isa.handle, hwparams, &isa.access);
    if (err) {
        instream_destroy_alsa(si, is_);
        return err;
    }

    err = snd_pcm_hw_params_set_channels(isa.handle, hwparams, ch_count);
    if (err < 0) {
        instream_destroy_alsa(si, is_);
        return SoundIoError.OpeningDevice;
    }

    err = snd_pcm_hw_params_set_rate(isa.handle, hwparams, instream.sample_rate, 0);
    if (err < 0) {
        instream_destroy_alsa(si, is_);
        return SoundIoError.OpeningDevice;
    }

    snd_pcm_format_t format = to_alsa_fmt(instream.format);
    int phys_bits_per_sample = snd_pcm_format_physical_width(format);
    if (phys_bits_per_sample % 8 != 0) {
        instream_destroy_alsa(si, is_);
        return SoundIoError.IncompatibleDevice;
    }
    int phys_bytes_per_sample = phys_bits_per_sample / 8;
    err = snd_pcm_hw_params_set_format(isa.handle, hwparams, format);
    if (err < 0) {
        instream_destroy_alsa(si, is_);
        return SoundIoError.OpeningDevice;
    }

    snd_pcm_uframes_t period_frames = ceil_dbl_to_uframes(0.5 * instream.software_latency * cast(double)instream.sample_rate);
    err = snd_pcm_hw_params_set_period_size_near(isa.handle, hwparams, &period_frames, null);
    if (err < 0) {
        instream_destroy_alsa(si, is_);
        return SoundIoError.OpeningDevice;
    }
    instream.software_latency = (cast(double)period_frames) / cast(double)instream.sample_rate;
    isa.period_size = cast(int) period_frames;


    snd_pcm_uframes_t buffer_size_frames;
    err = snd_pcm_hw_params_set_buffer_size_last(isa.handle, hwparams, &buffer_size_frames);
    if (err < 0) {
        instream_destroy_alsa(si, is_);
        return SoundIoError.OpeningDevice;
    }

    // write the hardware parameters to device
    err = snd_pcm_hw_params(isa.handle, hwparams);
    if (err < 0) {
        instream_destroy_alsa(si, is_);
        return (err == -EINVAL) ? SoundIoError.IncompatibleDevice : SoundIoError.OpeningDevice;
    }

    // set channel map
    isa.chmap.channels = ch_count;
    for (int i = 0; i < ch_count; i += 1) {
        // `pos` is variable length array typed `uint[0]`, .ptr to avoid range violation
        isa.chmap.pos.ptr[i] = to_alsa_chmap_pos(instream.layout.channels[i]);
    }
    err = snd_pcm_set_chmap(isa.handle, isa.chmap);
    if (err < 0)
        instream.layout_error = SoundIoError.IncompatibleDevice;

    // get current swparams
    snd_pcm_sw_params_t* swparams;
    snd_pcm_sw_params_malloc(&swparams);
    if (!swparams)
        return SoundIoError.NoMem;
    scope(exit) snd_pcm_sw_params_free(swparams);

    err = snd_pcm_sw_params_current(isa.handle, swparams);
    if (err < 0) {
        instream_destroy_alsa(si, is_);
        return SoundIoError.OpeningDevice;
    }

    // write the software parameters to device
    err = snd_pcm_sw_params(isa.handle, swparams);
    if (err < 0) {
        instream_destroy_alsa(si, is_);
        return (err == -EINVAL) ? SoundIoError.IncompatibleDevice : SoundIoError.OpeningDevice;
    }

    if (isa.access == SND_PCM_ACCESS_RW_INTERLEAVED || isa.access == SND_PCM_ACCESS_RW_NONINTERLEAVED) {
        isa.sample_buffer_size = ch_count * isa.period_size * phys_bytes_per_sample;
        isa.sample_buffer = ALLOCATE_NONZERO!char(isa.sample_buffer_size);
        if (!isa.sample_buffer) {
            instream_destroy_alsa(si, is_);
            return SoundIoError.NoMem;
        }
    }

    isa.poll_fd_count = snd_pcm_poll_descriptors_count(isa.handle);
    if (isa.poll_fd_count <= 0) {
        instream_destroy_alsa(si, is_);
        return SoundIoError.OpeningDevice;
    }

    isa.poll_fds = ALLOCATE!pollfd(isa.poll_fd_count);
    if (!isa.poll_fds) {
        instream_destroy_alsa(si, is_);
        return SoundIoError.NoMem;
    }

    err = snd_pcm_poll_descriptors(isa.handle, isa.poll_fds, isa.poll_fd_count);
    if (err < 0) {
        instream_destroy_alsa(si, is_);
        return SoundIoError.OpeningDevice;
    }

    return 0;
}

static int instream_start_alsa(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamAlsa* isa = &is_.backend_data.alsa;
    SoundIo* soundio = &si.pub;

    assert(!isa.thread);

    SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(isa.thread_exit_flag);
    if (auto err = soundio_os_thread_create(&instream_thread_run, is_, soundio.emit_rtprio_warning, &isa.thread)) {
        instream_destroy_alsa(si, is_);
        return err;
    }

    return 0;
}

static int instream_begin_read_alsa(SoundIoPrivate* si, SoundIoInStreamPrivate* is_, SoundIoChannelArea** out_areas, int* frame_count) {
    *out_areas = null;
    SoundIoInStreamAlsa* isa = &is_.backend_data.alsa;
    SoundIoInStream* instream = &is_.pub;

    if (isa.access == SND_PCM_ACCESS_RW_INTERLEAVED) {
        for (int ch = 0; ch < instream.layout.channel_count; ch += 1) {
            isa.areas[ch].ptr = isa.sample_buffer + ch * instream.bytes_per_sample;
            isa.areas[ch].step = instream.bytes_per_frame;
        }

        isa.read_frame_count = soundio_int_min(*frame_count, isa.period_size);
        *frame_count = isa.read_frame_count;

        snd_pcm_sframes_t commitres = snd_pcm_readi(isa.handle, isa.sample_buffer, isa.read_frame_count);
        if (commitres < 0 || commitres != isa.read_frame_count) {
            int err = cast(int) ((commitres >= 0) ? -EPIPE : commitres);
            err = instream_xrun_recovery(is_, err);
            if (err < 0)
                return SoundIoError.Streaming;
        }
    } else if (isa.access == SND_PCM_ACCESS_RW_NONINTERLEAVED) {
        char*[SOUNDIO_MAX_CHANNELS] ptrs;
        for (int ch = 0; ch < instream.layout.channel_count; ch += 1) {
            isa.areas[ch].ptr = isa.sample_buffer + ch * instream.bytes_per_sample * isa.period_size;
            isa.areas[ch].step = instream.bytes_per_sample;
            ptrs[ch] = isa.areas[ch].ptr;
        }

        isa.read_frame_count = soundio_int_min(*frame_count, isa.period_size);
        *frame_count = isa.read_frame_count;

        snd_pcm_sframes_t commitres = snd_pcm_readn(isa.handle, cast(void**)ptrs, isa.read_frame_count);
        if (commitres < 0 || commitres != isa.read_frame_count) {
            int err = cast(int) ((commitres >= 0) ? -EPIPE : commitres);
            err = instream_xrun_recovery(is_, err);
            if (err < 0)
                return SoundIoError.Streaming;
        }
    } else {
        const(snd_pcm_channel_area_t)* areas;
        snd_pcm_uframes_t frames = *frame_count;
        int err;

        err = snd_pcm_mmap_begin(isa.handle, &areas, &isa.offset, &frames);
        if (err < 0) {
            err = instream_xrun_recovery(is_, err);
            if (err < 0)
                return SoundIoError.Streaming;
        }

        for (int ch = 0; ch < instream.layout.channel_count; ch += 1) {
            if ((areas[ch].first % 8 != 0) || (areas[ch].step % 8 != 0))
                return SoundIoError.IncompatibleDevice;
            isa.areas[ch].step = areas[ch].step / 8;
            isa.areas[ch].ptr = (cast(char*)areas[ch].addr) + (areas[ch].first / 8) +
                (isa.areas[ch].step * isa.offset);
        }

        isa.read_frame_count = cast(int) frames;
        *frame_count = isa.read_frame_count;
    }

    *out_areas = isa.areas.ptr;
    return 0;
}

static int instream_end_read_alsa(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamAlsa* isa = &is_.backend_data.alsa;

    if (isa.access == SND_PCM_ACCESS_RW_INTERLEAVED) {
        // nothing to do
    } else if (isa.access == SND_PCM_ACCESS_RW_NONINTERLEAVED) {
        // nothing to do
    } else {
        snd_pcm_sframes_t commitres = snd_pcm_mmap_commit(isa.handle, isa.offset, isa.read_frame_count);
        if (commitres < 0 || commitres != isa.read_frame_count) {
            int err = cast(int) ((commitres >= 0) ? -EPIPE : commitres);
            err = instream_xrun_recovery(is_, err);
            if (err < 0)
                return SoundIoError.Streaming;
        }
    }

    return 0;
}

static int instream_pause_alsa(SoundIoPrivate* si, SoundIoInStreamPrivate* is_, bool pause) {
    SoundIoInStreamAlsa* isa = &is_.backend_data.alsa;

    if (isa.is_paused == pause)
        return 0;

    int err;
    err = snd_pcm_pause(isa.handle, pause);
    if (err < 0)
        return SoundIoError.IncompatibleDevice;

    isa.is_paused = pause;
    return 0;
}

static int instream_get_latency_alsa(SoundIoPrivate* si, SoundIoInStreamPrivate* is_, double* out_latency) {
    SoundIoInStream* instream = &is_.pub;
    SoundIoInStreamAlsa* isa = &is_.backend_data.alsa;
    int err;

    snd_pcm_sframes_t delay;
    err = snd_pcm_delay(isa.handle, &delay);
    if (err < 0) {
        return SoundIoError.Streaming;
    }

    *out_latency = delay / cast(double)instream.sample_rate;
    return 0;
}

package int soundio_alsa_init(SoundIoPrivate* si) {
    SoundIoAlsa* sia = &si.backend_data.alsa;
    int err;

    sia.notify_fd = -1;
    sia.notify_wd = -1;
    SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(sia.abort_flag);

    sia.mutex = soundio_os_mutex_create();
    if (!sia.mutex) {
        destroy_alsa(si);
        return SoundIoError.NoMem;
    }

    sia.cond = soundio_os_cond_create();
    if (!sia.cond) {
        destroy_alsa(si);
        return SoundIoError.NoMem;
    }


    // set up inotify to watch /dev/snd for devices added or removed
    sia.notify_fd = inotify_init1(IN_NONBLOCK);
    if (sia.notify_fd == -1) {
        err = errno;
        assert(err != EINVAL);
        destroy_alsa(si);
        if (err == EMFILE || err == ENFILE) {
            return SoundIoError.SystemResources;
        } else {
            assert(err == ENOMEM);
            return SoundIoError.NoMem;
        }
    }

    sia.notify_wd = inotify_add_watch(sia.notify_fd, "/dev/snd", IN_CREATE | IN_CLOSE_WRITE | IN_DELETE);
    if (sia.notify_wd == -1) {
        err = errno;
        assert(err != EACCES);
        assert(err != EBADF);
        assert(err != EFAULT);
        assert(err != EINVAL);
        assert(err != ENAMETOOLONG);
        destroy_alsa(si);
        if (err == ENOSPC) {
            return SoundIoError.SystemResources;
        } else if (err == ENOMEM) {
            return SoundIoError.NoMem;
        } else {
            // Kernel must not have ALSA support.
            return SoundIoError.InitAudioBackend;
        }
    }

    if (pipe2(sia.notify_pipe_fd.ptr, O_NONBLOCK)) {
        assert(errno != EFAULT);
        assert(errno != EINVAL);
        assert(errno == EMFILE || errno == ENFILE);
        return SoundIoError.SystemResources;
    }

    wakeup_device_poll(sia);

    //device_thread_run(si); TODO removeme
    err = soundio_os_thread_create(&device_thread_run, si, null, &sia.thread);
    if (err) {
        destroy_alsa(si);
        return err;
    }

    si.destroy = &destroy_alsa;
    si.flush_events = &flush_events_alsa;
    si.wait_events = &wait_events_alsa;
    si.wakeup = &wakeup_alsa;
    si.force_device_scan = &force_device_scan_alsa;

    si.outstream_open = &outstream_open_alsa;
    si.outstream_destroy = &outstream_destroy_alsa;
    si.outstream_start = &outstream_start_alsa;
    si.outstream_begin_write = &outstream_begin_write_alsa;
    si.outstream_end_write = &outstream_end_write_alsa;
    si.outstream_clear_buffer = &outstream_clear_buffer_alsa;
    si.outstream_pause = &outstream_pause_alsa;
    si.outstream_get_latency = &outstream_get_latency_alsa;

    si.instream_open = &instream_open_alsa;
    si.instream_destroy = &instream_destroy_alsa;
    si.instream_start = &instream_start_alsa;
    si.instream_begin_read = &instream_begin_read_alsa;
    si.instream_end_read = &instream_end_read_alsa;
    si.instream_pause = &instream_pause_alsa;
    si.instream_get_latency = &instream_get_latency_alsa;

    return 0;
}
