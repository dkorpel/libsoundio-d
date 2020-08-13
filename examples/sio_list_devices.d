/// Translated from C to D
module sio_list_devices;

extern(C): @nogc: nothrow: __gshared:

import soundio.api;
import soundio.util: printf_stderr;

import core.stdc.stdio;
import core.stdc.string;

// list or keep a watch on audio devices
private extern(D) int usage(char* exe) {
    printf_stderr("Usage: %s [options]\n"
            ~ "Options:\n"
            ~ "  [--watch]\n"
            ~ "  [--backend dummy|alsa|pulseaudio|jack|coreaudio|wasapi]\n"
            ~ "  [--short]\n", exe);
    return 1;
}

private extern(D) void print_channel_layout(const(SoundIoChannelLayout)* layout) {
    if (layout.name) {
        printf_stderr("%s", layout.name);
    } else {
        printf_stderr("%s", soundio_get_channel_name(layout.channels[0]));
        for (int i = 1; i < layout.channel_count; i += 1) {
            printf_stderr(", %s", soundio_get_channel_name(layout.channels[i]));
        }
    }
}

private extern(D) bool short_output = false;

private extern(D) void print_device(SoundIoDevice* device, bool is_default) {
    const(char)* default_str = is_default ? " (default)" : "";
    const(char)* raw_str = device.is_raw ? " (raw)" : "";
    printf_stderr("%s%s%s\n", device.name, default_str, raw_str);
    if (short_output)
        return;
    printf_stderr("  id: %s\n", device.id);

    if (device.probe_error) {
        printf_stderr("  probe error: %s\n", soundio_strerror(device.probe_error));
    } else {
        printf_stderr("  channel layouts:\n");
        for (int i = 0; i < device.layout_count; i += 1) {
            printf_stderr("    ");
            print_channel_layout(&device.layouts[i]);
            printf_stderr("\n");
        }
        if (device.current_layout.channel_count > 0) {
            printf_stderr("  current layout: ");
            print_channel_layout(&device.current_layout);
            printf_stderr("\n");
        }

        printf_stderr("  sample rates:\n");
        for (int i = 0; i < device.sample_rate_count; i += 1) {
            SoundIoSampleRateRange* range = &device.sample_rates[i];
            printf_stderr("    %d - %d\n", range.min, range.max);

        }
        if (device.sample_rate_current)
            printf_stderr("  current sample rate: %d\n", device.sample_rate_current);
        printf_stderr("  formats: ");
        for (int i = 0; i < device.format_count; i += 1) {
            const(char)* comma = (i == device.format_count - 1) ? "" : ", ";
            printf_stderr("%s%s", soundio_format_string(device.formats[i]), comma);
        }
        printf_stderr("\n");
        if (device.current_format != SoundIoFormat.Invalid)
            printf_stderr("  current format: %s\n", soundio_format_string(device.current_format));

        printf_stderr("  min software latency: %0.8f sec\n", device.software_latency_min);
        printf_stderr("  max software latency: %0.8f sec\n", device.software_latency_max);
        if (device.software_latency_current != 0.0)
            printf_stderr("  current software latency: %0.8f sec\n", device.software_latency_current);

    }
    printf_stderr("\n");
}

private extern(D) int list_devices(SoundIo* soundio) {
    const int output_count = soundio_output_device_count(soundio);
    const int input_count = soundio_input_device_count(soundio);

    int default_output = soundio_default_output_device_index(soundio);
    int default_input = soundio_default_input_device_index(soundio);

    printf_stderr("--------Input Devices--------\n\n");
    for (int i = 0; i < input_count; i += 1) {
        SoundIoDevice* device = soundio_get_input_device(soundio, i);
        print_device(device, default_input == i);
        soundio_device_unref(device);
    }
    printf_stderr("\n--------Output Devices--------\n\n");
    for (int i = 0; i < output_count; i += 1) {
        SoundIoDevice* device = soundio_get_output_device(soundio, i);
        print_device(device, default_output == i);
        soundio_device_unref(device);
    }

    printf_stderr("\n%d devices found\n", input_count + output_count);
    return 0;
}

private extern(C) void on_devices_change(SoundIo* soundio) {
    printf_stderr("devices changed\n");
    list_devices(soundio);
}

int main(int argc, char** argv) {
    char* exe = argv[0];
    bool watch = false;
    SoundIoBackend backend = SoundIoBackend.None;

    for (int i = 1; i < argc; i += 1) {
        char* arg = argv[i];
        if (strcmp("--watch", arg) == 0) {
            watch = true;
        } else if (strcmp("--short", arg) == 0) {
            short_output = true;
        } else if (arg[0] == '-' && arg[1] == '-') {
            i += 1;
            if (i >= argc) {
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
            } else {
                return usage(exe);
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

    if (int err = (backend == SoundIoBackend.None) ?
        soundio_connect(soundio) : soundio_connect_backend(soundio, backend)) {
        printf_stderr("%s\n", soundio_strerror(err));
        return err;
    }

    if (watch) {
        soundio.on_devices_change = &on_devices_change;
        for (;;) {
            soundio_wait_events(soundio);
        }
    } else {
        soundio_flush_events(soundio);
        const err = list_devices(soundio);
        soundio_destroy(soundio);
        return err;
    }
}