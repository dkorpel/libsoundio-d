module soundio.api;

extern (C): @nogc: nothrow:

/// See also ::soundio_strerror
enum SoundIoError
{
    None = 0,
    /// Out of memory.
    NoMem = 1,
    /// The backend does not appear to be active or running.
    InitAudioBackend = 2,
    /// A system resource other than memory was not available.
    SystemResources = 3,
    /// Attempted to open a device and failed.
    OpeningDevice = 4,
    NoSuchDevice = 5,
    /// The programmer did not comply with the API.
    Invalid = 6,
    /// libsoundio was compiled without support for that backend.
    BackendUnavailable = 7,
    /// An open stream had an error that can only be recovered from by
    /// destroying the stream and creating it again.
    Streaming = 8,
    /// Attempted to use a device with parameters it cannot support.
    IncompatibleDevice = 9,
    /// When JACK returns `JackNoSuchClient`
    NoSuchClient = 10,
    /// Attempted to use parameters that the backend cannot support.
    IncompatibleBackend = 11,
    /// Backend server shutdown or became inactive.
    BackendDisconnected = 12,
    Interrupted = 13,
    /// Buffer underrun occurred.
    Underflow = 14,
    /// Unable to convert to or from UTF-8 to the native string format.
    EncodingString = 15
}

enum SoundIoErrorNone = SoundIoError.None; /// ditto
enum SoundIoErrorNoMem = SoundIoError.NoMem; /// ditto
enum SoundIoErrorInitAudioBackend = SoundIoError.InitAudioBackend; /// ditto
enum SoundIoErrorSystemResources = SoundIoError.SystemResources; /// ditto
enum SoundIoErrorOpeningDevice = SoundIoError.OpeningDevice; /// ditto
enum SoundIoErrorNoSuchDevice = SoundIoError.NoSuchDevice; /// ditto
enum SoundIoErrorInvalid = SoundIoError.Invalid; /// ditto
enum SoundIoErrorBackendUnavailable = SoundIoError.BackendUnavailable; /// ditto
enum SoundIoErrorStreaming = SoundIoError.Streaming; /// ditto
enum SoundIoErrorIncompatibleDevice = SoundIoError.IncompatibleDevice; /// ditto
enum SoundIoErrorNoSuchClient = SoundIoError.NoSuchClient; /// ditto
enum SoundIoErrorIncompatibleBackend = SoundIoError.IncompatibleBackend; /// ditto
enum SoundIoErrorBackendDisconnected = SoundIoError.BackendDisconnected; /// ditto
enum SoundIoErrorInterrupted = SoundIoError.Interrupted; /// ditto
enum SoundIoErrorUnderflow = SoundIoError.Underflow; /// ditto
enum SoundIoErrorEncodingString = SoundIoError.EncodingString; /// ditto


/// Specifies where a channel is physically located.
enum SoundIoChannelId
{
    Invalid = 0,

    FrontLeft = 1, ///< First of the more commonly supported ids.
    FrontRight = 2,
    FrontCenter = 3,
    Lfe = 4,
    BackLeft = 5,
    BackRight = 6,
    FrontLeftCenter = 7,
    FrontRightCenter = 8,
    BackCenter = 9,
    SideLeft = 10,
    SideRight = 11,
    TopCenter = 12,
    TopFrontLeft = 13,
    TopFrontCenter = 14,
    TopFrontRight = 15,
    TopBackLeft = 16,
    TopBackCenter = 17,
    TopBackRight = 18, ///< Last of the more commonly supported ids.

    BackLeftCenter = 19, ///< First of the less commonly supported ids.
    BackRightCenter = 20,
    FrontLeftWide = 21,
    FrontRightWide = 22,
    FrontLeftHigh = 23,
    FrontCenterHigh = 24,
    FrontRightHigh = 25,
    TopFrontLeftCenter = 26,
    TopFrontRightCenter = 27,
    TopSideLeft = 28,
    TopSideRight = 29,
    LeftLfe = 30,
    RightLfe = 31,
    Lfe2 = 32,
    BottomCenter = 33,
    BottomLeftCenter = 34,
    BottomRightCenter = 35,

    /// Mid/side recording
    MsMid = 36,
    MsSide = 37,

    /// first order ambisonic channels
    AmbisonicW = 38,
    AmbisonicX = 39,
    AmbisonicY = 40,
    AmbisonicZ = 41,

    /// X-Y Recording
    XyX = 42,
    XyY = 43,

    HeadphonesLeft = 44, ///< First of the "other" channel ids
    HeadphonesRight = 45,
    ClickTrack = 46,
    ForeignLanguage = 47,
    HearingImpaired = 48,
    Narration = 49,
    Haptic = 50,
    DialogCentricMix = 51, ///< Last of the "other" channel ids

    Aux = 52,
    Aux0 = 53,
    Aux1 = 54,
    Aux2 = 55,
    Aux3 = 56,
    Aux4 = 57,
    Aux5 = 58,
    Aux6 = 59,
    Aux7 = 60,
    Aux8 = 61,
    Aux9 = 62,
    Aux10 = 63,
    Aux11 = 64,
    Aux12 = 65,
    Aux13 = 66,
    Aux14 = 67,
    Aux15 = 68
}

/// Built-in channel layouts for convenience.
enum SoundIoChannelLayoutId
{
    Mono = 0,
    Stereo = 1,
    _2Point1 = 2,
    _3Point0 = 3,
    _3Point0Back = 4,
    _3Point1 = 5,
    _4Point0 = 6,
    Quad = 7,
    QuadSide = 8,
    _4Point1 = 9,
    _5Point0Back = 10,
    _5Point0Side = 11,
    _5Point1 = 12,
    _5Point1Back = 13,
    _6Point0Side = 14,
    _6Point0Front = 15,
    Hexagonal = 16,
    _6Point1 = 17,
    _6Point1Back = 18,
    _6Point1Front = 19,
    _7Point0 = 20,
    _7Point0Front = 21,
    _7Point1 = 22,
    _7Point1Wide = 23,
    _7Point1WideBack = 24,
    Octagonal = 25
}

///
enum SoundIoBackend
{
    None = 0,
    Jack = 1,
    PulseAudio = 2,
    Alsa = 3,
    CoreAudio = 4,
    Wasapi = 5,
    Dummy = 6
}

enum SoundIoBackendNone = SoundIoBackend.None; /// ditto
enum SoundIoBackendJack = SoundIoBackend.Jack; /// ditto
enum SoundIoBackendPulseAudio = SoundIoBackend.PulseAudio; /// ditto
enum SoundIoBackendAlsa = SoundIoBackend.Alsa; /// ditto
enum SoundIoBackendCoreAudio = SoundIoBackend.CoreAudio; /// ditto
enum SoundIoBackendWasapi = SoundIoBackend.Wasapi; /// ditto
enum SoundIoBackendDummy = SoundIoBackend.Dummy; /// ditto

