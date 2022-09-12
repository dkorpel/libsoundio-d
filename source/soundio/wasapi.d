/// Translated from C to D
module soundio.wasapi;

version(Windows):
@nogc nothrow:
extern(C): __gshared:


import soundio.api;
import soundio.soundio_private;
import soundio.os;
import soundio.list;
import soundio.atomics;
import soundio.headers.wasapiheader;
import core.stdc.stdio;
import core.sys.windows.windows;
import core.stdc.stdlib: free;
import core.stdc.string: strlen;
import soundio.headers.wasapiheader;
import soundio.headers.wasapiheader: WAVEFORMATEX;

import core.atomic; // atomicOp!"+=" to replace InterlockedIncrement

// @nogc nothrow definitions
extern(Windows) {
    void CoTaskMemFree(PVOID);
    HRESULT CoCreateInstance(REFCLSID, LPUNKNOWN, DWORD, REFIID, PVOID*);
}

private:

enum AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM = 0x80000000;
enum AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY = 0x08000000;

package struct SoundIoDeviceWasapi {
    double period_duration;
    IMMDevice* mm_device;
}

package struct SoundIoWasapi {
    SoundIoOsMutex* mutex;
    SoundIoOsCond* cond;
    SoundIoOsCond* scan_devices_cond;
    SoundIoOsMutex* scan_devices_mutex;
    SoundIoOsThread* thread;
    bool abort_flag;
    // this one is ready to be read with flush_events. protected by mutex
    SoundIoDevicesInfo* ready_devices_info;
    bool have_devices_flag;
    bool device_scan_queued;
    int shutdown_err;
    bool emitted_shutdown_cb;

    IMMDeviceEnumerator* device_enumerator;
    IMMNotificationClient device_events;
    LONG device_events_refs;
}

package struct SoundIoOutStreamWasapi {
    IAudioClient* audio_client;
    IAudioClockAdjustment* audio_clock_adjustment;
    IAudioRenderClient* audio_render_client;
    IAudioSessionControl* audio_session_control;
    ISimpleAudioVolume* audio_volume_control;
    LPWSTR stream_name;
    bool need_resample;
    SoundIoOsThread* thread;
    SoundIoOsMutex* mutex;
    SoundIoOsCond* cond;
    SoundIoOsCond* start_cond;
    SoundIoAtomicFlag thread_exit_flag;
    bool is_raw;
    int writable_frame_count;
    UINT32 buffer_frame_count;
    int write_frame_count;
    HANDLE h_event;
    SoundIoAtomicBool desired_pause_state;
    SoundIoAtomicFlag pause_resume_flag;
    SoundIoAtomicFlag clear_buffer_flag;
    bool is_paused;
    bool open_complete;
    int open_err;
    bool started;
    UINT32 min_padding_frames;
    float volume;
    SoundIoChannelArea[SOUNDIO_MAX_CHANNELS] areas;
}

package struct SoundIoInStreamWasapi {
    IAudioClient* audio_client;
    IAudioCaptureClient* audio_capture_client;
    IAudioSessionControl* audio_session_control;
    LPWSTR stream_name;
    SoundIoOsThread* thread;
    SoundIoOsMutex* mutex;
    SoundIoOsCond* cond;
    SoundIoOsCond* start_cond;
    SoundIoAtomicFlag thread_exit_flag;
    bool is_raw;
    int readable_frame_count;
    UINT32 buffer_frame_count;
    int read_frame_count;
    HANDLE h_event;
    bool is_paused;
    bool open_complete;
    int open_err;
    bool started;
    char* read_buf;
    int read_buf_frames_left;
	int opened_buf_frames;
    SoundIoChannelArea[SOUNDIO_MAX_CHANNELS] areas;
}

enum E_NOTFOUND = 0x80070490;

/*
// In C++ mode, IsEqualGUID() takes its arguments by reference
enum string IS_EQUAL_GUID(string a, string b) = ` IsEqualGUID(*(a), *(b))`;
enum string IS_EQUAL_IID(string a, string b) = ` IsEqualIID((a), *(b))`;

// And some constants are passed by reference
enum IID_IAUDIOCLIENT =                      (IID_IAudioClient);
enum IID_IMMENDPOINT =                       (IID_IMMEndpoint);
enum IID_IAUDIOCLOCKADJUSTMENT =             (IID_IAudioClockAdjustment);
enum IID_IAUDIOSESSIONCONTROL =              (IID_IAudioSessionControl);
enum IID_IAUDIORENDERCLIENT =                (IID_IAudioRenderClient);
enum IID_IMMDEVICEENUMERATOR =               (IID_IMMDeviceEnumerator);
enum IID_IAUDIOCAPTURECLIENT =               (IID_IAudioCaptureClient);
enum IID_ISIMPLEAUDIOVOLUME =                (IID_ISimpleAudioVolume);
enum CLSID_MMDEVICEENUMERATOR =              (CLSID_MMDeviceEnumerator);
enum PKEY_DEVICE_FRIENDLYNAME =              (PKEY_Device_FriendlyName);
enum PKEY_AUDIOENGINE_DEVICEFORMAT =         (PKEY_AudioEngine_DeviceFormat);
*/

// And some GUID are never implemented (Ignoring the INITGUID define)
static const(CLSID) CLSID_MMDeviceEnumerator = CLSID(
    0xBCDE0395, 0xE52F, 0x467C, [0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E]
);
// TODO: Verify this equals __uuidof(MMDeviceEnumerator);
// class DECLSPEC_UUID("BCDE0395-E52F-467C-8E3D-C4579291692E")
// MMDeviceEnumerator;

static const(IID) IID_IMMDeviceEnumerator = IID(
    //MIDL_INTERFACE("A95664D2-9614-4F35-A746-DE8DB63617E6")
    0xa95664d2, 0x9614, 0x4f35, [0xa7, 0x46, 0xde, 0x8d, 0xb6, 0x36, 0x17, 0xe6]
);
static const(IID) IID_IMMNotificationClient = IID(
    //MIDL_INTERFACE("7991EEC9-7E89-4D85-8390-6C703CEC60C0")
    0x7991eec9, 0x7e89, 0x4d85, [0x83, 0x90, 0x6c, 0x70, 0x3c, 0xec, 0x60, 0xc0]
);
static const(IID) IID_IAudioClient = IID(
    //MIDL_INTERFACE("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2")
    0x1cb9ad4c, 0xdbfa, 0x4c32, [0xb1, 0x78, 0xc2, 0xf5, 0x68, 0xa7, 0x03, 0xb2]
);
static const(IID) IID_IAudioRenderClient = IID(
    //MIDL_INTERFACE("F294ACFC-3146-4483-A7BF-ADDCA7C260E2")
    0xf294acfc, 0x3146, 0x4483, [0xa7, 0xbf, 0xad, 0xdc, 0xa7, 0xc2, 0x60, 0xe2]
);
static const(IID) IID_IAudioSessionControl = IID(
    //MIDL_INTERFACE("F4B1A599-7266-4319-A8CA-E70ACB11E8CD")
    0xf4b1a599, 0x7266, 0x4319, [0xa8, 0xca, 0xe7, 0x0a, 0xcb, 0x11, 0xe8, 0xcd]
);
static const(IID) IID_IAudioSessionEvents = IID(
    //MIDL_INTERFACE("24918ACC-64B3-37C1-8CA9-74A66E9957A8")
    0x24918acc, 0x64b3, 0x37c1, [0x8c, 0xa9, 0x74, 0xa6, 0x6e, 0x99, 0x57, 0xa8]
);
static const(IID) IID_IMMEndpoint = IID(
    //MIDL_INTERFACE("1BE09788-6894-4089-8586-9A2A6C265AC5")
    0x1be09788, 0x6894, 0x4089, [0x85, 0x86, 0x9a, 0x2a, 0x6c, 0x26, 0x5a, 0xc5]
);
static const(IID) IID_IAudioClockAdjustment = IID(
    //MIDL_INTERFACE("f6e4c0a0-46d9-4fb8-be21-57a3ef2b626c")
    0xf6e4c0a0, 0x46d9, 0x4fb8, [0xbe, 0x21, 0x57, 0xa3, 0xef, 0x2b, 0x62, 0x6c]
);
static const(IID) IID_IAudioCaptureClient = IID(
    //MIDL_INTERFACE("C8ADBD64-E71E-48a0-A4DE-185C395CD317")
    0xc8adbd64, 0xe71e, 0x48a0, [0xa4, 0xde, 0x18, 0x5c, 0x39, 0x5c, 0xd3, 0x17]
);
static const(IID) IID_ISimpleAudioVolume = IID(
    //MIDL_INTERFACE("87ce5498-68d6-44e5-9215-6da47ef883d8")
    0x87ce5498, 0x68d6, 0x44e5,[0x92, 0x15, 0x6d, 0xa4, 0x7e, 0xf8, 0x83, 0xd8 ]
);

extern(Windows) BOOL IsEqualGUID(REFGUID rguid1, REFGUID rguid2);
alias IsEqualIID = IsEqualGUID;
bool IS_EQUAL_GUID(const(GUID)* a, const(GUID)* b) { return cast(bool) IsEqualGUID(a, b);}
bool IS_EQUAL_IID(const(IID)* a, const(IID)* b) { return cast(bool) IsEqualIID(a, b);}

enum IID_IAUDIOCLIENT = (&IID_IAudioClient);
enum IID_IMMENDPOINT = (&IID_IMMEndpoint);
enum PKEY_DEVICE_FRIENDLYNAME = (&PKEY_Device_FriendlyName);
enum PKEY_AUDIOENGINE_DEVICEFORMAT = (&PKEY_AudioEngine_DeviceFormat);
enum CLSID_MMDEVICEENUMERATOR = (&CLSID_MMDeviceEnumerator);
enum IID_IAUDIOCLOCKADJUSTMENT = (&IID_IAudioClockAdjustment);
enum IID_IAUDIOSESSIONCONTROL = (&IID_IAudioSessionControl);
enum IID_IAUDIORENDERCLIENT = (&IID_IAudioRenderClient);
enum IID_IMMDEVICEENUMERATOR = (&IID_IMMDeviceEnumerator);
enum IID_IAUDIOCAPTURECLIENT = (&IID_IAudioCaptureClient);
enum IID_ISIMPLEAUDIOVOLUME = (&IID_ISimpleAudioVolume);

// Attempting to use the Windows-supplied versions of these constants resulted
// in `undefined reference` linker errors.
static const(GUID) SOUNDIO_KSDATAFORMAT_SUBTYPE_IEEE_FLOAT = GUID(
    0x00000003,0x0000,0x0010, [0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71]);

static const(GUID) SOUNDIO_KSDATAFORMAT_SUBTYPE_PCM = GUID(
    0x00000001,0x0000,0x0010, [0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71]);

// Adding more common sample rates helps the heuristics; feel free to do that.
static int[19] test_sample_rates = [
    8000,
    11025,
    16000,
    22050,
    32000,
    37800,
    44056,
    44100,
    47250,
    48000,
    50000,
    50400,
    88200,
    96000,
    176400,
    192000,
    352800,
    2822400,
    5644800,
];

// If you modify this list, also modify `to_wave_format_format` appropriately.
immutable SoundIoFormat[6] test_formats = [
    SoundIoFormat.U8,
    SoundIoFormat.S16LE,
    SoundIoFormat.S24LE,
    SoundIoFormat.S32LE,
    SoundIoFormat.Float32LE,
    SoundIoFormat.Float64LE,
];

// If you modify this list, also modify `to_wave_format_layout` appropriately.
immutable SoundIoChannelLayoutId[7] test_layouts = [
    SoundIoChannelLayoutId.Mono,
    SoundIoChannelLayoutId.Stereo,
    SoundIoChannelLayoutId.Quad,
    SoundIoChannelLayoutId._4Point0,
    SoundIoChannelLayoutId._5Point1,
    SoundIoChannelLayoutId._7Point1,
    SoundIoChannelLayoutId._5Point1Back,
];

