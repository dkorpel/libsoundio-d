/// Translated from C to D
module soundio.soundio_private;

@nogc nothrow:
extern(C): __gshared:


public import soundio.api;
public import soundio.config;
public import soundio.list;

version(SOUNDIO_HAVE_JACK) {
    public import soundio.jack;
}
version(SOUNDIO_HAVE_PULSEAUDIO) {
    public import soundio.pulseaudio;
}
version(SOUNDIO_HAVE_ALSA) {
    public import soundio.alsa;
}
version(SOUNDIO_HAVE_COREAUDIO) {
    public import soundio.coreaudio;
}
version(SOUNDIO_HAVE_WASAPI) {
    public import soundio.wasapi;
}

public import soundio.dummy;

package:

struct SoundIoBackendData {
    union {
        version(SOUNDIO_HAVE_JACK) {
            SoundIoJack jack;
        }
        version(SOUNDIO_HAVE_PULSEAUDIO) {
            SoundIoPulseAudio pulseaudio;
        }
        version(SOUNDIO_HAVE_ALSA) {
            SoundIoAlsa alsa;
        }
        version(SOUNDIO_HAVE_COREAUDIO) {
            SoundIoCoreAudio coreaudio;
        }
        version(SOUNDIO_HAVE_WASAPI) {
            SoundIoWasapi wasapi;
        }
        SoundIoDummy dummy;
    }
}

struct SoundIoDeviceBackendData {
    union {
        version(SOUNDIO_HAVE_JACK) {
            SoundIoDeviceJack jack;
        }
        version(SOUNDIO_HAVE_PULSEAUDIO) {
            SoundIoDevicePulseAudio pulseaudio;
        }
        version(SOUNDIO_HAVE_ALSA) {
            SoundIoDeviceAlsa alsa;
        }
        version(SOUNDIO_HAVE_COREAUDIO) {
            SoundIoDeviceCoreAudio coreaudio;
        }
        version(SOUNDIO_HAVE_WASAPI) {
            SoundIoDeviceWasapi wasapi;
        }
        SoundIoDeviceDummy dummy;
    }
}

struct SoundIoOutStreamBackendData {
    union {
        version(SOUNDIO_HAVE_JACK) {
            SoundIoOutStreamJack jack;
        }
        version(SOUNDIO_HAVE_PULSEAUDIO) {
            SoundIoOutStreamPulseAudio pulseaudio;
        }
        version(SOUNDIO_HAVE_ALSA) {
            SoundIoOutStreamAlsa alsa;
        }
        version(SOUNDIO_HAVE_COREAUDIO) {
            SoundIoOutStreamCoreAudio coreaudio;
        }
        version(SOUNDIO_HAVE_WASAPI) {
            SoundIoOutStreamWasapi wasapi;
        }
        SoundIoOutStreamDummy dummy;
    }
}

struct SoundIoInStreamBackendData {
    union {
        version(SOUNDIO_HAVE_JACK) {
            SoundIoInStreamJack jack;
        }
        version(SOUNDIO_HAVE_PULSEAUDIO) {
            SoundIoInStreamPulseAudio pulseaudio;
        }
        version(SOUNDIO_HAVE_ALSA) {
            SoundIoInStreamAlsa alsa;
        }
        version(SOUNDIO_HAVE_COREAUDIO) {
            SoundIoInStreamCoreAudio coreaudio;
        }
        version(SOUNDIO_HAVE_WASAPI) {
            SoundIoInStreamWasapi wasapi;
        }
        SoundIoInStreamDummy dummy;
    }
}

alias SoundIoListDevicePtr = SOUNDIO_LIST!(SoundIoDevice*);

struct SoundIoDevicesInfo {
    SoundIoListDevicePtr input_devices;
    SoundIoListDevicePtr output_devices;
    // can be -1 when default device is unknown
    int default_output_index;
    int default_input_index;
}

struct SoundIoOutStreamPrivate {
    SoundIoOutStream pub;
    SoundIoOutStreamBackendData backend_data;
}

struct SoundIoInStreamPrivate {
    SoundIoInStream pub;
    SoundIoInStreamBackendData backend_data;
}

struct SoundIoPrivate {
    extern(C): @nogc: nothrow:
    SoundIo pub;

    // Safe to read from a single thread without a mutex.
    SoundIoDevicesInfo* safe_devices_info;

    void function(SoundIoPrivate*) destroy;
    void function(SoundIoPrivate*) flush_events;
    void function(SoundIoPrivate*) wait_events;
    void function(SoundIoPrivate*) wakeup;
    void function(SoundIoPrivate*) force_device_scan;

    int function(SoundIoPrivate*, SoundIoOutStreamPrivate*) outstream_open;
    void function(SoundIoPrivate*, SoundIoOutStreamPrivate*) outstream_destroy;
    int function(SoundIoPrivate*, SoundIoOutStreamPrivate*) outstream_start;
    int function(SoundIoPrivate*, SoundIoOutStreamPrivate*, SoundIoChannelArea** out_areas, int* out_frame_count) outstream_begin_write;
    int function(SoundIoPrivate*, SoundIoOutStreamPrivate*) outstream_end_write;
    int function(SoundIoPrivate*, SoundIoOutStreamPrivate*) outstream_clear_buffer;
    int function(SoundIoPrivate*, SoundIoOutStreamPrivate*, bool pause) outstream_pause;
    int function(SoundIoPrivate*, SoundIoOutStreamPrivate*, double* out_latency) outstream_get_latency;
    int function(SoundIoPrivate*, SoundIoOutStreamPrivate*, float volume) outstream_set_volume;

    int function(SoundIoPrivate*, SoundIoInStreamPrivate*) instream_open;
    void function(SoundIoPrivate*, SoundIoInStreamPrivate*) instream_destroy;
    int function(SoundIoPrivate*, SoundIoInStreamPrivate*) instream_start;
    int function(SoundIoPrivate*, SoundIoInStreamPrivate*, SoundIoChannelArea** out_areas, int* out_frame_count) instream_begin_read;
    int function(SoundIoPrivate*, SoundIoInStreamPrivate*) instream_end_read;
    int function(SoundIoPrivate*, SoundIoInStreamPrivate*, bool pause) instream_pause;
    int function(SoundIoPrivate*, SoundIoInStreamPrivate*, double* out_latency) instream_get_latency;

    SoundIoBackendData backend_data;
}

alias SoundIoListSampleRateRange = SOUNDIO_LIST!(SoundIoSampleRateRange);

struct SoundIoDevicePrivate {
    extern(C): @nogc: nothrow:
    SoundIoDevice pub;
    SoundIoDeviceBackendData backend_data;
    void function(SoundIoDevicePrivate*) destruct;
    SoundIoSampleRateRange prealloc_sample_rate_range;
    SoundIoListSampleRateRange sample_rates;
    SoundIoFormat prealloc_format;
}

void soundio_destroy_devices_info(SoundIoDevicesInfo* devices_info);

immutable int SOUNDIO_MIN_SAMPLE_RATE = 8000;
immutable int SOUNDIO_MAX_SAMPLE_RATE = 5644_800;