/// Whether a device is an input device or output device
enum SoundIoDeviceAim
{
    Input = 0, ///< capture / recording
    Output = 1 ///< playback
}
enum SoundIoDeviceAimInput = SoundIoDeviceAim.Input; /// ditto
enum SoundIoDeviceAimOutput = SoundIoDeviceAim.Output; /// ditto

/// For your convenience, Native Endian and Foreign Endian constants are defined
/// which point to the respective SoundIoFormat values.
enum SoundIoFormat
{
    Invalid = 0,
    S8 = 1, ///< Signed 8 bit
    U8 = 2, ///< Unsigned 8 bit
    S16LE = 3, ///< Signed 16 bit Little Endian
    S16BE = 4, ///< Signed 16 bit Big Endian
    U16LE = 5, ///< Unsigned 16 bit Little Endian
    U16BE = 6, ///< Unsigned 16 bit Big Endian
    S24LE = 7, ///< Signed 24 bit Little Endian using low three bytes in 32-bit word
    S24BE = 8, ///< Signed 24 bit Big Endian using low three bytes in 32-bit word
    U24LE = 9, ///< Unsigned 24 bit Little Endian using low three bytes in 32-bit word
    U24BE = 10, ///< Unsigned 24 bit Big Endian using low three bytes in 32-bit word
    S32LE = 11, ///< Signed 32 bit Little Endian
    S32BE = 12, ///< Signed 32 bit Big Endian
    U32LE = 13, ///< Unsigned 32 bit Little Endian
    U32BE = 14, ///< Unsigned 32 bit Big Endian
    Float32LE = 15, ///< Float 32 bit Little Endian, Range -1.0 to 1.0
    Float32BE = 16, ///< Float 32 bit Big Endian, Range -1.0 to 1.0
    Float64LE = 17, ///< Float 64 bit Little Endian, Range -1.0 to 1.0
    Float64BE = 18, ///< Float 64 bit Big Endian, Range -1.0 to 1.0
    S16NE = SoundIoFormatS16NE,
    U16NE = SoundIoFormatU16NE,
    S24NE = SoundIoFormatS24NE,
    U24NE = SoundIoFormatU24NE,
    S32NE = SoundIoFormatS32NE,
    U32NE = SoundIoFormatU32NE,
    Float32NE = SoundIoFormatFloat32NE,
    Float64NE = SoundIoFormatFloat64NE,
    S16FE = SoundIoFormatS16FE,
    U16FE = SoundIoFormatU16FE,
    S24FE = SoundIoFormatS24FE,
    U24FE = SoundIoFormatU24FE,
    S32FE = SoundIoFormatS32FE,
    U32FE = SoundIoFormatU32FE,
    Float32FE = SoundIoFormatFloat32FE,
    Float64FE = SoundIoFormatFloat64FE,
}

enum SoundIoFormatInvalid = SoundIoFormat.Invalid; /// ditto
enum SoundIoFormatS8 = SoundIoFormat.S8; /// ditto
enum SoundIoFormatU8 = SoundIoFormat.U8; /// ditto
enum SoundIoFormatS16LE = SoundIoFormat.S16LE; /// ditto
enum SoundIoFormatS16BE = SoundIoFormat.S16BE; /// ditto
enum SoundIoFormatU16LE = SoundIoFormat.U16LE; /// ditto
enum SoundIoFormatU16BE = SoundIoFormat.U16BE; /// ditto
enum SoundIoFormatS24LE = SoundIoFormat.S24LE; /// ditto
enum SoundIoFormatS24BE = SoundIoFormat.S24BE; /// ditto
enum SoundIoFormatU24LE = SoundIoFormat.U24LE; /// ditto
enum SoundIoFormatU24BE = SoundIoFormat.U24BE; /// ditto
enum SoundIoFormatS32LE = SoundIoFormat.S32LE; /// ditto
enum SoundIoFormatS32BE = SoundIoFormat.S32BE; /// ditto
enum SoundIoFormatU32LE = SoundIoFormat.U32LE; /// ditto
enum SoundIoFormatU32BE = SoundIoFormat.U32BE; /// ditto
enum SoundIoFormatFloat32LE = SoundIoFormat.Float32LE; /// ditto
enum SoundIoFormatFloat32BE = SoundIoFormat.Float32BE; /// ditto
enum SoundIoFormatFloat64LE = SoundIoFormat.Float64LE; /// ditto
enum SoundIoFormatFloat64BE = SoundIoFormat.Float64BE; /// ditto

/// Note that we build the documentation in Little Endian mode,
/// so all the "NE" macros in the docs point to "LE" and
/// "FE" macros point to "BE". On a Big Endian system it is the
/// other way around.
version(LittleEndian) {
    enum SoundIoFormatS16NE = SoundIoFormat.S16LE; /// ditto
    enum SoundIoFormatU16NE = SoundIoFormat.U16LE; /// ditto
    enum SoundIoFormatS24NE = SoundIoFormat.S24LE; /// ditto
    enum SoundIoFormatU24NE = SoundIoFormat.U24LE; /// ditto
    enum SoundIoFormatS32NE = SoundIoFormat.S32LE; /// ditto
    enum SoundIoFormatU32NE = SoundIoFormat.U32LE; /// ditto
    enum SoundIoFormatFloat32NE = SoundIoFormat.Float32LE; /// ditto
    enum SoundIoFormatFloat64NE = SoundIoFormat.Float64LE; /// ditto

    enum SoundIoFormatS16FE = SoundIoFormat.S16BE; /// ditto
    enum SoundIoFormatU16FE = SoundIoFormat.U16BE; /// ditto
    enum SoundIoFormatS24FE = SoundIoFormat.S24BE; /// ditto
    enum SoundIoFormatU24FE = SoundIoFormat.U24BE; /// ditto
    enum SoundIoFormatS32FE = SoundIoFormat.S32BE; /// ditto
    enum SoundIoFormatU32FE = SoundIoFormat.U32BE; /// ditto
    enum SoundIoFormatFloat32FE = SoundIoFormat.Float32BE; /// ditto
    enum SoundIoFormatFloat64FE = SoundIoFormat.Float64BE; /// ditto
} else version(BigEndian) {
    enum SoundIoFormatS16NE = SoundIoFormat.S16BE; /// ditto
    enum SoundIoFormatU16NE = SoundIoFormat.U16BE; /// ditto
    enum SoundIoFormatS24NE = SoundIoFormat.S24BE; /// ditto
    enum SoundIoFormatU24NE = SoundIoFormat.U24BE; /// ditto
    enum SoundIoFormatS32NE = SoundIoFormat.S32BE; /// ditto
    enum SoundIoFormatU32NE = SoundIoFormat.U32BE; /// ditto
    enum SoundIoFormatFloat32NE = SoundIoFormat.Float32BE; /// ditto
    enum SoundIoFormatFloat64NE = SoundIoFormat.Float64BE; /// ditto

    enum SoundIoFormatS16FE = SoundIoFormat.S16LE; /// ditto
    enum SoundIoFormatU16FE = SoundIoFormat.U16LE; /// ditto
    enum SoundIoFormatS24FE = SoundIoFormat.S24LE; /// ditto
    enum SoundIoFormatU24FE = SoundIoFormat.U24LE; /// ditto
    enum SoundIoFormatS32FE = SoundIoFormat.S32LE; /// ditto
    enum SoundIoFormatU32FE = SoundIoFormat.U32LE; /// ditto
    enum SoundIoFormatFloat32FE = SoundIoFormat.Float32LE; /// ditto
    enum SoundIoFormatFloat64FE = SoundIoFormat.Float64LE; /// ditto
} else {
    static assert(0, "no endian");
}

