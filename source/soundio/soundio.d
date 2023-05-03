/// Translated from C to D
module soundio.soundio;

@nogc nothrow:
extern(C): __gshared:


import soundio.atomics;
import soundio.soundio_private;
import soundio.util;
import soundio.os;
import soundio.config;
import core.stdc.string;
import core.stdc.assert_;
import core.stdc.stdio;
import core.stdc.stdlib: qsort, free;

package:

private extern(D) immutable SoundIoBackend[] available_backends = () {
    SoundIoBackend[] result;
    version(SOUNDIO_HAVE_JACK) result ~= SoundIoBackend.Jack;
    version(SOUNDIO_HAVE_PULSEAUDIO) result ~= SoundIoBackend.PulseAudio;
    version(SOUNDIO_HAVE_ALSA) result ~= SoundIoBackend.Alsa;
    version(SOUNDIO_HAVE_COREAUDIO) result ~= SoundIoBackend.CoreAudio;
    version(SOUNDIO_HAVE_WASAPI) result ~= SoundIoBackend.Wasapi;
    return result;
} ();

alias backend_init_t = int function(SoundIoPrivate*);

immutable backend_init_t[7] backend_init_fns = () {
    backend_init_t[7] result = null;
    result[0] = null; // None backend
    version(SOUNDIO_HAVE_JACK) result[1] = &soundio_jack_init;
    version(SOUNDIO_HAVE_PULSEAUDIO) result[2] = &soundio_pulseaudio_init;
    version(SOUNDIO_HAVE_ALSA) result[3] = &soundio_alsa_init;
    version(SOUNDIO_HAVE_COREAUDIO) result[4] = &soundio_coreaudio_init;
    version(SOUNDIO_HAVE_WASAPI) result[5] = &soundio_wasapi_init;
    result[6] = &soundio_dummy_init;
    return result;
} ();

const(char)* soundio_strerror(int error) {
    switch (cast(SoundIoError)error) {
        case SoundIoError.None: return "(no error)";
        case SoundIoError.NoMem: return "out of memory";
        case SoundIoError.InitAudioBackend: return "unable to initialize audio backend";
        case SoundIoError.SystemResources: return "system resource not available";
        case SoundIoError.OpeningDevice: return "unable to open device";
        case SoundIoError.NoSuchDevice: return "no such device";
        case SoundIoError.Invalid: return "invalid value";
        case SoundIoError.BackendUnavailable: return "backend unavailable";
        case SoundIoError.Streaming: return "unrecoverable streaming failure";
        case SoundIoError.IncompatibleDevice: return "incompatible device";
        case SoundIoError.NoSuchClient: return "no such client";
        case SoundIoError.IncompatibleBackend: return "incompatible backend";
        case SoundIoError.BackendDisconnected: return "backend disconnected";
        case SoundIoError.Interrupted: return "interrupted; try again";
        case SoundIoError.Underflow: return "buffer underflow";
        case SoundIoError.EncodingString: return "failed to encode string";
        default: return "(invalid error)";
    }
}

int soundio_get_bytes_per_sample(SoundIoFormat format) {
    switch (format) {
    case SoundIoFormat.U8:         return 1;
    case SoundIoFormat.S8:         return 1;
    case SoundIoFormat.S16LE:      return 2;
    case SoundIoFormat.S16BE:      return 2;
    case SoundIoFormat.U16LE:      return 2;
    case SoundIoFormat.U16BE:      return 2;
    case SoundIoFormat.S24LE:      return 4;
    case SoundIoFormat.S24BE:      return 4;
    case SoundIoFormat.U24LE:      return 4;
    case SoundIoFormat.U24BE:      return 4;
    case SoundIoFormat.S32LE:      return 4;
    case SoundIoFormat.S32BE:      return 4;
    case SoundIoFormat.U32LE:      return 4;
    case SoundIoFormat.U32BE:      return 4;
    case SoundIoFormat.Float32LE:  return 4;
    case SoundIoFormat.Float32BE:  return 4;
    case SoundIoFormat.Float64LE:  return 8;
    case SoundIoFormat.Float64BE:  return 8;

    case SoundIoFormat.Invalid:    return -1;
    default: break;
    }
    return -1;
}

