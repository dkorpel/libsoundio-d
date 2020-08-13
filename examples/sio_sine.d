/// Translated from C to D
module sio_sine;

extern(C): @nogc: nothrow: __gshared:

import soundio.api;
import soundio.util: printf_stderr;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.stdint;
import core.stdc.math;

/// Note: the original C example assumes an amplitude of 1, but that is really loud,
/// so I added this constant to make the sound less annoying
enum sineAmplitude = 0.25;

static int usage(char* exe) {
    printf_stderr("Usage: %s [options]\n"
            ~ "Options:\n"
            ~ "  [--backend dummy|alsa|pulseaudio|jack|coreaudio|wasapi]\n"
            ~ "  [--device id]\n"
            ~ "  [--raw]\n"
            ~ "  [--name stream_name]\n"
            ~ "  [--latency seconds]\n"
            ~ "  [--sample-rate hz]\n"
            , exe);
    return 1;
}

static void write_sample_s16ne(char* ptr, double sample) {
    short* buf = cast(short*)ptr;
    double range = cast(double)short.max - cast(double)short.min;
    double val = sample * range / 2.0;
    *buf = cast(short) val;
}

static void write_sample_s32ne(char* ptr, double sample) {
    int* buf = cast(int*)ptr;
    double range = cast(double)int.max - cast(double)int.min;
    double val = sample * range / 2.0;
    *buf = cast(int) val;
}

static void write_sample_float32ne(char* ptr, double sample) {
    float* buf = cast(float*)ptr;
    *buf = sample;
}

static void write_sample_float64ne(char* ptr, double sample) {
    double* buf = cast(double*)ptr;
    *buf = sample;
}

static void function(char* ptr, double sample) write_sample;
static const(double) PI = 3.14159265358979323846264338328;
static double seconds_offset = 0.0;
static /*volatile*/ bool want_pause = false;
static void write_callback(SoundIoOutStream* outstream, int frame_count_min, int frame_count_max) {
    double float_sample_rate = outstream.sample_rate;
    double seconds_per_frame = 1.0 / float_sample_rate;
    SoundIoChannelArea* areas;

    int frames_left = frame_count_max;

    for (;;) {
        int frame_count = frames_left;
        if (auto err = soundio_outstream_begin_write(outstream, &areas, &frame_count)) {
            printf_stderr("unrecoverable stream error: %s\n", soundio_strerror(err));
            exit(1);
        }

        if (!frame_count)
            break;

        const(SoundIoChannelLayout)* layout = &outstream.layout;

        double pitch = 440.0;
        double radians_per_second = pitch * 2.0 * PI;
        for (int frame = 0; frame < frame_count; frame += 1) {
            double sample = sineAmplitude * sin((seconds_offset + frame * seconds_per_frame) * radians_per_second);
            for (int channel = 0; channel < layout.channel_count; channel += 1) {
                write_sample(areas[channel].ptr, sample);
                areas[channel].ptr += areas[channel].step;
            }
        }
        seconds_offset = fmod(seconds_offset + seconds_per_frame * frame_count, 1.0);

        if (auto err = soundio_outstream_end_write(outstream)) {
            if (err == SoundIoError.Underflow)
                return;
            printf_stderr("unrecoverable stream error: %s\n", soundio_strerror(err));
            exit(1);
        }

        frames_left -= frame_count;
        if (frames_left <= 0)
            break;
    }

    soundio_outstream_pause(outstream, want_pause);
}

static void underflow_callback(SoundIoOutStream* outstream) {
    static int count = 0;
    printf_stderr("underflow %d\n", count++);
}