enum SOUNDIO_MAX_CHANNELS = 24;
/// The size of this struct is OK to use.
struct SoundIoChannelLayout
{
    const(char)* name;
    int channel_count;
    SoundIoChannelId[SOUNDIO_MAX_CHANNELS] channels;
}

/// The size of this struct is OK to use.
struct SoundIoSampleRateRange
{
    int min;
    int max;
}

/// The size of this struct is OK to use.
struct SoundIoChannelArea
{
    /// Base address of buffer.
    char* ptr;
    /// How many bytes it takes to get from the beginning of one sample to
    /// the beginning of the next sample.
    int step;
}

/// The size of this struct is not part of the API or ABI.
struct SoundIo
{
    extern(C): @nogc: nothrow:
    /// Optional. Put whatever you want here. Defaults to NULL.
    void* userdata;
    /// Optional callback. Called when the list of devices change. Only called
    /// during a call to ::soundio_flush_events or ::soundio_wait_events.
    void function (SoundIo*) on_devices_change;
    /// Optional callback. Called when the backend disconnects. For example,
    /// when the JACK server shuts down. When this happens, listing devices
    /// and opening streams will always fail with
    /// SoundIoErrorBackendDisconnected. This callback is only called during a
    /// call to ::soundio_flush_events or ::soundio_wait_events.
    /// If you do not supply a callback, the default will crash your program
    /// with an error message. This callback is also called when the thread
    /// that retrieves device information runs into an unrecoverable condition
    /// such as running out of memory.
    ///
    /// Possible errors:
    /// * #SoundIoErrorBackendDisconnected
    /// * #SoundIoErrorNoMem
    /// * #SoundIoErrorSystemResources
    /// * #SoundIoErrorOpeningDevice - unexpected problem accessing device
    ///   information
    void function (SoundIo*, int err) on_backend_disconnect;
    /// Optional callback. Called from an unknown thread that you should not use
    /// to call any soundio functions. You may use this to signal a condition
    /// variable to wake up. Called when ::soundio_wait_events would be woken up.
    void function (SoundIo*) on_events_signal;

    /// Read-only. After calling ::soundio_connect or ::soundio_connect_backend,
    /// this field tells which backend is currently connected.
    SoundIoBackend current_backend;

    /// Optional: Application name.
    /// PulseAudio uses this for "application name".
    /// JACK uses this for `client_name`.
    /// Must not contain a colon (":").
    const(char)* app_name;

    /// Optional: Real time priority warning.
    /// This callback is fired when making thread real-time priority failed. By
    /// default, it will print to stderr only the first time it is called
    /// a message instructing the user how to configure their system to allow
    /// real-time priority threads. This must be set to a function not NULL.
    /// To silence the warning, assign this to a function that does nothing.
    void function () emit_rtprio_warning;

    /// Optional: JACK info callback.
    /// By default, libsoundio sets this to an empty function in order to
    /// silence stdio messages from JACK. You may override the behavior by
    /// setting this to `NULL` or providing your own function. This is
    /// registered with JACK regardless of whether ::soundio_connect_backend
    /// succeeds.
    void function (const(char)* msg) jack_info_callback;
    /// Optional: JACK error callback.
    /// See SoundIo::jack_info_callback
    void function (const(char)* msg) jack_error_callback;
}

/// The size of this struct is not part of the API or ABI.
struct SoundIoDevice
{
    /// Read-only. Set automatically.
    SoundIo* soundio;

    /// A string of bytes that uniquely identifies this device.
    ///
    /// If the same physical device supports both input and output, that makes
    /// one SoundIoDevice for the input and one SoundIoDevice for the output.
    /// In this case, the id of each SoundIoDevice will be the same, and
    /// SoundIoDevice::aim will be different. Additionally, if the device
    /// supports raw mode, there may be up to four devices with the same id:
    /// one for each value of SoundIoDevice::is_raw and one for each value of
    /// SoundIoDevice::aim.
    char* id;
    /// User-friendly UTF-8 encoded text to describe the device.
    char* name;

    /// Tells whether this device is an input device or an output device.
    SoundIoDeviceAim aim;

    /// Channel layouts are handled similarly to SoundIoDevice::formats.
    ///
    /// If this information is missing due to a SoundIoDevice::probe_error,
    /// layouts will be NULL. It's OK to modify this data, for example calling
    /// ::soundio_sort_channel_layouts on it.
    /// Devices are guaranteed to have at least 1 channel layout.
    SoundIoChannelLayout* layouts;
    int layout_count;
    /// See SoundIoDevice::current_format
    SoundIoChannelLayout current_layout;

    /// List of formats this device supports. See also
    /// SoundIoDevice::current_format.
    SoundIoFormat* formats;
    /// How many formats are available in SoundIoDevice::formats.
    int format_count;
    /// A device is either a raw device or it is a virtual device that is
    /// provided by a software mixing service such as dmix or PulseAudio (see
    /// SoundIoDevice::is_raw). If it is a raw device,
    /// current_format is meaningless;
    /// the device has no current format until you open it. On the other hand,
    /// if it is a virtual device, current_format describes the
    /// destination sample format that your audio will be converted to. Or,
    /// if you're the lucky first application to open the device, you might
    /// cause the current_format to change to your format.
    /// Generally, you want to ignore current_format and use
    /// whatever format is most convenient
    /// for you which is supported by the device, because when you are the only
    /// application left, the mixer might decide to switch
    /// current_format to yours. You can learn the supported formats via
    /// formats and SoundIoDevice::format_count. If this information is missing
    /// due to a probe error, formats will be `NULL`. If current_format is
    /// unavailable, it will be set to #SoundIoFormatInvalid.
    /// Devices are guaranteed to have at least 1 format available.
    SoundIoFormat current_format;