/*
// useful for debugging but no point in compiling into binary
static const char *hresult_to_str(HRESULT hr) {
    switch (hr) {
        default: return "(unknown)";
        case AUDCLNT_E_NOT_INITIALIZED: return "AUDCLNT_E_NOT_INITIALIZED";
        case AUDCLNT_E_ALREADY_INITIALIZED: return "AUDCLNT_E_ALREADY_INITIALIZED";
        case AUDCLNT_E_WRONG_ENDPOINT_TYPE: return "AUDCLNT_E_WRONG_ENDPOINT_TYPE";
        case AUDCLNT_E_DEVICE_INVALIDATED: return "AUDCLNT_E_DEVICE_INVALIDATED";
        case AUDCLNT_E_NOT_STOPPED: return "AUDCLNT_E_NOT_STOPPED";
        case AUDCLNT_E_BUFFER_TOO_LARGE: return "AUDCLNT_E_BUFFER_TOO_LARGE";
        case AUDCLNT_E_OUT_OF_ORDER: return "AUDCLNT_E_OUT_OF_ORDER";
        case AUDCLNT_E_UNSUPPORTED_FORMAT: return "AUDCLNT_E_UNSUPPORTED_FORMAT";
        case AUDCLNT_E_INVALID_SIZE: return "AUDCLNT_E_INVALID_SIZE";
        case AUDCLNT_E_DEVICE_IN_USE: return "AUDCLNT_E_DEVICE_IN_USE";
        case AUDCLNT_E_BUFFER_OPERATION_PENDING: return "AUDCLNT_E_BUFFER_OPERATION_PENDING";
        case AUDCLNT_E_THREAD_NOT_REGISTERED: return "AUDCLNT_E_THREAD_NOT_REGISTERED";
        case AUDCLNT_E_EXCLUSIVE_MODE_NOT_ALLOWED: return "AUDCLNT_E_EXCLUSIVE_MODE_NOT_ALLOWED";
        case AUDCLNT_E_ENDPOINT_CREATE_FAILED: return "AUDCLNT_E_ENDPOINT_CREATE_FAILED";
        case AUDCLNT_E_SERVICE_NOT_RUNNING: return "AUDCLNT_E_SERVICE_NOT_RUNNING";
        case AUDCLNT_E_EVENTHANDLE_NOT_EXPECTED: return "AUDCLNT_E_EVENTHANDLE_NOT_EXPECTED";
        case AUDCLNT_E_EXCLUSIVE_MODE_ONLY: return "AUDCLNT_E_EXCLUSIVE_MODE_ONLY";
        case AUDCLNT_E_BUFDURATION_PERIOD_NOT_EQUAL: return "AUDCLNT_E_BUFDURATION_PERIOD_NOT_EQUAL";
        case AUDCLNT_E_EVENTHANDLE_NOT_SET: return "AUDCLNT_E_EVENTHANDLE_NOT_SET";
        case AUDCLNT_E_INCORRECT_BUFFER_SIZE: return "AUDCLNT_E_INCORRECT_BUFFER_SIZE";
        case AUDCLNT_E_BUFFER_SIZE_ERROR: return "AUDCLNT_E_BUFFER_SIZE_ERROR";
        case AUDCLNT_E_CPUUSAGE_EXCEEDED: return "AUDCLNT_E_CPUUSAGE_EXCEEDED";
        case AUDCLNT_E_BUFFER_ERROR: return "AUDCLNT_E_BUFFER_ERROR";
        case AUDCLNT_E_BUFFER_SIZE_NOT_ALIGNED: return "AUDCLNT_E_BUFFER_SIZE_NOT_ALIGNED";
        case AUDCLNT_E_INVALID_DEVICE_PERIOD: return "AUDCLNT_E_INVALID_DEVICE_PERIOD";
        case AUDCLNT_E_INVALID_STREAM_FLAG: return "AUDCLNT_E_INVALID_STREAM_FLAG";
        case AUDCLNT_E_ENDPOINT_OFFLOAD_NOT_CAPABLE: return "AUDCLNT_E_ENDPOINT_OFFLOAD_NOT_CAPABLE";
        case AUDCLNT_E_OUT_OF_OFFLOAD_RESOURCES: return "AUDCLNT_E_OUT_OF_OFFLOAD_RESOURCES";
        case AUDCLNT_E_OFFLOAD_MODE_ONLY: return "AUDCLNT_E_OFFLOAD_MODE_ONLY";
        case AUDCLNT_E_NONOFFLOAD_MODE_ONLY: return "AUDCLNT_E_NONOFFLOAD_MODE_ONLY";
        case AUDCLNT_E_RESOURCES_INVALIDATED: return "AUDCLNT_E_RESOURCES_INVALIDATED";
        case AUDCLNT_S_BUFFER_EMPTY: return "AUDCLNT_S_BUFFER_EMPTY";
        case AUDCLNT_S_THREAD_ALREADY_REGISTERED: return "AUDCLNT_S_THREAD_ALREADY_REGISTERED";
        case AUDCLNT_S_POSITION_STALLED: return "AUDCLNT_S_POSITION_STALLED";

        case E_POINTER: return "E_POINTER";
        case E_INVALIDARG: return "E_INVALIDARG";
        case E_OUTOFMEMORY: return "E_OUTOFMEMORY";
    }
}
*/

// converts a windows wide string to a UTF-8 encoded char *
// Possible errors:
//  * SoundIoError.oMem
//  * SoundIoError.EncodingString
static int from_lpwstr(LPWSTR lpwstr, char** out_str, int* out_str_len) {
    DWORD flags = 0;
    int buf_size = WideCharToMultiByte(CP_UTF8, flags, lpwstr, -1, null, 0, null, null);

    if (buf_size == 0)
        return SoundIoError.EncodingString;

    char* buf = ALLOCATE!char(buf_size);
    if (!buf)
        return SoundIoError.NoMem;

    if (WideCharToMultiByte(CP_UTF8, flags, lpwstr, -1, buf, buf_size, null, null) != buf_size) {
        free(buf);
        return SoundIoError.EncodingString;
    }

    *out_str = buf;
    *out_str_len = buf_size - 1;

    return 0;
}

static int to_lpwstr(const(char)* str, int str_len, LPWSTR* out_lpwstr) {
    DWORD flags = 0;
    int w_len = MultiByteToWideChar(CP_UTF8, flags, str, str_len, null, 0);
    if (w_len <= 0)
        return SoundIoError.EncodingString;

    LPWSTR buf = ALLOCATE!wchar(w_len + 1);
    if (!buf)
        return SoundIoError.NoMem;

    if (MultiByteToWideChar(CP_UTF8, flags, str, str_len, buf, w_len) != w_len) {
        free(buf);
        return SoundIoError.EncodingString;
    }

    *out_lpwstr = buf;
    return 0;
}

static void from_channel_mask_layout(UINT channel_mask, SoundIoChannelLayout* layout) {
    layout.channel_count = 0;
    if (channel_mask & SPEAKER_FRONT_LEFT)
        layout.channels[layout.channel_count++] = SoundIoChannelId.FrontLeft;
    if (channel_mask & SPEAKER_FRONT_RIGHT)
        layout.channels[layout.channel_count++] = SoundIoChannelId.FrontRight;
    if (channel_mask & SPEAKER_FRONT_CENTER)
        layout.channels[layout.channel_count++] = SoundIoChannelId.FrontCenter;
    if (channel_mask & SPEAKER_LOW_FREQUENCY)
        layout.channels[layout.channel_count++] = SoundIoChannelId.Lfe;
    if (channel_mask & SPEAKER_BACK_LEFT)
        layout.channels[layout.channel_count++] = SoundIoChannelId.BackLeft;
    if (channel_mask & SPEAKER_BACK_RIGHT)
        layout.channels[layout.channel_count++] = SoundIoChannelId.BackRight;
    if (channel_mask & SPEAKER_FRONT_LEFT_OF_CENTER)
        layout.channels[layout.channel_count++] = SoundIoChannelId.FrontLeftCenter;
    if (channel_mask & SPEAKER_FRONT_RIGHT_OF_CENTER)
        layout.channels[layout.channel_count++] = SoundIoChannelId.FrontRightCenter;
    if (channel_mask & SPEAKER_BACK_CENTER)
        layout.channels[layout.channel_count++] = SoundIoChannelId.BackCenter;
    if (channel_mask & SPEAKER_SIDE_LEFT)
        layout.channels[layout.channel_count++] = SoundIoChannelId.SideLeft;
    if (channel_mask & SPEAKER_SIDE_RIGHT)
        layout.channels[layout.channel_count++] = SoundIoChannelId.SideRight;
    if (channel_mask & SPEAKER_TOP_CENTER)
        layout.channels[layout.channel_count++] = SoundIoChannelId.TopCenter;
    if (channel_mask & SPEAKER_TOP_FRONT_LEFT)
        layout.channels[layout.channel_count++] = SoundIoChannelId.TopFrontLeft;
    if (channel_mask & SPEAKER_TOP_FRONT_CENTER)
        layout.channels[layout.channel_count++] = SoundIoChannelId.TopFrontCenter;
    if (channel_mask & SPEAKER_TOP_FRONT_RIGHT)
        layout.channels[layout.channel_count++] = SoundIoChannelId.TopFrontRight;
    if (channel_mask & SPEAKER_TOP_BACK_LEFT)
        layout.channels[layout.channel_count++] = SoundIoChannelId.TopBackLeft;
    if (channel_mask & SPEAKER_TOP_BACK_CENTER)
        layout.channels[layout.channel_count++] = SoundIoChannelId.TopBackCenter;
    if (channel_mask & SPEAKER_TOP_BACK_RIGHT)
        layout.channels[layout.channel_count++] = SoundIoChannelId.TopBackRight;

    soundio_channel_layout_detect_builtin(layout);
}

static void from_wave_format_layout(WAVEFORMATEXTENSIBLE* wave_format, SoundIoChannelLayout* layout) {
    assert(wave_format.Format.wFormatTag == WAVE_FORMAT_EXTENSIBLE);
    layout.channel_count = 0;
    from_channel_mask_layout(wave_format.dwChannelMask, layout);
}

static SoundIoFormat from_wave_format_format(WAVEFORMATEXTENSIBLE* wave_format) {
    assert(wave_format.Format.wFormatTag == WAVE_FORMAT_EXTENSIBLE);
    bool is_pcm = IS_EQUAL_GUID(&wave_format.SubFormat, &SOUNDIO_KSDATAFORMAT_SUBTYPE_PCM);
    bool is_float = IS_EQUAL_GUID(&wave_format.SubFormat, &SOUNDIO_KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);

    if (wave_format.Samples.wValidBitsPerSample == wave_format.Format.wBitsPerSample) {
        if (wave_format.Format.wBitsPerSample == 8) {
            if (is_pcm)
                return SoundIoFormat.U8;
        } else if (wave_format.Format.wBitsPerSample == 16) {
            if (is_pcm)
                return SoundIoFormat.S16LE;
        } else if (wave_format.Format.wBitsPerSample == 32) {
            if (is_pcm)
                return SoundIoFormat.S32LE;
            else if (is_float)
                return SoundIoFormat.Float32LE;
        } else if (wave_format.Format.wBitsPerSample == 64) {
            if (is_float)
                return SoundIoFormat.Float64LE;
        }
    } else if (wave_format.Format.wBitsPerSample == 32 &&
            wave_format.Samples.wValidBitsPerSample == 24)
    {
        return SoundIoFormat.S24LE;
    }

    return SoundIoFormat.Invalid;
}

// only needs to support the layouts in test_layouts
static void to_wave_format_layout(const(SoundIoChannelLayout)* layout, WAVEFORMATEXTENSIBLE* wave_format) {
    wave_format.dwChannelMask = 0;
    wave_format.Format.nChannels = cast(ushort) layout.channel_count;
    for (int i = 0; i < layout.channel_count; i += 1) {
        SoundIoChannelId channel_id = layout.channels[i];
        switch (channel_id) {
            case SoundIoChannelId.FrontLeft:
                wave_format.dwChannelMask |= SPEAKER_FRONT_LEFT;
                break;
            case SoundIoChannelId.FrontRight:
                wave_format.dwChannelMask |= SPEAKER_FRONT_RIGHT;
                break;
            case SoundIoChannelId.FrontCenter:
                wave_format.dwChannelMask |= SPEAKER_FRONT_CENTER;
                break;
            case SoundIoChannelId.Lfe:
                wave_format.dwChannelMask |= SPEAKER_LOW_FREQUENCY;
                break;
            case SoundIoChannelId.BackLeft:
                wave_format.dwChannelMask |= SPEAKER_BACK_LEFT;
                break;
            case SoundIoChannelId.BackRight:
                wave_format.dwChannelMask |= SPEAKER_BACK_RIGHT;
                break;
            case SoundIoChannelId.FrontLeftCenter:
                wave_format.dwChannelMask |= SPEAKER_FRONT_LEFT_OF_CENTER;
                break;
            case SoundIoChannelId.FrontRightCenter:
                wave_format.dwChannelMask |= SPEAKER_FRONT_RIGHT_OF_CENTER;
                break;
            case SoundIoChannelId.BackCenter:
                wave_format.dwChannelMask |= SPEAKER_BACK_CENTER;
                break;
            case SoundIoChannelId.SideLeft:
                wave_format.dwChannelMask |= SPEAKER_SIDE_LEFT;
                break;
            case SoundIoChannelId.SideRight:
                wave_format.dwChannelMask |= SPEAKER_SIDE_RIGHT;
                break;
            case SoundIoChannelId.TopCenter:
                wave_format.dwChannelMask |= SPEAKER_TOP_CENTER;
                break;
            case SoundIoChannelId.TopFrontLeft:
                wave_format.dwChannelMask |= SPEAKER_TOP_FRONT_LEFT;
                break;
            case SoundIoChannelId.TopFrontCenter:
                wave_format.dwChannelMask |= SPEAKER_TOP_FRONT_CENTER;
                break;
            case SoundIoChannelId.TopFrontRight:
                wave_format.dwChannelMask |= SPEAKER_TOP_FRONT_RIGHT;
                break;
            case SoundIoChannelId.TopBackLeft:
                wave_format.dwChannelMask |= SPEAKER_TOP_BACK_LEFT;
                break;
            case SoundIoChannelId.TopBackCenter:
                wave_format.dwChannelMask |= SPEAKER_TOP_BACK_CENTER;
                break;
            case SoundIoChannelId.TopBackRight:
                wave_format.dwChannelMask |= SPEAKER_TOP_BACK_RIGHT;
                break;
            default:
                soundio_panic("to_wave_format_layout: unsupported channel id");
        }
    }
}

