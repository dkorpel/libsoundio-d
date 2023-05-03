/// Translated from C to D
module soundio.jack;

version(SOUNDIO_HAVE_JACK):
@nogc nothrow:
extern(C): __gshared:

import core.stdc.config: c_long, c_ulong;

import soundio.api;
import soundio.os;
import soundio.atomics;

import soundio.soundio_private;
import soundio.list;
import core.stdc.stdio;
import core.stdc.stdlib: free;
import core.stdc.string: strlen, strcmp, memcpy;

import soundio.headers.jackheader;

package:

struct SoundIoDeviceJackPort {
    char* full_name;
    int full_name_len;
    SoundIoChannelId channel_id;
    jack_latency_range_t latency_range;
}

struct SoundIoDeviceJack {
    int port_count;
    SoundIoDeviceJackPort* ports;
}

struct SoundIoJack {
    jack_client_t* client;
    SoundIoOsMutex* mutex;
    SoundIoOsCond* cond;
    SoundIoAtomicFlag refresh_devices_flag;
    int sample_rate;
    int period_size;
    bool is_shutdown;
    bool emitted_shutdown_cb;
}

struct SoundIoOutStreamJackPort {
    jack_port_t* source_port;
    const(char)* dest_port_name;
    int dest_port_name_len;
}

struct SoundIoOutStreamJack {
    jack_client_t* client;
    int period_size;
    int frames_left;
    double hardware_latency;
    SoundIoOutStreamJackPort[SOUNDIO_MAX_CHANNELS] ports;
    SoundIoChannelArea[SOUNDIO_MAX_CHANNELS] areas;
}

struct SoundIoInStreamJackPort {
    jack_port_t* dest_port;
    const(char)* source_port_name;
    int source_port_name_len;
}

struct SoundIoInStreamJack {
    jack_client_t* client;
    int period_size;
    int frames_left;
    double hardware_latency;
    SoundIoInStreamJackPort[SOUNDIO_MAX_CHANNELS] ports;
    SoundIoChannelArea[SOUNDIO_MAX_CHANNELS] areas;
    char*[SOUNDIO_MAX_CHANNELS] buf_ptrs;
}

private SoundIoAtomicFlag global_msg_callback_flag = SOUNDIO_ATOMIC_FLAG_INIT;

struct SoundIoJackPort {
    const(char)* full_name;
    int full_name_len;
    const(char)* name;
    int name_len;
    SoundIoChannelId channel_id;
    jack_latency_range_t latency_range;
}

struct SoundIoJackClient {
    const(char)* name;
    int name_len;
    bool is_physical;
    SoundIoDeviceAim aim;
    int port_count;
    SoundIoJackPort[SOUNDIO_MAX_CHANNELS] ports;
}

alias SoundIoListJackClient = SOUNDIO_LIST!SoundIoJackClient;

private void split_str(const(char)* input_str, int input_str_len, char c, const(char)** out_1, int* out_len_1, const(char)** out_2, int* out_len_2) {
    *out_1 = input_str;
    while (*input_str) {
        if (*input_str == c) {
            *out_len_1 = cast(int) (input_str - *out_1);
            *out_2 = input_str + 1;
            *out_len_2 = input_str_len - 1 - *out_len_1;
            return;
        }
        input_str += 1;
    }
}

private SoundIoJackClient* find_or_create_client(SoundIoListJackClient* clients, SoundIoDeviceAim aim, bool is_physical, const(char)* client_name, int client_name_len) {
    for (int i = 0; i < clients.length; i += 1) {
        SoundIoJackClient* client = clients.ptr_at(i);
        if (client.is_physical == is_physical &&
            client.aim == aim &&
            soundio_streql(client.name, client.name_len, client_name, client_name_len))
        {
            return client;
        }
    }
    if (auto err = clients.add_one())
        return null;
    SoundIoJackClient* client = clients.last_ptr();
    client.is_physical = is_physical;
    client.aim = aim;
    client.name = client_name;
    client.name_len = client_name_len;
    client.port_count = 0;
    return client;
}

private void destruct_device(SoundIoDevicePrivate* dp) {
    SoundIoDeviceJack* dj = &dp.backend_data.jack;
    for (int i = 0; i < dj.port_count; i += 1) {
        SoundIoDeviceJackPort* djp = &dj.ports[i];
        free(djp.full_name);
    }
    free(dj.ports);
}

