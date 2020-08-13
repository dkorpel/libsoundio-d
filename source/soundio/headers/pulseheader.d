/// C declarations of PulseAudio that libsoundio uses
module soundio.headers.pulseheader;
extern(C): @nogc: nothrow: __gshared:

// mainloop-api.h
struct pa_mainloop_api;

// operation.h
struct pa_operation;
pa_operation_state_t pa_operation_get_state(pa_operation* o);
void pa_operation_unref(pa_operation* o);

// proplist.h
struct pa_proplist;
pa_proplist* pa_proplist_new();
void pa_proplist_free(pa_proplist* p);

//stream.h
struct pa_stream;
alias void function(pa_stream* s, int success, void* userdata) pa_stream_success_cb_t;
alias void function(pa_stream* p, size_t nbytes, void* userdata) pa_stream_request_cb_t;
alias void function(pa_stream* p, void* userdata) pa_stream_notify_cb_t;

int pa_stream_begin_write(pa_stream* p, void** data, size_t* nbytes);
int pa_stream_connect_playback(pa_stream* s, const(char)* dev, const(pa_buffer_attr)* attr, pa_stream_flags_t flags, const(pa_cvolume)* volume, pa_stream* sync_stream);
int pa_stream_connect_record(pa_stream* s, const(char)* dev, const(pa_buffer_attr)* attr, pa_stream_flags_t flags);
pa_operation* pa_stream_cork(pa_stream* s, int b, pa_stream_success_cb_t cb, void* userdata);
int pa_stream_disconnect(pa_stream* s);
int pa_stream_drop(pa_stream* p);
int pa_stream_get_latency(pa_stream* s, pa_usec_t* r_usec, int* negative);
pa_stream_state_t pa_stream_get_state(pa_stream* p);
int pa_stream_is_corked(pa_stream* s);
pa_stream* pa_stream_new(pa_context* c, const(char)* name, const(pa_sample_spec)* ss, const(pa_channel_map)* map);
int pa_stream_peek(pa_stream* p, const(void)** data, size_t* nbytes);
void pa_stream_set_overflow_callback(pa_stream* p, pa_stream_notify_cb_t cb, void* userdata);
void pa_stream_set_read_callback(pa_stream* p, pa_stream_request_cb_t cb, void* userdata);
void pa_stream_set_state_callback(pa_stream* s, pa_stream_notify_cb_t cb, void* userdata);
void pa_stream_set_underflow_callback(pa_stream* p, pa_stream_notify_cb_t cb, void* userdata);
void pa_stream_set_write_callback(pa_stream* p, pa_stream_request_cb_t cb, void* userdata);
void pa_stream_unref(pa_stream* s);
pa_operation* pa_stream_update_timing_info(pa_stream* p, pa_stream_success_cb_t cb, void* userdata);
size_t pa_stream_writable_size(pa_stream* p);
int pa_stream_write(pa_stream* p, const(void)* data, size_t nbytes, pa_free_cb_t free_cb, long offset, pa_seek_mode_t seek);

// def.h
alias void function(void* p) pa_free_cb_t;

alias pa_stream_flags_t = int; // C enum
enum {
    PA_STREAM_NOFLAGS = 0x0000U,
    PA_STREAM_START_CORKED = 0x0001U,
    PA_STREAM_INTERPOLATE_TIMING = 0x0002U,
    PA_STREAM_NOT_MONOTONIC = 0x0004U,
    PA_STREAM_AUTO_TIMING_UPDATE = 0x0008U,
    PA_STREAM_NO_REMAP_CHANNELS = 0x0010U,
    PA_STREAM_NO_REMIX_CHANNELS = 0x0020U,
    PA_STREAM_FIX_FORMAT = 0x0040U,
    PA_STREAM_FIX_RATE = 0x0080U,
    PA_STREAM_FIX_CHANNELS = 0x0100,
    PA_STREAM_DONT_MOVE = 0x0200U,
    PA_STREAM_VARIABLE_RATE = 0x0400U,
    PA_STREAM_PEAK_DETECT = 0x0800U,
    PA_STREAM_START_MUTED = 0x1000U,
    PA_STREAM_ADJUST_LATENCY = 0x2000U,
    PA_STREAM_EARLY_REQUESTS = 0x4000U,
    PA_STREAM_DONT_INHIBIT_AUTO_SUSPEND = 0x8000U,
    PA_STREAM_START_UNMUTED = 0x10000U,
    PA_STREAM_FAIL_ON_SUSPEND = 0x20000U,
    PA_STREAM_RELATIVE_VOLUME = 0x40000U,
    PA_STREAM_PASSTHROUGH = 0x80000U
}