const(char)* soundio_format_string(SoundIoFormat format) {
    switch (format) {
    case SoundIoFormat.S8:         return "signed 8-bit";
    case SoundIoFormat.U8:         return "unsigned 8-bit";
    case SoundIoFormat.S16LE:      return "signed 16-bit LE";
    case SoundIoFormat.S16BE:      return "signed 16-bit BE";
    case SoundIoFormat.U16LE:      return "unsigned 16-bit LE";
    case SoundIoFormat.U16BE:      return "unsigned 16-bit LE";
    case SoundIoFormat.S24LE:      return "signed 24-bit LE";
    case SoundIoFormat.S24BE:      return "signed 24-bit BE";
    case SoundIoFormat.U24LE:      return "unsigned 24-bit LE";
    case SoundIoFormat.U24BE:      return "unsigned 24-bit BE";
    case SoundIoFormat.S32LE:      return "signed 32-bit LE";
    case SoundIoFormat.S32BE:      return "signed 32-bit BE";
    case SoundIoFormat.U32LE:      return "unsigned 32-bit LE";
    case SoundIoFormat.U32BE:      return "unsigned 32-bit BE";
    case SoundIoFormat.Float32LE:  return "float 32-bit LE";
    case SoundIoFormat.Float32BE:  return "float 32-bit BE";
    case SoundIoFormat.Float64LE:  return "float 64-bit LE";
    case SoundIoFormat.Float64BE:  return "float 64-bit BE";
    case SoundIoFormat.Invalid:
    default: break;
    }
    return "(invalid sample format)";
}


const(char)* soundio_backend_name(SoundIoBackend backend) {
    switch (backend) {
        case SoundIoBackend.None: return "(none)";
        case SoundIoBackend.Jack: return "JACK";
        case SoundIoBackend.PulseAudio: return "PulseAudio";
        case SoundIoBackend.Alsa: return "ALSA";
        case SoundIoBackend.CoreAudio: return "CoreAudio";
        case SoundIoBackend.Wasapi: return "WASAPI";
        case SoundIoBackend.Dummy: return "Dummy";
        default: break;
    }
    return "(invalid backend)";
}

void soundio_destroy(SoundIo* soundio) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;

    soundio_disconnect(soundio);

    free(si);
}

private void do_nothing_cb(SoundIo* soundio) { }
private void default_msg_callback(const(char)* msg) { }

private void default_backend_disconnect_cb(SoundIo* soundio, int err) {
    soundio_panic("libsoundio: backend disconnected: %s", soundio_strerror(err));
}

private SoundIoAtomicFlag rtprio_seen = SoundIoAtomicFlag.init;
private void default_emit_rtprio_warning() {
    if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(rtprio_seen)) {
        printf_stderr("warning: unable to set high priority thread: Operation not permitted\n");
        printf_stderr("See "
            ~ "https://github.com/andrewrk/genesis/wiki/warning:-unable-to-set-high-priority-thread:-Operation-not-permitted\n");
    }
}

SoundIo* soundio_create() {
    if (auto err = soundio_os_init())
        return null;
    SoundIoPrivate* si = ALLOCATE!SoundIoPrivate(1);
    if (!si)
        return null;
    SoundIo* soundio = &si.pub;
    soundio.on_devices_change = &do_nothing_cb;
    soundio.on_backend_disconnect = &default_backend_disconnect_cb;
    soundio.on_events_signal = &do_nothing_cb;
    soundio.app_name = "SoundIo";
    soundio.emit_rtprio_warning = &default_emit_rtprio_warning;
    soundio.jack_info_callback = &default_msg_callback;
    soundio.jack_error_callback = &default_msg_callback;
    return soundio;
}

int soundio_connect(SoundIo* soundio) {
    int err = 0;

    for (int i = 0; i < available_backends.length; i += 1) {
        SoundIoBackend backend = available_backends[i];
        err = soundio_connect_backend(soundio, backend);
        if (!err)
            return 0;
        if (err != SoundIoError.InitAudioBackend)
            return err;
    }

    return err;
}

int soundio_connect_backend(SoundIo* soundio, SoundIoBackend backend) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;

    if (soundio.current_backend)
        return SoundIoError.Invalid;

    if (backend <= 0 || backend > SoundIoBackend.Dummy)
        return SoundIoError.Invalid;

    extern(C) int function(SoundIoPrivate*) fn = backend_init_fns[backend];

    if (!fn)
        return SoundIoError.BackendUnavailable;

    if (auto err = backend_init_fns[backend](si)) {
        soundio_disconnect(soundio);
        return err;
    }
    soundio.current_backend = backend;

    return 0;
}