private int refresh_devices_bare(SoundIoPrivate* si) {
    SoundIo* soundio = &si.pub;
    SoundIoJack* sij = &si.backend_data.jack;

    if (sij.is_shutdown)
        return SoundIoErrorBackendDisconnected;


    SoundIoDevicesInfo* devices_info = ALLOCATE!SoundIoDevicesInfo(1);
    if (!devices_info)
        return SoundIoErrorNoMem;

    devices_info.default_output_index = -1;
    devices_info.default_input_index = -1;
    const(char)** port_names = jack_get_ports(sij.client, null, null, 0);
    if (!port_names) {
        soundio_destroy_devices_info(devices_info);
        return SoundIoErrorNoMem;
    }

    SoundIoListJackClient clients = SoundIoListJackClient.init; // TODO: zero?
    const(char)** port_name_ptr = port_names;
    for (; *port_name_ptr; port_name_ptr += 1) {
        const(char)* client_and_port_name = *port_name_ptr;
        int client_and_port_name_len = cast(int) strlen(client_and_port_name);
        jack_port_t* jport = jack_port_by_name(sij.client, client_and_port_name);
        if (!jport) {
            // This refresh devices scan is already outdated. Just give up and
            // let refresh_devices be called again.
            jack_free(port_names);
            soundio_destroy_devices_info(devices_info);
            return SoundIoErrorInterrupted;
        }

        int flags = jack_port_flags(jport);
        const(char)* port_type = jack_port_type(jport);
        if (strcmp(port_type, JACK_DEFAULT_AUDIO_TYPE) != 0) {
            // we don't know how to support such a port
            continue;
        }

        SoundIoDeviceAim aim = (flags & JackPortIsInput) ?
            SoundIoDeviceAimOutput : SoundIoDeviceAimInput;
        bool is_physical = cast(bool) (flags & JackPortIsPhysical);

        const(char)* client_name = null;
        const(char)* port_name = null;
        int client_name_len;
        int port_name_len;
        split_str(client_and_port_name, client_and_port_name_len, ':',
                &client_name, &client_name_len, &port_name, &port_name_len);
        if (!client_name || !port_name) {
            // device does not have colon, skip it
            continue;
        }
        SoundIoJackClient* client = find_or_create_client(&clients, aim, is_physical,
                client_name, client_name_len);
        if (!client) {
            jack_free(port_names);
            soundio_destroy_devices_info(devices_info);
            return SoundIoErrorNoMem;
        }
        if (client.port_count >= SOUNDIO_MAX_CHANNELS) {
            // we hit the channel limit, skip the leftovers
            continue;
        }
        SoundIoJackPort* port = &client.ports[client.port_count++];
        port.full_name = client_and_port_name;
        port.full_name_len = client_and_port_name_len;
        port.name = port_name;
        port.name_len = port_name_len;
        port.channel_id = soundio_parse_channel_id(port_name, port_name_len);

        jack_latency_callback_mode_t latency_mode = (aim == SoundIoDeviceAimOutput) ?
            JackPlaybackLatency : JackCaptureLatency;
        jack_port_get_latency_range(jport, latency_mode, &port.latency_range);
    }

    for (int i = 0; i < clients.length; i += 1) {
        SoundIoJackClient* client = clients.ptr_at(i);
        if (client.port_count <= 0)
            continue;

        SoundIoDevicePrivate* dev = ALLOCATE!SoundIoDevicePrivate(1);
        if (!dev) {
            jack_free(port_names);
            soundio_destroy_devices_info(devices_info);
            return SoundIoErrorNoMem;
        }
        SoundIoDevice* device = &dev.pub;
        SoundIoDeviceJack* dj = &dev.backend_data.jack;
        int description_len = client.name_len + 3 + 2 * client.port_count;
        for (int port_index = 0; port_index < client.port_count; port_index += 1) {
            SoundIoJackPort* port = &client.ports[port_index];

            description_len += port.name_len;
        }

        dev.destruct = &destruct_device;

        device.ref_count = 1;
        device.soundio = soundio;
        device.is_raw = false;
        device.aim = client.aim;
        device.id = soundio_str_dupe(client.name, client.name_len);
        device.name = ALLOCATE!char(description_len);
        device.current_format = SoundIoFormatFloat32NE;
        device.sample_rate_count = 1;
        device.sample_rates = &dev.prealloc_sample_rate_range;
        device.sample_rates[0].min = sij.sample_rate;
        device.sample_rates[0].max = sij.sample_rate;
        device.sample_rate_current = sij.sample_rate;

        device.software_latency_current = sij.period_size / cast(double) sij.sample_rate;
        device.software_latency_min = sij.period_size / cast(double) sij.sample_rate;
        device.software_latency_max = sij.period_size / cast(double) sij.sample_rate;

        dj.port_count = client.port_count;
        dj.ports = ALLOCATE!SoundIoDeviceJackPort(dj.port_count);

        if (!device.id || !device.name || !dj.ports) {
            jack_free(port_names);
            soundio_device_unref(device);
            soundio_destroy_devices_info(devices_info);
            return SoundIoErrorNoMem;
        }

        for (int port_index = 0; port_index < client.port_count; port_index += 1) {
            SoundIoJackPort* port = &client.ports[port_index];
            SoundIoDeviceJackPort* djp = &dj.ports[port_index];
            djp.full_name = soundio_str_dupe(port.full_name, port.full_name_len);
            djp.full_name_len = port.full_name_len;
            djp.channel_id = port.channel_id;
            djp.latency_range = port.latency_range;

            if (!djp.full_name) {
                jack_free(port_names);
                soundio_device_unref(device);
                soundio_destroy_devices_info(devices_info);
                return SoundIoErrorNoMem;
            }
        }

        memcpy(device.name, client.name, client.name_len);
        memcpy(&device.name[client.name_len], ": ".ptr, 2);
        int index = client.name_len + 2;
        for (int port_index = 0; port_index < client.port_count; port_index += 1) {
            SoundIoJackPort* port = &client.ports[port_index];
            memcpy(&device.name[index], port.name, port.name_len);
            index += port.name_len;
            if (port_index + 1 < client.port_count) {
                memcpy(&device.name[index], ", ".ptr, 2);
                index += 2;
            }
        }

        device.current_layout.channel_count = client.port_count;
        bool any_invalid = false;
        for (int port_index = 0; port_index < client.port_count; port_index += 1) {
            SoundIoJackPort* port = &client.ports[port_index];
            device.current_layout.channels[port_index] = port.channel_id;
            any_invalid = any_invalid || (port.channel_id == SoundIoChannelId.Invalid);
        }
        if (any_invalid) {
            const(SoundIoChannelLayout)* layout = soundio_channel_layout_get_default(client.port_count);
            if (layout)
                device.current_layout = *layout;
        } else {
            soundio_channel_layout_detect_builtin(&device.current_layout);
        }

        device.layout_count = 1;
        device.layouts = &device.current_layout;
        device.format_count = 1;
        device.formats = &dev.prealloc_format;
        device.formats[0] = device.current_format;

        SoundIoListDevicePtr* device_list;
        if (device.aim == SoundIoDeviceAimOutput) {
            device_list = &devices_info.output_devices;
            if (devices_info.default_output_index < 0 && client.is_physical)
                devices_info.default_output_index = device_list.length;
        } else {
            assert(device.aim == SoundIoDeviceAimInput);
            device_list = &devices_info.input_devices;
            if (devices_info.default_input_index < 0 && client.is_physical)
                devices_info.default_input_index = device_list.length;
        }

        if (device_list.append(device)) {
            soundio_device_unref(device);
            soundio_destroy_devices_info(devices_info);
            return SoundIoErrorNoMem;
        }

    }
    jack_free(port_names);

    soundio_destroy_devices_info(si.safe_devices_info);
    si.safe_devices_info = devices_info;

    return 0;
}