struct pa_spawn_api {
	extern(C): @nogc: nothrow:
    void function() prefork;
    void function() postfork;
    void function() atfork;
}

// thread-mainloop.h
struct pa_threaded_mainloop;
pa_threaded_mainloop *pa_threaded_mainloop_new();
void pa_threaded_mainloop_free(pa_threaded_mainloop* m);
int pa_threaded_mainloop_start(pa_threaded_mainloop* m);
void pa_threaded_mainloop_stop(pa_threaded_mainloop* m);
void pa_threaded_mainloop_lock(pa_threaded_mainloop* m);
void pa_threaded_mainloop_unlock(pa_threaded_mainloop* m);
void pa_threaded_mainloop_wait(pa_threaded_mainloop* m);
void pa_threaded_mainloop_signal(pa_threaded_mainloop* m, int wait_for_accept);
pa_mainloop_api* pa_threaded_mainloop_get_api(pa_threaded_mainloop* m);
int pa_threaded_mainloop_in_thread(pa_threaded_mainloop* m);

// context.h
struct pa_context;
alias void function(pa_context* c, void* userdata) pa_context_notify_cb_t;
alias void function(pa_context* c, int success, void* userdata) pa_context_success_cb_t;

alias pa_context_flags_t = int; // C enum
int pa_context_connect(pa_context* c, const(char)* server, pa_context_flags_t flags, const(pa_spawn_api)* api);
void pa_context_disconnect(pa_context* c);
pa_context_state_t pa_context_get_state(pa_context* c);
pa_context* pa_context_new_with_proplist(pa_mainloop_api* mainloop, const(char)* name, pa_proplist* proplist);
void pa_context_set_state_callback(pa_context* c, pa_context_notify_cb_t cb, void* userdata);
void pa_context_unref(pa_context* c);

// subscribe.h
alias pa_subscription_mask_t = int; // C enum
enum {
    PA_SUBSCRIPTION_MASK_NULL = 0x0000U,
    PA_SUBSCRIPTION_MASK_SINK = 0x0001U,
    PA_SUBSCRIPTION_MASK_SOURCE = 0x0002U,
    PA_SUBSCRIPTION_MASK_SINK_INPUT = 0x0004U,
    PA_SUBSCRIPTION_MASK_SOURCE_OUTPUT = 0x0008U,
    PA_SUBSCRIPTION_MASK_MODULE = 0x0010U,
    PA_SUBSCRIPTION_MASK_CLIENT = 0x0020U,
    PA_SUBSCRIPTION_MASK_SAMPLE_CACHE = 0x0040U,
    PA_SUBSCRIPTION_MASK_SERVER = 0x0080U,
    PA_SUBSCRIPTION_MASK_AUTOLOAD = 0x0100U,
    PA_SUBSCRIPTION_MASK_CARD = 0x0200U,
    PA_SUBSCRIPTION_MASK_ALL = 0x02ffU
}

alias void function(pa_context* c, pa_subscription_event_type_t t, uint idx, void* userdata) pa_context_subscribe_cb_t;
pa_operation* pa_context_subscribe(pa_context* c, pa_subscription_mask_t m, pa_context_success_cb_t cb, void* userdata);
void pa_context_set_subscribe_callback(pa_context* c, pa_context_subscribe_cb_t cb, void* userdata);

// introspect.h
alias void function(pa_context* c, const(pa_server_info)* i, void* userdata) pa_server_info_cb_t;
pa_operation* pa_context_get_server_info(pa_context* c, pa_server_info_cb_t cb, void* userdata);
alias void function(pa_context* c, const(pa_sink_info)* i, int eol, void* userdata) pa_sink_info_cb_t;
pa_operation* pa_context_get_sink_info_list(pa_context* c, pa_sink_info_cb_t cb, void* userdata);
alias void function(pa_context* c, const(pa_source_info)* i, int eol, void* userdata) pa_source_info_cb_t;
pa_operation* pa_context_get_source_info_list(pa_context* c, pa_source_info_cb_t cb, void* userdata);

alias pa_volume_t = uint;
alias pa_usec_t = ulong;

alias pa_sink_flags_t = int; // C enum
alias pa_sink_state_t = int; // C enum
alias pa_source_flags_t = int; // C enum
alias pa_source_state_t = int; // C enum

struct pa_cvolume {
    ubyte channels;
    pa_volume_t[PA_CHANNELS_MAX] values;
}

alias pa_encoding_t = int; // C enum
struct pa_format_info {
    pa_encoding_t encoding;
    pa_proplist *plist;
}

struct pa_sink_port_info {
    const(char)* name;
    const(char)* description;
    uint priority;
    int available;
}