void soundio_disconnect(SoundIo* soundio) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;

    if (!si)
        return;

    if (si.destroy)
        si.destroy(si);
    memset(&si.backend_data, 0, SoundIoBackendData.sizeof);

    soundio.current_backend = SoundIoBackend.None;

    soundio_destroy_devices_info(si.safe_devices_info);
    si.safe_devices_info = null;

    si.destroy = null;
    si.flush_events = null;
    si.wait_events = null;
    si.wakeup = null;
    si.force_device_scan = null;

    si.outstream_open = null;
    si.outstream_destroy = null;
    si.outstream_start = null;
    si.outstream_begin_write = null;
    si.outstream_end_write = null;
    si.outstream_clear_buffer = null;
    si.outstream_pause = null;
    si.outstream_get_latency = null;
    si.outstream_set_volume = null;

    si.instream_open = null;
    si.instream_destroy = null;
    si.instream_start = null;
    si.instream_begin_read = null;
    si.instream_end_read = null;
    si.instream_pause = null;
    si.instream_get_latency = null;
}

void soundio_flush_events(SoundIo* soundio) {
    assert(soundio.current_backend != SoundIoBackend.None);
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    si.flush_events(si);
}

int soundio_input_device_count(SoundIo* soundio) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;

    assert(si.safe_devices_info);
    if (!si.safe_devices_info)
        return -1;

    assert(soundio.current_backend != SoundIoBackend.None);
    if (soundio.current_backend == SoundIoBackend.None)
        return -1;

    return si.safe_devices_info.input_devices.length;
}

int soundio_output_device_count(SoundIo* soundio) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;

    assert(si.safe_devices_info);
    if (!si.safe_devices_info)
        return -1;

    assert(soundio.current_backend != SoundIoBackend.None);
    if (soundio.current_backend == SoundIoBackend.None)
        return -1;

    return si.safe_devices_info.output_devices.length;
}

int soundio_default_input_device_index(SoundIo* soundio) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;

    assert(si.safe_devices_info);
    if (!si.safe_devices_info)
        return -1;

    assert(soundio.current_backend != SoundIoBackend.None);
    if (soundio.current_backend == SoundIoBackend.None)
        return -1;

    return si.safe_devices_info.default_input_index;
}

int soundio_default_output_device_index(SoundIo* soundio) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;

    assert(si.safe_devices_info);
    if (!si.safe_devices_info)
        return -1;

    assert(soundio.current_backend != SoundIoBackend.None);
    if (soundio.current_backend == SoundIoBackend.None)
        return -1;

    return si.safe_devices_info.default_output_index;
}

SoundIoDevice* soundio_get_input_device(SoundIo* soundio, int index) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;

    assert(soundio.current_backend != SoundIoBackend.None);
    if (soundio.current_backend == SoundIoBackend.None)
        return null;

    assert(si.safe_devices_info);
    if (!si.safe_devices_info)
        return null;

    assert(index >= 0);
    assert(index < si.safe_devices_info.input_devices.length);
    if (index < 0 || index >= si.safe_devices_info.input_devices.length)
        return null;

    SoundIoDevice* device = si.safe_devices_info.input_devices.val_at(index);
    soundio_device_ref(device);
    return device;
}

SoundIoDevice* soundio_get_output_device(SoundIo* soundio, int index) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;

    assert(soundio.current_backend != SoundIoBackend.None);
    if (soundio.current_backend == SoundIoBackend.None)
        return null;

    assert(si.safe_devices_info);
    if (!si.safe_devices_info)
        return null;

    assert(index >= 0);
    assert(index < si.safe_devices_info.output_devices.length);
    if (index < 0 || index >= si.safe_devices_info.output_devices.length)
        return null;

    SoundIoDevice* device = si.safe_devices_info.output_devices.val_at(index);
    soundio_device_ref(device);
    return device;
}

void soundio_device_unref(SoundIoDevice* device) {
    if (!device)
        return;

    device.ref_count -= 1;
    assert(device.ref_count >= 0);

    if (device.ref_count == 0) {
        SoundIoDevicePrivate* dev = cast(SoundIoDevicePrivate*)device;
        if (dev.destruct)
            dev.destruct(dev);

        free(device.id);
        free(device.name);

        if (device.sample_rates != &dev.prealloc_sample_rate_range &&
            device.sample_rates != dev.sample_rates.items)
        {
            free(device.sample_rates);
        }
        dev.sample_rates.deinit();

        if (device.formats != &dev.prealloc_format)
            free(device.formats);

        if (device.layouts != &device.current_layout)
            free(device.layouts);

        free(dev);
    }
}

