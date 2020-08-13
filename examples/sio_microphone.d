/// Translated from C to D
module sio_microphone;

extern(C): @nogc: nothrow: __gshared:

import soundio.api;
import soundio.util: printf_stderr;

import core.stdc.stdio;
import core.stdc.stdarg;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.math;

SoundIoRingBuffer* ring_buffer = null;

private SoundIoFormat[19] prioritized_formats = [
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

private int[5] prioritized_sample_rates = [
    48000,
    44100,
    96000,
    24000,
    0,
];

private void panic(T...)(const(char)* format, T args) {
    printf_stderr(format, args);
    /+va_list ap;
    va_start(ap, format);
    vprintf_stderr(format, ap);
    printf_stderr("\n");
    va_end(ap);
    +/
    abort();
}

private int min_int(int a, int b) {
    return (a < b) ? a : b;
}

private void read_callback(SoundIoInStream* instream, int frame_count_min, int frame_count_max) {
    SoundIoChannelArea* areas;
    char* write_ptr = soundio_ring_buffer_write_ptr(ring_buffer);
    int free_bytes = soundio_ring_buffer_free_count(ring_buffer);
    int free_count = free_bytes / instream.bytes_per_frame;

    if (frame_count_min > free_count)
        panic("ring buffer overflow");

    int write_frames = min_int(free_count, frame_count_max);
    int frames_left = write_frames;

    for (;;) {
        int frame_count = frames_left;

        if (auto err = soundio_instream_begin_read(instream, &areas, &frame_count))
            panic("begin read error: %s", soundio_strerror(err));

        if (!frame_count)
            break;

        if (!areas) {
            // Due to an overflow there is a hole. Fill the ring buffer with
            // silence for the size of the hole.
            memset(write_ptr, 0, frame_count * instream.bytes_per_frame);
            printf_stderr("Dropped %d frames due to internal overflow\n", frame_count);
        } else {
            for (int frame = 0; frame < frame_count; frame += 1) {
                for (int ch = 0; ch < instream.layout.channel_count; ch += 1) {
                    memcpy(write_ptr, areas[ch].ptr, instream.bytes_per_sample);
                    areas[ch].ptr += areas[ch].step;
                    write_ptr += instream.bytes_per_sample;
                }
            }
        }

        if (auto err = soundio_instream_end_read(instream))
            panic("end read error: %s", soundio_strerror(err));

        frames_left -= frame_count;
        if (frames_left <= 0)
            break;
    }

    int advance_bytes = write_frames * instream.bytes_per_frame;
    soundio_ring_buffer_advance_write_ptr(ring_buffer, advance_bytes);
}

private void write_callback(SoundIoOutStream* outstream, int frame_count_min, int frame_count_max) {
    SoundIoChannelArea* areas;
    int frames_left;

    char* read_ptr = soundio_ring_buffer_read_ptr(ring_buffer);
    int fill_bytes = soundio_ring_buffer_fill_count(ring_buffer);
    int fill_count = fill_bytes / outstream.bytes_per_frame;

    if (frame_count_min > fill_count) {
        int frame_count;
        // Ring buffer does not have enough data, fill with zeroes.
        frames_left = frame_count_min;
        for (;;) {
            frame_count = frames_left;
            if (frame_count <= 0)
              return;
            if (auto err = soundio_outstream_begin_write(outstream, &areas, &frame_count))
                panic("begin write error: %s", soundio_strerror(err));
            if (frame_count <= 0)
                return;
            for (int frame = 0; frame < frame_count; frame += 1) {
                for (int ch = 0; ch < outstream.layout.channel_count; ch += 1) {
                    memset(areas[ch].ptr, 0, outstream.bytes_per_sample);
                    areas[ch].ptr += areas[ch].step;
                }
            }
            if (auto err = soundio_outstream_end_write(outstream))
                panic("end write error: %s", soundio_strerror(err));
            frames_left -= frame_count;
        }
    }

    int read_count = min_int(frame_count_max, fill_count);
    frames_left = read_count;

    while (frames_left > 0) {
        int frame_count = frames_left;

        if (auto err = soundio_outstream_begin_write(outstream, &areas, &frame_count))
            panic("begin write error: %s", soundio_strerror(err));

        if (frame_count <= 0)
            break;

        for (int frame = 0; frame < frame_count; frame += 1) {
            for (int ch = 0; ch < outstream.layout.channel_count; ch += 1) {
                memcpy(areas[ch].ptr, read_ptr, outstream.bytes_per_sample);
                areas[ch].ptr += areas[ch].step;
                read_ptr += outstream.bytes_per_sample;
            }
        }

        if (auto err = soundio_outstream_end_write(outstream))
            panic("end write error: %s", soundio_strerror(err));

        frames_left -= frame_count;
    }

    soundio_ring_buffer_advance_read_ptr(ring_buffer, read_count * outstream.bytes_per_frame);
}

private void underflow_callback(SoundIoOutStream* outstream) {
    static int count = 0;
    printf_stderr("underflow %d\n", ++count);
}

private int usage(char* exe) {
    printf_stderr("Usage: %s [options]\n"
            ~ "Options:\n"
            ~ "  [--backend dummy|alsa|pulseaudio|jack|coreaudio|wasapi]\n"
            ~ "  [--in-device id]\n"
            ~ "  [--in-raw]\n"
            ~ "  [--out-device id]\n"
            ~ "  [--out-raw]\n"
            ~ "  [--latency seconds]\n"
            , exe);
    return 1;
}

int main(int argc, char** argv) {
    char* exe = argv[0];
    SoundIoBackend backend = SoundIoBackend.None;
    char* in_device_id = null;
    char* out_device_id = null;
    bool in_raw = false;
    bool out_raw = false;

    double microphone_latency = 0.2; // seconds

    for (int i = 1; i < argc; i += 1) {
        char* arg = argv[i];
        if (arg[0] == '-' && arg[1] == '-') {
            if (strcmp(arg, "--in-raw") == 0) {
                in_raw = true;
            } else if (strcmp(arg, "--out-raw") == 0) {
                out_raw = true;
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
            } else if (strcmp(arg, "--in-device") == 0) {
                in_device_id = argv[i];
            } else if (strcmp(arg, "--out-device") == 0) {
                out_device_id = argv[i];
            } else if (strcmp(arg, "--latency") == 0) {
                microphone_latency = atof(argv[i]);
            } else {
                return usage(exe);
            }
        } else {
            return usage(exe);
        }
    }
    SoundIo* soundio = soundio_create();
    if (!soundio)
        panic("out of memory");

    if (auto err = (backend == SoundIoBackend.None) ?
        soundio_connect(soundio) : soundio_connect_backend(soundio, backend))
        panic("error connecting: %s", soundio_strerror(err));

    soundio_flush_events(soundio);

    int default_out_device_index = soundio_default_output_device_index(soundio);
    if (default_out_device_index < 0)
        panic("no output device found");

    int default_in_device_index = soundio_default_input_device_index(soundio);
    if (default_in_device_index < 0)
        panic("no input device found");

    int in_device_index = default_in_device_index;
    if (in_device_id) {
        bool found = false;
        for (int i = 0; i < soundio_input_device_count(soundio); i += 1) {
            SoundIoDevice* device = soundio_get_input_device(soundio, i);
            if (device.is_raw == in_raw && strcmp(device.id, in_device_id) == 0) {
                in_device_index = i;
                found = true;
                soundio_device_unref(device);
                break;
            }
            soundio_device_unref(device);
        }
        if (!found)
            panic("invalid input device id: %s", in_device_id);
    }

    int out_device_index = default_out_device_index;
    if (out_device_id) {
        bool found = false;
        for (int i = 0; i < soundio_output_device_count(soundio); i += 1) {
            SoundIoDevice* device = soundio_get_output_device(soundio, i);
            if (device.is_raw == out_raw && strcmp(device.id, out_device_id) == 0) {
                out_device_index = i;
                found = true;
                soundio_device_unref(device);
                break;
            }
            soundio_device_unref(device);
        }
        if (!found)
            panic("invalid output device id: %s", out_device_id);
    }

    SoundIoDevice* out_device = soundio_get_output_device(soundio, out_device_index);
    if (!out_device)
        panic("could not get output device: out of memory");

    SoundIoDevice* in_device = soundio_get_input_device(soundio, in_device_index);
    if (!in_device)
        panic("could not get input device: out of memory");

    printf_stderr("Input device: %s\n", in_device.name);
    printf_stderr("Output device: %s\n", out_device.name);

    soundio_device_sort_channel_layouts(out_device);
    const(SoundIoChannelLayout)* layout = soundio_best_matching_channel_layout(
            out_device.layouts, out_device.layout_count,
            in_device.layouts, in_device.layout_count);

    if (!layout)
        panic("channel layouts not compatible");

    int* sample_rate;
    for (sample_rate = prioritized_sample_rates.ptr; *sample_rate; sample_rate += 1) {
        if (soundio_device_supports_sample_rate(in_device, *sample_rate) &&
            soundio_device_supports_sample_rate(out_device, *sample_rate))
        {
            break;
        }
    }
    if (!*sample_rate)
        panic("incompatible sample rates");

    SoundIoFormat* fmt;
    for (fmt = prioritized_formats.ptr; *fmt != SoundIoFormat.Invalid; fmt += 1) {
        if (soundio_device_supports_format(in_device, *fmt) &&
            soundio_device_supports_format(out_device, *fmt))
        {
            break;
        }
    }
    if (*fmt == SoundIoFormat.Invalid)
        panic("incompatible sample formats");

    SoundIoInStream* instream = soundio_instream_create(in_device);
    if (!instream)
        panic("out of memory");
    instream.format = *fmt;
    instream.sample_rate = *sample_rate;
    instream.layout = *layout;
    instream.software_latency = microphone_latency;
    instream.read_callback = &read_callback;

    if (auto err = soundio_instream_open(instream)) {
        printf_stderr("unable to open input stream: %s", soundio_strerror(err));
        return 1;
    }

    SoundIoOutStream* outstream = soundio_outstream_create(out_device);
    if (!outstream)
        panic("out of memory");
    outstream.format = *fmt;
    outstream.sample_rate = *sample_rate;
    outstream.layout = *layout;
    outstream.software_latency = microphone_latency;
    outstream.write_callback = &write_callback;
    outstream.underflow_callback = &underflow_callback;

    if (auto err = soundio_outstream_open(outstream)) {
        printf_stderr("unable to open output stream: %s", soundio_strerror(err));
        return 1;
    }

    int capacity = cast(int) (microphone_latency * 2 * instream.sample_rate * instream.bytes_per_frame);
    ring_buffer = soundio_ring_buffer_create(soundio, capacity);
    if (!ring_buffer)
        panic("unable to create ring buffer: out of memory");
    char* buf = soundio_ring_buffer_write_ptr(ring_buffer);
    int fill_count = cast(int) (microphone_latency * outstream.sample_rate * outstream.bytes_per_frame);
    memset(buf, 0, fill_count);
    soundio_ring_buffer_advance_write_ptr(ring_buffer, fill_count);

    if (auto err = soundio_instream_start(instream))
        panic("unable to start input device: %s", soundio_strerror(err));

    if (auto err = soundio_outstream_start(outstream))
        panic("unable to start output device: %s", soundio_strerror(err));

    for (;;)
        soundio_wait_events(soundio);

    soundio_outstream_destroy(outstream);
    soundio_instream_destroy(instream);
    soundio_device_unref(in_device);
    soundio_device_unref(out_device);
    soundio_destroy(soundio);
    return 0;
}