struct pa_source_port_info {
    const(char)* name;
    const(char)* description;
    uint priority;
    int available;
}

struct pa_server_info {
    const(char)* user_name;
    const(char)* host_name;
    const(char)* server_version;
    const(char)* server_name;
    pa_sample_spec sample_spec;
    const(char)* default_sink_name;
    const(char)* default_source_name;
    uint cookie;
    pa_channel_map channel_map;
}

struct pa_sink_info {
    const(char)* name;
    uint index;
    const(char)* description;
    pa_sample_spec sample_spec;
    pa_channel_map channel_map;
    uint owner_module;
    pa_cvolume volume;
    int mute;
    uint monitor_source;
    const(char)* monitor_source_name;
    pa_usec_t latency;
    const(char)* driver;
    pa_sink_flags_t flags;
    pa_proplist* proplist;
    pa_usec_t configured_latency;
    pa_volume_t base_volume;
    pa_sink_state_t state;
    uint n_volume_steps;
    uint card;
    uint n_ports;
    pa_sink_port_info** ports;
    pa_sink_port_info* active_port;
    ubyte n_formats;
    pa_format_info** formats;
}

struct pa_source_info {
    const(char)* name;
    uint index;
    const(char)* description;
    pa_sample_spec sample_spec;
    pa_channel_map channel_map;
    uint owner_module;
    pa_cvolume volume;
    int mute;
    uint monitor_of_sink;
    const(char)* monitor_of_sink_name;
    pa_usec_t latency;
    const(char)* driver;
    pa_source_flags_t flags;
    pa_proplist* proplist;
    pa_usec_t configured_latency;
    pa_volume_t base_volume;
    pa_source_state_t state;
    uint n_volume_steps;
    uint card;
    uint n_ports;
    pa_source_port_info** ports;
    pa_source_port_info* active_port;
    ubyte n_formats;
    pa_format_info** formats;
}

struct pa_buffer_attr {
    uint maxlength;
    uint tlength;
    uint prebuf;
    uint minreq;
    uint fragsize;
}

enum PA_CHANNELS_MAX = 32;
struct pa_channel_map {
	ubyte channels;
	pa_channel_position_t[PA_CHANNELS_MAX] map;
}
struct pa_sample_spec {
	pa_sample_format_t format;
	uint rate;
	ubyte channels;
}

alias pa_context_state_t = int; // C enum
enum {
	PA_CONTEXT_UNCONNECTED,
	PA_CONTEXT_CONNECTING,
	PA_CONTEXT_AUTHORIZING,
	PA_CONTEXT_SETTING_NAME,
	PA_CONTEXT_READY,
	PA_CONTEXT_FAILED,
	PA_CONTEXT_TERMINATED
}

alias pa_operation_state_t = int; // C enum
enum {
	PA_OPERATION_RUNNING,
	PA_OPERATION_DONE,
	PA_OPERATION_CANCELLED
}

alias pa_seek_mode_t = int;
enum {
    PA_SEEK_RELATIVE = 0,
    PA_SEEK_ABSOLUTE = 1,
    PA_SEEK_RELATIVE_ON_READ = 2,
    PA_SEEK_RELATIVE_END = 3
}

alias pa_stream_state_t = int; // C enum
enum {
	PA_STREAM_UNCONNECTED,
	PA_STREAM_CREATING,
	PA_STREAM_READY,
	PA_STREAM_FAILED,
	PA_STREAM_TERMINATED
}

