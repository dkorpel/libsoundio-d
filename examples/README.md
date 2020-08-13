
# Examples

These examples are translated from the original C examples, so they are not idiomatic D.

Note that the dub commands below should be executed from the root of the repository, not this examples folder.

### Sine

Plays a simple sine wave sound.
```
dub run libsoundio-d:sine
```

### List devices

Lists available input- and output devices.

Without the `--short` flag, it displays each device's id, which can be passed as an argument to the other examples to select an input/output device.
```
dub run libsoundio-d:list-devices
dub run libsoundio-d:list-devices -- --short
```

### Microphone

Reads from an input device (microphone) and pipe it to an output device (speaker / headphones).
Watch out that your microphone is not too close to the speaker or you might get a feedback loop.
```
dub run libsoundio-d:microphone -- --latency 0.05
```

### Record

Records sound from an input device and saves it as a binary file.
```
dub run libsoundio-d:record -- test.bin
```