private int refresh_devices(SoundIoPrivate* si) {
    int err = SoundIoErrorInterrupted;
    while (err == SoundIoErrorInterrupted)
        err = refresh_devices_bare(si);
    return err;
}

private extern(D) void my_flush_events(SoundIoPrivate* si, bool wait) {
    SoundIo* soundio = &si.pub;
    SoundIoJack* sij = &si.backend_data.jack;

    bool cb_shutdown = false;

    soundio_os_mutex_lock(sij.mutex);

    if (wait)
        soundio_os_cond_wait(sij.cond, sij.mutex);

    if (sij.is_shutdown && !sij.emitted_shutdown_cb) {
        sij.emitted_shutdown_cb = true;
        cb_shutdown = true;
    }

    soundio_os_mutex_unlock(sij.mutex);

    if (cb_shutdown) {
        soundio.on_backend_disconnect(soundio, SoundIoErrorBackendDisconnected);
    } else {
        if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(sij.refresh_devices_flag)) {
            if (auto err = refresh_devices(si)) {
                SOUNDIO_ATOMIC_FLAG_CLEAR(sij.refresh_devices_flag);
            } else {
                soundio.on_devices_change(soundio);
            }
        }
    }
}

private void flush_events_jack(SoundIoPrivate* si) {
    my_flush_events(si, false);
}

private void wait_events_jack(SoundIoPrivate* si) {
    my_flush_events(si, false);
    my_flush_events(si, true);
}

private void wakeup_jack(SoundIoPrivate* si) {
    SoundIoJack* sij = &si.backend_data.jack;
    soundio_os_mutex_lock(sij.mutex);
    soundio_os_cond_signal(sij.cond, sij.mutex);
    soundio_os_mutex_unlock(sij.mutex);
}