    /// Sample rate is the number of frames per second.
    /// Sample rate is handled very similar to SoundIoDevice::formats.
    /// If sample rate information is missing due to a probe error, the field
    /// will be set to NULL.
    /// Devices which have SoundIoDevice::probe_error set to #SoundIoErrorNone are
    /// guaranteed to have at least 1 sample rate available.
    SoundIoSampleRateRange* sample_rates;
    /// How many sample rate ranges are available in
    /// SoundIoDevice::sample_rates. 0 if sample rate information is missing
    /// due to a probe error.
    int sample_rate_count;
    /// See SoundIoDevice::current_format
    /// 0 if sample rate information is missing due to a probe error.
    int sample_rate_current;

    /// Software latency minimum in seconds. If this value is unknown or
    /// irrelevant, it is set to 0.0.
    /// For PulseAudio and WASAPI this value is unknown until you open a
    /// stream.
    double software_latency_min;
    /// Software latency maximum in seconds. If this value is unknown or
    /// irrelevant, it is set to 0.0.
    /// For PulseAudio and WASAPI this value is unknown until you open a
    /// stream.
    double software_latency_max;
    /// Software latency in seconds. If this value is unknown or
    /// irrelevant, it is set to 0.0.
    /// For PulseAudio and WASAPI this value is unknown until you open a
    /// stream.
    /// See SoundIoDevice::current_format
    double software_latency_current;

    /// Raw means that you are directly opening the hardware device and not
    /// going through a proxy such as dmix, PulseAudio, or JACK. When you open a
    /// raw device, other applications on the computer are not able to
    /// simultaneously access the device. Raw devices do not perform automatic
    /// resampling and thus tend to have fewer formats available.
    bool is_raw;

    /// Devices are reference counted. See ::soundio_device_ref and
    /// ::soundio_device_unref.
    int ref_count;

    /// This is set to a SoundIoError representing the result of the device
    /// probe. Ideally this will be SoundIoErrorNone in which case all the
    /// fields of the device will be populated. If there is an error code here
    /// then information about formats, sample rates, and channel layouts might
    /// be missing.
    ///
    /// Possible errors:
    /// * #SoundIoErrorOpeningDevice
    /// * #SoundIoErrorNoMem
    int probe_error;
}

/// The size of this struct is not part of the API or ABI.
struct SoundIoOutStream
{
    extern(C): @nogc: nothrow:
    /// Populated automatically when you call ::soundio_outstream_create.
    SoundIoDevice* device;

    /// Defaults to #SoundIoFormatFloat32NE, followed by the first one
    /// supported.
    SoundIoFormat format;

    /// Sample rate is the number of frames per second.
    /// Defaults to 48000 (and then clamped into range).
    int sample_rate;

    /// Defaults to Stereo, if available, followed by the first layout
    /// supported.
    SoundIoChannelLayout layout;

    /// Ignoring hardware latency, this is the number of seconds it takes for
    /// the last sample in a full buffer to be played.
    /// After you call ::soundio_outstream_open, this value is replaced with the
    /// actual software latency, as near to this value as possible.
    /// On systems that support clearing the buffer, this defaults to a large
    /// latency, potentially upwards of 2 seconds, with the understanding that
    /// you will call ::soundio_outstream_clear_buffer when you want to reduce
    /// the latency to 0. On systems that do not support clearing the buffer,
    /// this defaults to a reasonable lower latency value.
    ///
    /// On backends with high latencies (such as 2 seconds), `frame_count_min`
    /// will be 0, meaning you don't have to fill the entire buffer. In this
    /// case, the large buffer is there if you want it; you only have to fill
    /// as much as you want. On backends like JACK, `frame_count_min` will be
    /// equal to `frame_count_max` and if you don't fill that many frames, you
    /// will get glitches.
    ///
    /// If the device has unknown software latency min and max values, you may
    /// still set this, but you might not get the value you requested.
    /// For PulseAudio, if you set this value to non-default, it sets
    /// `PA_STREAM_ADJUST_LATENCY` and is the value used for `maxlength` and
    /// `tlength`.
    ///
    /// For JACK, this value is always equal to
    /// SoundIoDevice::software_latency_current of the device.
    double software_latency;
    /// Core Audio and WASAPI only: current output Audio Unit volume. Float, 0.0-1.0.
    float volume;
    /// Defaults to NULL. Put whatever you want here.
    void* userdata;
    /// In this callback, you call ::soundio_outstream_begin_write and
    /// ::soundio_outstream_end_write as many times as necessary to write
    /// at minimum `frame_count_min` frames and at maximum `frame_count_max`
    /// frames. `frame_count_max` will always be greater than 0. Note that you
    /// should write as many frames as you can; `frame_count_min` might be 0 and
    /// you can still get a buffer underflow if you always write
    /// `frame_count_min` frames.
    ///
    /// For Dummy, ALSA, and PulseAudio, `frame_count_min` will be 0. For JACK
    /// and CoreAudio `frame_count_min` will be equal to `frame_count_max`.
    ///
    /// The code in the supplied function must be suitable for real-time
    /// execution. That means that it cannot call functions that might block
    /// for a long time. This includes all I/O functions (disk, TTY, network),
    /// malloc, free, printf, pthread_mutex_lock, sleep, wait, poll, select,
    /// pthread_join, pthread_cond_wait, etc.
    void function (
        SoundIoOutStream*,
        int frame_count_min,
        int frame_count_max) write_callback;
    /// This optional callback happens when the sound device runs out of
    /// buffered audio data to play. After this occurs, the outstream waits
    /// until the buffer is full to resume playback.
    /// This is called from the SoundIoOutStream::write_callback thread context.
    void function (SoundIoOutStream*) underflow_callback;
    /// Optional callback. `err` is always SoundIoErrorStreaming.
    /// SoundIoErrorStreaming is an unrecoverable error. The stream is in an
    /// invalid state and must be destroyed.
    /// If you do not supply error_callback, the default callback will print
    /// a message to stderr and then call `abort`.
    /// This is called from the SoundIoOutStream::write_callback thread context.
    void function (SoundIoOutStream*, int err) error_callback;

    /// Optional: Name of the stream. Defaults to "SoundIoOutStream"
    /// PulseAudio uses this for the stream name.
    /// JACK uses this for the client name of the client that connects when you
    /// open the stream.
    /// WASAPI uses this for the session display name.
    /// Must not contain a colon (":").
    const(char)* name;

    /// Optional: Hint that this output stream is nonterminal. This is used by
    /// JACK and it means that the output stream data originates from an input
    /// stream. Defaults to `false`.
    bool non_terminal_hint;

    /// computed automatically when you call ::soundio_outstream_open
    int bytes_per_frame;
    /// computed automatically when you call ::soundio_outstream_open
    int bytes_per_sample;

    /// If setting the channel layout fails for some reason, this field is set
    /// to an error code. Possible error codes are:
    /// * #SoundIoErrorIncompatibleDevice
    int layout_error;
}

