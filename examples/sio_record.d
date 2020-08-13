/// Translated from C to D
module sio_record;

extern(C): @nogc: nothrow: __gshared:

import soundio.api;
import soundio.util: printf_stderr;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.math;
import core.stdc.errno;
import core.sys.posix.unistd;

struct RecordContext {
    SoundIoRingBuffer* ring_buffer;
}

immutable SoundIoFormat[19] prioritized_formats = [
    SoundIoFormat.Float32NE,
    SoundIoFormat.Float32FE,
    SoundIoFormat.S32NE,
    SoundIoFormat.S32FE,
    SoundIoFormat.S24NE,
    SoundIoFormat.S24FE,
    SoundIoFormat.S16NE,
    SoundIoFormat.S16FE,
    SoundIoFormat.Float64NE,
    SoundIoFormat.Float64FE,
    SoundIoFormat.U32NE,
    SoundIoFormat.U32FE,
    SoundIoFormat.U24NE,
    SoundIoFormat.U24FE,
    SoundIoFormat.U16NE,
    SoundIoFormat.U16FE,
    SoundIoFormat.S8,
    SoundIoFormat.U8,
    SoundIoFormat.Invalid,
];

immutable int[5] prioritized_sample_rates = [
    48000,
    44100,
    96000,
    24000,
    0,
];

static int min_int(int a, int b) {
    return (a < b) ? a : b;
}

static void read_callback(SoundIoInStream* instream, int frame_count_min, int frame_count_max) {
    RecordContext* rc = cast(RecordContext*) instream.userdata;
    SoundIoChannelArea* areas;

    char* write_ptr = soundio_ring_buffer_write_ptr(rc.ring_buffer);
    int free_bytes = soundio_ring_buffer_free_count(rc.ring_buffer);
    int free_count = free_bytes / instream.bytes_per_frame;

    if (free_count < frame_count_min) {
        printf_stderr("ring buffer overflow\n");
        exit(1);
    }

    int write_frames = min_int(free_count, frame_count_max);
    int frames_left = write_frames;

    for (;;) {
        int frame_count = frames_left;

        if (auto err = soundio_instream_begin_read(instream, &areas, &frame_count)) {
            printf_stderr("begin read error: %s", soundio_strerror(err));
            exit(1);
        }

        if (!frame_count)
            break;

        if (!areas) {
            // Due to an overflow there is a hole. Fill the ring buffer with
            // silence for the size of the hole.
            memset(write_ptr, 0, frame_count * instream.bytes_per_frame);
        } else {
            for (int frame = 0; frame < frame_count; frame += 1) {
                for (int ch = 0; ch < instream.layout.channel_count; ch += 1) {
                    memcpy(write_ptr, areas[ch].ptr, instream.bytes_per_sample);
                    areas[ch].ptr += areas[ch].step;
                    write_ptr += instream.bytes_per_sample;
                }
            }
        }

        if (auto err = soundio_instream_end_read(instream)) {
            printf_stderr("end read error: %s", soundio_strerror(err));
            exit(1);
        }

        frames_left -= frame_count;
        if (frames_left <= 0)
            break;
    }

    int advance_bytes = write_frames * instream.bytes_per_frame;
    soundio_ring_buffer_advance_write_ptr(rc.ring_buffer, advance_bytes);
}

static void overflow_callback(SoundIoInStream* instream) {
    static int count = 0;
    printf_stderr("overflow %d\n", ++count);
}

static int usage(char* exe) {
    printf_stderr("Usage: %s [options] outfile\n"
            ~ "Options:\n"
            ~ "  [--backend dummy|alsa|pulseaudio|jack|coreaudio|wasapi]\n"
            ~ "  [--device id]\n"
            ~ "  [--raw]\n"
            , exe);
    return 1;
}