// only needs to support the formats in test_formats
static void to_wave_format_format(SoundIoFormat format, WAVEFORMATEXTENSIBLE* wave_format) {
    switch (format) {
    case SoundIoFormat.U8:
        wave_format.SubFormat = SOUNDIO_KSDATAFORMAT_SUBTYPE_PCM;
        wave_format.Format.wBitsPerSample = 8;
        wave_format.Samples.wValidBitsPerSample = 8;
        break;
    case SoundIoFormat.S16LE:
        wave_format.SubFormat = SOUNDIO_KSDATAFORMAT_SUBTYPE_PCM;
        wave_format.Format.wBitsPerSample = 16;
        wave_format.Samples.wValidBitsPerSample = 16;
        break;
    case SoundIoFormat.S24LE:
        wave_format.SubFormat = SOUNDIO_KSDATAFORMAT_SUBTYPE_PCM;
        wave_format.Format.wBitsPerSample = 32;
        wave_format.Samples.wValidBitsPerSample = 24;
        break;
    case SoundIoFormat.S32LE:
        wave_format.SubFormat = SOUNDIO_KSDATAFORMAT_SUBTYPE_PCM;
        wave_format.Format.wBitsPerSample = 32;
        wave_format.Samples.wValidBitsPerSample = 32;
        break;
    case SoundIoFormat.Float32LE:
        wave_format.SubFormat = SOUNDIO_KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
        wave_format.Format.wBitsPerSample = 32;
        wave_format.Samples.wValidBitsPerSample = 32;
        break;
    case SoundIoFormat.Float64LE:
        wave_format.SubFormat = SOUNDIO_KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
        wave_format.Format.wBitsPerSample = 64;
        wave_format.Samples.wValidBitsPerSample = 64;
        break;
    default:
        soundio_panic("to_wave_format_format: unsupported format");
    }
}

static void complete_wave_format_data(WAVEFORMATEXTENSIBLE* wave_format) {
    wave_format.Format.nBlockAlign = cast(ushort) ((wave_format.Format.wBitsPerSample * wave_format.Format.nChannels) / 8);
    wave_format.Format.nAvgBytesPerSec = wave_format.Format.nSamplesPerSec * wave_format.Format.nBlockAlign;
}

static SoundIoDeviceAim data_flow_to_aim(EDataFlow data_flow) {
    return (data_flow == eRender) ? SoundIoDeviceAim.Output : SoundIoDeviceAim.Input;
}


static double from_reference_time(REFERENCE_TIME rt) {
    return (cast(double)rt) / 10000000.0;
}

static REFERENCE_TIME to_reference_time(double seconds) {
    return cast(REFERENCE_TIME)(seconds * 10000000.0 + 0.5);
}

static void destruct_device(SoundIoDevicePrivate* dev) {
    SoundIoDeviceWasapi* dw = &dev.backend_data.wasapi;
    if (dw.mm_device)
        IMMDevice_Release(dw.mm_device);
}

struct RefreshDevices {
    IMMDeviceCollection* collection;
    IMMDevice* mm_device;
    IMMDevice* default_render_device;
    IMMDevice* default_capture_device;
    IMMEndpoint* endpoint;
    IPropertyStore* prop_store;
    IAudioClient* audio_client;
    LPWSTR lpwstr;
    PROPVARIANT prop_variant_value;
    WAVEFORMATEXTENSIBLE* wave_format;
    bool prop_variant_value_inited;
    SoundIoDevicesInfo* devices_info;
    SoundIoDevice* device_shared;
    SoundIoDevice* device_raw;
    char* default_render_id;
    int default_render_id_len;
    char* default_capture_id;
    int default_capture_id_len;
}
// static assert(RefreshDevices.sizeof == 160); 64-bit

static void deinit_refresh_devices(RefreshDevices* rd) {
    soundio_destroy_devices_info(rd.devices_info);
    soundio_device_unref(rd.device_shared);
    soundio_device_unref(rd.device_raw);
    if (rd.mm_device)
        IMMDevice_Release(rd.mm_device);
    if (rd.default_render_device)
    {
        IMMDevice_Release(rd.default_render_device);
        free(rd.default_render_id);
    }
    if (rd.default_capture_device)
    {
        IMMDevice_Release(rd.default_capture_device);
        free(rd.default_capture_id);
    }
    if (rd.collection)
        IMMDeviceCollection_Release(rd.collection);
    if (rd.lpwstr)
        CoTaskMemFree(rd.lpwstr);
    if (rd.endpoint)
        IMMEndpoint_Release(rd.endpoint);
    if (rd.prop_store)
        IPropertyStore_Release(rd.prop_store);
    if (rd.prop_variant_value_inited)
        PropVariantClear(&rd.prop_variant_value);
    if (rd.wave_format)
        CoTaskMemFree(rd.wave_format);
    if (rd.audio_client)
        IUnknown_Release(rd.audio_client);
}

static int detect_valid_layouts(RefreshDevices* rd, WAVEFORMATEXTENSIBLE* wave_format, SoundIoDevicePrivate* dev, AUDCLNT_SHAREMODE share_mode) {
    SoundIoDevice* device = &dev.pub;
    HRESULT hr;

    device.layout_count = 0;
    device.layouts = ALLOCATE!SoundIoChannelLayout(test_layouts.length);
    if (!device.layouts)
        return SoundIoError.NoMem;

    WAVEFORMATEX* closest_match = null;
    WAVEFORMATEXTENSIBLE orig_wave_format = *wave_format;

    for (int i = 0; i < test_formats.length; i += 1) {
        SoundIoChannelLayoutId test_layout_id = test_layouts[i];
        const(SoundIoChannelLayout)* test_layout = soundio_channel_layout_get_builtin(test_layout_id);
        to_wave_format_layout(test_layout, wave_format);
        complete_wave_format_data(wave_format);

        hr = IAudioClient_IsFormatSupported(rd.audio_client, share_mode,
                cast(WAVEFORMATEX*)wave_format, &closest_match);
        if (closest_match) {
            CoTaskMemFree(closest_match);
            closest_match = null;
        }
        if (hr == S_OK) {
            device.layouts[device.layout_count++] = *test_layout;
        } else if (hr == AUDCLNT_E_UNSUPPORTED_FORMAT || hr == S_FALSE || hr == E_INVALIDARG) {
            continue;
        } else {
            *wave_format = orig_wave_format;
            return SoundIoError.OpeningDevice;
        }
    }

    *wave_format = orig_wave_format;
    return 0;
}

static int detect_valid_formats(RefreshDevices* rd, WAVEFORMATEXTENSIBLE* wave_format, SoundIoDevicePrivate* dev, AUDCLNT_SHAREMODE share_mode) {
    SoundIoDevice* device = &dev.pub;
    HRESULT hr;

    device.format_count = 0;
    device.formats = ALLOCATE!SoundIoFormat(test_formats.length);
    if (!device.formats)
        return SoundIoError.NoMem;

    WAVEFORMATEX* closest_match = null;
    WAVEFORMATEXTENSIBLE orig_wave_format = *wave_format;

    for (int i = 0; i < test_formats.length; i += 1) {
        SoundIoFormat test_format = test_formats[i];
        to_wave_format_format(test_format, wave_format);
        complete_wave_format_data(wave_format);

        hr = IAudioClient_IsFormatSupported(rd.audio_client, share_mode,
                cast(WAVEFORMATEX*)wave_format, &closest_match);
        if (closest_match) {
            CoTaskMemFree(closest_match);
            closest_match = null;
        }
        if (hr == S_OK) {
            device.formats[device.format_count++] = test_format;
        } else if (hr == AUDCLNT_E_UNSUPPORTED_FORMAT || hr == S_FALSE || hr == E_INVALIDARG) {
            continue;
        } else {
            *wave_format = orig_wave_format;
            return SoundIoError.OpeningDevice;
        }
    }

    *wave_format = orig_wave_format;
    return 0;
}

static int add_sample_rate(SoundIoListSampleRateRange* sample_rates, int* current_min, int the_max) {
    if (auto err = sample_rates.add_one())
        return err;

    SoundIoSampleRateRange* last_range = sample_rates.last_ptr();
    last_range.min = *current_min;
    last_range.max = the_max;
    return 0;
}

static int do_sample_rate_test(RefreshDevices* rd, SoundIoDevicePrivate* dev, WAVEFORMATEXTENSIBLE* wave_format, int test_sample_rate, AUDCLNT_SHAREMODE share_mode, int* current_min, int* last_success_rate) {
    WAVEFORMATEX* closest_match = null;

    wave_format.Format.nSamplesPerSec = test_sample_rate;
    HRESULT hr = IAudioClient_IsFormatSupported(rd.audio_client, share_mode,
            cast(WAVEFORMATEX*)wave_format, &closest_match);
    if (closest_match) {
        CoTaskMemFree(closest_match);
        closest_match = null;
    }
    if (hr == S_OK) {
        if (*current_min == -1) {
            *current_min = test_sample_rate;
        }
        *last_success_rate = test_sample_rate;
    } else if (hr == AUDCLNT_E_UNSUPPORTED_FORMAT || hr == S_FALSE || hr == E_INVALIDARG) {
        if (*current_min != -1) {
            if (auto err = add_sample_rate(&dev.sample_rates, current_min, *last_success_rate))
                return err;
            *current_min = -1;
        }
    } else {
        return SoundIoError.OpeningDevice;
    }

    return 0;
}

static int detect_valid_sample_rates(RefreshDevices* rd, WAVEFORMATEXTENSIBLE* wave_format, SoundIoDevicePrivate* dev, AUDCLNT_SHAREMODE share_mode) {
    DWORD orig_sample_rate = wave_format.Format.nSamplesPerSec;

    assert(dev.sample_rates.length == 0);

    int current_min = -1;
    int last_success_rate = -1;
    for (int i = 0; i < test_sample_rates.length; i += 1) {
        for (int offset = -1; offset <= 1; offset += 1) {
            int test_sample_rate = test_sample_rates[i] + offset;
            if (auto err = do_sample_rate_test(rd, dev, wave_format, test_sample_rate, share_mode,
                            &current_min, &last_success_rate))
            {
                wave_format.Format.nSamplesPerSec = orig_sample_rate;
                return err;
            }
        }
    }

    if (current_min != -1) {
        if (auto err = add_sample_rate(&dev.sample_rates, &current_min, last_success_rate)) {
            wave_format.Format.nSamplesPerSec = orig_sample_rate;
            return err;
        }
    }

    SoundIoDevice* device = &dev.pub;

    device.sample_rate_count = dev.sample_rates.length;
    device.sample_rates = dev.sample_rates.items;

    wave_format.Format.nSamplesPerSec = orig_sample_rate;
    return 0;
}