/// The size of this struct is not part of the API or ABI.
struct SoundIoInStream
{
    extern(C): @nogc: nothrow:
    /// Populated automatically when you call ::soundio_outstream_create.
    SoundIoDevice* device;

    /// Defaults to #SoundIoFormatFloat32NE, followed by the first one
    /// supported.
    SoundIoFormat format;

    /// Sample rate is the number of frames per second.
    /// Defaults to max(sample_rate_min, min(sample_rate_max, 48000))
    int sample_rate;

    /// Defaults to Stereo, if available, followed by the first layout
    /// supported.
    SoundIoChannelLayout layout;

    /// Ignoring hardware latency, this is the number of seconds it takes for a
    /// captured sample to become available for reading.
    /// After you call ::soundio_instream_open, this value is replaced with the
    /// actual software latency, as near to this value as possible.
    /// A higher value means less CPU usage. Defaults to a large value,
    /// potentially upwards of 2 seconds.
    /// If the device has unknown software latency min and max values, you may
    /// still set this, but you might not get the value you requested.
    /// For PulseAudio, if you set this value to non-default, it sets
    /// `PA_STREAM_ADJUST_LATENCY` and is the value used for `fragsize`.
    /// For JACK, this value is always equal to
    /// SoundIoDevice::software_latency_current
    double software_latency;

    /// Defaults to NULL. Put whatever you want here.
    void* userdata;
    /// In this function call ::soundio_instream_begin_read and
    /// ::soundio_instream_end_read as many times as necessary to read at
    /// minimum `frame_count_min` frames and at maximum `frame_count_max`
    /// frames. If you return from read_callback without having read
    /// `frame_count_min`, the frames will be dropped. `frame_count_max` is how
    /// many frames are available to read.
    ///
    /// The code in the supplied function must be suitable for real-time
    /// execution. That means that it cannot call functions that might block
    /// for a long time. This includes all I/O functions (disk, TTY, network),
    /// malloc, free, printf, pthread_mutex_lock, sleep, wait, poll, select,
    /// pthread_join, pthread_cond_wait, etc.
    void function (SoundIoInStream*, int frame_count_min, int frame_count_max) read_callback;
    /// This optional callback happens when the sound device buffer is full,
    /// yet there is more captured audio to put in it.
    /// This is never fired for PulseAudio.
    /// This is called from the SoundIoInStream::read_callback thread context.
    void function (SoundIoInStream*) overflow_callback;
    /// Optional callback. `err` is always SoundIoErrorStreaming.
    /// SoundIoErrorStreaming is an unrecoverable error. The stream is in an
    /// invalid state and must be destroyed.
    /// If you do not supply `error_callback`, the default callback will print
    /// a message to stderr and then abort().
    /// This is called from the SoundIoInStream::read_callback thread context.
    void function (SoundIoInStream*, int err) error_callback;

    /// Optional: Name of the stream. Defaults to "SoundIoInStream";
    /// PulseAudio uses this for the stream name.
    /// JACK uses this for the client name of the client that connects when you
    /// open the stream.
    /// WASAPI uses this for the session display name.
    /// Must not contain a colon (":").
    const(char)* name;

    /// Optional: Hint that this input stream is nonterminal. This is used by
    /// JACK and it means that the data received by the stream will be
    /// passed on or made available to another stream. Defaults to `false`.
    bool non_terminal_hint;

    /// computed automatically when you call ::soundio_instream_open
    int bytes_per_frame;
    /// computed automatically when you call ::soundio_instream_open
    int bytes_per_sample;

    /// If setting the channel layout fails for some reason, this field is set
    /// to an error code. Possible error codes are: #SoundIoErrorIncompatibleDevice
    int layout_error;
}

/// See also ::soundio_version_major, ::soundio_version_minor, ::soundio_version_patch
const(char)* soundio_version_string ();
/// See also ::soundio_version_string, ::soundio_version_minor, ::soundio_version_patch
int soundio_version_major ();
/// See also ::soundio_version_major, ::soundio_version_string, ::soundio_version_patch
int soundio_version_minor ();
/// See also ::soundio_version_major, ::soundio_version_minor, ::soundio_version_string
int soundio_version_patch ();

/// Create a SoundIo context. You may create multiple instances of this to
/// connect to multiple backends. Sets all fields to defaults.
/// Returns `NULL` if and only if memory could not be allocated.
/// See also ::soundio_destroy
SoundIo* soundio_create ();
/// ditto
void soundio_destroy (SoundIo* soundio);

/// Tries ::soundio_connect_backend on all available backends in order.
/// Possible errors:
/// * #SoundIoErrorInvalid - already connected
/// * #SoundIoErrorNoMem
/// * #SoundIoErrorSystemResources
/// * #SoundIoErrorNoSuchClient - when JACK returns `JackNoSuchClient`
/// See also ::soundio_disconnect
int soundio_connect (SoundIo* soundio);
/// Instead of calling ::soundio_connect you may call this function to try a
/// specific backend.
/// Possible errors:
/// * #SoundIoErrorInvalid - already connected or invalid backend parameter
/// * #SoundIoErrorNoMem
/// * #SoundIoErrorBackendUnavailable - backend was not compiled in
/// * #SoundIoErrorSystemResources
/// * #SoundIoErrorNoSuchClient - when JACK returns `JackNoSuchClient`
/// * #SoundIoErrorInitAudioBackend - requested `backend` is not active
/// * #SoundIoErrorBackendDisconnected - backend disconnected while connecting
/// See also ::soundio_disconnect
int soundio_connect_backend (SoundIo* soundio, SoundIoBackend backend);
/// ditto
void soundio_disconnect (SoundIo* soundio);

/// Get a string representation of a #SoundIoError
const(char)* soundio_strerror (int error);
/// Get a string representation of a #SoundIoBackend
const(char)* soundio_backend_name (SoundIoBackend backend);

/// Returns the number of available backends.
int soundio_backend_count (SoundIo* soundio);
/// get the available backend at the specified index
/// (0 <= index < ::soundio_backend_count)
SoundIoBackend soundio_get_backend (SoundIo* soundio, int index);

/// Returns whether libsoundio was compiled with backend.
bool soundio_have_backend (SoundIoBackend backend);

/// Atomically update information for all connected devices. Note that calling
/// this function merely flips a pointer; the actual work of collecting device
/// information is done elsewhere. It is performant to call this function many
/// times per second.
///
/// When you call this, the following callbacks might be called:
/// * SoundIo::on_devices_change
/// * SoundIo::on_backend_disconnect
/// This is the only time those callbacks can be called.
///
/// This must be called from the same thread as the thread in which you call
/// these functions:
/// * ::soundio_input_device_count
/// * ::soundio_output_device_count
/// * ::soundio_get_input_device
/// * ::soundio_get_output_device
/// * ::soundio_default_input_device_index
/// * ::soundio_default_output_device_index
///
/// Note that if you do not care about learning about updated devices, you
/// might call this function only once ever and never call
/// ::soundio_wait_events.
void soundio_flush_events (SoundIo* soundio);