void soundio_device_ref(SoundIoDevice* device) {
    assert(device);
    device.ref_count += 1;
}

void soundio_wait_events(SoundIo* soundio) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    si.wait_events(si);
}

void soundio_wakeup(SoundIo* soundio) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    si.wakeup(si);
}

void soundio_force_device_scan(SoundIo* soundio) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    si.force_device_scan(si);
}

int soundio_outstream_begin_write(SoundIoOutStream* outstream, SoundIoChannelArea** areas, int* frame_count) {
    SoundIo* soundio = outstream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)outstream;
    if (*frame_count <= 0)
        return SoundIoError.Invalid;
    return si.outstream_begin_write(si, os, areas, frame_count);
}

int soundio_outstream_end_write(SoundIoOutStream* outstream) {
    SoundIo* soundio = outstream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)outstream;
    return si.outstream_end_write(si, os);
}

private void default_outstream_error_callback(SoundIoOutStream* os, int err) {
    soundio_panic("libsoundio: %s", soundio_strerror(err));
}

private void default_underflow_callback(SoundIoOutStream* outstream) { }

SoundIoOutStream* soundio_outstream_create(SoundIoDevice* device) {
    SoundIoOutStreamPrivate* os = ALLOCATE!SoundIoOutStreamPrivate(1);
    SoundIoOutStream* outstream = &os.pub;

    if (!os)
        return null;
    if (!device)
        return null;

    outstream.device = device;
    soundio_device_ref(device);

    outstream.error_callback = &default_outstream_error_callback;
    outstream.underflow_callback = &default_underflow_callback;

    return outstream;
}

int soundio_outstream_open(SoundIoOutStream* outstream) {
    SoundIoDevice* device = outstream.device;

    if (device.aim != SoundIoDeviceAim.Output)
        return SoundIoError.Invalid;

    if (device.probe_error)
        return device.probe_error;

    if (outstream.layout.channel_count > SOUNDIO_MAX_CHANNELS)
        return SoundIoError.Invalid;

    if (outstream.format == SoundIoFormat.Invalid) {
        outstream.format = soundio_device_supports_format(device, SoundIoFormatFloat32NE) ?
            SoundIoFormatFloat32NE : device.formats[0];
    }

    if (outstream.format <= SoundIoFormat.Invalid)
        return SoundIoError.Invalid;

    if (!outstream.layout.channel_count) {
        const(SoundIoChannelLayout)* stereo = soundio_channel_layout_get_builtin(SoundIoChannelLayoutId.Stereo);
        outstream.layout = soundio_device_supports_layout(device, stereo) ? *stereo : device.layouts[0];
    }

    if (!outstream.sample_rate)
        outstream.sample_rate = soundio_device_nearest_sample_rate(device, 48000);

    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)outstream;
    outstream.bytes_per_frame = soundio_get_bytes_per_frame(outstream.format, outstream.layout.channel_count);
    outstream.bytes_per_sample = soundio_get_bytes_per_sample(outstream.format);

    SoundIo* soundio = device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    return si.outstream_open(si, os);
}

void soundio_outstream_destroy(SoundIoOutStream* outstream) {
    if (!outstream)
        return;

    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)outstream;
    SoundIo* soundio = outstream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;

    if (si.outstream_destroy)
        si.outstream_destroy(si, os);

    soundio_device_unref(outstream.device);
    free(os);
}

int soundio_outstream_start(SoundIoOutStream* outstream) {
    SoundIo* soundio = outstream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)outstream;
    return si.outstream_start(si, os);
}

int soundio_outstream_pause(SoundIoOutStream* outstream, bool pause) {
    SoundIo* soundio = outstream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)outstream;
    return si.outstream_pause(si, os, pause);
}

int soundio_outstream_clear_buffer(SoundIoOutStream* outstream) {
    SoundIo* soundio = outstream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)outstream;
    return si.outstream_clear_buffer(si, os);
}

int soundio_outstream_get_latency(SoundIoOutStream* outstream, double* out_latency) {
    SoundIo* soundio = outstream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)outstream;
    return si.outstream_get_latency(si, os, out_latency);
}