static int refresh_devices(SoundIoPrivate* si) {
    SoundIo* soundio = &si.pub;
    SoundIoWasapi* siw = &si.backend_data.wasapi;
    RefreshDevices rd = RefreshDevices.init; // todo: is this zero?
    HRESULT hr;

    if (FAILED(hr = IMMDeviceEnumerator_GetDefaultAudioEndpoint(siw.device_enumerator, eRender,
                    eMultimedia, &rd.default_render_device)))
    {
        if (hr != E_NOTFOUND) {
            deinit_refresh_devices(&rd);
            if (hr == E_OUTOFMEMORY) {
                return SoundIoError.NoMem;
            }
            return SoundIoError.OpeningDevice;
        }
    }
    if (rd.default_render_device) {
        if (rd.lpwstr) {
            CoTaskMemFree(rd.lpwstr);
            rd.lpwstr = null;
        }
        if (FAILED(hr = IMMDevice_GetId(rd.default_render_device, &rd.lpwstr))) {
            deinit_refresh_devices(&rd);
            // MSDN states the IMMDevice_GetId can fail if the device is NULL, or if we're out of memory
            // We know the device point isn't NULL so we're necessarily out of memory
            return SoundIoError.NoMem;
        }
        if (auto err = from_lpwstr(rd.lpwstr, &rd.default_render_id, &rd.default_render_id_len)) {
            deinit_refresh_devices(&rd);
            return err;
        }
    }


    if (FAILED(hr = IMMDeviceEnumerator_GetDefaultAudioEndpoint(siw.device_enumerator, eCapture,
                    eMultimedia, &rd.default_capture_device)))
    {
        if (hr != E_NOTFOUND) {
            deinit_refresh_devices(&rd);
            if (hr == E_OUTOFMEMORY) {
                return SoundIoError.NoMem;
            }
            return SoundIoError.OpeningDevice;
        }
    }
    if (rd.default_capture_device) {
        if (rd.lpwstr) {
            CoTaskMemFree(rd.lpwstr);
            rd.lpwstr = null;
        }
        if (FAILED(hr = IMMDevice_GetId(rd.default_capture_device, &rd.lpwstr))) {
            deinit_refresh_devices(&rd);
            if (hr == E_OUTOFMEMORY) {
                return SoundIoError.NoMem;
            }
            return SoundIoError.OpeningDevice;
        }
        if (auto err = from_lpwstr(rd.lpwstr, &rd.default_capture_id, &rd.default_capture_id_len)) {
            deinit_refresh_devices(&rd);
            return err;
        }
    }


    if (FAILED(hr = IMMDeviceEnumerator_EnumAudioEndpoints(siw.device_enumerator,
                    eAll, DEVICE_STATE_ACTIVE, &rd.collection)))
    {
        deinit_refresh_devices(&rd);
        if (hr == E_OUTOFMEMORY) {
            return SoundIoError.NoMem;
        }
        return SoundIoError.OpeningDevice;
    }

    UINT unsigned_count;
    if (FAILED(hr = IMMDeviceCollection_GetCount(rd.collection, &unsigned_count))) {
        // In theory this shouldn't happen since the only documented failure case is that
        // rd.collection is NULL, but then EnumAudioEndpoints should have failed.
        deinit_refresh_devices(&rd);
        return SoundIoError.OpeningDevice;
    }

    if (unsigned_count > cast(UINT)int.max) {
        deinit_refresh_devices(&rd);
        return SoundIoError.IncompatibleDevice;
    }

    int device_count = unsigned_count;

    if (!cast(bool)(rd.devices_info = ALLOCATE!SoundIoDevicesInfo(1))) {
        deinit_refresh_devices(&rd);
        return SoundIoError.NoMem;
    }
    rd.devices_info.default_input_index = -1;
    rd.devices_info.default_output_index = -1;

    for (int device_i = 0; device_i < device_count; device_i += 1) {
        if (rd.mm_device) {
            IMMDevice_Release(rd.mm_device);
            rd.mm_device = null;
        }
        if (FAILED(hr = IMMDeviceCollection_Item(rd.collection, device_i, &rd.mm_device))) {
            continue;
        }
        if (rd.lpwstr) {
            CoTaskMemFree(rd.lpwstr);
            rd.lpwstr = null;
        }
        if (FAILED(hr = IMMDevice_GetId(rd.mm_device, &rd.lpwstr))) {
            continue;
        }



        SoundIoDevicePrivate* dev_shared = ALLOCATE!SoundIoDevicePrivate(1);
        if (!dev_shared) {
            deinit_refresh_devices(&rd);
            return SoundIoError.NoMem;
        }
        SoundIoDeviceWasapi* dev_w_shared = &dev_shared.backend_data.wasapi;
        dev_shared.destruct = &destruct_device;
        assert(!rd.device_shared);
        rd.device_shared = &dev_shared.pub;
        rd.device_shared.ref_count = 1;
        rd.device_shared.soundio = soundio;
        rd.device_shared.is_raw = false;
        rd.device_shared.software_latency_max = 2.0;

        SoundIoDevicePrivate* dev_raw = ALLOCATE!SoundIoDevicePrivate(1);
        if (!dev_raw) {
            deinit_refresh_devices(&rd);
            return SoundIoError.NoMem;
        }
        SoundIoDeviceWasapi* dev_w_raw = &dev_raw.backend_data.wasapi;
        dev_raw.destruct = &destruct_device;
        assert(!rd.device_raw);
        rd.device_raw = &dev_raw.pub;
        rd.device_raw.ref_count = 1;
        rd.device_raw.soundio = soundio;
        rd.device_raw.is_raw = true;
        rd.device_raw.software_latency_max = 0.5;

        int device_id_len;
        if (auto err = from_lpwstr(rd.lpwstr, &rd.device_shared.id, &device_id_len)) {
            deinit_refresh_devices(&rd);
            return err;
        }

        rd.device_raw.id = soundio_str_dupe(rd.device_shared.id, device_id_len);
        if (!rd.device_raw.id) {
            deinit_refresh_devices(&rd);
            return SoundIoError.NoMem;
        }

        if (rd.endpoint) {
            IMMEndpoint_Release(rd.endpoint);
            rd.endpoint = null;
        }
        if (FAILED(hr = IMMDevice_QueryInterface(rd.mm_device, IID_IMMENDPOINT, cast(void**)&rd.endpoint))) {
            rd.device_shared.probe_error = SoundIoError.OpeningDevice;
            rd.device_raw.probe_error = SoundIoError.OpeningDevice;
            rd.device_shared = null;
            rd.device_raw = null;
            continue;
        }

        EDataFlow data_flow;
        if (FAILED(hr = IMMEndpoint_GetDataFlow(rd.endpoint, &data_flow))) {
            rd.device_shared.probe_error = SoundIoError.OpeningDevice;
            rd.device_raw.probe_error = SoundIoError.OpeningDevice;
            rd.device_shared = null;
            rd.device_raw = null;
            continue;
        }

        rd.device_shared.aim = data_flow_to_aim(data_flow);
        rd.device_raw.aim = rd.device_shared.aim;

        SoundIoListDevicePtr* device_list;
        if (rd.device_shared.aim == SoundIoDeviceAim.Output) {
            device_list = &rd.devices_info.output_devices;
            if (soundio_streql(rd.device_shared.id, device_id_len,
                        rd.default_render_id, rd.default_render_id_len))
            {
                rd.devices_info.default_output_index = device_list.length;
            }
        } else {
            assert(rd.device_shared.aim == SoundIoDeviceAim.Input);
            device_list = &rd.devices_info.input_devices;
            if (soundio_streql(rd.device_shared.id, device_id_len,
                        rd.default_capture_id, rd.default_capture_id_len))
            {
                rd.devices_info.default_input_index = device_list.length;
            }
        }

        if (auto err = device_list.append(rd.device_shared)) {
            deinit_refresh_devices(&rd);
            return err;
        }
        if (auto err = device_list.append(rd.device_raw)) {
            deinit_refresh_devices(&rd);
            return err;
        }

        if (rd.audio_client) {
            IUnknown_Release(rd.audio_client);
            rd.audio_client = null;
        }
        if (FAILED(hr = IMMDevice_Activate(rd.mm_device, IID_IAUDIOCLIENT,
                        CLSCTX_ALL, null, cast(void**)&rd.audio_client)))
        {
            rd.device_shared.probe_error = SoundIoError.OpeningDevice;
            rd.device_raw.probe_error = SoundIoError.OpeningDevice;
            rd.device_shared = null;
            rd.device_raw = null;
            continue;
        }

        REFERENCE_TIME default_device_period;
        REFERENCE_TIME min_device_period;
        if (FAILED(hr = IAudioClient_GetDevicePeriod(rd.audio_client,
                        &default_device_period, &min_device_period)))
        {
            rd.device_shared.probe_error = SoundIoError.OpeningDevice;
            rd.device_raw.probe_error = SoundIoError.OpeningDevice;
            rd.device_shared = null;
            rd.device_raw = null;
            continue;
        }
        dev_w_shared.period_duration = from_reference_time(default_device_period);
        rd.device_shared.software_latency_current = dev_w_shared.period_duration;

        dev_w_raw.period_duration = from_reference_time(min_device_period);
        rd.device_raw.software_latency_min = dev_w_raw.period_duration * 2;

        if (rd.prop_store) {
            IPropertyStore_Release(rd.prop_store);
            rd.prop_store = null;
        }
        if (FAILED(hr = IMMDevice_OpenPropertyStore(rd.mm_device, STGM_READ, &rd.prop_store))) {
            rd.device_shared.probe_error = SoundIoError.OpeningDevice;
            rd.device_raw.probe_error = SoundIoError.OpeningDevice;
            rd.device_shared = null;
            rd.device_raw = null;
            continue;
        }

        if (rd.prop_variant_value_inited) {
            PropVariantClear(&rd.prop_variant_value);
            rd.prop_variant_value_inited = false;
        }
        PropVariantInit(&rd.prop_variant_value);
        rd.prop_variant_value_inited = true;
        if (FAILED(hr = IPropertyStore_GetValue(rd.prop_store,
                        PKEY_DEVICE_FRIENDLYNAME, &rd.prop_variant_value)))
        {
            rd.device_shared.probe_error = SoundIoError.OpeningDevice;
            rd.device_raw.probe_error = SoundIoError.OpeningDevice;
            rd.device_shared = null;
            rd.device_raw = null;
            continue;
        }
        if (!rd.prop_variant_value.pwszVal) {
            rd.device_shared.probe_error = SoundIoError.OpeningDevice;
            rd.device_raw.probe_error = SoundIoError.OpeningDevice;
            rd.device_shared = null;
            rd.device_raw = null;
            continue;
        }
        int device_name_len;
        if (auto err = from_lpwstr(rd.prop_variant_value.pwszVal, &rd.device_shared.name, &device_name_len)) {
            rd.device_shared.probe_error = err;
            rd.device_raw.probe_error = err;
            rd.device_shared = null;
            rd.device_raw = null;
            continue;
        }

        rd.device_raw.name = soundio_str_dupe(rd.device_shared.name, device_name_len);
        if (!rd.device_raw.name) {
            deinit_refresh_devices(&rd);
            return SoundIoError.NoMem;
        }

        // Get the format that WASAPI opens the device with for shared streams.
        // This is guaranteed to work, so we use this to modulate the sample
        // rate while holding the format constant and vice versa.
        if (rd.prop_variant_value_inited) {
            PropVariantClear(&rd.prop_variant_value);
            rd.prop_variant_value_inited = false;
        }
        PropVariantInit(&rd.prop_variant_value);
        rd.prop_variant_value_inited = true;
        if (FAILED(hr = IPropertyStore_GetValue(rd.prop_store, PKEY_AUDIOENGINE_DEVICEFORMAT,
                        &rd.prop_variant_value)))
        {
            rd.device_shared.probe_error = SoundIoError.OpeningDevice;
            rd.device_raw.probe_error = SoundIoError.OpeningDevice;
            rd.device_shared = null;
            rd.device_raw = null;
            continue;
        }
        WAVEFORMATEXTENSIBLE* valid_wave_format = cast(WAVEFORMATEXTENSIBLE*)rd.prop_variant_value.blob.pBlobData;
        if (valid_wave_format.Format.wFormatTag != WAVE_FORMAT_EXTENSIBLE) {
            rd.device_shared.probe_error = SoundIoError.OpeningDevice;
            rd.device_raw.probe_error = SoundIoError.OpeningDevice;
            rd.device_shared = null;
            rd.device_raw = null;
            continue;
        }
        if (auto err = detect_valid_sample_rates(&rd, valid_wave_format, dev_raw,
                        AUDCLNT_SHAREMODE_EXCLUSIVE))
        {
            rd.device_raw.probe_error = err;
            rd.device_raw = null;
        }
        if (rd.device_raw) if (auto err = detect_valid_formats(&rd, valid_wave_format, dev_raw,
                        AUDCLNT_SHAREMODE_EXCLUSIVE))
        {
            rd.device_raw.probe_error = err;
            rd.device_raw = null;
        }
        if (rd.device_raw) if (auto err = detect_valid_layouts(&rd, valid_wave_format, dev_raw,
            AUDCLNT_SHAREMODE_EXCLUSIVE))
        {
            rd.device_raw.probe_error = err;
            rd.device_raw = null;
        }

        if (rd.wave_format) {
            CoTaskMemFree(rd.wave_format);
            rd.wave_format = null;
        }
        if (FAILED(hr = IAudioClient_GetMixFormat(rd.audio_client, cast(WAVEFORMATEX**)&rd.wave_format))) {
            // According to MSDN GetMixFormat only applies to shared-mode devices.
            rd.device_shared.probe_error = SoundIoError.OpeningDevice;
            rd.device_shared = null;
        }
        else if (rd.wave_format && (rd.wave_format.Format.wFormatTag != WAVE_FORMAT_EXTENSIBLE)) {
            rd.device_shared.probe_error = SoundIoError.OpeningDevice;
            rd.device_shared = null;
        }

        if (rd.device_shared) {
            rd.device_shared.sample_rate_current = rd.wave_format.Format.nSamplesPerSec;
            rd.device_shared.current_format = from_wave_format_format(rd.wave_format);

            if (rd.device_shared.aim == SoundIoDeviceAim.Output) {
                // For output streams in shared mode,
                // WASAPI performs resampling, so any value is valid.
                // Let's pick some reasonable min and max values.
                rd.device_shared.sample_rate_count = 1;
                rd.device_shared.sample_rates = &dev_shared.prealloc_sample_rate_range;
                rd.device_shared.sample_rates[0].min = soundio_int_min(SOUNDIO_MIN_SAMPLE_RATE,
                    rd.device_shared.sample_rate_current);
                rd.device_shared.sample_rates[0].max = soundio_int_max(SOUNDIO_MAX_SAMPLE_RATE,
                    rd.device_shared.sample_rate_current);
            }
            else {
                // Shared mode input stream: mix format is all we can do.
                rd.device_shared.sample_rate_count = 1;
                rd.device_shared.sample_rates = &dev_shared.prealloc_sample_rate_range;
                rd.device_shared.sample_rates[0].min = rd.device_shared.sample_rate_current;
                rd.device_shared.sample_rates[0].max = rd.device_shared.sample_rate_current;
            }

            if (auto err = detect_valid_formats(&rd, rd.wave_format, dev_shared,
                AUDCLNT_SHAREMODE_SHARED))
            {
                rd.device_shared.probe_error = err;
                rd.device_shared = null;
            }
            else {
                from_wave_format_layout(rd.wave_format, &rd.device_shared.current_layout);
                rd.device_shared.layout_count = 1;
                rd.device_shared.layouts = &rd.device_shared.current_layout;
            }
        }

        IMMDevice_AddRef(rd.mm_device);
        dev_w_shared.mm_device = rd.mm_device;
        dev_w_raw.mm_device = rd.mm_device;
        rd.mm_device = null;

        rd.device_shared = null;
        rd.device_raw = null;
    }

    soundio_os_mutex_lock(siw.mutex);
    soundio_destroy_devices_info(siw.ready_devices_info);
    siw.ready_devices_info = rd.devices_info;
    siw.have_devices_flag = true;
    soundio_os_cond_signal(siw.cond, siw.mutex);
    soundio.on_events_signal(soundio);
    soundio_os_mutex_unlock(siw.mutex);

    rd.devices_info = null;
    deinit_refresh_devices(&rd);

    return 0;
}


