/// C declarations of JACK that libsoundio uses
module soundio.headers.jackheader;

@nogc nothrow:
extern(C): __gshared:


import core.stdc.config: c_long, c_ulong;

enum JACK_DEFAULT_AUDIO_TYPE = "32 bit float mono audio";

alias jack_nframes_t = uint;
alias jack_port_id_t = uint;

struct jack_latency_range_t {
    jack_nframes_t min;
    jack_nframes_t max;
}

struct jack_client_t;
struct jack_port_t;

alias int function(jack_nframes_t nframes, void* arg) JackBufferSizeCallback;
alias int function(jack_nframes_t nframes, void* arg) JackSampleRateCallback;
alias void function(jack_port_id_t port, int, void* arg) JackPortRegistrationCallback;
alias void function(jack_port_id_t port, const(char)* old_name, const(char)* new_name, void* arg) JackPortRenameCallback;
alias void function(void* arg) JackShutdownCallback;
alias int function(jack_nframes_t nframes, void* arg) JackProcessCallback;
alias int function(void* arg) JackXRunCallback;

alias jack_latency_callback_mode_t = int; // C enum; JackLatencyCallbackMode
enum {
    JackCaptureLatency,
    JackPlaybackLatency,
}

// JackPortFlags
enum {
    JackPortIsInput = 0x1,
    JackPortIsOutput = 0x2,
    JackPortIsPhysical = 0x4,
    JackPortCanMonitor = 0x8,
    JackPortIsTerminal = 0x10
}

alias jack_status_t = int; // C enum
enum {
    JackFailure = 0x01,
    JackInvalidOption = 0x02,
    JackNameNotUnique = 0x04,
    JackServerStarted = 0x08,
    JackServerFailed = 0x10,
    JackServerError = 0x20,
    JackNoSuchClient = 0x40,
    JackLoadFailure = 0x80,
    JackInitFailure = 0x100,
    JackShmFailure = 0x200,
    JackVersionError = 0x400,
    JackBackendError = 0x800,
    JackClientZombie = 0x1000
}

alias jack_options_t = int;
enum {
    JackNullOption = 0x00,
    JackNoStartServer = 0x01,
    JackUseExactName = 0x02,
    JackServerName = 0x04,
    JackLoadName = 0x08,
    JackLoadInit = 0x10,
    JackSessionID = 0x20
}

void jack_free(void* ptr);
int jack_set_buffer_size_callback(jack_client_t* client, JackBufferSizeCallback bufsize_callback, void* arg);
int jack_set_sample_rate_callback(jack_client_t* client, JackSampleRateCallback srate_callback, void* arg);
jack_port_t* jack_port_by_name(jack_client_t*, const(char)* port_name);
int jack_port_flags(const(jack_port_t)* port);
const(char)* jack_port_type(const(jack_port_t)* port);
void jack_port_get_latency_range(jack_port_t* port, jack_latency_callback_mode_t mode, jack_latency_range_t* range);
const(char)** jack_get_ports(jack_client_t*, const(char)* port_name_pattern, const(char)* type_name_pattern, c_ulong flags);
jack_nframes_t jack_get_sample_rate(jack_client_t*);
jack_nframes_t jack_get_buffer_size(jack_client_t*);
int jack_activate(jack_client_t* client);
int jack_set_port_rename_callback(jack_client_t*, JackPortRenameCallback rename_callback, void* arg);
int jack_set_port_registration_callback(jack_client_t*, JackPortRegistrationCallback registration_callback, void* arg);
jack_client_t* jack_client_open(const(char)* client_name, jack_options_t options, jack_status_t* status, ...);
void jack_set_info_function(void function(const(char)*) func);
void jack_on_shutdown(jack_client_t* client, JackShutdownCallback function_, void* arg);
void jack_set_error_function(void function(const(char)*) func);
int jack_client_close(jack_client_t* client);
int jack_connect(jack_client_t*, const(char)* source_port, const(char)* destination_port);
const(char)* jack_port_name(const(jack_port_t)* port);
void* jack_port_get_buffer(jack_port_t*, jack_nframes_t);
int jack_set_process_callback(jack_client_t* client, JackProcessCallback process_callback, void* arg);
int jack_set_xrun_callback(jack_client_t*, JackXRunCallback xrun_callback, void* arg);
jack_port_t* jack_port_register(jack_client_t* client, const(char)* port_name, const(char)* port_type, c_ulong flags, c_ulong buffer_size);
