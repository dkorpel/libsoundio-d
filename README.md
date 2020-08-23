# libsoundio-d
Translation from C to D of [libsoundio](https://github.com/andrewrk/libsoundio) ([commit a46b0f2](https://github.com/andrewrk/libsoundio/commit/a46b0f21c397cd095319f8c9feccf0f1e50e31ba)).

Libsoundio is a library for cross-platform real-time audio input and output.

It is licensed under the MIT License.
The translation is not affiliated with the original project.

Currently not all backends are translated.

| Backend                                                                  | Translated      | Used for                                   |
|--------------------------------------------------------------------------|-----------------|--------------------------------------------|
| [Jack](https://jackaudio.org)                                            | 🟠 Yes (untested)| See [JACK FAQ](https://jackaudio.org/faq/) |
| [Pulseaudio](https://en.wikipedia.org/wiki/PulseAudio)                   | ✔️ Yes           | Linux (higher-level)                       |
| [Alsa](https://en.wikipedia.org/wiki/Advanced_Linux_Sound_Architecture)  | ✔️ Yes           | Linux (lower-level)                        |
| [WASAPI](https://docs.microsoft.com/en-us/windows/win32/coreaudio/wasapi)| ✔️ Yes           | Windows                                    |
| [Core Audio](https://en.wikipedia.org/wiki/Core_Audio)                   | ❌ No            | macOS                                      |
| Dummy                                                                    | ✔️ Yes           | Testing                                    |

### Usage

Add this package as a dependency to your project.

dub.sdl:
```
dependency "libsoundio-d" version="~>1.0.0"
```

dub.json:
```
"dependencies": {
	"libsoundio-d": "~>1.0.0"
}
```

And then use it:
```D
import soundio.api;

void main() {
	SoundIo* soundio = soundio_create();
	soundio_connect(soundio);
	// your app
	soundio_destroy(soundio);
}
```

The configuration should be automatically selected based on your platform, but you can also choose one explicitly:
- linux
- windows
- dummy

dub.sdl:
```
subConfiguration "libsoundio-d" "dummy"
```

dub.json:
```
"subConfigurations": {
	"libsoundio-d": "dummy"
}
```

On Linux, you should have ALSA and PulseAudio installed (which you probably have by default, otherwise look up how to install it).

The following version identifiers are used:
- `SOUNDIO_HAVE_JACK`
- `SOUNDIO_HAVE_PULSEAUDIO`
- `SOUNDIO_HAVE_ALSA`
- `SOUNDIO_HAVE_COREAUDIO`
- `SOUNDIO_HAVE_WASAPI`

**Run the examples**

Assuming your current directory is the root of this repository:
```
dub run libsoundio-d:sine
dub run libsoundio-d:list-devices -- --short
dub run libsoundio-d:microphone -- --latency 0.05
dub run libsoundio-d:record -- output.bin
```

**Run the tests**
```
dub run libsoundio-d:backend-disconnect-recover
dub run libsoundio-d:latency
dub run libsoundio-d:overflow
dub run libsoundio-d:underflow
dub run libsoundio-d:unit-tests
```

### Translation events

The translation is closely converting C-syntax to D-syntax, no attempt to change the style to idiomatic D has been made.
There are a few exceptions where certain constructs had to be changed however.

- ALSA defines certain structs with an unknown size at compile time.
There are specific `alloca` macros that allocate these structs on the stack, and libsoundio uses these.
I translated these with malloc and free variants, because alloca has its own share of problems.

- Libsoundio has certain `static` functions with the same name across backends: both ALSA and Pulse have `probe_device` and `my_flush_events`.
Since D does not have C's notion of `static` functions (even `private` functions emit symbols), this introduces a name clash.
Worse, because DMD emits weak symbols, it gives no multiple definition error, but instead silently calls the wrong function:
The Pulse backend calls `probe_device` from the alsa backend instead of its own.
This is mitigated by making those functions `extern(D)` giving them unique names.

- D does not have C bindings of `stdatomic.h`, so I used equivalent functionality from `core.atomic`.
`core.atomic` has no direct equivalent of 'flag test and set'.
I initially translated as `cas` (compare and swap), but return value needed to be negated.
`atomicFetchAdd` was added in dmd 2.089 and is not supported in LDC as of 1.22, so I used `atomicOp!"+="` instead.

- On Windows `InterlockedIncrement` and `InterlockedDecrement` are not in the shipped import library "Kernel32.lib".
I replaced it with a corresponding `atomicOp!"+="` and `atomicOp!"-="`.

- On 32-bit Windows, 64-bit atomic operations are not supported.
The `SoundIoRingBuffer` uses `ulong` for its read and write offset, even on 32-bit.
I changed these to a `size_t` instead.

- Use of `fprintf(sderr, ...)` on Windows with `extern(C) main` triggers [issue 20532](https://issues.dlang.org/show_bug.cgi?id=20532). A custom `printf_stderr` function was made to work around this.