static void shutdown_backend(SoundIoPrivate* si, int err) {
    SoundIo* soundio = &si.pub;
    SoundIoWasapi* siw = &si.backend_data.wasapi;
    soundio_os_mutex_lock(siw.mutex);
    siw.shutdown_err = err;
    soundio_os_cond_signal(siw.cond, siw.mutex);
    soundio.on_events_signal(soundio);
    soundio_os_mutex_unlock(siw.mutex);
}

static void device_thread_run(void* arg) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)arg;
    SoundIoWasapi* siw = &si.backend_data.wasapi;
    int err;

    HRESULT hr = CoCreateInstance(CLSID_MMDEVICEENUMERATOR, null,
            CLSCTX_ALL, IID_IMMDEVICEENUMERATOR, cast(void**)&siw.device_enumerator);
    if (FAILED(hr)) {
        shutdown_backend(si, SoundIoError.SystemResources);
        return;
    }

    if (FAILED(hr = IMMDeviceEnumerator_RegisterEndpointNotificationCallback(
                    siw.device_enumerator, &siw.device_events)))
    {
        shutdown_backend(si, SoundIoError.SystemResources);
        return;
    }

    soundio_os_mutex_lock(siw.scan_devices_mutex);
    for (;;) {
        if (siw.abort_flag)
            break;
        if (siw.device_scan_queued) {
            siw.device_scan_queued = false;
            soundio_os_mutex_unlock(siw.scan_devices_mutex);
            err = refresh_devices(si);
            if (err) {
                shutdown_backend(si, err);
                return;
            }
            soundio_os_mutex_lock(siw.scan_devices_mutex);
            continue;
        }
        soundio_os_cond_wait(siw.scan_devices_cond, siw.scan_devices_mutex);
    }
    soundio_os_mutex_unlock(siw.scan_devices_mutex);

    IMMDeviceEnumerator_UnregisterEndpointNotificationCallback(siw.device_enumerator, &siw.device_events);
    IMMDeviceEnumerator_Release(siw.device_enumerator);
    siw.device_enumerator = null;
}

private extern(D) void my_flush_events(SoundIoPrivate* si, bool wait) {
    SoundIo* soundio = &si.pub;
    SoundIoWasapi* siw = &si.backend_data.wasapi;

    bool change = false;
    bool cb_shutdown = false;
    SoundIoDevicesInfo* old_devices_info = null;

    soundio_os_mutex_lock(siw.mutex);

    // block until have devices
    while (wait || (!siw.have_devices_flag && !siw.shutdown_err)) {
        soundio_os_cond_wait(siw.cond, siw.mutex);
        wait = false;
    }

    if (siw.shutdown_err && !siw.emitted_shutdown_cb) {
        siw.emitted_shutdown_cb = true;
        cb_shutdown = true;
    } else if (siw.ready_devices_info) {
        old_devices_info = si.safe_devices_info;
        si.safe_devices_info = siw.ready_devices_info;
        siw.ready_devices_info = null;
        change = true;
    }

    soundio_os_mutex_unlock(siw.mutex);

    if (cb_shutdown)
        soundio.on_backend_disconnect(soundio, siw.shutdown_err);
    else if (change)
        soundio.on_devices_change(soundio);

    soundio_destroy_devices_info(old_devices_info);
}

static void flush_events_wasapi(SoundIoPrivate* si) {
    my_flush_events(si, false);
}

static void wait_events_wasapi(SoundIoPrivate* si) {
    my_flush_events(si, false);
    my_flush_events(si, true);
}

static void wakeup_wasapi(SoundIoPrivate* si) {
    SoundIoWasapi* siw = &si.backend_data.wasapi;
    soundio_os_cond_signal(siw.cond, siw.mutex);
}

static void force_device_scan_wasapi(SoundIoPrivate* si) {
    SoundIoWasapi* siw = &si.backend_data.wasapi;
    soundio_os_mutex_lock(siw.scan_devices_mutex);
    siw.device_scan_queued = true;
    soundio_os_cond_signal(siw.scan_devices_cond, siw.scan_devices_mutex);
    soundio_os_mutex_unlock(siw.scan_devices_mutex);
}

static void outstream_thread_deinit(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamWasapi* osw = &os.backend_data.wasapi;

    if (osw.audio_volume_control)
        IUnknown_Release(osw.audio_volume_control);
    if (osw.audio_render_client)
        IUnknown_Release(osw.audio_render_client);
    if (osw.audio_session_control)
        IUnknown_Release(osw.audio_session_control);
    if (osw.audio_clock_adjustment)
        IUnknown_Release(osw.audio_clock_adjustment);
    if (osw.audio_client)
        IUnknown_Release(osw.audio_client);
}

static void outstream_destroy_wasapi(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamWasapi* osw = &os.backend_data.wasapi;

    if (osw.thread) {
        SOUNDIO_ATOMIC_FLAG_CLEAR(osw.thread_exit_flag);
        if (osw.h_event)
            SetEvent(osw.h_event);

        soundio_os_mutex_lock(osw.mutex);
        soundio_os_cond_signal(osw.cond, osw.mutex);
        soundio_os_cond_signal(osw.start_cond, osw.mutex);
        soundio_os_mutex_unlock(osw.mutex);

        soundio_os_thread_destroy(osw.thread);

        osw.thread = null;
    }

    if (osw.h_event) {
        CloseHandle(osw.h_event);
        osw.h_event = null;
    }

    free(osw.stream_name);
    osw.stream_name = null;

    soundio_os_cond_destroy(osw.cond);
    osw.cond = null;

    soundio_os_cond_destroy(osw.start_cond);
    osw.start_cond = null;

    soundio_os_mutex_destroy(osw.mutex);
    osw.mutex = null;
}

static int outstream_do_open(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamWasapi* osw = &os.backend_data.wasapi;
    SoundIoOutStream* outstream = &os.pub;
    SoundIoDevice* device = outstream.device;
    SoundIoDevicePrivate* dev = cast(SoundIoDevicePrivate*)device;
    SoundIoDeviceWasapi* dw = &dev.backend_data.wasapi;
    HRESULT hr;

    if (FAILED(hr = IMMDevice_Activate(dw.mm_device, IID_IAUDIOCLIENT,
                    CLSCTX_ALL, null, cast(void**)&osw.audio_client)))
    {
        return SoundIoError.OpeningDevice;
    }


    AUDCLNT_SHAREMODE share_mode;
    DWORD flags;
    REFERENCE_TIME buffer_duration;
    REFERENCE_TIME periodicity;
    WAVEFORMATEXTENSIBLE wave_format = WAVEFORMATEXTENSIBLE.init; // TODO: equal to 0?
    wave_format.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
    wave_format.Format.cbSize = WAVEFORMATEXTENSIBLE.sizeof - WAVEFORMATEX.sizeof;
    if (osw.is_raw) {
        wave_format.Format.nSamplesPerSec = outstream.sample_rate;
        flags = AUDCLNT_STREAMFLAGS_EVENTCALLBACK;
        share_mode = AUDCLNT_SHAREMODE_EXCLUSIVE;
        periodicity = to_reference_time(dw.period_duration);
        buffer_duration = periodicity;
    } else {
        WAVEFORMATEXTENSIBLE* mix_format;
        if (FAILED(hr = IAudioClient_GetMixFormat(osw.audio_client, cast(WAVEFORMATEX**)&mix_format))) {
            return SoundIoError.OpeningDevice;
        }
        wave_format.Format.nSamplesPerSec = cast(DWORD)outstream.sample_rate;
        osw.need_resample = (mix_format.Format.nSamplesPerSec != wave_format.Format.nSamplesPerSec);
        CoTaskMemFree(mix_format);
        mix_format = null;
        flags = osw.need_resample ? AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY : 0;
        share_mode = AUDCLNT_SHAREMODE_SHARED;
        periodicity = 0;
        buffer_duration = to_reference_time(4.0);
    }
    to_wave_format_layout(&outstream.layout, &wave_format);
    to_wave_format_format(outstream.format, &wave_format);
    complete_wave_format_data(&wave_format);

    if (FAILED(hr = IAudioClient_Initialize(osw.audio_client, share_mode, flags,
            buffer_duration, periodicity, cast(WAVEFORMATEX*)&wave_format, null)))
    {
        if (hr == AUDCLNT_E_BUFFER_SIZE_NOT_ALIGNED) {
            if (FAILED(hr = IAudioClient_GetBufferSize(osw.audio_client, &osw.buffer_frame_count))) {
                return SoundIoError.OpeningDevice;
            }
            IUnknown_Release(osw.audio_client);
            osw.audio_client = null;
            if (FAILED(hr = IMMDevice_Activate(dw.mm_device, IID_IAUDIOCLIENT,
                            CLSCTX_ALL, null, cast(void**)&osw.audio_client)))
            {
                return SoundIoError.OpeningDevice;
            }
            if (!osw.is_raw) {
                WAVEFORMATEXTENSIBLE* mix_format;
                if (FAILED(hr = IAudioClient_GetMixFormat(osw.audio_client, cast(WAVEFORMATEX**)&mix_format))) {
                    return SoundIoError.OpeningDevice;
                }
                wave_format.Format.nSamplesPerSec = cast(DWORD)outstream.sample_rate;
                osw.need_resample = (mix_format.Format.nSamplesPerSec != wave_format.Format.nSamplesPerSec);
                CoTaskMemFree(mix_format);
                mix_format = null;
                flags = osw.need_resample ? AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY : 0;
                to_wave_format_layout(&outstream.layout, &wave_format);
                to_wave_format_format(outstream.format, &wave_format);
                complete_wave_format_data(&wave_format);
            }

            buffer_duration = to_reference_time(osw.buffer_frame_count / cast(double)outstream.sample_rate);
            if (osw.is_raw)
                periodicity = buffer_duration;
            if (FAILED(hr = IAudioClient_Initialize(osw.audio_client, share_mode, flags,
                    buffer_duration, periodicity, cast(WAVEFORMATEX*)&wave_format, null)))
            {
                if (hr == AUDCLNT_E_UNSUPPORTED_FORMAT) {
                    return SoundIoError.IncompatibleDevice;
                } else if (hr == E_OUTOFMEMORY) {
                    return SoundIoError.NoMem;
                } else {
                    return SoundIoError.OpeningDevice;
                }
            }
        } else if (hr == AUDCLNT_E_UNSUPPORTED_FORMAT) {
            return SoundIoError.IncompatibleDevice;
        } else if (hr == E_OUTOFMEMORY) {
            return SoundIoError.NoMem;
        } else {
            return SoundIoError.OpeningDevice;
        }
    }
    REFERENCE_TIME max_latency_ref_time;
    if (FAILED(hr = IAudioClient_GetStreamLatency(osw.audio_client, &max_latency_ref_time))) {
        return SoundIoError.OpeningDevice;
    }
    double max_latency_sec = from_reference_time(max_latency_ref_time);
    osw.min_padding_frames = cast(int) ((max_latency_sec * outstream.sample_rate) + 0.5);


    if (FAILED(hr = IAudioClient_GetBufferSize(osw.audio_client, &osw.buffer_frame_count))) {
        return SoundIoError.OpeningDevice;
    }
    outstream.software_latency = osw.buffer_frame_count / cast(double)outstream.sample_rate;

    if (osw.is_raw) {
        if (FAILED(hr = IAudioClient_SetEventHandle(osw.audio_client, osw.h_event))) {
            return SoundIoError.OpeningDevice;
        }
    }

    if (outstream.name) {
        if (FAILED(hr = IAudioClient_GetService(osw.audio_client, IID_IAUDIOSESSIONCONTROL,
                        cast(void**)&osw.audio_session_control)))
        {
            return SoundIoError.OpeningDevice;
        }

        if (auto err = to_lpwstr(outstream.name, cast(int) strlen(outstream.name), &osw.stream_name)) {
            return err;
        }
        if (FAILED(hr = IAudioSessionControl_SetDisplayName(osw.audio_session_control,
                        osw.stream_name, null)))
        {
            return SoundIoError.OpeningDevice;
        }
    }

    if (FAILED(hr = IAudioClient_GetService(osw.audio_client, IID_IAUDIORENDERCLIENT,
                    cast(void**)&osw.audio_render_client)))
    {
        return SoundIoError.OpeningDevice;
    }

    if (FAILED(hr = IAudioClient_GetService(osw.audio_client, IID_ISIMPLEAUDIOVOLUME,
                    cast(void**)&osw.audio_volume_control)))
    {
        return SoundIoError.OpeningDevice;
    }

    if (FAILED(hr = osw.audio_volume_control.lpVtbl.GetMasterVolume(osw.audio_volume_control, &outstream.volume)))
    {
        return SoundIoError.OpeningDevice;
    }

    return 0;
}

