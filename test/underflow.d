/// Translated from C to D
module underflow;

extern(C): @nogc: nothrow: __gshared:

import soundio.api;
import soundio.util: printf_stderr;

import core.stdc.stdio;
import core.stdc.stdarg;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.math;
import core.sys.posix.unistd;
import core.stdc.stdint;

private void panic(T...)(const(char)* format, T args) {
    printf_stderr(format, args);
    printf_stderr("\n");
    abort();
}

private int usage(char* exe) {
    printf_stderr("Usage: %s [options]\n"
            ~ "Options:\n"
            ~ "  [--backend dummy|alsa|pulseaudio|jack|coreaudio|wasapi]\n"
            ~ "  [--device id]\n"
            ~ "  [--raw]\n"
            ~ "  [--sample-rate hz]\n"
            , exe);
    return 1;
}

private void write_sample_s16ne(char* ptr, double sample) {
    short* buf = cast(short*)ptr;
    double range = cast(double)short.max - cast(double)short.min;
    const double val = sample * range / 2.0;
    *buf = cast(short) val;
}

private void write_sample_s32ne(char* ptr, double sample) {
    int* buf = cast(int*)ptr;
    double range = cast(double)INT32_MAX - cast(double)INT32_MIN;
    const double val = sample * range / 2.0;
    *buf = cast(int) val;
}

private void write_sample_float32ne(char* ptr, double sample) {
    float* buf = cast(float*)ptr;
    *buf = sample;
}

private void write_sample_float64ne(char* ptr, double sample) {
    double* buf = cast(double*)ptr;
    *buf = sample;
}

private void function(char* ptr, double sample) write_sample;
private const(double) PI = 3.14159265358979323846264338328;
private double seconds_offset = 0.0;
private bool caused_underflow = false;
private SoundIo* soundio = null;
private double seconds_end = 9.0f;

private void write_callback(SoundIoOutStream* outstream, int frame_count_min, int frame_count_max) {
    const double float_sample_rate = outstream.sample_rate;
    double seconds_per_frame = 1.0 / float_sample_rate;
    SoundIoChannelArea* areas;
    int err;

    if (!caused_underflow && seconds_offset >= 3.0) {
        caused_underflow = true;
        sleep(3);
    }

    if (seconds_offset >= seconds_end) {
        soundio_wakeup(soundio);
        return;
    }

    int frames_left = frame_count_max;

    for (;;) {
        int frame_count = frames_left;
        if (cast(bool) (err = soundio_outstream_begin_write(outstream, &areas, &frame_count)))
            panic("%s", soundio_strerror(err));

        if (!frame_count)
            break;

        const(SoundIoChannelLayout)* layout = &outstream.layout;

        const double pitch = 440.0;
        double radians_per_second = pitch * 2.0 * PI;
        for (int frame = 0; frame < frame_count; frame += 1) {
            double sample = sinf((seconds_offset + frame * seconds_per_frame) * radians_per_second);
            for (int channel = 0; channel < layout.channel_count; channel += 1) {
                write_sample(areas[channel].ptr, sample);
                areas[channel].ptr += areas[channel].step;
            }
        }
        seconds_offset += seconds_per_frame * frame_count;

        if (cast(bool) (err = soundio_outstream_end_write(outstream))) {
            if (err == SoundIoErrorUnderflow)
                return;
            panic("%s", soundio_strerror(err));
        }

        frames_left -= frame_count;
        if (frames_left <= 0)
            break;
    }
}

private void underflow_callback(SoundIoOutStream* outstream) {
    static int count = 0;
    printf_stderr("underflow %d\n", count++);
}

