/// Translated from C to D
module backend_disconnect_recover;

extern(C): @nogc: nothrow:

import soundio.api;
import soundio.util: printf_stderr;

import core.stdc.stdio;
import core.stdc.stdarg;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.math;

version (Posix)
    import core.sys.posix.unistd;
else version(Windows)
    import core.sys.windows.winbase;
else
    static assert(false);

private void panic(T...)(const(char)* format, T args) {
    printf_stderr(format, args);
    printf_stderr("\n");
    abort();
}

private int usage(char* exe) {
    printf_stderr("Usage: %s [options]\n"
            ~ "Options:\n"
            ~ "  [--backend dummy|alsa|pulseaudio|jack|coreaudio|wasapi]\n"
            ~ "  [--timeout seconds]\n", exe);
    return 1;
}

private SoundIoBackend backend = SoundIoBackend.None;

private bool severed = false;

private void on_backend_disconnect(SoundIo* soundio, int err) {
    printf_stderr("OK backend disconnected with '%s'.\n", soundio_strerror(err));
    severed = true;
}

int main(int argc, char** argv) {
    char* exe = argv[0];
    int timeout = 0;
    for (int i = 1; i < argc; i += 1) {
        char* arg = argv[i];
        if (arg[0] == '-' && arg[1] == '-') {
            i += 1;
            if (i >= argc) {
                return usage(exe);
            } else if (strcmp(arg, "--timeout") == 0) {
                timeout = atoi(argv[i]);
            } else if (strcmp(arg, "--backend") == 0) {
                if (strcmp("-dummy", argv[i]) == 0) {
                    backend = SoundIoBackendDummy;
                } else if (strcmp("alsa", argv[i]) == 0) {
                    backend = SoundIoBackendAlsa;
                } else if (strcmp("pulseaudio", argv[i]) == 0) {
                    backend = SoundIoBackendPulseAudio;
                } else if (strcmp("jack", argv[i]) == 0) {
                    backend = SoundIoBackendJack;
                } else if (strcmp("coreaudio", argv[i]) == 0) {
                    backend = SoundIoBackendCoreAudio;
                } else if (strcmp("wasapi", argv[i]) == 0) {
                    backend = SoundIoBackendWasapi;
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

    SoundIo* soundio;
    if (!cast(bool)(soundio = soundio_create()))
        panic("out of memory");

    int err = (backend == SoundIoBackendNone) ?
        soundio_connect(soundio) : soundio_connect_backend(soundio, backend);

    if (err)
        panic("error connecting: %s", soundio_strerror(err));

    soundio.on_backend_disconnect = &on_backend_disconnect;

    printf_stderr("OK connected to %s. Now cause the backend to disconnect.\n",
            soundio_backend_name(soundio.current_backend));

    while (!severed)
        soundio_wait_events(soundio);

    soundio_disconnect(soundio);

    if (timeout > 0) {
        printf_stderr("OK sleeping for %d seconds\n", timeout);
        version(Posix)
            sleep(timeout);
        else version(Windows)
            Sleep(timeout * 1000);
        else
            static assert(false);
    }

    printf_stderr("OK cleaned up. Reconnecting...\n");

    err = (backend == SoundIoBackendNone) ?
        soundio_connect(soundio) : soundio_connect_backend(soundio, backend);

    if (err)
        panic("error reconnecting: %s", soundio_strerror(err));

    printf_stderr("OK reconnected successfully to %s\n", soundio_backend_name(soundio.current_backend));

    soundio_flush_events(soundio);

    printf_stderr("OK test passed\n");

    return 0;
}