static void outstream_shared_run(SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamWasapi* osw = &os.backend_data.wasapi;
    SoundIoOutStream* outstream = &os.pub;

    HRESULT hr;

    UINT32 frames_used;
    if (FAILED(hr = IAudioClient_GetCurrentPadding(osw.audio_client, &frames_used))) {
        outstream.error_callback(outstream, SoundIoError.Streaming);
        return;
    }
    osw.writable_frame_count = osw.buffer_frame_count - frames_used;
    if (osw.writable_frame_count <= 0) {
        outstream.error_callback(outstream, SoundIoError.Streaming);
        return;
    }
    int frame_count_min = soundio_int_max(0, cast(int)osw.min_padding_frames - cast(int)frames_used);
    outstream.write_callback(outstream, frame_count_min, osw.writable_frame_count);

    if (FAILED(hr = IAudioClient_Start(osw.audio_client))) {
        outstream.error_callback(outstream, SoundIoError.Streaming);
        return;
    }

    for (;;) {
        if (FAILED(hr = IAudioClient_GetCurrentPadding(osw.audio_client, &frames_used))) {
            outstream.error_callback(outstream, SoundIoError.Streaming);
            return;
        }
        osw.writable_frame_count = osw.buffer_frame_count - frames_used;
        double time_until_underrun = frames_used / cast(double)outstream.sample_rate;
        double wait_time = time_until_underrun / 2.0;
        soundio_os_mutex_lock(osw.mutex);
        soundio_os_cond_timed_wait(osw.cond, osw.mutex, wait_time);
        if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osw.thread_exit_flag)) {
            soundio_os_mutex_unlock(osw.mutex);
            return;
        }
        soundio_os_mutex_unlock(osw.mutex);
        bool reset_buffer = false;
        if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osw.clear_buffer_flag)) {
            if (!osw.is_paused) {
                if (FAILED(hr = IAudioClient_Stop(osw.audio_client))) {
                    outstream.error_callback(outstream, SoundIoError.Streaming);
                    return;
                }
                osw.is_paused = true;
            }
            if (FAILED(hr = IAudioClient_Reset(osw.audio_client))) {
                outstream.error_callback(outstream, SoundIoError.Streaming);
                return;
            }
            SOUNDIO_ATOMIC_FLAG_CLEAR(osw.pause_resume_flag);
            reset_buffer = true;
        }
        if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osw.pause_resume_flag)) {
            bool pause = SOUNDIO_ATOMIC_LOAD(osw.desired_pause_state);
            if (pause && !osw.is_paused) {
                if (FAILED(hr = IAudioClient_Stop(osw.audio_client))) {
                    outstream.error_callback(outstream, SoundIoError.Streaming);
                    return;
                }
                osw.is_paused = true;
            } else if (!pause && osw.is_paused) {
                if (FAILED(hr = IAudioClient_Start(osw.audio_client))) {
                    outstream.error_callback(outstream, SoundIoError.Streaming);
                    return;
                }
                osw.is_paused = false;
            }
        }

        if (FAILED(hr = IAudioClient_GetCurrentPadding(osw.audio_client, &frames_used))) {
            outstream.error_callback(outstream, SoundIoError.Streaming);
            return;
        }
        osw.writable_frame_count = osw.buffer_frame_count - frames_used;
        if (osw.writable_frame_count > 0) {
            if (frames_used == 0 && !reset_buffer)
                outstream.underflow_callback(outstream);
            int frame_count_min1 = soundio_int_max(0, cast(int)osw.min_padding_frames - cast(int)frames_used);
            outstream.write_callback(outstream, frame_count_min1, osw.writable_frame_count);
        }
    }
}

static void outstream_raw_run(SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamWasapi* osw = &os.backend_data.wasapi;
    SoundIoOutStream* outstream = &os.pub;

    HRESULT hr;

    outstream.write_callback(outstream, osw.buffer_frame_count, osw.buffer_frame_count);

    if (FAILED(hr = IAudioClient_Start(osw.audio_client))) {
        outstream.error_callback(outstream, SoundIoError.Streaming);
        return;
    }

    for (;;) {
        WaitForSingleObject(osw.h_event, INFINITE);
        if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osw.thread_exit_flag))
            return;
        if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osw.pause_resume_flag)) {
            bool pause = SOUNDIO_ATOMIC_LOAD(osw.desired_pause_state);
            if (pause && !osw.is_paused) {
                if (FAILED(hr = IAudioClient_Stop(osw.audio_client))) {
                    outstream.error_callback(outstream, SoundIoError.Streaming);
                    return;
                }
                osw.is_paused = true;
            } else if (!pause && osw.is_paused) {
                if (FAILED(hr = IAudioClient_Start(osw.audio_client))) {
                    outstream.error_callback(outstream, SoundIoError.Streaming);
                    return;
                }
                osw.is_paused = false;
            }
        }

        outstream.write_callback(outstream, osw.buffer_frame_count, osw.buffer_frame_count);
    }
}

static void outstream_thread_run(void* arg) {
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)arg;
    SoundIoOutStreamWasapi* osw = &os.backend_data.wasapi;
    SoundIoOutStream* outstream = &os.pub;
    SoundIoDevice* device = outstream.device;
    SoundIo* soundio = device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;

    if (auto err = outstream_do_open(si, os)) {
        outstream_thread_deinit(si, os);

        soundio_os_mutex_lock(osw.mutex);
        osw.open_err = err;
        osw.open_complete = true;
        soundio_os_cond_signal(osw.cond, osw.mutex);
        soundio_os_mutex_unlock(osw.mutex);
        return;
    }

    soundio_os_mutex_lock(osw.mutex);
    osw.open_complete = true;
    soundio_os_cond_signal(osw.cond, osw.mutex);
    for (;;) {
        if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osw.thread_exit_flag)) {
            soundio_os_mutex_unlock(osw.mutex);
            return;
        }
        if (osw.started) {
            soundio_os_mutex_unlock(osw.mutex);
            break;
        }
        soundio_os_cond_wait(osw.start_cond, osw.mutex);
    }

    if (osw.is_raw)
        outstream_raw_run(os);
    else
        outstream_shared_run(os);

    outstream_thread_deinit(si, os);
}

static int outstream_open_wasapi(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamWasapi* osw = &os.backend_data.wasapi;
    SoundIoOutStream* outstream = &os.pub;
    SoundIoDevice* device = outstream.device;
    SoundIo* soundio = &si.pub;

    SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osw.pause_resume_flag);
    SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osw.clear_buffer_flag);
    SOUNDIO_ATOMIC_STORE(osw.desired_pause_state, false);

    // All the COM functions are supposed to be called from the same thread. libsoundio API does not
    // restrict the calling thread context in this way. Furthermore, the user might have called
    // CoInitializeEx with a different threading model than Single Threaded Apartment.
    // So we create a thread to do all the initialization and teardown, and communicate state
    // via conditions and signals. The thread for initialization and teardown is also used
    // for the realtime code calls the user write_callback.

    osw.is_raw = device.is_raw;

    if (!cast(bool)(osw.cond = soundio_os_cond_create())) {
        outstream_destroy_wasapi(si, os);
        return SoundIoError.NoMem;
    }

    if (!cast(bool)(osw.start_cond = soundio_os_cond_create())) {
        outstream_destroy_wasapi(si, os);
        return SoundIoError.NoMem;
    }

    if (!cast(bool)(osw.mutex = soundio_os_mutex_create())) {
        outstream_destroy_wasapi(si, os);
        return SoundIoError.NoMem;
    }

    if (osw.is_raw) {
        osw.h_event = CreateEvent(null, FALSE, FALSE, null);
        if (!osw.h_event) {
            outstream_destroy_wasapi(si, os);
            return SoundIoError.OpeningDevice;
        }
    }

    SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(osw.thread_exit_flag);
    if (auto err = soundio_os_thread_create(&outstream_thread_run, os,
                    soundio.emit_rtprio_warning, &osw.thread))
    {
        outstream_destroy_wasapi(si, os);
        return err;
    }

    soundio_os_mutex_lock(osw.mutex);
    while (!osw.open_complete)
        soundio_os_cond_wait(osw.cond, osw.mutex);
    soundio_os_mutex_unlock(osw.mutex);

    if (osw.open_err) {
        outstream_destroy_wasapi(si, os);
        return osw.open_err;
    }

    return 0;
}

static int outstream_pause_wasapi(SoundIoPrivate* si, SoundIoOutStreamPrivate* os, bool pause) {
    SoundIoOutStreamWasapi* osw = &os.backend_data.wasapi;

    SOUNDIO_ATOMIC_STORE(osw.desired_pause_state, pause);
    SOUNDIO_ATOMIC_FLAG_CLEAR(osw.pause_resume_flag);
    if (osw.h_event) {
        SetEvent(osw.h_event);
    } else {
        soundio_os_mutex_lock(osw.mutex);
        soundio_os_cond_signal(osw.cond, osw.mutex);
        soundio_os_mutex_unlock(osw.mutex);
    }

    return 0;
}

static int outstream_start_wasapi(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamWasapi* osw = &os.backend_data.wasapi;

    soundio_os_mutex_lock(osw.mutex);
    osw.started = true;
    soundio_os_cond_signal(osw.start_cond, osw.mutex);
    soundio_os_mutex_unlock(osw.mutex);

    return 0;
}