private void force_device_scan_jack(SoundIoPrivate* si) {
    SoundIo* soundio = &si.pub;
    SoundIoJack* sij = &si.backend_data.jack;
    SOUNDIO_ATOMIC_FLAG_CLEAR(sij.refresh_devices_flag);
    soundio_os_mutex_lock(sij.mutex);
    soundio_os_cond_signal(sij.cond, sij.mutex);
    soundio.on_events_signal(soundio);
    soundio_os_mutex_unlock(sij.mutex);
}

private int outstream_process_callback(jack_nframes_t nframes, void* arg) {
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)arg;
    SoundIoOutStreamJack* osj = &os.backend_data.jack;
    SoundIoOutStream* outstream = &os.pub;
    osj.frames_left = nframes;
    for (int ch = 0; ch < outstream.layout.channel_count; ch += 1) {
        SoundIoOutStreamJackPort* osjp = &osj.ports[ch];
        osj.areas[ch].ptr = cast(char*)jack_port_get_buffer(osjp.source_port, nframes);
        osj.areas[ch].step = outstream.bytes_per_sample;
    }
    outstream.write_callback(outstream, osj.frames_left, osj.frames_left);
    return 0;
}

private void outstream_destroy_jack(SoundIoPrivate* is_, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamJack* osj = &os.backend_data.jack;

    jack_client_close(osj.client);
    osj.client = null;
}

private SoundIoDeviceJackPort* find_port_matching_channel(SoundIoDevice* device, SoundIoChannelId id) {
    SoundIoDevicePrivate* dev = cast(SoundIoDevicePrivate*)device;
    SoundIoDeviceJack* dj = &dev.backend_data.jack;

    for (int ch = 0; ch < device.current_layout.channel_count; ch += 1) {
        SoundIoChannelId chan_id = device.current_layout.channels[ch];
        if (chan_id == id)
            return &dj.ports[ch];
    }

    return null;
}

private int outstream_xrun_callback(void* arg) {
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)arg;
    SoundIoOutStream* outstream = &os.pub;
    outstream.underflow_callback(outstream);
    return 0;
}

private int outstream_buffer_size_callback(jack_nframes_t nframes, void* arg) {
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)arg;
    SoundIoOutStreamJack* osj = &os.backend_data.jack;
    SoundIoOutStream* outstream = &os.pub;
    if (cast(jack_nframes_t)osj.period_size == nframes) {
        return 0;
    } else {
        outstream.error_callback(outstream, SoundIoErrorStreaming);
        return -1;
    }
}

private int outstream_sample_rate_callback(jack_nframes_t nframes, void* arg) {
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)arg;
    SoundIoOutStream* outstream = &os.pub;
    if (nframes == cast(jack_nframes_t)outstream.sample_rate) {
        return 0;
    } else {
        outstream.error_callback(outstream, SoundIoErrorStreaming);
        return -1;
    }
}

private void outstream_shutdown_callback(void* arg) {
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)arg;
    SoundIoOutStream* outstream = &os.pub;
    outstream.error_callback(outstream, SoundIoErrorStreaming);
}

pragma(inline, true) private jack_nframes_t nframes_max(jack_nframes_t a, jack_nframes_t b) {
    return (a >= b) ? a : b;
}