alias pa_channel_position_t = int; // C enum
enum {
	PA_CHANNEL_POSITION_INVALID = -1,
	PA_CHANNEL_POSITION_MONO = 0,
	PA_CHANNEL_POSITION_FRONT_LEFT,
	PA_CHANNEL_POSITION_FRONT_RIGHT,
	PA_CHANNEL_POSITION_FRONT_CENTER,
	PA_CHANNEL_POSITION_LEFT = PA_CHANNEL_POSITION_FRONT_LEFT,
	PA_CHANNEL_POSITION_RIGHT = PA_CHANNEL_POSITION_FRONT_RIGHT,
	PA_CHANNEL_POSITION_CENTER = PA_CHANNEL_POSITION_FRONT_CENTER,
	PA_CHANNEL_POSITION_REAR_CENTER,
	PA_CHANNEL_POSITION_REAR_LEFT,
	PA_CHANNEL_POSITION_REAR_RIGHT,
	PA_CHANNEL_POSITION_LFE,
	PA_CHANNEL_POSITION_SUBWOOFER = PA_CHANNEL_POSITION_LFE,
	PA_CHANNEL_POSITION_FRONT_LEFT_OF_CENTER,
	PA_CHANNEL_POSITION_FRONT_RIGHT_OF_CENTER,
	PA_CHANNEL_POSITION_SIDE_LEFT,
	PA_CHANNEL_POSITION_SIDE_RIGHT,
	PA_CHANNEL_POSITION_AUX0,
	PA_CHANNEL_POSITION_AUX1,
	PA_CHANNEL_POSITION_AUX2,
	PA_CHANNEL_POSITION_AUX3,
	PA_CHANNEL_POSITION_AUX4,
	PA_CHANNEL_POSITION_AUX5,
	PA_CHANNEL_POSITION_AUX6,
	PA_CHANNEL_POSITION_AUX7,
	PA_CHANNEL_POSITION_AUX8,
	PA_CHANNEL_POSITION_AUX9,
	PA_CHANNEL_POSITION_AUX10,
	PA_CHANNEL_POSITION_AUX11,
	PA_CHANNEL_POSITION_AUX12,
	PA_CHANNEL_POSITION_AUX13,
	PA_CHANNEL_POSITION_AUX14,
	PA_CHANNEL_POSITION_AUX15,
	PA_CHANNEL_POSITION_AUX16,
	PA_CHANNEL_POSITION_AUX17,
	PA_CHANNEL_POSITION_AUX18,
	PA_CHANNEL_POSITION_AUX19,
	PA_CHANNEL_POSITION_AUX20,
	PA_CHANNEL_POSITION_AUX21,
	PA_CHANNEL_POSITION_AUX22,
	PA_CHANNEL_POSITION_AUX23,
	PA_CHANNEL_POSITION_AUX24,
	PA_CHANNEL_POSITION_AUX25,
	PA_CHANNEL_POSITION_AUX26,
	PA_CHANNEL_POSITION_AUX27,
	PA_CHANNEL_POSITION_AUX28,
	PA_CHANNEL_POSITION_AUX29,
	PA_CHANNEL_POSITION_AUX30,
	PA_CHANNEL_POSITION_AUX31,
	PA_CHANNEL_POSITION_TOP_CENTER,
	PA_CHANNEL_POSITION_TOP_FRONT_LEFT,
	PA_CHANNEL_POSITION_TOP_FRONT_RIGHT,
	PA_CHANNEL_POSITION_TOP_FRONT_CENTER,
	PA_CHANNEL_POSITION_TOP_REAR_LEFT,
	PA_CHANNEL_POSITION_TOP_REAR_RIGHT,
	PA_CHANNEL_POSITION_TOP_REAR_CENTER,
	PA_CHANNEL_POSITION_MAX
}
alias pa_subscription_event_type_t = int;
enum {
	PA_SUBSCRIPTION_EVENT_SINK = 0x0000U,
	PA_SUBSCRIPTION_EVENT_SOURCE = 0x0001U,
	PA_SUBSCRIPTION_EVENT_SINK_INPUT = 0x0002U,
	PA_SUBSCRIPTION_EVENT_SOURCE_OUTPUT = 0x0003U,
	PA_SUBSCRIPTION_EVENT_MODULE = 0x0004U,
	PA_SUBSCRIPTION_EVENT_CLIENT = 0x0005U,
	PA_SUBSCRIPTION_EVENT_SAMPLE_CACHE = 0x0006U,
	PA_SUBSCRIPTION_EVENT_SERVER = 0x0007U,
	PA_SUBSCRIPTION_EVENT_AUTOLOAD = 0x0008U,
	PA_SUBSCRIPTION_EVENT_CARD = 0x0009U,
	PA_SUBSCRIPTION_EVENT_FACILITY_MASK = 0x000FU,
	PA_SUBSCRIPTION_EVENT_NEW = 0x0000U,
	PA_SUBSCRIPTION_EVENT_CHANGE = 0x0010U,
	PA_SUBSCRIPTION_EVENT_REMOVE = 0x0020U,
	PA_SUBSCRIPTION_EVENT_TYPE_MASK = 0x0030U
}
alias pa_sample_format_t = int;
enum {
	PA_SAMPLE_U8,
	PA_SAMPLE_ALAW,
	PA_SAMPLE_ULAW,
	PA_SAMPLE_S16LE,
	PA_SAMPLE_S16BE,
	PA_SAMPLE_FLOAT32LE,
	PA_SAMPLE_FLOAT32BE,
	PA_SAMPLE_S32LE,
	PA_SAMPLE_S32BE,
	PA_SAMPLE_S24LE,
	PA_SAMPLE_S24BE,
	PA_SAMPLE_S24_32LE,
	PA_SAMPLE_S24_32BE,
	PA_SAMPLE_MAX,
	PA_SAMPLE_INVALID = -1
}