static int outstream_begin_write_wasapi(SoundIoPrivate* si, SoundIoOutStreamPrivate* os, SoundIoChannelArea** out_areas, int* frame_count) {
    SoundIoOutStreamWasapi* osw = &os.backend_data.wasapi;
    SoundIoOutStream* outstream = &os.pub;
    HRESULT hr;

    osw.write_frame_count = *frame_count;


    char* data;
    if (FAILED(hr = IAudioRenderClient_GetBuffer(osw.audio_render_client,
                    osw.write_frame_count, cast(BYTE**)&data)))
    {
        return SoundIoError.Streaming;
    }

    for (int ch = 0; ch < outstream.layout.channel_count; ch += 1) {
        osw.areas[ch].ptr = data + ch * outstream.bytes_per_sample;
        osw.areas[ch].step = outstream.bytes_per_frame;
    }

    *out_areas = osw.areas.ptr;

    return 0;
}

static int outstream_end_write_wasapi(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamWasapi* osw = &os.backend_data.wasapi;
    HRESULT hr;
    if (FAILED(hr = IAudioRenderClient_ReleaseBuffer(osw.audio_render_client, osw.write_frame_count, 0))) {
        return SoundIoError.Streaming;
    }
    return 0;
}

static int outstream_clear_buffer_wasapi(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamWasapi* osw = &os.backend_data.wasapi;

    if (osw.h_event) {
        return SoundIoError.IncompatibleDevice;
    } else {
        SOUNDIO_ATOMIC_FLAG_CLEAR(osw.clear_buffer_flag);
        soundio_os_mutex_lock(osw.mutex);
        soundio_os_cond_signal(osw.cond, osw.mutex);
        soundio_os_mutex_unlock(osw.mutex);
    }

    return 0;
}

static int outstream_get_latency_wasapi(SoundIoPrivate* si, SoundIoOutStreamPrivate* os, double* out_latency) {
    SoundIoOutStream* outstream = &os.pub;
    SoundIoOutStreamWasapi* osw = &os.backend_data.wasapi;

    HRESULT hr;
    UINT32 frames_used;
    if (FAILED(hr = IAudioClient_GetCurrentPadding(osw.audio_client, &frames_used))) {
        return SoundIoError.Streaming;
    }

    *out_latency = frames_used / cast(double)outstream.sample_rate;
    return 0;
}

static int outstream_set_volume_wasapi(SoundIoPrivate* si, SoundIoOutStreamPrivate* os, float volume) {
    SoundIoOutStream* outstream = &os.pub;
    SoundIoOutStreamWasapi* osw = &os.backend_data.wasapi;

    HRESULT hr;
    if (FAILED(hr = osw.audio_volume_control.lpVtbl.SetMasterVolume(osw.audio_volume_control, volume, null)))
    {
        return SoundIoError.IncompatibleDevice;
    }

    outstream.volume = volume;
    return 0;
}

static void instream_thread_deinit(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamWasapi* isw = &is_.backend_data.wasapi;

    if (isw.audio_capture_client)
        IUnknown_Release(isw.audio_capture_client);
    if (isw.audio_client)
        IUnknown_Release(isw.audio_client);
}


static void instream_destroy_wasapi(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamWasapi* isw = &is_.backend_data.wasapi;

    if (isw.thread) {
        SOUNDIO_ATOMIC_FLAG_CLEAR(isw.thread_exit_flag);
        if (isw.h_event)
            SetEvent(isw.h_event);

        soundio_os_mutex_lock(isw.mutex);
        soundio_os_cond_signal(isw.cond, isw.mutex);
        soundio_os_cond_signal(isw.start_cond, isw.mutex);
        soundio_os_mutex_unlock(isw.mutex);
        soundio_os_thread_destroy(isw.thread);

        isw.thread = null;
    }

    if (isw.h_event) {
        CloseHandle(isw.h_event);
        isw.h_event = null;
    }

    soundio_os_cond_destroy(isw.cond);
    isw.cond = null;

    soundio_os_cond_destroy(isw.start_cond);
    isw.start_cond = null;

    soundio_os_mutex_destroy(isw.mutex);
    isw.mutex = null;
}

static int instream_do_open(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamWasapi* isw = &is_.backend_data.wasapi;
    SoundIoInStream* instream = &is_.pub;
    SoundIoDevice* device = instream.device;
    SoundIoDevicePrivate* dev = cast(SoundIoDevicePrivate*)device;
    SoundIoDeviceWasapi* dw = &dev.backend_data.wasapi;
    HRESULT hr;

    if (FAILED(hr = IMMDevice_Activate(dw.mm_device, IID_IAUDIOCLIENT,
                    CLSCTX_ALL, null, cast(void**)&isw.audio_client)))
    {
        return SoundIoError.OpeningDevice;
    }

    AUDCLNT_SHAREMODE share_mode;
    DWORD flags;
    REFERENCE_TIME buffer_duration;
    REFERENCE_TIME periodicity;
    WAVEFORMATEXTENSIBLE wave_format = WAVEFORMATEXTENSIBLE.init; // todo: zero?
    wave_format.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
    wave_format.Format.cbSize = WAVEFORMATEXTENSIBLE.sizeof - WAVEFORMATEX.sizeof;
    if (isw.is_raw) {
        wave_format.Format.nSamplesPerSec = instream.sample_rate;
        flags = AUDCLNT_STREAMFLAGS_EVENTCALLBACK;
        share_mode = AUDCLNT_SHAREMODE_EXCLUSIVE;
        periodicity = to_reference_time(dw.period_duration);
        buffer_duration = periodicity;
    } else {
        WAVEFORMATEXTENSIBLE* mix_format;
        if (FAILED(hr = IAudioClient_GetMixFormat(isw.audio_client, cast(WAVEFORMATEX**)&mix_format))) {
            return SoundIoError.OpeningDevice;
        }
        wave_format.Format.nSamplesPerSec = mix_format.Format.nSamplesPerSec;
        CoTaskMemFree(mix_format);
        mix_format = null;
        if (wave_format.Format.nSamplesPerSec != cast(DWORD)instream.sample_rate) {
            return SoundIoError.IncompatibleDevice;
        }
        flags = 0;
        share_mode = AUDCLNT_SHAREMODE_SHARED;
        periodicity = 0;
        buffer_duration = to_reference_time(4.0);
    }
    to_wave_format_layout(&instream.layout, &wave_format);
    to_wave_format_format(instream.format, &wave_format);
    complete_wave_format_data(&wave_format);

    if (FAILED(hr = IAudioClient_Initialize(isw.audio_client, share_mode, flags,
            buffer_duration, periodicity, cast(WAVEFORMATEX*)&wave_format, null)))
    {
        if (hr == AUDCLNT_E_BUFFER_SIZE_NOT_ALIGNED) {
            if (FAILED(hr = IAudioClient_GetBufferSize(isw.audio_client, &isw.buffer_frame_count))) {
                return SoundIoError.OpeningDevice;
            }
            IUnknown_Release(isw.audio_client);
            isw.audio_client = null;
            if (FAILED(hr = IMMDevice_Activate(dw.mm_device, IID_IAUDIOCLIENT,
                            CLSCTX_ALL, null, cast(void**)&isw.audio_client)))
            {
                return SoundIoError.OpeningDevice;
            }
            if (!isw.is_raw) {
                WAVEFORMATEXTENSIBLE* mix_format;
                if (FAILED(hr = IAudioClient_GetMixFormat(isw.audio_client, cast(WAVEFORMATEX**)&mix_format))) {
                    return SoundIoError.OpeningDevice;
                }
                wave_format.Format.nSamplesPerSec = mix_format.Format.nSamplesPerSec;
                CoTaskMemFree(mix_format);
                mix_format = null;
                flags = 0;
                to_wave_format_layout(&instream.layout, &wave_format);
                to_wave_format_format(instream.format, &wave_format);
                complete_wave_format_data(&wave_format);
            }

            buffer_duration = to_reference_time(isw.buffer_frame_count / cast(double)instream.sample_rate);
            if (isw.is_raw)
                periodicity = buffer_duration;
            if (FAILED(hr = IAudioClient_Initialize(isw.audio_client, share_mode, flags,
                    buffer_duration, periodicity, cast(WAVEFORMATEX*)&wave_format, null)))
            {
                if (hr == AUDCLNT_E_UNSUPPORTED_FORMAT) {
                    return SoundIoError.IncompatibleDevice;
                } else if (hr == E_OUTOFMEMORY) {
                    return SoundIoError.NoMem;
                } else {
                    return SoundIoError.OpeningDevice;
                }
            }
        } else if (hr == AUDCLNT_E_UNSUPPORTED_FORMAT) {
            return SoundIoError.IncompatibleDevice;
        } else if (hr == E_OUTOFMEMORY) {
            return SoundIoError.NoMem;
        } else {
            return SoundIoError.OpeningDevice;
        }
    }
    if (FAILED(hr = IAudioClient_GetBufferSize(isw.audio_client, &isw.buffer_frame_count))) {
        return SoundIoError.OpeningDevice;
    }
    if (instream.software_latency == 0.0)
        instream.software_latency = 1.0;
    instream.software_latency = soundio_double_clamp(device.software_latency_min,
            instream.software_latency, device.software_latency_max);
    if (isw.is_raw)
        instream.software_latency = isw.buffer_frame_count / cast(double)instream.sample_rate;

    if (isw.is_raw) {
        if (FAILED(hr = IAudioClient_SetEventHandle(isw.audio_client, isw.h_event))) {
            return SoundIoError.OpeningDevice;
        }
    }

    if (instream.name) {
        if (FAILED(hr = IAudioClient_GetService(isw.audio_client, IID_IAUDIOSESSIONCONTROL,
                        cast(void**)&isw.audio_session_control)))
        {
            return SoundIoError.OpeningDevice;
        }

        if (auto err = to_lpwstr(instream.name, cast(int) strlen(instream.name), &isw.stream_name)) {
            return err;
        }
        if (FAILED(hr = IAudioSessionControl_SetDisplayName(isw.audio_session_control,
                        isw.stream_name, null)))
        {
            return SoundIoError.OpeningDevice;
        }
    }

    if (FAILED(hr = IAudioClient_GetService(isw.audio_client, IID_IAUDIOCAPTURECLIENT,
                    cast(void**)&isw.audio_capture_client)))
    {
        return SoundIoError.OpeningDevice;
    }

    return 0;
}

static void instream_raw_run(SoundIoInStreamPrivate* is_) {
    SoundIoInStreamWasapi* isw = &is_.backend_data.wasapi;
    SoundIoInStream* instream = &is_.pub;

    HRESULT hr;

    if (FAILED(hr = IAudioClient_Start(isw.audio_client))) {
        instream.error_callback(instream, SoundIoError.Streaming);
        return;
    }

    for (;;) {
        WaitForSingleObject(isw.h_event, INFINITE);
        if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(isw.thread_exit_flag))
            return;

        instream.read_callback(instream, isw.buffer_frame_count, isw.buffer_frame_count);
    }
}

static void instream_shared_run(SoundIoInStreamPrivate* is_) {
    SoundIoInStreamWasapi* isw = &is_.backend_data.wasapi;
    SoundIoInStream* instream = &is_.pub;

    HRESULT hr;

    if (FAILED(hr = IAudioClient_Start(isw.audio_client))) {
        instream.error_callback(instream, SoundIoError.Streaming);
        return;
    }

    for (;;) {
        soundio_os_mutex_lock(isw.mutex);
        soundio_os_cond_timed_wait(isw.cond, isw.mutex, instream.software_latency / 2.0);
        if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(isw.thread_exit_flag)) {
            soundio_os_mutex_unlock(isw.mutex);
            return;
        }
        soundio_os_mutex_unlock(isw.mutex);

        UINT32 frames_available;
        if (FAILED(hr = IAudioClient_GetCurrentPadding(isw.audio_client, &frames_available))) {
            instream.error_callback(instream, SoundIoError.Streaming);
            return;
        }

        isw.readable_frame_count = frames_available;
        if (isw.readable_frame_count > 0)
            instream.read_callback(instream, 0, isw.readable_frame_count);
    }
}

static void instream_thread_run(void* arg) {
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)arg;
    SoundIoInStreamWasapi* isw = &is_.backend_data.wasapi;
    SoundIoInStream* instream = &is_.pub;
    SoundIoDevice* device = instream.device;
    SoundIo* soundio = device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;

    if (auto err = instream_do_open(si, is_)) {
        instream_thread_deinit(si, is_);

        soundio_os_mutex_lock(isw.mutex);
        isw.open_err = err;
        isw.open_complete = true;
        soundio_os_cond_signal(isw.cond, isw.mutex);
        soundio_os_mutex_unlock(isw.mutex);
        return;
    }

    soundio_os_mutex_lock(isw.mutex);
    isw.open_complete = true;
    soundio_os_cond_signal(isw.cond, isw.mutex);
    for (;;) {
        if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(isw.thread_exit_flag)) {
            soundio_os_mutex_unlock(isw.mutex);
            return;
        }
        if (isw.started) {
            soundio_os_mutex_unlock(isw.mutex);
            break;
        }
        soundio_os_cond_wait(isw.start_cond, isw.mutex);
    }

    if (isw.is_raw)
        instream_raw_run(is_);
    else
        instream_shared_run(is_);

    instream_thread_deinit(si, is_);
}