private int outstream_open_jack(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoJack* sij = &si.backend_data.jack;
    SoundIoOutStreamJack* osj = &os.backend_data.jack;
    SoundIoOutStream* outstream = &os.pub;
    SoundIoDevice* device = outstream.device;
    SoundIoDevicePrivate* dev = cast(SoundIoDevicePrivate*)device;
    SoundIoDeviceJack* dj = &dev.backend_data.jack;

    if (sij.is_shutdown)
        return SoundIoErrorBackendDisconnected;

    if (!outstream.name)
        outstream.name = "SoundIoOutStream";

    outstream.software_latency = device.software_latency_current;
    osj.period_size = sij.period_size;

    jack_status_t status;
    osj.client = jack_client_open(outstream.name, JackNoStartServer, &status);
    if (!osj.client) {
        outstream_destroy_jack(si, os);
        assert(!(status & JackInvalidOption));
        if (status & JackShmFailure)
            return SoundIoErrorSystemResources;
        if (status & JackNoSuchClient)
            return SoundIoErrorNoSuchClient;
        return SoundIoErrorOpeningDevice;
    }

    if (auto err = jack_set_process_callback(osj.client, &outstream_process_callback, os)) {
        outstream_destroy_jack(si, os);
        return SoundIoErrorOpeningDevice;
    }
    if (auto err = jack_set_buffer_size_callback(osj.client, &outstream_buffer_size_callback, os)) {
        outstream_destroy_jack(si, os);
        return SoundIoErrorOpeningDevice;
    }
    if (auto err = jack_set_sample_rate_callback(osj.client, &outstream_sample_rate_callback, os)) {
        outstream_destroy_jack(si, os);
        return SoundIoErrorOpeningDevice;
    }
    if (auto err = jack_set_xrun_callback(osj.client, &outstream_xrun_callback, os)) {
        outstream_destroy_jack(si, os);
        return SoundIoErrorOpeningDevice;
    }
    jack_on_shutdown(osj.client, &outstream_shutdown_callback, os);


    jack_nframes_t max_port_latency = 0;

    // register ports and map channels
    int connected_count = 0;
    for (int ch = 0; ch < outstream.layout.channel_count; ch += 1) {
        SoundIoChannelId my_channel_id = outstream.layout.channels[ch];
        const(char)* channel_name = soundio_get_channel_name(my_channel_id);
        c_ulong flags = JackPortIsOutput;
        if (!outstream.non_terminal_hint)
            flags |= JackPortIsTerminal;
        jack_port_t* jport = jack_port_register(osj.client, channel_name, JACK_DEFAULT_AUDIO_TYPE, flags, 0);
        if (!jport) {
            outstream_destroy_jack(si, os);
            return SoundIoErrorOpeningDevice;
        }
        SoundIoOutStreamJackPort* osjp = &osj.ports[ch];
        osjp.source_port = jport;
        // figure out which dest port this connects to
        SoundIoDeviceJackPort* djp = find_port_matching_channel(device, my_channel_id);
        if (djp) {
            osjp.dest_port_name = djp.full_name;
            osjp.dest_port_name_len = djp.full_name_len;
            connected_count += 1;
            max_port_latency = nframes_max(max_port_latency, djp.latency_range.max);
        }
    }
    // If nothing got connected, channel layouts aren't working. Just send the
    // data in the order of the ports.
    if (connected_count == 0) {
        max_port_latency = 0;
        outstream.layout_error = SoundIoErrorIncompatibleDevice;

        int ch_count = soundio_int_min(outstream.layout.channel_count, dj.port_count);
        for (int ch = 0; ch < ch_count; ch += 1) {
            SoundIoOutStreamJackPort* osjp = &osj.ports[ch];
            SoundIoDeviceJackPort* djp = &dj.ports[ch];
            osjp.dest_port_name = djp.full_name;
            osjp.dest_port_name_len = djp.full_name_len;
            max_port_latency = nframes_max(max_port_latency, djp.latency_range.max);
        }
    }

    osj.hardware_latency = max_port_latency / cast(double)outstream.sample_rate;

    return 0;
}

private int outstream_pause_jack(SoundIoPrivate* si, SoundIoOutStreamPrivate* os, bool pause) {
    SoundIoJack* sij = &si.backend_data.jack;

    if (sij.is_shutdown)
        return SoundIoErrorBackendDisconnected;

    return SoundIoErrorIncompatibleBackend;
}

private int outstream_start_jack(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamJack* osj = &os.backend_data.jack;
    SoundIoOutStream* outstream = &os.pub;
    SoundIoJack* sij = &si.backend_data.jack;

    if (sij.is_shutdown)
        return SoundIoErrorBackendDisconnected;

    if (auto err = jack_activate(osj.client))
        return SoundIoErrorStreaming;

    for (int ch = 0; ch < outstream.layout.channel_count; ch += 1) {
        SoundIoOutStreamJackPort* osjp = &osj.ports[ch];
        const(char)* dest_port_name = osjp.dest_port_name;
        // allow unconnected ports
        if (!dest_port_name)
            continue;
        const(char)* source_port_name = jack_port_name(osjp.source_port);
        if (auto err = jack_connect(osj.client, source_port_name, dest_port_name))
            return SoundIoErrorStreaming;
    }

    return 0;
}

private int outstream_begin_write_jack(SoundIoPrivate* si, SoundIoOutStreamPrivate* os, SoundIoChannelArea** out_areas, int* frame_count) {
    SoundIoOutStreamJack* osj = &os.backend_data.jack;

    if (*frame_count != osj.frames_left)
        return SoundIoErrorInvalid;

    *out_areas = osj.areas.ptr;

    return 0;
}

private int outstream_end_write_jack(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamJack* osj = &os.backend_data.jack;
    osj.frames_left = 0;
    return 0;
}

private int outstream_clear_buffer_jack(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    return SoundIoErrorIncompatibleBackend;
}