int main(int argc, char** argv) {
    char* exe = argv[0];
    SoundIoBackend backend = SoundIoBackendNone;
    char* device_id = null;
    bool raw = false;
    int sample_rate = 0;
    for (int i = 1; i < argc; i += 1) {
        char* arg = argv[i];
        if (arg[0] == '-' && arg[1] == '-') {
            if (strcmp(arg, "--raw") == 0) {
                raw = true;
            } else {
                i += 1;
                if (i >= argc) {
                    return usage(exe);
                } else if (strcmp(arg, "--backend") == 0) {
                    if (strcmp(argv[i], "dummy") == 0) {
                        backend = SoundIoBackendDummy;
                    } else if (strcmp(argv[i], "alsa") == 0) {
                        backend = SoundIoBackendAlsa;
                    } else if (strcmp(argv[i], "pulseaudio") == 0) {
                        backend = SoundIoBackendPulseAudio;
                    } else if (strcmp(argv[i], "jack") == 0) {
                        backend = SoundIoBackendJack;
                    } else if (strcmp(argv[i], "coreaudio") == 0) {
                        backend = SoundIoBackendCoreAudio;
                    } else if (strcmp(argv[i], "wasapi") == 0) {
                        backend = SoundIoBackendWasapi;
                    } else {
                        printf_stderr("Invalid backend: %s\n", argv[i]);
                        return 1;
                    }
                } else if (strcmp(arg, "--device") == 0) {
                    device_id = argv[i];
                } else if (strcmp(arg, "--sample-rate") == 0) {
                    sample_rate = atoi(argv[i]);
                } else {
                    return usage(exe);
                }
            }
        } else {
            return usage(exe);
        }
    }

    printf_stderr("You should hear a sine wave for 3 seconds, then some period of silence or glitches,\n"
                    ~ "then you should see at least one buffer underflow message, then hear a sine\n"
                    ~ "wave for 3 seconds, then the program should exit successfully.\n"
                    ~ "WASAPI does not report buffer underflows.\n");

    if (!cast(bool) (soundio = soundio_create()))
        panic("out of memory");

    int err = (backend == SoundIoBackendNone) ?
        soundio_connect(soundio) : soundio_connect_backend(soundio, backend);

    if (err)
        panic("error connecting: %s", soundio_strerror(err));

    soundio_flush_events(soundio);

    int selected_device_index = -1;
    if (device_id) {
        const int device_count = soundio_output_device_count(soundio);
        for (int i = 0; i < device_count; i += 1) {
            SoundIoDevice* device = soundio_get_output_device(soundio, i);
            if (strcmp(device.id, device_id) == 0 && device.is_raw == raw) {
                selected_device_index = i;
                break;
            }
        }
    } else {
        selected_device_index = soundio_default_output_device_index(soundio);
    }

    if (selected_device_index < 0)
        panic("Output device not found");

    SoundIoDevice* device = soundio_get_output_device(soundio, selected_device_index);
    if (!device)
        panic("out of memory");

    printf_stderr("Output device: %s\n", device.name);

    SoundIoOutStream* outstream = soundio_outstream_create(device);
    outstream.format = SoundIoFormatFloat32NE;
    outstream.write_callback = &write_callback;
    outstream.underflow_callback = &underflow_callback;
    outstream.sample_rate = sample_rate;

    if (soundio_device_supports_format(device, SoundIoFormatFloat32NE)) {
        outstream.format = SoundIoFormatFloat32NE;
        write_sample = &write_sample_float32ne;
    } else if (soundio_device_supports_format(device, SoundIoFormatFloat64NE)) {
        outstream.format = SoundIoFormatFloat64NE;
        write_sample = &write_sample_float64ne;
    } else if (soundio_device_supports_format(device, SoundIoFormatS32NE)) {
        outstream.format = SoundIoFormatS32NE;
        write_sample = &write_sample_s32ne;
    } else if (soundio_device_supports_format(device, SoundIoFormatS16NE)) {
        outstream.format = SoundIoFormatS16NE;
        write_sample = &write_sample_s16ne;
    } else {
        printf_stderr("No suitable device format available.\n");
        return 1;
    }

    if (cast(bool) (err = soundio_outstream_open(outstream)))
        panic("unable to open device: %s", soundio_strerror(err));

    if (outstream.layout_error)
        printf_stderr("unable to set channel layout: %s\n", soundio_strerror(outstream.layout_error));

    if (cast(bool) (err = soundio_outstream_start(outstream)))
        panic("unable to start device: %s", soundio_strerror(err));

    while (seconds_offset < seconds_end)
        soundio_wait_events(soundio);

    soundio_outstream_destroy(outstream);
    soundio_device_unref(device);
    soundio_destroy(soundio);
    return 0;
}