/// This function calls ::soundio_flush_events then blocks until another event
/// is ready or you call ::soundio_wakeup. Be ready for spurious wakeups.
void soundio_wait_events (SoundIo* soundio);

/// Makes ::soundio_wait_events stop blocking.
void soundio_wakeup (SoundIo* soundio);

/// If necessary you can manually trigger a device rescan. Normally you will
/// not ever have to call this function, as libsoundio listens to system events
/// for device changes and responds to them by rescanning devices and preparing
/// the new device information for you to be atomically replaced when you call
/// ::soundio_flush_events. However you might run into cases where you want to
/// force trigger a device rescan, for example if an ALSA device has a
/// SoundIoDevice::probe_error.
///
/// After you call this you still have to use ::soundio_flush_events or
/// ::soundio_wait_events and then wait for the
/// SoundIo::on_devices_change callback.
///
/// This can be called from any thread context except for
/// SoundIoOutStream::write_callback and SoundIoInStream::read_callback
void soundio_force_device_scan (SoundIo* soundio);

// Channel Layouts

/// Returns whether the channel count field and each channel id matches in
/// the supplied channel layouts.
bool soundio_channel_layout_equal (
    const(SoundIoChannelLayout)* a,
    const(SoundIoChannelLayout)* b);

const(char)* soundio_get_channel_name (SoundIoChannelId id);
/// Given UTF-8 encoded text which is the name of a channel such as
/// "Front Left", "FL", or "front-left", return the corresponding
/// SoundIoChannelId. Returns SoundIoChannelIdInvalid for no match.
SoundIoChannelId soundio_parse_channel_id (const(char)* str, int str_len);

/// Returns the number of builtin channel layouts.
int soundio_channel_layout_builtin_count ();
/// Returns a builtin channel layout. 0 <= `index` < ::soundio_channel_layout_builtin_count
///
/// Although `index` is of type `int`, it should be a valid
/// #SoundIoChannelLayoutId enum value.
const(SoundIoChannelLayout)* soundio_channel_layout_get_builtin (int index);

/// Get the default builtin channel layout for the given number of channels.
const(SoundIoChannelLayout)* soundio_channel_layout_get_default (int channel_count);

/// Return the index of `channel` in `layout`, or `-1` if not found.
int soundio_channel_layout_find_channel (
    const(SoundIoChannelLayout)* layout,
    SoundIoChannelId channel);

/// Populates the name field of layout if it matches a builtin one.
/// returns whether it found a match
bool soundio_channel_layout_detect_builtin (SoundIoChannelLayout* layout);

/// Iterates over preferred_layouts. Returns the first channel layout in
/// preferred_layouts which matches one of the channel layouts in
/// available_layouts. Returns NULL if none matches.
const(SoundIoChannelLayout)* soundio_best_matching_channel_layout (
    const(SoundIoChannelLayout)* preferred_layouts,
    int preferred_layout_count,
    const(SoundIoChannelLayout)* available_layouts,
    int available_layout_count);

/// Sorts by channel count, descending.
void soundio_sort_channel_layouts (SoundIoChannelLayout* layouts, int layout_count);

// Sample Formats

/// Returns -1 on invalid format.
int soundio_get_bytes_per_sample (SoundIoFormat format);

/// A frame is one sample per channel.
pragma(inline, true) int soundio_get_bytes_per_frame(SoundIoFormat format, int channel_count) {
	return soundio_get_bytes_per_sample(format) * channel_count;
}

/// Sample rate is the number of frames per second.
pragma(inline, true) int soundio_get_bytes_per_second(
    SoundIoFormat format, int channel_count, int sample_rate
) {
	return soundio_get_bytes_per_frame(format, channel_count) * sample_rate;
}

/// Returns string representation of `format`.
const(char)* soundio_format_string (SoundIoFormat format);

// Devices

/// When you call ::soundio_flush_events, a snapshot of all device state is
/// saved and these functions merely access the snapshot data. When you want
/// to check for new devices, call ::soundio_flush_events. Or you can call
/// ::soundio_wait_events to block until devices change. If an error occurs
/// scanning devices in a background thread, SoundIo::on_backend_disconnect is called
/// with the error code.

/// Get the number of input devices.
/// Returns -1 if you never called ::soundio_flush_events.
int soundio_input_device_count (SoundIo* soundio);
/// Get the number of output devices.
/// Returns -1 if you never called ::soundio_flush_events.
int soundio_output_device_count (SoundIo* soundio);

/// Always returns a device. Call ::soundio_device_unref when done.
/// `index` must be 0 <= index < ::soundio_input_device_count
/// Returns NULL if you never called ::soundio_flush_events or if you provide
/// invalid parameter values.
SoundIoDevice* soundio_get_input_device (SoundIo* soundio, int index);
/// Always returns a device. Call ::soundio_device_unref when done.
/// `index` must be 0 <= index < ::soundio_output_device_count
/// Returns NULL if you never called ::soundio_flush_events or if you provide
/// invalid parameter values.
SoundIoDevice* soundio_get_output_device (SoundIo* soundio, int index);

/// returns the index of the default input device
/// returns -1 if there are no devices or if you never called
/// ::soundio_flush_events.
int soundio_default_input_device_index (SoundIo* soundio);

/// returns the index of the default output device
/// returns -1 if there are no devices or if you never called
/// ::soundio_flush_events.
int soundio_default_output_device_index (SoundIo* soundio);

/// Add 1 to the reference count of `device`.
void soundio_device_ref (SoundIoDevice* device);
/// Remove 1 to the reference count of `device`. Clean up if it was the last
/// reference.
void soundio_device_unref (SoundIoDevice* device);

/// Return `true` if and only if the devices have the same SoundIoDevice::id,
/// SoundIoDevice::is_raw, and SoundIoDevice::aim are the same.
bool soundio_device_equal (const(SoundIoDevice)* a, const(SoundIoDevice)* b);

/// Sorts channel layouts by channel count, descending.
void soundio_device_sort_channel_layouts (SoundIoDevice* device);

/// Convenience function. Returns whether `format` is included in the device's
/// supported formats.
bool soundio_device_supports_format (
    SoundIoDevice* device,
    SoundIoFormat format);

/// Convenience function. Returns whether `layout` is included in the device's
/// supported channel layouts.
bool soundio_device_supports_layout (
    SoundIoDevice* device,
    const(SoundIoChannelLayout)* layout);

/// Convenience function. Returns whether `sample_rate` is included in the
/// device's supported sample rates.
bool soundio_device_supports_sample_rate (
    SoundIoDevice* device,
    int sample_rate);

/// Convenience function. Returns the available sample rate nearest to
/// `sample_rate`, rounding up.
int soundio_device_nearest_sample_rate (SoundIoDevice* device, int sample_rate);