private int outstream_get_latency_jack(SoundIoPrivate* si, SoundIoOutStreamPrivate* os, double* out_latency) {
    SoundIoOutStreamJack* osj = &os.backend_data.jack;
    *out_latency = osj.hardware_latency;
    return 0;
}


private void instream_destroy_jack(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamJack* isj = &is_.backend_data.jack;

    jack_client_close(isj.client);
    isj.client = null;
}

private int instream_xrun_callback(void* arg) {
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)arg;
    SoundIoInStream* instream = &is_.pub;
    instream.overflow_callback(instream);
    return 0;
}

private int instream_buffer_size_callback(jack_nframes_t nframes, void* arg) {
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)arg;
    SoundIoInStreamJack* isj = &is_.backend_data.jack;
    SoundIoInStream* instream = &is_.pub;

    if (cast(jack_nframes_t)isj.period_size == nframes) {
        return 0;
    } else {
        instream.error_callback(instream, SoundIoErrorStreaming);
        return -1;
    }
}

private int instream_sample_rate_callback(jack_nframes_t nframes, void* arg) {
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)arg;
    SoundIoInStream* instream = &is_.pub;
    if (nframes == cast(jack_nframes_t)instream.sample_rate) {
        return 0;
    } else {
        instream.error_callback(instream, SoundIoErrorStreaming);
        return -1;
    }
}

private void instream_shutdown_callback(void* arg) {
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)arg;
    SoundIoInStream* instream = &is_.pub;
    instream.error_callback(instream, SoundIoErrorStreaming);
}

private int instream_process_callback(jack_nframes_t nframes, void* arg) {
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)arg;
    SoundIoInStream* instream = &is_.pub;
    SoundIoInStreamJack* isj = &is_.backend_data.jack;
    isj.frames_left = nframes;
    for (int ch = 0; ch < instream.layout.channel_count; ch += 1) {
        SoundIoInStreamJackPort* isjp = &isj.ports[ch];
        isj.areas[ch].ptr = cast(char*)jack_port_get_buffer(isjp.dest_port, nframes);
        isj.areas[ch].step = instream.bytes_per_sample;
    }
    instream.read_callback(instream, isj.frames_left, isj.frames_left);
    return 0;
}

private int instream_open_jack(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStream* instream = &is_.pub;
    SoundIoInStreamJack* isj = &is_.backend_data.jack;
    SoundIoJack* sij = &si.backend_data.jack;
    SoundIoDevice* device = instream.device;
    SoundIoDevicePrivate* dev = cast(SoundIoDevicePrivate*)device;
    SoundIoDeviceJack* dj = &dev.backend_data.jack;

    if (sij.is_shutdown)
        return SoundIoErrorBackendDisconnected;

    if (!instream.name)
        instream.name = "SoundIoInStream";

    instream.software_latency = device.software_latency_current;
    isj.period_size = sij.period_size;

    jack_status_t status;
    isj.client = jack_client_open(instream.name, JackNoStartServer, &status);
    if (!isj.client) {
        instream_destroy_jack(si, is_);
        assert(!(status & JackInvalidOption));
        if (status & JackShmFailure)
            return SoundIoErrorSystemResources;
        if (status & JackNoSuchClient)
            return SoundIoErrorNoSuchClient;
        return SoundIoErrorOpeningDevice;
    }

    if (auto err = jack_set_process_callback(isj.client, &instream_process_callback, is_)) {
        instream_destroy_jack(si, is_);
        return SoundIoErrorOpeningDevice;
    }
    if (auto err = jack_set_buffer_size_callback(isj.client, &instream_buffer_size_callback, is_)) {
        instream_destroy_jack(si, is_);
        return SoundIoErrorOpeningDevice;
    }
    if (auto err = jack_set_sample_rate_callback(isj.client, &instream_sample_rate_callback, is_)) {
        instream_destroy_jack(si, is_);
        return SoundIoErrorOpeningDevice;
    }
    if (auto err = jack_set_xrun_callback(isj.client, &instream_xrun_callback, is_)) {
        instream_destroy_jack(si, is_);
        return SoundIoErrorOpeningDevice;
    }
    jack_on_shutdown(isj.client, &instream_shutdown_callback, is_);

    jack_nframes_t max_port_latency = 0;

    // register ports and map channels
    int connected_count = 0;
    for (int ch = 0; ch < instream.layout.channel_count; ch += 1) {
        SoundIoChannelId my_channel_id = instream.layout.channels[ch];
        const(char)* channel_name = soundio_get_channel_name(my_channel_id);
        c_ulong flags = JackPortIsInput;
        if (!instream.non_terminal_hint)
            flags |= JackPortIsTerminal;
        jack_port_t* jport = jack_port_register(isj.client, channel_name, JACK_DEFAULT_AUDIO_TYPE, flags, 0);
        if (!jport) {
            instream_destroy_jack(si, is_);
            return SoundIoErrorOpeningDevice;
        }
        SoundIoInStreamJackPort* isjp = &isj.ports[ch];
        isjp.dest_port = jport;
        // figure out which source port this connects to
        SoundIoDeviceJackPort* djp = find_port_matching_channel(device, my_channel_id);
        if (djp) {
            isjp.source_port_name = djp.full_name;
            isjp.source_port_name_len = djp.full_name_len;
            connected_count += 1;
            max_port_latency = nframes_max(max_port_latency, djp.latency_range.max);
        }
    }
    // If nothing got connected, channel layouts aren't working. Just send the
    // data in the order of the ports.
    if (connected_count == 0) {
        max_port_latency = 0;
        instream.layout_error = SoundIoErrorIncompatibleDevice;

        int ch_count = soundio_int_min(instream.layout.channel_count, dj.port_count);
        for (int ch = 0; ch < ch_count; ch += 1) {
            SoundIoInStreamJackPort* isjp = &isj.ports[ch];
            SoundIoDeviceJackPort* djp = &dj.ports[ch];
            isjp.source_port_name = djp.full_name;
            isjp.source_port_name_len = djp.full_name_len;
            max_port_latency = nframes_max(max_port_latency, djp.latency_range.max);
        }
    }

    isj.hardware_latency = max_port_latency / cast(double)instream.sample_rate;

    return 0;
}