int soundio_outstream_set_volume(SoundIoOutStream* outstream, double volume) {
    SoundIo* soundio = outstream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)outstream;
    return si.outstream_set_volume(si, os, volume);
}

private void default_instream_error_callback(SoundIoInStream* is_, int err) {
    soundio_panic("libsoundio: %s", soundio_strerror(err));
}

private void default_overflow_callback(SoundIoInStream* instream) { }

SoundIoInStream* soundio_instream_create(SoundIoDevice* device) {
    SoundIoInStreamPrivate* is_ = ALLOCATE!SoundIoInStreamPrivate(1);
    SoundIoInStream* instream = &is_.pub;

    if (!is_)
        return null;
    if (!device)
        return null;

    instream.device = device;
    soundio_device_ref(device);

    instream.error_callback = &default_instream_error_callback;
    instream.overflow_callback = &default_overflow_callback;

    return instream;
}

int soundio_instream_open(SoundIoInStream* instream) {
    SoundIoDevice* device = instream.device;
    if (device.aim != SoundIoDeviceAim.Input)
        return SoundIoError.Invalid;

    if (instream.format <= SoundIoFormat.Invalid)
        return SoundIoError.Invalid;

    if (instream.layout.channel_count > SOUNDIO_MAX_CHANNELS)
        return SoundIoError.Invalid;

    if (device.probe_error)
        return device.probe_error;

    if (instream.format == SoundIoFormat.Invalid) {
        instream.format = soundio_device_supports_format(device, SoundIoFormat.Float32NE) ?
            SoundIoFormat.Float32NE : device.formats[0];
    }

    if (!instream.layout.channel_count) {
        const(SoundIoChannelLayout)* stereo = soundio_channel_layout_get_builtin(SoundIoChannelLayoutId.Stereo);
        instream.layout = soundio_device_supports_layout(device, stereo) ? *stereo : device.layouts[0];
    }

    if (!instream.sample_rate)
        instream.sample_rate = soundio_device_nearest_sample_rate(device, 48000);


    instream.bytes_per_frame = soundio_get_bytes_per_frame(instream.format, instream.layout.channel_count);
    instream.bytes_per_sample = soundio_get_bytes_per_sample(instream.format);
    SoundIo* soundio = device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)instream;
    return si.instream_open(si, is_);
}

int soundio_instream_start(SoundIoInStream* instream) {
    SoundIo* soundio = instream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)instream;
    return si.instream_start(si, is_);
}

void soundio_instream_destroy(SoundIoInStream* instream) {
    if (!instream)
        return;

    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)instream;
    SoundIo* soundio = instream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;

    if (si.instream_destroy)
        si.instream_destroy(si, is_);

    soundio_device_unref(instream.device);
    free(is_);
}

int soundio_instream_pause(SoundIoInStream* instream, bool pause) {
    SoundIo* soundio = instream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)instream;
    return si.instream_pause(si, is_, pause);
}

int soundio_instream_begin_read(SoundIoInStream* instream, SoundIoChannelArea** areas, int* frame_count) {
    SoundIo* soundio = instream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)instream;
    return si.instream_begin_read(si, is_, areas, frame_count);
}

int soundio_instream_end_read(SoundIoInStream* instream) {
    SoundIo* soundio = instream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)instream;
    return si.instream_end_read(si, is_);
}

int soundio_instream_get_latency(SoundIoInStream* instream, double* out_latency) {
    SoundIo* soundio = instream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)instream;
    return si.instream_get_latency(si, is_, out_latency);
}

void soundio_destroy_devices_info(SoundIoDevicesInfo* devices_info) {
    if (!devices_info)
        return;

    for (int i = 0; i < devices_info.input_devices.length; i += 1)
        soundio_device_unref(devices_info.input_devices.val_at(i));
    for (int i = 0; i < devices_info.output_devices.length; i += 1)
        soundio_device_unref(devices_info.output_devices.val_at(i));

    devices_info.input_devices.deinit();
    devices_info.output_devices.deinit();

    free(devices_info);
}

bool soundio_have_backend(SoundIoBackend backend) {
    assert(backend > 0);
    assert(backend <= SoundIoBackend.max);
    return cast(bool) backend_init_fns[backend];
}

int soundio_backend_count(SoundIo* soundio) {
    return cast(int) available_backends.length;
}