int main(int argc, char** argv) {
    char* exe = argv[0];
    SoundIoBackend backend = SoundIoBackend.None;
    char* device_id = null;
    bool raw = false;
    char* stream_name = null;
    double latency = 0.0;
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
                        backend = SoundIoBackend.Dummy;
                    } else if (strcmp(argv[i], "alsa") == 0) {
                        backend = SoundIoBackend.Alsa;
                    } else if (strcmp(argv[i], "pulseaudio") == 0) {
                        backend = SoundIoBackend.PulseAudio;
                    } else if (strcmp(argv[i], "jack") == 0) {
                        backend = SoundIoBackend.Jack;
                    } else if (strcmp(argv[i], "coreaudio") == 0) {
                        backend = SoundIoBackend.CoreAudio;
                    } else if (strcmp(argv[i], "wasapi") == 0) {
                        backend = SoundIoBackend.Wasapi;
                    } else {
                        printf_stderr("Invalid backend: %s\n", argv[i]);
                        return 1;
                    }
                } else if (strcmp(arg, "--device") == 0) {
                    device_id = argv[i];
                } else if (strcmp(arg, "--name") == 0) {
                    stream_name = argv[i];
                } else if (strcmp(arg, "--latency") == 0) {
                    latency = atof(argv[i]);
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

    SoundIo* soundio = soundio_create();
    if (!soundio) {
        printf_stderr("out of memory\n");
        return 1;
    }

    if (auto err = (backend == SoundIoBackend.None) ? soundio_connect(soundio) : soundio_connect_backend(soundio, backend)) {
        printf_stderr("Unable to connect to backend: %s\n", soundio_strerror(err));
        return 1;
    }

    printf_stderr("Backend: %s\n", soundio_backend_name(soundio.current_backend));

    soundio_flush_events(soundio);

    int selected_device_index = -1;
    if (device_id) {
        int device_count = soundio_output_device_count(soundio);
        for (int i = 0; i < device_count; i += 1) {
            SoundIoDevice* device = soundio_get_output_device(soundio, i);
            bool select_this_one = strcmp(device.id, device_id) == 0 && device.is_raw == raw;
            soundio_device_unref(device);
            if (select_this_one) {
                selected_device_index = i;
                break;
            }
        }
    } else {
        selected_device_index = soundio_default_output_device_index(soundio);
    }

    if (selected_device_index < 0) {
        printf_stderr("Output device not found\n");
        return 1;
    }

    SoundIoDevice* device = soundio_get_output_device(soundio, selected_device_index);
    if (!device) {
        printf_stderr("out of memory\n");
        return 1;
    }

    printf_stderr("Output device: %s\n", device.name);

    if (device.probe_error) {
        printf_stderr("Cannot probe device: %s\n", soundio_strerror(device.probe_error));
        return 1;
    }

    SoundIoOutStream* outstream = soundio_outstream_create(device);
    if (!outstream) {
        printf_stderr("out of memory\n");
        return 1;
    }

    outstream.write_callback = &write_callback;
    outstream.underflow_callback = &underflow_callback;
    outstream.name = stream_name;
    outstream.software_latency = latency;
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

    if (auto err = soundio_outstream_open(outstream)) {
        printf_stderr("unable to open device: %s", soundio_strerror(err));
        return 1;
    }

    printf_stderr("Software latency: %f\n", outstream.software_latency);
    printf_stderr(
            "'p\\n' - pause\n"
            ~ "'u\\n' - unpause\n"
            ~ "'P\\n' - pause from within callback\n"
            ~ "'c\\n' - clear buffer\n"
            ~ "'q\\n' - quit\n");

    if (outstream.layout_error)
        printf_stderr("unable to set channel layout: %s\n", soundio_strerror(outstream.layout_error));

    if (auto err = soundio_outstream_start(outstream)) {
        printf_stderr("unable to start device: %s\n", soundio_strerror(err));
        return 1;
    }

    for (;;) {
        soundio_flush_events(soundio);
        version(CRuntime_Microsoft) {
            int c = 0; // stdin not initialized
            if (c == 0) continue;
        } else {
            int c = getc(stdin);
        }
        if (c == 'p') {
            printf_stderr("pausing result: %s\n",
                    soundio_strerror(soundio_outstream_pause(outstream, true)));
        } else if (c == 'P') {
            want_pause = true;
        } else if (c == 'u') {
            want_pause = false;
            printf_stderr("unpausing result: %s\n",
                    soundio_strerror(soundio_outstream_pause(outstream, false)));
        } else if (c == 'c') {
            printf_stderr("clear buffer result: %s\n",
                    soundio_strerror(soundio_outstream_clear_buffer(outstream)));
        } else if (c == 'q') {
            break;
        } else if (c == '\r' || c == '\n') {
            // ignore
        } else {
            printf_stderr("Unrecognized command: %c\n", c);
        }
    }

    soundio_outstream_destroy(outstream);
    soundio_device_unref(device);
    soundio_destroy(soundio);
    return 0;
}