static int instream_open_wasapi(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamWasapi* isw = &is_.backend_data.wasapi;
    SoundIoInStream* instream = &is_.pub;
    SoundIoDevice* device = instream.device;
    SoundIo* soundio = &si.pub;

    // All the COM functions are supposed to be called from the same thread. libsoundio API does not
    // restrict the calling thread context in this way. Furthermore, the user might have called
    // CoInitializeEx with a different threading model than Single Threaded Apartment.
    // So we create a thread to do all the initialization and teardown, and communicate state
    // via conditions and signals. The thread for initialization and teardown is also used
    // for the realtime code calls the user write_callback.

    isw.is_raw = device.is_raw;

    isw.cond = soundio_os_cond_create();
    if (!isw.cond) {
        instream_destroy_wasapi(si, is_);
        return SoundIoError.NoMem;
    }

    isw.start_cond = soundio_os_cond_create();
    if (!isw.start_cond) {
        instream_destroy_wasapi(si, is_);
        return SoundIoError.NoMem;
    }

    isw.mutex = soundio_os_mutex_create();
    if (!isw.mutex) {
        instream_destroy_wasapi(si, is_);
        return SoundIoError.NoMem;
    }

    if (isw.is_raw) {
        isw.h_event = CreateEvent(null, FALSE, FALSE, null);
        if (!isw.h_event) {
            instream_destroy_wasapi(si, is_);
            return SoundIoError.OpeningDevice;
        }
    }

    SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(isw.thread_exit_flag);
    if (auto err = soundio_os_thread_create(&instream_thread_run, is_,
                    soundio.emit_rtprio_warning, &isw.thread))
    {
        instream_destroy_wasapi(si, is_);
        return err;
    }

    soundio_os_mutex_lock(isw.mutex);
    while (!isw.open_complete)
        soundio_os_cond_wait(isw.cond, isw.mutex);
    soundio_os_mutex_unlock(isw.mutex);

    if (isw.open_err) {
        instream_destroy_wasapi(si, is_);
        return isw.open_err;
    }

    return 0;
}

static int instream_pause_wasapi(SoundIoPrivate* si, SoundIoInStreamPrivate* is_, bool pause) {
    SoundIoInStreamWasapi* isw = &is_.backend_data.wasapi;
    HRESULT hr;
    if (pause && !isw.is_paused) {
        if (FAILED(hr = IAudioClient_Stop(isw.audio_client)))
            return SoundIoError.Streaming;
        isw.is_paused = true;
    } else if (!pause && isw.is_paused) {
        if (FAILED(hr = IAudioClient_Start(isw.audio_client)))
            return SoundIoError.Streaming;
        isw.is_paused = false;
    }
    return 0;
}

static int instream_start_wasapi(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamWasapi* isw = &is_.backend_data.wasapi;

    soundio_os_mutex_lock(isw.mutex);
    isw.started = true;
    soundio_os_cond_signal(isw.start_cond, isw.mutex);
    soundio_os_mutex_unlock(isw.mutex);

    return 0;
}

static int instream_begin_read_wasapi(SoundIoPrivate* si, SoundIoInStreamPrivate* is_, SoundIoChannelArea** out_areas, int* frame_count) {
    SoundIoInStreamWasapi* isw = &is_.backend_data.wasapi;
    SoundIoInStream* instream = &is_.pub;
    HRESULT hr;

    if (isw.read_buf_frames_left <= 0) {
        UINT32 frames_to_read;
        DWORD flags;
        if (FAILED(hr = IAudioCaptureClient_GetBuffer(isw.audio_capture_client,
                        cast(BYTE**)&isw.read_buf, &frames_to_read, &flags, null, null)))
        {
            return SoundIoError.Streaming;
        }
		isw.opened_buf_frames = frames_to_read;
		isw.read_buf_frames_left = frames_to_read;

        if (flags & AUDCLNT_BUFFERFLAGS_SILENT)
            isw.read_buf = null;
    }

    isw.read_frame_count = soundio_int_min(*frame_count, isw.read_buf_frames_left);
    *frame_count = isw.read_frame_count;

    if (isw.read_buf) {
        for (int ch = 0; ch < instream.layout.channel_count; ch += 1) {
            isw.areas[ch].ptr = isw.read_buf + ch * instream.bytes_per_sample;
            isw.areas[ch].step = instream.bytes_per_frame;

			isw.areas[ch].ptr += instream.bytes_per_frame * (isw.opened_buf_frames - isw.read_buf_frames_left);
        }

        *out_areas = isw.areas.ptr;
    } else {
        *out_areas = null;
    }

    return 0;
}

static int instream_end_read_wasapi(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamWasapi* isw = &is_.backend_data.wasapi;
    HRESULT hr;

	isw.read_buf_frames_left -= isw.read_frame_count;

	if (isw.read_buf_frames_left <= 0) {
		if (FAILED(hr = IAudioCaptureClient_ReleaseBuffer(isw.audio_capture_client, isw.opened_buf_frames))) {
			return SoundIoError.Streaming;
		}
	}

    return 0;
}

static int instream_get_latency_wasapi(SoundIoPrivate* si, SoundIoInStreamPrivate* is_, double* out_latency) {
    SoundIoInStream* instream = &is_.pub;
    SoundIoInStreamWasapi* isw = &is_.backend_data.wasapi;

    HRESULT hr;
    UINT32 frames_used;
    if (FAILED(hr = IAudioClient_GetCurrentPadding(isw.audio_client, &frames_used))) {
        return SoundIoError.Streaming;
    }

    *out_latency = frames_used / cast(double)instream.sample_rate;
    return 0;
}


static void destroy_wasapi(SoundIoPrivate* si) {
    SoundIoWasapi* siw = &si.backend_data.wasapi;

    if (siw.thread) {
        soundio_os_mutex_lock(siw.scan_devices_mutex);
        siw.abort_flag = true;
        soundio_os_cond_signal(siw.scan_devices_cond, siw.scan_devices_mutex);
        soundio_os_mutex_unlock(siw.scan_devices_mutex);
        soundio_os_thread_destroy(siw.thread);
    }

    if (siw.cond)
        soundio_os_cond_destroy(siw.cond);

    if (siw.scan_devices_cond)
        soundio_os_cond_destroy(siw.scan_devices_cond);

    if (siw.scan_devices_mutex)
        soundio_os_mutex_destroy(siw.scan_devices_mutex);

    if (siw.mutex)
        soundio_os_mutex_destroy(siw.mutex);

    soundio_destroy_devices_info(siw.ready_devices_info);
}

pragma(inline, true) static shared(SoundIoPrivate)* soundio_MMNotificationClient_si(IMMNotificationClient* client) {
    auto siw = cast(SoundIoWasapi*)((cast(ubyte*)client) - SoundIoWasapi.device_events.offsetof);
    auto si = cast(shared(SoundIoPrivate)*)((cast(ubyte*)siw)   - SoundIoPrivate.backend_data.offsetof);
    return si;
}

static extern(Windows) HRESULT soundio_MMNotificationClient_QueryInterface(IMMNotificationClient* client, REFIID riid, void** ppv) {
    if (IS_EQUAL_IID(riid, &IID_IUnknown) || IS_EQUAL_IID(riid, &IID_IMMNotificationClient)) {
        *ppv = client;
        IUnknown_AddRef(client);
        return S_OK;
    } else {
       *ppv = null;
        return E_NOINTERFACE;
    }
}

static extern(Windows) ULONG soundio_MMNotificationClient_AddRef(IMMNotificationClient* client) {
    shared SoundIoPrivate* si = soundio_MMNotificationClient_si(client);
    shared SoundIoWasapi* siw = &si.backend_data.wasapi;
    // workaround because `InterlockedIncrement` is missing in D's Kernel32 import library
    return atomicOp!"+="(siw.device_events_refs, 1);
    //return InterlockedIncrement(&siw.device_events_refs);
}

static extern(Windows) ULONG soundio_MMNotificationClient_Release(IMMNotificationClient* client) {
    shared SoundIoPrivate* si = soundio_MMNotificationClient_si(client);
    shared SoundIoWasapi* siw = &si.backend_data.wasapi;
    // workaround because `InterlockedDecrement` is missing in D's Kernel32 import library
    return atomicOp!"-="(siw.device_events_refs, 1);
    //return InterlockedDecrement(&siw.device_events_refs);
}

static HRESULT queue_device_scan(IMMNotificationClient* client) {
    auto si = cast(SoundIoPrivate*) soundio_MMNotificationClient_si(client); // cast away shared
    force_device_scan_wasapi(si);
    return S_OK;
}

static extern(Windows) HRESULT soundio_MMNotificationClient_OnDeviceStateChanged(IMMNotificationClient* client, LPCWSTR wid, DWORD state) {
    return queue_device_scan(client);
}

static extern(Windows) HRESULT soundio_MMNotificationClient_OnDeviceAdded(IMMNotificationClient* client, LPCWSTR wid) {
    return queue_device_scan(client);
}

static extern(Windows) HRESULT soundio_MMNotificationClient_OnDeviceRemoved(IMMNotificationClient* client, LPCWSTR wid) {
    return queue_device_scan(client);
}

static extern(Windows) HRESULT soundio_MMNotificationClient_OnDefaultDeviceChange(IMMNotificationClient* client, EDataFlow flow, ERole role, LPCWSTR wid) {
    return queue_device_scan(client);
}

static extern(Windows) HRESULT soundio_MMNotificationClient_OnPropertyValueChanged(IMMNotificationClient* client, LPCWSTR wid, const(PROPERTYKEY) key) {
    return queue_device_scan(client);
}


static IMMNotificationClientVtbl soundio_MMNotificationClient = IMMNotificationClientVtbl(
    &soundio_MMNotificationClient_QueryInterface,
    &soundio_MMNotificationClient_AddRef,
    &soundio_MMNotificationClient_Release,
    &soundio_MMNotificationClient_OnDeviceStateChanged,
    &soundio_MMNotificationClient_OnDeviceAdded,
    &soundio_MMNotificationClient_OnDeviceRemoved,
    &soundio_MMNotificationClient_OnDefaultDeviceChange,
    &soundio_MMNotificationClient_OnPropertyValueChanged,
);

package int soundio_wasapi_init(SoundIoPrivate* si) {
    SoundIoWasapi* siw = &si.backend_data.wasapi;

    siw.device_scan_queued = true;

    siw.mutex = soundio_os_mutex_create();
    if (!siw.mutex) {
        destroy_wasapi(si);
        return SoundIoError.NoMem;
    }

    siw.scan_devices_mutex = soundio_os_mutex_create();
    if (!siw.scan_devices_mutex) {
        destroy_wasapi(si);
        return SoundIoError.NoMem;
    }

    siw.cond = soundio_os_cond_create();
    if (!siw.cond) {
        destroy_wasapi(si);
        return SoundIoError.NoMem;
    }

    siw.scan_devices_cond = soundio_os_cond_create();
    if (!siw.scan_devices_cond) {
        destroy_wasapi(si);
        return SoundIoError.NoMem;
    }

    siw.device_events.lpVtbl = &soundio_MMNotificationClient;
    siw.device_events_refs = 1;

    if (auto err = soundio_os_thread_create(&device_thread_run, si, null, &siw.thread)) {
        destroy_wasapi(si);
        return err;
    }

    si.destroy = &destroy_wasapi;
    si.flush_events = &flush_events_wasapi;
    si.wait_events = &wait_events_wasapi;
    si.wakeup = &wakeup_wasapi;
    si.force_device_scan = &force_device_scan_wasapi;

    si.outstream_open = &outstream_open_wasapi;
    si.outstream_destroy = &outstream_destroy_wasapi;
    si.outstream_start = &outstream_start_wasapi;
    si.outstream_begin_write = &outstream_begin_write_wasapi;
    si.outstream_end_write = &outstream_end_write_wasapi;
    si.outstream_clear_buffer = &outstream_clear_buffer_wasapi;
    si.outstream_pause = &outstream_pause_wasapi;
    si.outstream_get_latency = &outstream_get_latency_wasapi;
    si.outstream_set_volume = &outstream_set_volume_wasapi;

    si.instream_open = &instream_open_wasapi;
    si.instream_destroy = &instream_destroy_wasapi;
    si.instream_start = &instream_start_wasapi;
    si.instream_begin_read = &instream_begin_read_wasapi;
    si.instream_end_read = &instream_end_read_wasapi;
    si.instream_pause = &instream_pause_wasapi;
    si.instream_get_latency = &instream_get_latency_wasapi;

    return 0;
}