// Output Streams
/// Allocates memory and sets defaults. Next you should fill out the struct fields
/// and then call ::soundio_outstream_open. Sets all fields to defaults.
/// Returns `NULL` if and only if memory could not be allocated.
/// See also ::soundio_outstream_destroy
SoundIoOutStream* soundio_outstream_create (SoundIoDevice* device);
/// You may not call this function from the SoundIoOutStream::write_callback thread context.
void soundio_outstream_destroy (SoundIoOutStream* outstream);

/// After you call this function, SoundIoOutStream::software_latency is set to
/// the correct value.
///
/// The next thing to do is call ::soundio_outstream_start.
/// If this function returns an error, the outstream is in an invalid state and
/// you must call ::soundio_outstream_destroy on it.
///
/// Possible errors:
/// * #SoundIoErrorInvalid
///   * SoundIoDevice::aim is not #SoundIoDeviceAimOutput
///   * SoundIoOutStream::format is not valid
///   * SoundIoOutStream::channel_count is greater than #SOUNDIO_MAX_CHANNELS
/// * #SoundIoErrorNoMem
/// * #SoundIoErrorOpeningDevice
/// * #SoundIoErrorBackendDisconnected
/// * #SoundIoErrorSystemResources
/// * #SoundIoErrorNoSuchClient - when JACK returns `JackNoSuchClient`
/// * #SoundIoErrorIncompatibleBackend - SoundIoOutStream::channel_count is
///   greater than the number of channels the backend can handle.
/// * #SoundIoErrorIncompatibleDevice - stream parameters requested are not
///   compatible with the chosen device.
int soundio_outstream_open (SoundIoOutStream* outstream);

/// After you call this function, SoundIoOutStream::write_callback will be called.
///
/// This function might directly call SoundIoOutStream::write_callback.
///
/// Possible errors:
/// * #SoundIoErrorStreaming
/// * #SoundIoErrorNoMem
/// * #SoundIoErrorSystemResources
/// * #SoundIoErrorBackendDisconnected
int soundio_outstream_start (SoundIoOutStream* outstream);

/// Call this function when you are ready to begin writing to the device buffer.
///  * `outstream` - (in) The output stream you want to write to.
///  * `areas` - (out) The memory addresses you can write data to, one per
///    channel. It is OK to modify the pointers if that helps you iterate.
///  * `frame_count` - (in/out) Provide the number of frames you want to write.
///    Returned will be the number of frames you can actually write, which is
///    also the number of frames that will be written when you call
///    ::soundio_outstream_end_write. The value returned will always be less
///    than or equal to the value provided.
/// It is your responsibility to call this function exactly as many times as
/// necessary to meet the `frame_count_min` and `frame_count_max` criteria from
/// SoundIoOutStream::write_callback.
/// You must call this function only from the SoundIoOutStream::write_callback thread context.
/// After calling this function, write data to `areas` and then call
/// ::soundio_outstream_end_write.
/// If this function returns an error, do not call ::soundio_outstream_end_write.
///
/// Possible errors:
/// * #SoundIoErrorInvalid
///   * `*frame_count` <= 0
///   * `*frame_count` < `frame_count_min` or `*frame_count` > `frame_count_max`
///   * function called too many times without respecting `frame_count_max`
/// * #SoundIoErrorStreaming
/// * #SoundIoErrorUnderflow - an underflow caused this call to fail. You might
///   also get a SoundIoOutStream::underflow_callback, and you might not get
///   this error code when an underflow occurs. Unlike #SoundIoErrorStreaming,
///   the outstream is still in a valid state and streaming can continue.
/// * #SoundIoErrorIncompatibleDevice - in rare cases it might just now
///   be discovered that the device uses non-byte-aligned access, in which
///   case this error code is returned.
int soundio_outstream_begin_write (
    SoundIoOutStream* outstream,
    SoundIoChannelArea** areas,
    int* frame_count);

/// Commits the write that you began with ::soundio_outstream_begin_write.
/// You must call this function only from the SoundIoOutStream::write_callback thread context.
///
/// Possible errors:
/// * #SoundIoErrorStreaming
/// * #SoundIoErrorUnderflow - an underflow caused this call to fail. You might
///   also get a SoundIoOutStream::underflow_callback, and you might not get
///   this error code when an underflow occurs. Unlike #SoundIoErrorStreaming,
///   the outstream is still in a valid state and streaming can continue.
int soundio_outstream_end_write (SoundIoOutStream* outstream);

/// Clears the output stream buffer.
/// This function can be called from any thread.
/// This function can be called regardless of whether the outstream is paused
/// or not.
/// Some backends do not support clearing the buffer. On these backends this
/// function will return SoundIoErrorIncompatibleBackend.
/// Some devices do not support clearing the buffer. On these devices this
/// function might return SoundIoErrorIncompatibleDevice.
/// Possible errors:
///
/// * #SoundIoErrorStreaming
/// * #SoundIoErrorIncompatibleBackend
/// * #SoundIoErrorIncompatibleDevice
int soundio_outstream_clear_buffer (SoundIoOutStream* outstream);

/// If the underlying backend and device support pausing, this pauses the
/// stream. SoundIoOutStream::write_callback may be called a few more times if
/// the buffer is not full.
/// Pausing might put the hardware into a low power state which is ideal if your
/// software is silent for some time.
/// This function may be called from any thread context, including
/// SoundIoOutStream::write_callback.
/// Pausing when already paused or unpausing when already unpaused has no
/// effect and returns #SoundIoErrorNone.
///
/// Possible errors:
/// * #SoundIoErrorBackendDisconnected
/// * #SoundIoErrorStreaming
/// * #SoundIoErrorIncompatibleDevice - device does not support
///   pausing/unpausing. This error code might not be returned even if the
///   device does not support pausing/unpausing.
/// * #SoundIoErrorIncompatibleBackend - backend does not support
///   pausing/unpausing.
/// * #SoundIoErrorInvalid - outstream not opened and started
int soundio_outstream_pause (SoundIoOutStream* outstream, bool pause);

/// Obtain the total number of seconds that the next frame written after the
/// last frame written with ::soundio_outstream_end_write will take to become
/// audible. This includes both software and hardware latency. In other words,
/// if you call this function directly after calling ::soundio_outstream_end_write,
/// this gives you the number of seconds that the next frame written will take
/// to become audible.
///
/// This function must be called only from within SoundIoOutStream::write_callback.
///
/// Possible errors:
/// * #SoundIoErrorStreaming
int soundio_outstream_get_latency (
    SoundIoOutStream* outstream,
    double* out_latency);

int soundio_outstream_set_volume (SoundIoOutStream* outstream, double volume);