SoundIoBackend soundio_get_backend(SoundIo* soundio, int index) {
    return available_backends[index];
}

private bool layout_contains(const(SoundIoChannelLayout)* available_layouts, int available_layouts_count, const(SoundIoChannelLayout)* target_layout) {
    for (int i = 0; i < available_layouts_count; i += 1) {
        const(SoundIoChannelLayout)* available_layout = &available_layouts[i];
        if (soundio_channel_layout_equal(target_layout, available_layout))
            return true;
    }
    return false;
}

const(SoundIoChannelLayout)* soundio_best_matching_channel_layout(const(SoundIoChannelLayout)* preferred_layouts, int preferred_layouts_count, const(SoundIoChannelLayout)* available_layouts, int available_layouts_count) {
    for (int i = 0; i < preferred_layouts_count; i += 1) {
        const(SoundIoChannelLayout)* preferred_layout = &preferred_layouts[i];
        if (layout_contains(available_layouts, available_layouts_count, preferred_layout))
            return preferred_layout;
    }
    return null;
}

private int compare_layouts(const(void)* a, const(void)* b) {
    const(SoundIoChannelLayout)* layout_a = cast(const(SoundIoChannelLayout)*)a;
    const(SoundIoChannelLayout)* layout_b = cast(const(SoundIoChannelLayout)*)b;
    if (layout_a.channel_count > layout_b.channel_count)
        return -1;
    else if (layout_a.channel_count < layout_b.channel_count)
        return 1;
    else
        return 0;
}

void soundio_sort_channel_layouts(SoundIoChannelLayout* layouts, int layouts_count) {
    if (!layouts)
        return;

    qsort(layouts, layouts_count, SoundIoChannelLayout.sizeof, &compare_layouts);
}

void soundio_device_sort_channel_layouts(SoundIoDevice* device) {
    soundio_sort_channel_layouts(device.layouts, device.layout_count);
}

bool soundio_device_supports_format(SoundIoDevice* device, SoundIoFormat format) {
    for (int i = 0; i < device.format_count; i += 1) {
        if (device.formats[i] == format)
            return true;
    }
    return false;
}

bool soundio_device_supports_layout(SoundIoDevice* device, const(SoundIoChannelLayout)* layout) {
    for (int i = 0; i < device.layout_count; i += 1) {
        if (soundio_channel_layout_equal(&device.layouts[i], layout))
            return true;
    }
    return false;
}

bool soundio_device_supports_sample_rate(SoundIoDevice* device, int sample_rate) {
    for (int i = 0; i < device.sample_rate_count; i += 1) {
        SoundIoSampleRateRange* range = &device.sample_rates[i];
        if (sample_rate >= range.min && sample_rate <= range.max)
            return true;
    }
    return false;
}

private int abs_diff_int(int a, int b) {
    int x = a - b;
    return (x >= 0) ? x : -x;
}

int soundio_device_nearest_sample_rate(SoundIoDevice* device, int sample_rate) {
    int best_rate = -1;
    int best_delta = -1;
    for (int i = 0; i < device.sample_rate_count; i += 1) {
        SoundIoSampleRateRange* range = &device.sample_rates[i];
        int candidate_rate = soundio_int_clamp(range.min, sample_rate, range.max);
        if (candidate_rate == sample_rate)
            return candidate_rate;

        int delta = abs_diff_int(candidate_rate, sample_rate);
        bool best_rate_too_small = best_rate < sample_rate;
        bool candidate_rate_too_small = candidate_rate < sample_rate;
        if (best_rate == -1 ||
            (best_rate_too_small && !candidate_rate_too_small) ||
            ((best_rate_too_small || !candidate_rate_too_small) && delta < best_delta))
        {
            best_rate = candidate_rate;
            best_delta = delta;
        }
    }
    return best_rate;
}

bool soundio_device_equal(const(SoundIoDevice)* a, const(SoundIoDevice)* b) {
    return a.is_raw == b.is_raw && a.aim == b.aim && strcmp(a.id, b.id) == 0;
}

const(char)* soundio_version_string() {
    return SOUNDIO_VERSION_STRING;
}

int soundio_version_major() {
    return SOUNDIO_VERSION_MAJOR;
}

int soundio_version_minor() {
    return SOUNDIO_VERSION_MINOR;
}

int soundio_version_patch() {
    return SOUNDIO_VERSION_PATCH;
}
