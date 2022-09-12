/// Translated from C to D
module soundio.coreaudio;

version(OSX):
@nogc nothrow:
extern(C): __gshared:


import soundio.api;
import soundio.os;
import soundio.list;
import soundio.atomics;

//import coreaudio;
//import audiounit;

package struct SoundIoDeviceCoreAudio {
    AudioDeviceID device_id;
    UInt32 latency_frames;
}

alias SoundIoListAudioDeviceID = SOUNDIO_LIST!AudioDeviceID; // static

package struct SoundIoCoreAudio {
    SoundIoOsMutex* mutex;
    SoundIoOsCond* cond;
    SoundIoOsThread* thread;
    SoundIoAtomicFlag abort_flag;

    // this one is ready to be read with flush_events. protected by mutex
    SoundIoDevicesInfo* ready_devices_info;
    SoundIoAtomicBool have_devices_flag;
    SoundIoOsCond* have_devices_cond;
    SoundIoOsCond* scan_devices_cond;
    SoundIoListAudioDeviceID registered_listeners;

    SoundIoAtomicBool device_scan_queued;
    SoundIoAtomicBool service_restarted;
    int shutdown_err;
    bool emitted_shutdown_cb;
}

package struct SoundIoOutStreamCoreAudio {
    AudioComponentInstance instance;
    AudioBufferList* io_data;
    int buffer_index;
    int frames_left;
    int write_frame_count;
    double hardware_latency;
    float volume;
    SoundIoChannelArea[SOUNDIO_MAX_CHANNELS] areas;
}

package struct SoundIoInStreamCoreAudio {
    AudioComponentInstance instance;
    AudioBufferList* buffer_list;
    int frames_left;
    double hardware_latency;
    SoundIoChannelArea[SOUNDIO_MAX_CHANNELS] areas;
}