private int instream_pause_jack(SoundIoPrivate* si, SoundIoInStreamPrivate* is_, bool pause) {
    SoundIoJack* sij = &si.backend_data.jack;

    if (sij.is_shutdown)
        return SoundIoErrorBackendDisconnected;

    return SoundIoErrorIncompatibleBackend;
}

private int instream_start_jack(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamJack* isj = &is_.backend_data.jack;
    SoundIoInStream* instream = &is_.pub;
    SoundIoJack* sij = &si.backend_data.jack;

    if (sij.is_shutdown)
        return SoundIoErrorBackendDisconnected;

    if (auto err = jack_activate(isj.client))
        return SoundIoErrorStreaming;

    for (int ch = 0; ch < instream.layout.channel_count; ch += 1) {
        SoundIoInStreamJackPort* isjp = &isj.ports[ch];
        const(char)* source_port_name = isjp.source_port_name;
        // allow unconnected ports
        if (!source_port_name)
            continue;
        const(char)* dest_port_name = jack_port_name(isjp.dest_port);
        if (auto err = jack_connect(isj.client, source_port_name, dest_port_name))
            return SoundIoErrorStreaming;
    }

    return 0;
}

private int instream_begin_read_jack(SoundIoPrivate* si, SoundIoInStreamPrivate* is_, SoundIoChannelArea** out_areas, int* frame_count) {
    SoundIoInStreamJack* isj = &is_.backend_data.jack;

    if (*frame_count != isj.frames_left)
        return SoundIoErrorInvalid;

    *out_areas = isj.areas.ptr;

    return 0;
}

private int instream_end_read_jack(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamJack* isj = &is_.backend_data.jack;
    isj.frames_left = 0;
    return 0;
}

private int instream_get_latency_jack(SoundIoPrivate* si, SoundIoInStreamPrivate* is_, double* out_latency) {
    SoundIoInStreamJack* isj = &is_.backend_data.jack;
    *out_latency = isj.hardware_latency;
    return 0;
}

private void notify_devices_change(SoundIoPrivate* si) {
    SoundIo* soundio = &si.pub;
    SoundIoJack* sij = &si.backend_data.jack;
    SOUNDIO_ATOMIC_FLAG_CLEAR(sij.refresh_devices_flag);
    soundio_os_mutex_lock(sij.mutex);
    soundio_os_cond_signal(sij.cond, sij.mutex);
    soundio.on_events_signal(soundio);
    soundio_os_mutex_unlock(sij.mutex);
}

private int buffer_size_callback(jack_nframes_t nframes, void* arg) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)arg;
    SoundIoJack* sij = &si.backend_data.jack;
    sij.period_size = nframes;
    notify_devices_change(si);
    return 0;
}

private int sample_rate_callback(jack_nframes_t nframes, void* arg) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)arg;
    SoundIoJack* sij = &si.backend_data.jack;
    sij.sample_rate = nframes;
    notify_devices_change(si);
    return 0;
}

private void port_registration_callback(jack_port_id_t port_id, int reg, void* arg) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)arg;
    notify_devices_change(si);
}