// Input Streams
/// Allocates memory and sets defaults. Next you should fill out the struct fields
/// and then call ::soundio_instream_open. Sets all fields to defaults.
/// Returns `NULL` if and only if memory could not be allocated.
/// See also ::soundio_instream_destroy
SoundIoInStream* soundio_instream_create (SoundIoDevice* device);
/// You may not call this function from SoundIoInStream::read_callback.
void soundio_instream_destroy (SoundIoInStream* instream);

/// After you call this function, SoundIoInStream::software_latency is set to the correct
/// value.
/// The next thing to do is call ::soundio_instream_start.
/// If this function returns an error, the instream is in an invalid state and
/// you must call ::soundio_instream_destroy on it.
///
/// Possible errors:
/// * #SoundIoErrorInvalid
///   * device aim is not #SoundIoDeviceAimInput
///   * format is not valid
///   * requested layout channel count > #SOUNDIO_MAX_CHANNELS
/// * #SoundIoErrorOpeningDevice
/// * #SoundIoErrorNoMem
/// * #SoundIoErrorBackendDisconnected
/// * #SoundIoErrorSystemResources
/// * #SoundIoErrorNoSuchClient
/// * #SoundIoErrorIncompatibleBackend
/// * #SoundIoErrorIncompatibleDevice
int soundio_instream_open (SoundIoInStream* instream);

/// After you call this function, SoundIoInStream::read_callback will be called.
///
/// Possible errors:
/// * #SoundIoErrorBackendDisconnected
/// * #SoundIoErrorStreaming
/// * #SoundIoErrorOpeningDevice
/// * #SoundIoErrorSystemResources
int soundio_instream_start (SoundIoInStream* instream);

/// Call this function when you are ready to begin reading from the device
/// buffer.
/// * `instream` - (in) The input stream you want to read from.
/// * `areas` - (out) The memory addresses you can read data from. It is OK
///   to modify the pointers if that helps you iterate. There might be a "hole"
///   in the buffer. To indicate this, `areas` will be `NULL` and `frame_count`
///   tells how big the hole is in frames.
/// * `frame_count` - (in/out) - Provide the number of frames you want to read;
///   returns the number of frames you can actually read. The returned value
///   will always be less than or equal to the provided value. If the provided
///   value is less than `frame_count_min` from SoundIoInStream::read_callback this function
///   returns with #SoundIoErrorInvalid.
/// It is your responsibility to call this function no more and no fewer than the
/// correct number of times according to the `frame_count_min` and
/// `frame_count_max` criteria from SoundIoInStream::read_callback.
/// You must call this function only from the SoundIoInStream::read_callback thread context.
/// After calling this function, read data from `areas` and then use
/// ::soundio_instream_end_read` to actually remove the data from the buffer
/// and move the read index forward. ::soundio_instream_end_read should not be
/// called if the buffer is empty (`frame_count` == 0), but it should be called
/// if there is a hole.
///
/// Possible errors:
/// * #SoundIoErrorInvalid
///   * `*frame_count` < `frame_count_min` or `*frame_count` > `frame_count_max`
/// * #SoundIoErrorStreaming
/// * #SoundIoErrorIncompatibleDevice - in rare cases it might just now
///   be discovered that the device uses non-byte-aligned access, in which
///   case this error code is returned.
int soundio_instream_begin_read (
    SoundIoInStream* instream,
    SoundIoChannelArea** areas,
    int* frame_count);
/// This will drop all of the frames from when you called
/// ::soundio_instream_begin_read.
/// You must call this function only from the SoundIoInStream::read_callback thread context.
/// You must call this function only after a successful call to
/// ::soundio_instream_begin_read.
///
/// Possible errors:
/// * #SoundIoErrorStreaming
int soundio_instream_end_read (SoundIoInStream* instream);

/// If the underyling device supports pausing, this pauses the stream and
/// prevents SoundIoInStream::read_callback from being called. Otherwise this returns
/// #SoundIoErrorIncompatibleDevice.
/// This function may be called from any thread.
/// Pausing when already paused or unpausing when already unpaused has no
/// effect and always returns #SoundIoErrorNone.
///
/// Possible errors:
/// * #SoundIoErrorBackendDisconnected
/// * #SoundIoErrorStreaming
/// * #SoundIoErrorIncompatibleDevice - device does not support pausing/unpausing
int soundio_instream_pause (SoundIoInStream* instream, bool pause);

/// Obtain the number of seconds that the next frame of sound being
/// captured will take to arrive in the buffer, plus the amount of time that is
/// represented in the buffer. This includes both software and hardware latency.
///
/// This function must be called only from within SoundIoInStream::read_callback.
///
/// Possible errors:
/// * #SoundIoErrorStreaming
int soundio_instream_get_latency (
    SoundIoInStream* instream,
    double* out_latency);


// Note: those function declarations crash LDC when built with --combined
version(LDC)
    private enum LDC_predecl_workaround = true;
else
    private enum LDC_predecl_workaround = false;

static if (!LDC_predecl_workaround)
{

struct SoundIoRingBuffer;

/// A ring buffer is a single-reader single-writer lock-free fixed-size queue.
/// libsoundio ring buffers use memory mapping techniques to enable a
/// contiguous buffer when reading or writing across the boundary of the ring
/// buffer's capacity.
/// `requested_capacity` in bytes.
/// Returns `NULL` if and only if memory could not be allocated.
/// Use ::soundio_ring_buffer_capacity to get the actual capacity, which might
/// be greater for alignment purposes.
/// See also ::soundio_ring_buffer_destroy
SoundIoRingBuffer* soundio_ring_buffer_create (SoundIo* soundio, int requested_capacity);
/// ditto
void soundio_ring_buffer_destroy (SoundIoRingBuffer* ring_buffer);

/// When you create a ring buffer, capacity might be more than the requested
/// capacity for alignment purposes. This function returns the actual capacity.
int soundio_ring_buffer_capacity (SoundIoRingBuffer* ring_buffer);

/// Do not write more than capacity.
char* soundio_ring_buffer_write_ptr (SoundIoRingBuffer* ring_buffer);
/// `count` in bytes.
void soundio_ring_buffer_advance_write_ptr (SoundIoRingBuffer* ring_buffer, int count);

/// Do not read more than capacity.
char* soundio_ring_buffer_read_ptr (SoundIoRingBuffer* ring_buffer);
/// `count` in bytes.
void soundio_ring_buffer_advance_read_ptr (SoundIoRingBuffer* ring_buffer, int count);

/// Returns: how many bytes of the buffer is used, ready for reading.
int soundio_ring_buffer_fill_count (SoundIoRingBuffer* ring_buffer);

/// Returns: how many bytes of the buffer is free, ready for writing.
int soundio_ring_buffer_free_count (SoundIoRingBuffer* ring_buffer);

/// Must be called by the writer.
void soundio_ring_buffer_clear (SoundIoRingBuffer* ring_buffer);

}