int main(int argc, char** argv) {
    char* exe = argv[0];
    SoundIoBackend backend = SoundIoBackend.None;
    char* device_id = null;
    bool is_raw = false;
    char* outfile = null;
    for (int i = 1; i < argc; i += 1) {
        char* arg = argv[i];
        if (arg[0] == '-' && arg[1] == '-') {
            if (strcmp(arg, "--raw") == 0) {
                is_raw = true;
            } else if (++i >= argc) {
                return usage(exe);
            } else if (strcmp(arg, "--backend") == 0) {
                if (strcmp("dummy", argv[i]) == 0) {
                    backend = SoundIoBackend.Dummy;
                } else if (strcmp("alsa", argv[i]) == 0) {
                    backend = SoundIoBackend.Alsa;
                } else if (strcmp("pulseaudio", argv[i]) == 0) {
                    backend = SoundIoBackend.PulseAudio;
                } else if (strcmp("jack", argv[i]) == 0) {
                    backend = SoundIoBackend.Jack;
                } else if (strcmp("coreaudio", argv[i]) == 0) {
                    backend = SoundIoBackend.CoreAudio;
                } else if (strcmp("wasapi", argv[i]) == 0) {
                    backend = SoundIoBackend.Wasapi;
                } else {
                    printf_stderr("Invalid backend: %s\n", argv[i]);
                    return 1;
                }
            } else if (strcmp(arg, "--device") == 0) {
                device_id = argv[i];
            } else {
                return usage(exe);
            }
        } else if (!outfile) {
            outfile = argv[i];
        } else {
            return usage(exe);
        }
    }

    if (!outfile)
        return usage(exe);

    RecordContext rc;

    SoundIo* soundio = soundio_create();
    if (!soundio) {
        printf_stderr("out of memory\n");
        return 1;
    }

    if (auto err = (backend == SoundIoBackend.None) ?
        soundio_connect(soundio) : soundio_connect_backend(soundio, backend)) {
        printf_stderr("error connecting: %s", soundio_strerror(err));
        return 1;
    }

    soundio_flush_events(soundio);

    SoundIoDevice* selected_device = null;

    if (device_id) {
        for (int i = 0; i < soundio_input_device_count(soundio); i += 1) {
            SoundIoDevice* device = soundio_get_input_device(soundio, i);
            if (device.is_raw == is_raw && strcmp(device.id, device_id) == 0) {
                selected_device = device;
                break;
            }
            soundio_device_unref(device);
        }
        if (!selected_device) {
            printf_stderr("Invalid device id: %s\n", device_id);
            return 1;
        }
    } else {
        int device_index = soundio_default_input_device_index(soundio);
        selected_device = soundio_get_input_device(soundio, device_index);
        if (!selected_device) {
            printf_stderr("No input devices available.\n");
            return 1;
        }
    }

    printf_stderr("Device: %s\n", selected_device.name);

    if (selected_device.probe_error) {
        printf_stderr("Unable to probe device: %s\n", soundio_strerror(selected_device.probe_error));
        return 1;
    }

    soundio_device_sort_channel_layouts(selected_device);

    int sample_rate = 0;
    const(int)* sample_rate_ptr;
    foreach (sr; prioritized_sample_rates) {
        if (soundio_device_supports_sample_rate(selected_device, sr)) {
            sample_rate = sr;
            break;
        }
    }
    if (!sample_rate)
        sample_rate = selected_device.sample_rates[0].max;

    SoundIoFormat fmt = SoundIoFormat.Invalid;
    const(SoundIoFormat)* fmt_ptr;
    for (fmt_ptr = prioritized_formats.ptr; *fmt_ptr != SoundIoFormat.Invalid; fmt_ptr += 1) {
        if (soundio_device_supports_format(selected_device, *fmt_ptr)) {
            fmt = *fmt_ptr;
            break;
        }
    }
    if (fmt == SoundIoFormat.Invalid)
        fmt = selected_device.formats[0];

    FILE* out_f = fopen(outfile, "wb");
    if (!out_f) {
        printf_stderr("unable to open %s: %s\n", outfile, strerror(errno));
        return 1;
    }
    SoundIoInStream* instream = soundio_instream_create(selected_device);
    if (!instream) {
        printf_stderr("out of memory\n");
        return 1;
    }
    instream.format = fmt;
    instream.sample_rate = sample_rate;
    instream.read_callback = &read_callback;
    instream.overflow_callback = &overflow_callback;
    instream.userdata = &rc;

    if (auto err = soundio_instream_open(instream)) {
        printf_stderr("unable to open input stream: %s", soundio_strerror(err));
        return 1;
    }

    printf_stderr("%s %dHz %s interleaved\n",
            instream.layout.name, sample_rate, soundio_format_string(fmt));

    const(int) ring_buffer_duration_seconds = 30;
    int capacity = ring_buffer_duration_seconds * instream.sample_rate * instream.bytes_per_frame;
    rc.ring_buffer = soundio_ring_buffer_create(soundio, capacity);
    if (!rc.ring_buffer) {
        printf_stderr("out of memory\n");
        return 1;
    }

    if (auto err = soundio_instream_start(instream)) {
        printf_stderr("unable to start input device: %s", soundio_strerror(err));
        return 1;
    }

    // Note: in this example, if you send SIGINT (by pressing Ctrl+C for example)
    // you will lose up to 1 second of recorded audio data. In non-example code,
    // consider a better shutdown strategy.
    for (;;) {
        soundio_flush_events(soundio);
        sleep(1);
        int fill_bytes = soundio_ring_buffer_fill_count(rc.ring_buffer);
        char* read_buf = soundio_ring_buffer_read_ptr(rc.ring_buffer);
        size_t amt = fwrite(read_buf, 1, fill_bytes, out_f);
        if (cast(int)amt != fill_bytes) {
            printf_stderr("write error: %s\n", strerror(errno));
            return 1;
        }
        soundio_ring_buffer_advance_read_ptr(rc.ring_buffer, fill_bytes);
    }

    soundio_instream_destroy(instream);
    soundio_device_unref(selected_device);
    soundio_destroy(soundio);
    return 0;
}