private void port_rename_calllback(jack_port_id_t port_id, const(char)* old_name, const(char)* new_name, void* arg) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)arg;
    notify_devices_change(si);
}

private void shutdown_callback(void* arg) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)arg;
    SoundIo* soundio = &si.pub;
    SoundIoJack* sij = &si.backend_data.jack;
    soundio_os_mutex_lock(sij.mutex);
    sij.is_shutdown = true;
    soundio_os_cond_signal(sij.cond, sij.mutex);
    soundio.on_events_signal(soundio);
    soundio_os_mutex_unlock(sij.mutex);
}

private void destroy_jack(SoundIoPrivate* si) {
    SoundIoJack* sij = &si.backend_data.jack;

    if (sij.client)
        jack_client_close(sij.client);

    if (sij.cond)
        soundio_os_cond_destroy(sij.cond);

    if (sij.mutex)
        soundio_os_mutex_destroy(sij.mutex);
}

int soundio_jack_init(SoundIoPrivate* si) {
    SoundIoJack* sij = &si.backend_data.jack;
    SoundIo* soundio = &si.pub;

    if (!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(global_msg_callback_flag)) {
        if (soundio.jack_error_callback)
            jack_set_error_function(soundio.jack_error_callback);
        if (soundio.jack_info_callback)
            jack_set_info_function(soundio.jack_info_callback);
        SOUNDIO_ATOMIC_FLAG_CLEAR(global_msg_callback_flag);
    }

    sij.mutex = soundio_os_mutex_create();
    if (!sij.mutex) {
        destroy_jack(si);
        return SoundIoErrorNoMem;
    }

    sij.cond = soundio_os_cond_create();
    if (!sij.cond) {
        destroy_jack(si);
        return SoundIoErrorNoMem;
    }

    // We pass JackNoStartServer due to
    // https://github.com/jackaudio/jack2/issues/138
    jack_status_t status;
    sij.client = jack_client_open(soundio.app_name, JackNoStartServer, &status);
    if (!sij.client) {
        destroy_jack(si);
        assert(!(status & JackInvalidOption));
        if (status & JackShmFailure)
            return SoundIoErrorSystemResources;
        if (status & JackNoSuchClient)
            return SoundIoErrorNoSuchClient;

        return SoundIoErrorInitAudioBackend;
    }

    if (auto err = jack_set_buffer_size_callback(sij.client, &buffer_size_callback, si)) {
        destroy_jack(si);
        return SoundIoErrorInitAudioBackend;
    }
    if (auto err = jack_set_sample_rate_callback(sij.client, &sample_rate_callback, si)) {
        destroy_jack(si);
        return SoundIoErrorInitAudioBackend;
    }
    if (auto err = jack_set_port_registration_callback(sij.client, &port_registration_callback, si)) {
        destroy_jack(si);
        return SoundIoErrorInitAudioBackend;
    }
    if (auto err = jack_set_port_rename_callback(sij.client, &port_rename_calllback, si)) {
        destroy_jack(si);
        return SoundIoErrorInitAudioBackend;
    }
    jack_on_shutdown(sij.client, &shutdown_callback, si);

    SOUNDIO_ATOMIC_FLAG_CLEAR(sij.refresh_devices_flag);
    sij.period_size = jack_get_buffer_size(sij.client);
    sij.sample_rate = jack_get_sample_rate(sij.client);

    if (auto err = jack_activate(sij.client)) {
        destroy_jack(si);
        return SoundIoErrorInitAudioBackend;
    }

    if (auto err = refresh_devices(si)) {
        destroy_jack(si);
        return err;
    }

    si.destroy = &destroy_jack;
    si.flush_events = &flush_events_jack;
    si.wait_events = &wait_events_jack;
    si.wakeup = &wakeup_jack;
    si.force_device_scan = &force_device_scan_jack;

    si.outstream_open = &outstream_open_jack;
    si.outstream_destroy = &outstream_destroy_jack;
    si.outstream_start = &outstream_start_jack;
    si.outstream_begin_write = &outstream_begin_write_jack;
    si.outstream_end_write = &outstream_end_write_jack;
    si.outstream_clear_buffer = &outstream_clear_buffer_jack;
    si.outstream_pause = &outstream_pause_jack;
    si.outstream_get_latency = &outstream_get_latency_jack;

    si.instream_open = &instream_open_jack;
    si.instream_destroy = &instream_destroy_jack;
    si.instream_start = &instream_start_jack;
    si.instream_begin_read = &instream_begin_read_jack;
    si.instream_end_read = &instream_end_read_jack;
    si.instream_pause = &instream_pause_jack;
    si.instream_get_latency = &instream_get_latency_jack;

    return 0;
}
