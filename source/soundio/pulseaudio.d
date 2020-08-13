/// Translated from C to D
module soundio.pulseaudio;

extern(C): @nogc: nothrow: __gshared:

import soundio.soundio_internal;
import soundio.atomics;
import soundio.util;
import soundio.soundio_private;
import soundio.headers.pulseheader;
import core.stdc.string;
import core.stdc.stdio;
import core.stdc.stdlib: free;

private:

package struct SoundIoDevicePulseAudio { int make_the_struct_not_empty; }

package struct SoundIoPulseAudio {
    int device_query_err;
    int connection_err;
    bool emitted_shutdown_cb;

    pa_context* pulse_context;
    bool device_scan_queued;

    // the one that we're working on building
    SoundIoDevicesInfo* current_devices_info;
    char* default_sink_name;
    char* default_source_name;

    // this one is ready to be read with flush_events. protected by mutex
    SoundIoDevicesInfo* ready_devices_info;

    bool ready_flag;

    pa_threaded_mainloop* main_loop;
    pa_proplist* props;
}

package struct SoundIoOutStreamPulseAudio {
    pa_stream* stream;
    SoundIoAtomicBool stream_ready;
    pa_buffer_attr buffer_attr;
    char* write_ptr;
    size_t write_byte_count;
    SoundIoAtomicFlag clear_buffer_flag;
    SoundIoChannelArea[SOUNDIO_MAX_CHANNELS] areas;
}

package struct SoundIoInStreamPulseAudio {
    pa_stream* stream;
    SoundIoAtomicBool stream_ready;
    pa_buffer_attr buffer_attr;
    char* peek_buf;
    size_t peek_buf_index;
    size_t peek_buf_size;
    int peek_buf_frames_left;
    int read_frame_count;
    SoundIoChannelArea[SOUNDIO_MAX_CHANNELS] areas;
}

static void subscribe_callback(pa_context* context, pa_subscription_event_type_t event_bits, uint index, void* userdata) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)userdata;
    SoundIo* soundio = &si.pub;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    sipa.device_scan_queued = true;
    pa_threaded_mainloop_signal(sipa.main_loop, 0);
    soundio.on_events_signal(soundio);
}

static int subscribe_to_events(SoundIoPrivate* si) {
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    pa_subscription_mask_t events = cast(pa_subscription_mask_t)(
            PA_SUBSCRIPTION_MASK_SINK|PA_SUBSCRIPTION_MASK_SOURCE|PA_SUBSCRIPTION_MASK_SERVER
    );
    pa_operation* subscribe_op = pa_context_subscribe(sipa.pulse_context, events, null, si);
    if (!subscribe_op)
        return SoundIoError.NoMem;
    pa_operation_unref(subscribe_op);
    return 0;
}

static void context_state_callback(pa_context* context, void* userdata) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)userdata;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    SoundIo* soundio = &si.pub;

    switch (pa_context_get_state(context)) {
    case PA_CONTEXT_UNCONNECTED: // The context hasn't been connected yet.
        return;
    case PA_CONTEXT_CONNECTING: // A connection is being established.
        return;
    case PA_CONTEXT_AUTHORIZING: // The client is authorizing itself to the daemon.
        return;
    case PA_CONTEXT_SETTING_NAME: // The client is passing its application name to the daemon.
        return;
    case PA_CONTEXT_READY: // The connection is established, the context is ready to execute operations.
        sipa.ready_flag = true;
        pa_threaded_mainloop_signal(sipa.main_loop, 0);
        return;
    case PA_CONTEXT_TERMINATED: // The connection was terminated cleanly.
        pa_threaded_mainloop_signal(sipa.main_loop, 0);
        return;
    case PA_CONTEXT_FAILED: // The connection failed or was disconnected.
        if (sipa.ready_flag) {
            sipa.connection_err = SoundIoError.BackendDisconnected;
        } else {
            sipa.connection_err = SoundIoError.InitAudioBackend;
            sipa.ready_flag = true;
        }
        pa_threaded_mainloop_signal(sipa.main_loop, 0);
        soundio.on_events_signal(soundio);
        return;
    default: break;
    }
}

static void destroy_pa(SoundIoPrivate* si) {
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;

    if (sipa.main_loop)
        pa_threaded_mainloop_stop(sipa.main_loop);

    pa_context_disconnect(sipa.pulse_context);
    pa_context_unref(sipa.pulse_context);

    soundio_destroy_devices_info(sipa.current_devices_info);
    soundio_destroy_devices_info(sipa.ready_devices_info);

    if (sipa.main_loop)
        pa_threaded_mainloop_free(sipa.main_loop);

    if (sipa.props)
        pa_proplist_free(sipa.props);

    free(sipa.default_sink_name);
    free(sipa.default_source_name);
}

static SoundIoFormat from_pulseaudio_format(pa_sample_spec sample_spec) {
    switch (sample_spec.format) {
    case PA_SAMPLE_U8:          return SoundIoFormat.U8;
    case PA_SAMPLE_S16LE:       return SoundIoFormat.S16LE;
    case PA_SAMPLE_S16BE:       return SoundIoFormat.S16BE;
    case PA_SAMPLE_FLOAT32LE:   return SoundIoFormat.Float32LE;
    case PA_SAMPLE_FLOAT32BE:   return SoundIoFormat.Float32BE;
    case PA_SAMPLE_S32LE:       return SoundIoFormat.S32LE;
    case PA_SAMPLE_S32BE:       return SoundIoFormat.S32BE;
    case PA_SAMPLE_S24_32LE:    return SoundIoFormat.S24LE;
    case PA_SAMPLE_S24_32BE:    return SoundIoFormat.S24BE;

    case PA_SAMPLE_MAX:
    case PA_SAMPLE_INVALID:
    case PA_SAMPLE_ALAW:
    case PA_SAMPLE_ULAW:
    case PA_SAMPLE_S24LE:
    case PA_SAMPLE_S24BE:
        return SoundIoFormat.Invalid;
    default: break;
    }
    return SoundIoFormat.Invalid;
}

static SoundIoChannelId from_pulseaudio_channel_pos(pa_channel_position_t pos) {
    switch (pos) {
    case PA_CHANNEL_POSITION_MONO: return SoundIoChannelId.FrontCenter;
    case PA_CHANNEL_POSITION_FRONT_LEFT: return SoundIoChannelId.FrontLeft;
    case PA_CHANNEL_POSITION_FRONT_RIGHT: return SoundIoChannelId.FrontRight;
    case PA_CHANNEL_POSITION_FRONT_CENTER: return SoundIoChannelId.FrontCenter;
    case PA_CHANNEL_POSITION_REAR_CENTER: return SoundIoChannelId.BackCenter;
    case PA_CHANNEL_POSITION_REAR_LEFT: return SoundIoChannelId.BackLeft;
    case PA_CHANNEL_POSITION_REAR_RIGHT: return SoundIoChannelId.BackRight;
    case PA_CHANNEL_POSITION_LFE: return SoundIoChannelId.Lfe;
    case PA_CHANNEL_POSITION_FRONT_LEFT_OF_CENTER: return SoundIoChannelId.FrontLeftCenter;
    case PA_CHANNEL_POSITION_FRONT_RIGHT_OF_CENTER: return SoundIoChannelId.FrontRightCenter;
    case PA_CHANNEL_POSITION_SIDE_LEFT: return SoundIoChannelId.SideLeft;
    case PA_CHANNEL_POSITION_SIDE_RIGHT: return SoundIoChannelId.SideRight;
    case PA_CHANNEL_POSITION_TOP_CENTER: return SoundIoChannelId.TopCenter;
    case PA_CHANNEL_POSITION_TOP_FRONT_LEFT: return SoundIoChannelId.TopFrontLeft;
    case PA_CHANNEL_POSITION_TOP_FRONT_RIGHT: return SoundIoChannelId.TopFrontRight;
    case PA_CHANNEL_POSITION_TOP_FRONT_CENTER: return SoundIoChannelId.TopFrontCenter;
    case PA_CHANNEL_POSITION_TOP_REAR_LEFT: return SoundIoChannelId.TopBackLeft;
    case PA_CHANNEL_POSITION_TOP_REAR_RIGHT: return SoundIoChannelId.TopBackRight;
    case PA_CHANNEL_POSITION_TOP_REAR_CENTER: return SoundIoChannelId.TopBackCenter;

    case PA_CHANNEL_POSITION_AUX0: return SoundIoChannelId.Aux0;
    case PA_CHANNEL_POSITION_AUX1: return SoundIoChannelId.Aux1;
    case PA_CHANNEL_POSITION_AUX2: return SoundIoChannelId.Aux2;
    case PA_CHANNEL_POSITION_AUX3: return SoundIoChannelId.Aux3;
    case PA_CHANNEL_POSITION_AUX4: return SoundIoChannelId.Aux4;
    case PA_CHANNEL_POSITION_AUX5: return SoundIoChannelId.Aux5;
    case PA_CHANNEL_POSITION_AUX6: return SoundIoChannelId.Aux6;
    case PA_CHANNEL_POSITION_AUX7: return SoundIoChannelId.Aux7;
    case PA_CHANNEL_POSITION_AUX8: return SoundIoChannelId.Aux8;
    case PA_CHANNEL_POSITION_AUX9: return SoundIoChannelId.Aux9;
    case PA_CHANNEL_POSITION_AUX10: return SoundIoChannelId.Aux10;
    case PA_CHANNEL_POSITION_AUX11: return SoundIoChannelId.Aux11;
    case PA_CHANNEL_POSITION_AUX12: return SoundIoChannelId.Aux12;
    case PA_CHANNEL_POSITION_AUX13: return SoundIoChannelId.Aux13;
    case PA_CHANNEL_POSITION_AUX14: return SoundIoChannelId.Aux14;
    case PA_CHANNEL_POSITION_AUX15: return SoundIoChannelId.Aux15;

    default: return SoundIoChannelId.Invalid;
    }
}

static void set_from_pulseaudio_channel_map(pa_channel_map channel_map, SoundIoChannelLayout* channel_layout) {
    channel_layout.channel_count = channel_map.channels;
    for (int i = 0; i < channel_map.channels; i += 1) {
        channel_layout.channels[i] = from_pulseaudio_channel_pos(channel_map.map[i]);
    }
    channel_layout.name = null;
    int builtin_layout_count = soundio_channel_layout_builtin_count();
    for (int i = 0; i < builtin_layout_count; i += 1) {
        const(SoundIoChannelLayout)* builtin_layout = soundio_channel_layout_get_builtin(i);
        if (soundio_channel_layout_equal(builtin_layout, channel_layout)) {
            channel_layout.name = builtin_layout.name;
            break;
        }
    }
}

extern(D) int set_all_device_channel_layouts(SoundIoDevice* device) {
    device.layout_count = soundio_channel_layout_builtin_count();
    device.layouts = ALLOCATE!SoundIoChannelLayout(device.layout_count);
    if (!device.layouts)
        return SoundIoError.NoMem;
    for (int i = 0; i < device.layout_count; i += 1)
        device.layouts[i] = *soundio_channel_layout_get_builtin(i);
    return 0;
}

extern(D) int set_all_device_formats(SoundIoDevice* device) {
    device.format_count = 9;
    device.formats = ALLOCATE!SoundIoFormat(device.format_count);
    if (!device.formats)
        return SoundIoError.NoMem;
    device.formats[0] = SoundIoFormat.U8;
    device.formats[1] = SoundIoFormat.S16LE;
    device.formats[2] = SoundIoFormat.S16BE;
    device.formats[3] = SoundIoFormat.Float32LE;
    device.formats[4] = SoundIoFormat.Float32BE;
    device.formats[5] = SoundIoFormat.S32LE;
    device.formats[6] = SoundIoFormat.S32BE;
    device.formats[7] = SoundIoFormat.S24LE;
    device.formats[8] = SoundIoFormat.S24BE;
    return 0;
}

extern(D) int perform_operation(SoundIoPrivate* si, pa_operation* op) {
    if (!op)
        return SoundIoError.NoMem;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    for (;;) {
        switch (pa_operation_get_state(op)) {
        case PA_OPERATION_RUNNING:
            pa_threaded_mainloop_wait(sipa.main_loop);
            continue;
        case PA_OPERATION_DONE:
            pa_operation_unref(op);
            return 0;
        case PA_OPERATION_CANCELLED:
            pa_operation_unref(op);
            return SoundIoError.Interrupted;
        default: break;
        }
    }
}

void sink_info_callback(pa_context* pulse_context, const(pa_sink_info)* info, int eol, void* userdata) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)userdata;
    SoundIo* soundio = &si.pub;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    if (eol) {
        pa_threaded_mainloop_signal(sipa.main_loop, 0);
        return;
    }
    if (sipa.device_query_err)
        return;

    SoundIoDevicePrivate* dev = ALLOCATE!SoundIoDevicePrivate(1);
    if (!dev) {
        sipa.device_query_err = SoundIoError.NoMem;
        return;
    }
    SoundIoDevice* device = &dev.pub;

    device.ref_count = 1;
    device.soundio = soundio;
    device.id = strdup(info.name);
    device.name = strdup(info.description);
    if (!device.id || !device.name) {
        soundio_device_unref(device);
        sipa.device_query_err = SoundIoError.NoMem;
        return;
    }

    device.sample_rate_current = info.sample_spec.rate;
    // PulseAudio performs resampling, so any value is valid. Let's pick
    // some reasonable min and max values.
    device.sample_rate_count = 1;
    device.sample_rates = &dev.prealloc_sample_rate_range;
    device.sample_rates[0].min = soundio_int_min(SOUNDIO_MIN_SAMPLE_RATE, device.sample_rate_current);
    device.sample_rates[0].max = soundio_int_max(SOUNDIO_MAX_SAMPLE_RATE, device.sample_rate_current);

    device.current_format = from_pulseaudio_format(info.sample_spec);
    // PulseAudio performs sample format conversion, so any PulseAudio
    // value is valid.
    if (auto err = set_all_device_formats(device)) {
        soundio_device_unref(device);
        sipa.device_query_err = SoundIoError.NoMem;
        return;
    }

    set_from_pulseaudio_channel_map(info.channel_map, &device.current_layout);
    // PulseAudio does channel layout remapping, so any channel layout is valid.
    if (auto err = set_all_device_channel_layouts(device)) {
        soundio_device_unref(device);
        sipa.device_query_err = SoundIoError.NoMem;
        return;
    }

    device.aim = SoundIoDeviceAim.Output;

    if (sipa.current_devices_info.output_devices.append(device)) {
        soundio_device_unref(device);
        sipa.device_query_err = SoundIoError.NoMem;
        return;
    }
}

void source_info_callback(pa_context* pulse_context, const(pa_source_info)* info, int eol, void* userdata) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)userdata;
    SoundIo* soundio = &si.pub;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;

    if (eol) {
        pa_threaded_mainloop_signal(sipa.main_loop, 0);
        return;
    }
    if (sipa.device_query_err)
        return;

    SoundIoDevicePrivate* dev = ALLOCATE!SoundIoDevicePrivate(1);
    if (!dev) {
        sipa.device_query_err = SoundIoError.NoMem;
        return;
    }
    SoundIoDevice* device = &dev.pub;

    device.ref_count = 1;
    device.soundio = soundio;
    device.id = strdup(info.name);
    device.name = strdup(info.description);
    if (!device.id || !device.name) {
        soundio_device_unref(device);
        sipa.device_query_err = SoundIoError.NoMem;
        return;
    }

    device.sample_rate_current = info.sample_spec.rate;
    // PulseAudio performs resampling, so any value is valid. Let's pick
    // some reasonable min and max values.
    device.sample_rate_count = 1;
    device.sample_rates = &dev.prealloc_sample_rate_range;
    device.sample_rates[0].min = soundio_int_min(SOUNDIO_MIN_SAMPLE_RATE, device.sample_rate_current);
    device.sample_rates[0].max = soundio_int_max(SOUNDIO_MAX_SAMPLE_RATE, device.sample_rate_current);

    device.current_format = from_pulseaudio_format(info.sample_spec);
    // PulseAudio performs sample format conversion, so any PulseAudio
    // value is valid.
    if (auto err = set_all_device_formats(device)) {
        soundio_device_unref(device);
        sipa.device_query_err = SoundIoError.NoMem;
        return;
    }

    set_from_pulseaudio_channel_map(info.channel_map, &device.current_layout);
    // PulseAudio does channel layout remapping, so any channel layout is valid.
    if (auto err = set_all_device_channel_layouts(device)) {
        soundio_device_unref(device);
        sipa.device_query_err = SoundIoError.NoMem;
        return;
    }

    device.aim = SoundIoDeviceAim.Input;

    if (sipa.current_devices_info.input_devices.append(device)) {
        soundio_device_unref(device);
        sipa.device_query_err = SoundIoError.NoMem;
        return;
    }
}

static void server_info_callback(pa_context* pulse_context, const(pa_server_info)* info, void* userdata) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)userdata;
    assert(si);
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;

    assert(!sipa.default_sink_name);
    assert(!sipa.default_source_name);

    sipa.default_sink_name = strdup(info.default_sink_name);
    sipa.default_source_name = strdup(info.default_source_name);

    if (!sipa.default_sink_name || !sipa.default_source_name)
        sipa.device_query_err = SoundIoError.NoMem;

    pa_threaded_mainloop_signal(sipa.main_loop, 0);
}

// always called even when refresh_devices succeeds
extern(D) void cleanup_refresh_devices(SoundIoPrivate* si) {
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;

    soundio_destroy_devices_info(sipa.current_devices_info);
    sipa.current_devices_info = null;

    free(sipa.default_sink_name);
    sipa.default_sink_name = null;

    free(sipa.default_source_name);
    sipa.default_source_name = null;
}

// call this while holding the main loop lock
extern(D) int refresh_devices(SoundIoPrivate* si) {
    SoundIo* soundio = &si.pub;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;

    assert(!sipa.current_devices_info);
    sipa.current_devices_info = ALLOCATE!SoundIoDevicesInfo(1);
    if (!sipa.current_devices_info)
        return SoundIoError.NoMem;

    pa_operation* list_sink_op = pa_context_get_sink_info_list(sipa.pulse_context, &sink_info_callback, si);
    pa_operation* list_source_op = pa_context_get_source_info_list(sipa.pulse_context, &source_info_callback, si);
    pa_operation* server_info_op = pa_context_get_server_info(sipa.pulse_context, &server_info_callback, si);

    if (auto err = perform_operation(si, list_sink_op)) {
        return err;
    }
    if (auto err = perform_operation(si, list_source_op)) {
        return err;
    }
    if (auto err = perform_operation(si, server_info_op)) {
        return err;
    }

    if (sipa.device_query_err) {
        return sipa.device_query_err;
    }

    // based on the default sink name, figure out the default output index
    // if the name doesn't match just pick the first one. if there are no
    // devices then we need to set it to -1.
    sipa.current_devices_info.default_output_index = -1;
    sipa.current_devices_info.default_input_index = -1;

    if (sipa.current_devices_info.input_devices.length > 0) {
        sipa.current_devices_info.default_input_index = 0;
        for (int i = 0; i < sipa.current_devices_info.input_devices.length; i += 1) {
            SoundIoDevice* device = sipa.current_devices_info.input_devices.val_at(i);

            assert(device.aim == SoundIoDeviceAim.Input);
            if (strcmp(device.id, sipa.default_source_name) == 0) {
                sipa.current_devices_info.default_input_index = i;
            }
        }
    }

    if (sipa.current_devices_info.output_devices.length > 0) {
        sipa.current_devices_info.default_output_index = 0;
        for (int i = 0; i < sipa.current_devices_info.output_devices.length; i += 1) {
            SoundIoDevice* device = sipa.current_devices_info.output_devices.val_at(i);

            assert(device.aim == SoundIoDeviceAim.Output);
            if (strcmp(device.id, sipa.default_sink_name) == 0) {
                sipa.current_devices_info.default_output_index = i;
            }
        }
    }

    soundio_destroy_devices_info(sipa.ready_devices_info);
    sipa.ready_devices_info = sipa.current_devices_info;
    sipa.current_devices_info = null;
    pa_threaded_mainloop_signal(sipa.main_loop, 0);
    soundio.on_events_signal(soundio);

    return 0;
}

extern(D) void my_flush_events(SoundIoPrivate* si, bool wait) {
    SoundIo* soundio = &si.pub;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;

    bool change = false;
    bool cb_shutdown = false;
    SoundIoDevicesInfo* old_devices_info = null;

    pa_threaded_mainloop_lock(sipa.main_loop);

    if (wait)
        pa_threaded_mainloop_wait(sipa.main_loop);

    if (sipa.device_scan_queued && !sipa.connection_err) {
        sipa.device_scan_queued = false;
        sipa.connection_err = refresh_devices(si);
        cleanup_refresh_devices(si);
    }

    if (sipa.connection_err && !sipa.emitted_shutdown_cb) {
        sipa.emitted_shutdown_cb = true;
        cb_shutdown = true;
    } else if (sipa.ready_devices_info) {
        old_devices_info = si.safe_devices_info;
        si.safe_devices_info = sipa.ready_devices_info;
        sipa.ready_devices_info = null;
        change = true;
    }

    pa_threaded_mainloop_unlock(sipa.main_loop);

    if (cb_shutdown)
        soundio.on_backend_disconnect(soundio, sipa.connection_err);
    else if (change)
        soundio.on_devices_change(soundio);

    soundio_destroy_devices_info(old_devices_info);
}

static void flush_events_pa(SoundIoPrivate* si) {
    my_flush_events(si, false);
}

static void wait_events_pa(SoundIoPrivate* si) {
    my_flush_events(si, false);
    my_flush_events(si, true);
}

static void wakeup_pa(SoundIoPrivate* si) {
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    pa_threaded_mainloop_lock(sipa.main_loop);
    pa_threaded_mainloop_signal(sipa.main_loop, 0);
    pa_threaded_mainloop_unlock(sipa.main_loop);
}

static void force_device_scan_pa(SoundIoPrivate* si) {
    SoundIo* soundio = &si.pub;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    pa_threaded_mainloop_lock(sipa.main_loop);
    sipa.device_scan_queued = true;
    pa_threaded_mainloop_signal(sipa.main_loop, 0);
    soundio.on_events_signal(soundio);
    pa_threaded_mainloop_unlock(sipa.main_loop);
}

static pa_sample_format_t to_pulseaudio_format(SoundIoFormat format) {
    switch (format) {
    case SoundIoFormat.U8:         return PA_SAMPLE_U8;
    case SoundIoFormat.S16LE:      return PA_SAMPLE_S16LE;
    case SoundIoFormat.S16BE:      return PA_SAMPLE_S16BE;
    case SoundIoFormat.S24LE:      return PA_SAMPLE_S24_32LE;
    case SoundIoFormat.S24BE:      return PA_SAMPLE_S24_32BE;
    case SoundIoFormat.S32LE:      return PA_SAMPLE_S32LE;
    case SoundIoFormat.S32BE:      return PA_SAMPLE_S32BE;
    case SoundIoFormat.Float32LE:  return PA_SAMPLE_FLOAT32LE;
    case SoundIoFormat.Float32BE:  return PA_SAMPLE_FLOAT32BE;

    case SoundIoFormat.Invalid:
    case SoundIoFormat.S8:
    case SoundIoFormat.U16LE:
    case SoundIoFormat.U16BE:
    case SoundIoFormat.U24LE:
    case SoundIoFormat.U24BE:
    case SoundIoFormat.U32LE:
    case SoundIoFormat.U32BE:
    case SoundIoFormat.Float64LE:
    case SoundIoFormat.Float64BE:
        return PA_SAMPLE_INVALID;
    default: break;
    }
    return PA_SAMPLE_INVALID;
}

static pa_channel_position_t to_pulseaudio_channel_pos(SoundIoChannelId channel_id) {
    switch (channel_id) {
    case SoundIoChannelId.FrontLeft: return PA_CHANNEL_POSITION_FRONT_LEFT;
    case SoundIoChannelId.FrontRight: return PA_CHANNEL_POSITION_FRONT_RIGHT;
    case SoundIoChannelId.FrontCenter: return PA_CHANNEL_POSITION_FRONT_CENTER;
    case SoundIoChannelId.Lfe: return PA_CHANNEL_POSITION_LFE;
    case SoundIoChannelId.BackLeft: return PA_CHANNEL_POSITION_REAR_LEFT;
    case SoundIoChannelId.BackRight: return PA_CHANNEL_POSITION_REAR_RIGHT;
    case SoundIoChannelId.FrontLeftCenter: return PA_CHANNEL_POSITION_FRONT_LEFT_OF_CENTER;
    case SoundIoChannelId.FrontRightCenter: return PA_CHANNEL_POSITION_FRONT_RIGHT_OF_CENTER;
    case SoundIoChannelId.BackCenter: return PA_CHANNEL_POSITION_REAR_CENTER;
    case SoundIoChannelId.SideLeft: return PA_CHANNEL_POSITION_SIDE_LEFT;
    case SoundIoChannelId.SideRight: return PA_CHANNEL_POSITION_SIDE_RIGHT;
    case SoundIoChannelId.TopCenter: return PA_CHANNEL_POSITION_TOP_CENTER;
    case SoundIoChannelId.TopFrontLeft: return PA_CHANNEL_POSITION_TOP_FRONT_LEFT;
    case SoundIoChannelId.TopFrontCenter: return PA_CHANNEL_POSITION_TOP_FRONT_CENTER;
    case SoundIoChannelId.TopFrontRight: return PA_CHANNEL_POSITION_TOP_FRONT_RIGHT;
    case SoundIoChannelId.TopBackLeft: return PA_CHANNEL_POSITION_TOP_REAR_LEFT;
    case SoundIoChannelId.TopBackCenter: return PA_CHANNEL_POSITION_TOP_REAR_CENTER;
    case SoundIoChannelId.TopBackRight: return PA_CHANNEL_POSITION_TOP_REAR_RIGHT;

    case SoundIoChannelId.Aux0: return PA_CHANNEL_POSITION_AUX0;
    case SoundIoChannelId.Aux1: return PA_CHANNEL_POSITION_AUX1;
    case SoundIoChannelId.Aux2: return PA_CHANNEL_POSITION_AUX2;
    case SoundIoChannelId.Aux3: return PA_CHANNEL_POSITION_AUX3;
    case SoundIoChannelId.Aux4: return PA_CHANNEL_POSITION_AUX4;
    case SoundIoChannelId.Aux5: return PA_CHANNEL_POSITION_AUX5;
    case SoundIoChannelId.Aux6: return PA_CHANNEL_POSITION_AUX6;
    case SoundIoChannelId.Aux7: return PA_CHANNEL_POSITION_AUX7;
    case SoundIoChannelId.Aux8: return PA_CHANNEL_POSITION_AUX8;
    case SoundIoChannelId.Aux9: return PA_CHANNEL_POSITION_AUX9;
    case SoundIoChannelId.Aux10: return PA_CHANNEL_POSITION_AUX10;
    case SoundIoChannelId.Aux11: return PA_CHANNEL_POSITION_AUX11;
    case SoundIoChannelId.Aux12: return PA_CHANNEL_POSITION_AUX12;
    case SoundIoChannelId.Aux13: return PA_CHANNEL_POSITION_AUX13;
    case SoundIoChannelId.Aux14: return PA_CHANNEL_POSITION_AUX14;
    case SoundIoChannelId.Aux15: return PA_CHANNEL_POSITION_AUX15;

    default:
        return PA_CHANNEL_POSITION_INVALID;
    }
}

static pa_channel_map to_pulseaudio_channel_map(const(SoundIoChannelLayout)* channel_layout) {
    pa_channel_map channel_map;
    channel_map.channels = cast(ubyte) channel_layout.channel_count;

    assert(cast()channel_layout.channel_count <= PA_CHANNELS_MAX);

    for (int i = 0; i < channel_layout.channel_count; i += 1)
        channel_map.map[i] = to_pulseaudio_channel_pos(channel_layout.channels[i]);

    return channel_map;
}

static void playback_stream_state_callback(pa_stream* stream, void* userdata) {
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*) userdata;
    SoundIoOutStream* outstream = &os.pub;
    SoundIo* soundio = outstream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    SoundIoOutStreamPulseAudio* ospa = &os.backend_data.pulseaudio;
    switch (pa_stream_get_state(stream)) {
        case PA_STREAM_UNCONNECTED:
        case PA_STREAM_CREATING:
        case PA_STREAM_TERMINATED:
            break;
        case PA_STREAM_READY:
            SOUNDIO_ATOMIC_STORE(ospa.stream_ready, true);
            pa_threaded_mainloop_signal(sipa.main_loop, 0);
            break;
        case PA_STREAM_FAILED:
            outstream.error_callback(outstream, SoundIoError.Streaming);
            break;
        default: break;
    }
}

static void playback_stream_underflow_callback(pa_stream* stream, void* userdata) {
    SoundIoOutStream* outstream = cast(SoundIoOutStream*)userdata;
    outstream.underflow_callback(outstream);
}

static void playback_stream_write_callback(pa_stream* stream, size_t nbytes, void* userdata) {
    SoundIoOutStreamPrivate* os = cast(SoundIoOutStreamPrivate*)(userdata);
    SoundIoOutStream* outstream = &os.pub;
    int frame_count = cast(int) (nbytes / outstream.bytes_per_frame);
    outstream.write_callback(outstream, 0, frame_count);
}

static void outstream_destroy_pa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamPulseAudio* ospa = &os.backend_data.pulseaudio;

    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    pa_stream* stream = ospa.stream;
    if (stream) {
        pa_threaded_mainloop_lock(sipa.main_loop);

        pa_stream_set_write_callback(stream, null, null);
        pa_stream_set_state_callback(stream, null, null);
        pa_stream_set_underflow_callback(stream, null, null);
        pa_stream_set_overflow_callback(stream, null, null);
        pa_stream_disconnect(stream);

        pa_stream_unref(stream);

        pa_threaded_mainloop_unlock(sipa.main_loop);

        ospa.stream = null;
    }
}

static void timing_update_callback(pa_stream* stream, int success, void* userdata) {
    SoundIoPrivate* si = cast(SoundIoPrivate*)userdata;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    pa_threaded_mainloop_signal(sipa.main_loop, 0);
}

static int outstream_open_pa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamPulseAudio* ospa = &os.backend_data.pulseaudio;
    SoundIoOutStream* outstream = &os.pub;

    if (cast()outstream.layout.channel_count > PA_CHANNELS_MAX)
        return SoundIoError.IncompatibleBackend;

    if (!outstream.name)
        outstream.name = "SoundIoOutStream";

    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    SOUNDIO_ATOMIC_STORE(ospa.stream_ready, false);
    SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(ospa.clear_buffer_flag);

    assert(sipa.pulse_context);

    pa_threaded_mainloop_lock(sipa.main_loop);

    pa_sample_spec sample_spec;
    sample_spec.format = to_pulseaudio_format(outstream.format);
    sample_spec.rate = outstream.sample_rate;

    sample_spec.channels = cast(ubyte) outstream.layout.channel_count;
    pa_channel_map channel_map = to_pulseaudio_channel_map(&outstream.layout);

    ospa.stream = pa_stream_new(sipa.pulse_context, outstream.name, &sample_spec, &channel_map);
    if (!ospa.stream) {
        pa_threaded_mainloop_unlock(sipa.main_loop);
        outstream_destroy_pa(si, os);
        return SoundIoError.NoMem;
    }
    pa_stream_set_state_callback(ospa.stream, &playback_stream_state_callback, os);

    ospa.buffer_attr.maxlength = uint.max;
    ospa.buffer_attr.tlength = uint.max;
    ospa.buffer_attr.prebuf = 0;
    ospa.buffer_attr.minreq = uint.max;
    ospa.buffer_attr.fragsize = uint.max;

    int bytes_per_second = outstream.bytes_per_frame * outstream.sample_rate;
    if (outstream.software_latency > 0.0) {
        int buffer_length = outstream.bytes_per_frame *
            ceil_dbl_to_int(outstream.software_latency * bytes_per_second / cast(double)outstream.bytes_per_frame);

        ospa.buffer_attr.maxlength = buffer_length;
        ospa.buffer_attr.tlength = buffer_length;
    }

    pa_stream_flags_t flags = cast(pa_stream_flags_t)(
        PA_STREAM_START_CORKED | PA_STREAM_AUTO_TIMING_UPDATE |
        PA_STREAM_INTERPOLATE_TIMING | PA_STREAM_ADJUST_LATENCY
    );

    if (auto err = pa_stream_connect_playback(ospa.stream,outstream.device.id, &ospa.buffer_attr,flags, null, null)) {
        pa_threaded_mainloop_unlock(sipa.main_loop);
        return SoundIoError.OpeningDevice;
    }

    while (!SOUNDIO_ATOMIC_LOAD(ospa.stream_ready))
        pa_threaded_mainloop_wait(sipa.main_loop);

    pa_operation* update_timing_info_op = pa_stream_update_timing_info(ospa.stream, &timing_update_callback, si);
    if (auto err = perform_operation(si, update_timing_info_op)) {
        pa_threaded_mainloop_unlock(sipa.main_loop);
        return err;
    }

    size_t writable_size = pa_stream_writable_size(ospa.stream);
    outstream.software_latency = (cast(double)writable_size) / cast(double)bytes_per_second;

    pa_threaded_mainloop_unlock(sipa.main_loop);

    return 0;
}

static int outstream_start_pa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStream* outstream = &os.pub;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    SoundIoOutStreamPulseAudio* ospa = &os.backend_data.pulseaudio;

    pa_threaded_mainloop_lock(sipa.main_loop);

    ospa.write_byte_count = pa_stream_writable_size(ospa.stream);
    int frame_count = cast(int) (ospa.write_byte_count / outstream.bytes_per_frame);
    outstream.write_callback(outstream, 0, frame_count);

    pa_operation* op = pa_stream_cork(ospa.stream, false, null, null);
    if (!op) {
        pa_threaded_mainloop_unlock(sipa.main_loop);
        return SoundIoError.Streaming;
    }
    pa_operation_unref(op);
    pa_stream_set_write_callback(ospa.stream, &playback_stream_write_callback, os);
    pa_stream_set_underflow_callback(ospa.stream, &playback_stream_underflow_callback, outstream);
    pa_stream_set_overflow_callback(ospa.stream, &playback_stream_underflow_callback, outstream);

    pa_threaded_mainloop_unlock(sipa.main_loop);

    return 0;
}

static int outstream_begin_write_pa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os, SoundIoChannelArea** out_areas, int* frame_count) {
    SoundIoOutStream* outstream = &os.pub;
    SoundIoOutStreamPulseAudio* ospa = &os.backend_data.pulseaudio;
    pa_stream* stream = ospa.stream;

    ospa.write_byte_count = *frame_count * outstream.bytes_per_frame;
    if (pa_stream_begin_write(stream, cast(void**)&ospa.write_ptr, &ospa.write_byte_count))
        return SoundIoError.Streaming;

    for (int ch = 0; ch < outstream.layout.channel_count; ch += 1) {
        ospa.areas[ch].ptr = ospa.write_ptr + outstream.bytes_per_sample * ch;
        ospa.areas[ch].step = outstream.bytes_per_frame;
    }

    *frame_count = cast(int) (ospa.write_byte_count / outstream.bytes_per_frame);
    *out_areas = ospa.areas.ptr;

    return 0;
}

static int outstream_end_write_pa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamPulseAudio* ospa = &os.backend_data.pulseaudio;
    pa_stream* stream = ospa.stream;

    pa_seek_mode_t seek_mode = SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(ospa.clear_buffer_flag) ? PA_SEEK_RELATIVE : PA_SEEK_RELATIVE_ON_READ;
    if (pa_stream_write(stream, ospa.write_ptr, ospa.write_byte_count, null, 0, seek_mode))
        return SoundIoError.Streaming;

    return 0;
}

static int outstream_clear_buffer_pa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os) {
    SoundIoOutStreamPulseAudio* ospa = &os.backend_data.pulseaudio;
    SOUNDIO_ATOMIC_FLAG_CLEAR(ospa.clear_buffer_flag);
    return 0;
}

static int outstream_pause_pa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os, bool pause) {
    SoundIoOutStreamPulseAudio* ospa = &os.backend_data.pulseaudio;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;

    if (!pa_threaded_mainloop_in_thread(sipa.main_loop)) {
        pa_threaded_mainloop_lock(sipa.main_loop);
    }

    if (pause != pa_stream_is_corked(ospa.stream)) {
        pa_operation* op = pa_stream_cork(ospa.stream, pause, null, null);
        if (!op) {
            pa_threaded_mainloop_unlock(sipa.main_loop);
            return SoundIoError.Streaming;
        }
        pa_operation_unref(op);
    }

    if (!pa_threaded_mainloop_in_thread(sipa.main_loop)) {
        pa_threaded_mainloop_unlock(sipa.main_loop);
    }

    return 0;
}

static int outstream_get_latency_pa(SoundIoPrivate* si, SoundIoOutStreamPrivate* os, double* out_latency) {
    SoundIoOutStreamPulseAudio* ospa = &os.backend_data.pulseaudio;

    pa_usec_t r_usec;
    int negative;
    if (auto err = pa_stream_get_latency(ospa.stream, &r_usec, &negative)) {
        return SoundIoError.Streaming;
    }
    *out_latency = r_usec / 1000000.0;
    return 0;
}

static void recording_stream_state_callback(pa_stream* stream, void* userdata) {
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)userdata;
    SoundIoInStreamPulseAudio* ispa = &is_.backend_data.pulseaudio;
    SoundIoInStream* instream = &is_.pub;
    SoundIo* soundio = instream.device.soundio;
    SoundIoPrivate* si = cast(SoundIoPrivate*)soundio;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    switch (pa_stream_get_state(stream)) {
        case PA_STREAM_UNCONNECTED:
        case PA_STREAM_CREATING:
        case PA_STREAM_TERMINATED:
            break;
        case PA_STREAM_READY:
            SOUNDIO_ATOMIC_STORE(ispa.stream_ready, true);
            pa_threaded_mainloop_signal(sipa.main_loop, 0);
            break;
        case PA_STREAM_FAILED:
            instream.error_callback(instream, SoundIoError.Streaming);
            break;
        default: break;
    }
}

static void recording_stream_read_callback(pa_stream* stream, size_t nbytes, void* userdata) {
    SoundIoInStreamPrivate* is_ = cast(SoundIoInStreamPrivate*)userdata;
    SoundIoInStream* instream = &is_.pub;
    assert(nbytes % instream.bytes_per_frame == 0);
    assert(nbytes > 0);
    int available_frame_count = cast(int) (nbytes / instream.bytes_per_frame);
    instream.read_callback(instream, 0, available_frame_count);
}

static void instream_destroy_pa(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamPulseAudio* ispa = &is_.backend_data.pulseaudio;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    pa_stream* stream = ispa.stream;
    if (stream) {
        pa_threaded_mainloop_lock(sipa.main_loop);

        pa_stream_set_state_callback(stream, null, null);
        pa_stream_set_read_callback(stream, null, null);
        pa_stream_disconnect(stream);
        pa_stream_unref(stream);

        pa_threaded_mainloop_unlock(sipa.main_loop);

        ispa.stream = null;
    }
}

static int instream_open_pa(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStreamPulseAudio* ispa = &is_.backend_data.pulseaudio;
    SoundIoInStream* instream = &is_.pub;

    if (cast()instream.layout.channel_count > PA_CHANNELS_MAX)
        return SoundIoError.IncompatibleBackend;
    if (!instream.name)
        instream.name = "SoundIoInStream";

    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    SOUNDIO_ATOMIC_STORE(ispa.stream_ready, false);

    pa_threaded_mainloop_lock(sipa.main_loop);

    pa_sample_spec sample_spec;
    sample_spec.format = to_pulseaudio_format(instream.format);
    sample_spec.rate = instream.sample_rate;
    sample_spec.channels = cast(ubyte) instream.layout.channel_count;

    pa_channel_map channel_map = to_pulseaudio_channel_map(&instream.layout);

    ispa.stream = pa_stream_new(sipa.pulse_context, instream.name, &sample_spec, &channel_map);
    if (!ispa.stream) {
        pa_threaded_mainloop_unlock(sipa.main_loop);
        instream_destroy_pa(si, is_);
        return SoundIoError.NoMem;
    }

    pa_stream* stream = ispa.stream;

    pa_stream_set_state_callback(stream, &recording_stream_state_callback, is_);
    pa_stream_set_read_callback(stream, &recording_stream_read_callback, is_);

    ispa.buffer_attr.maxlength = uint.max;
    ispa.buffer_attr.tlength = uint.max;
    ispa.buffer_attr.prebuf = 0;
    ispa.buffer_attr.minreq = uint.max;
    ispa.buffer_attr.fragsize = uint.max;

    if (instream.software_latency > 0.0) {
        int bytes_per_second = instream.bytes_per_frame * instream.sample_rate;
        int buffer_length = instream.bytes_per_frame *
            ceil_dbl_to_int(instream.software_latency * bytes_per_second / cast(double)instream.bytes_per_frame);
        ispa.buffer_attr.fragsize = buffer_length;
    }

    pa_threaded_mainloop_unlock(sipa.main_loop);

    return 0;
}

static int instream_start_pa(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStream* instream = &is_.pub;
    SoundIoInStreamPulseAudio* ispa = &is_.backend_data.pulseaudio;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;
    pa_threaded_mainloop_lock(sipa.main_loop);

    pa_stream_flags_t flags = cast(pa_stream_flags_t)(
        PA_STREAM_AUTO_TIMING_UPDATE | PA_STREAM_INTERPOLATE_TIMING | PA_STREAM_ADJUST_LATENCY
    );

    if (auto err = pa_stream_connect_record(ispa.stream, instream.device.id, &ispa.buffer_attr, flags)) {
        pa_threaded_mainloop_unlock(sipa.main_loop);
        return SoundIoError.OpeningDevice;
    }

    while (!SOUNDIO_ATOMIC_LOAD(ispa.stream_ready))
        pa_threaded_mainloop_wait(sipa.main_loop);

    pa_operation* update_timing_info_op = pa_stream_update_timing_info(ispa.stream, &timing_update_callback, si);
    if (auto err = perform_operation(si, update_timing_info_op)) {
        pa_threaded_mainloop_unlock(sipa.main_loop);
        return err;
    }


    pa_threaded_mainloop_unlock(sipa.main_loop);
    return 0;
}

static int instream_begin_read_pa(SoundIoPrivate* si, SoundIoInStreamPrivate* is_, SoundIoChannelArea** out_areas, int* frame_count) {
    SoundIoInStream* instream = &is_.pub;
    SoundIoInStreamPulseAudio* ispa = &is_.backend_data.pulseaudio;
    pa_stream* stream = ispa.stream;

    assert(SOUNDIO_ATOMIC_LOAD(ispa.stream_ready));

    if (!ispa.peek_buf) {
        if (pa_stream_peek(stream, cast(const(void)**)&ispa.peek_buf, &ispa.peek_buf_size))
            return SoundIoError.Streaming;

        ispa.peek_buf_frames_left = cast(int) (ispa.peek_buf_size / instream.bytes_per_frame);
        ispa.peek_buf_index = 0;

        // hole
        if (!ispa.peek_buf) {
            *frame_count = ispa.peek_buf_frames_left;
            *out_areas = null;
            return 0;
        }
    }

    ispa.read_frame_count = soundio_int_min(*frame_count, ispa.peek_buf_frames_left);
    *frame_count = ispa.read_frame_count;
    for (int ch = 0; ch < instream.layout.channel_count; ch += 1) {
        ispa.areas[ch].ptr = ispa.peek_buf + ispa.peek_buf_index + instream.bytes_per_sample * ch;
        ispa.areas[ch].step = instream.bytes_per_frame;
    }

    *out_areas = ispa.areas.ptr;

    return 0;
}

static int instream_end_read_pa(SoundIoPrivate* si, SoundIoInStreamPrivate* is_) {
    SoundIoInStream* instream = &is_.pub;
    SoundIoInStreamPulseAudio* ispa = &is_.backend_data.pulseaudio;
    pa_stream* stream = ispa.stream;

    // hole
    if (!ispa.peek_buf) {
        if (pa_stream_drop(stream))
            return SoundIoError.Streaming;
        return 0;
    }

    size_t advance_bytes = ispa.read_frame_count * instream.bytes_per_frame;
    ispa.peek_buf_index += advance_bytes;
    ispa.peek_buf_frames_left -= ispa.read_frame_count;

    if (ispa.peek_buf_index >= ispa.peek_buf_size) {
        if (pa_stream_drop(stream))
            return SoundIoError.Streaming;
        ispa.peek_buf = null;
    }

    return 0;
}

static int instream_pause_pa(SoundIoPrivate* si, SoundIoInStreamPrivate* is_, bool pause) {
    SoundIoInStreamPulseAudio* ispa = &is_.backend_data.pulseaudio;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;

    if (!pa_threaded_mainloop_in_thread(sipa.main_loop)) {
        pa_threaded_mainloop_lock(sipa.main_loop);
    }

    if (pause != pa_stream_is_corked(ispa.stream)) {
        pa_operation* op = pa_stream_cork(ispa.stream, pause, null, null);
        if (!op)
            return SoundIoError.Streaming;
        pa_operation_unref(op);
    }

    if (!pa_threaded_mainloop_in_thread(sipa.main_loop)) {
        pa_threaded_mainloop_unlock(sipa.main_loop);
    }

    return 0;
}

static int instream_get_latency_pa(SoundIoPrivate* si, SoundIoInStreamPrivate* is_, double* out_latency) {
    SoundIoInStreamPulseAudio* ispa = &is_.backend_data.pulseaudio;

    pa_usec_t r_usec;
    int negative;
    if (auto err = pa_stream_get_latency(ispa.stream, &r_usec, &negative)) {
        return SoundIoError.Streaming;
    }
    *out_latency = r_usec / 1000000.0;
    return 0;
}

package int soundio_pulseaudio_init(SoundIoPrivate* si) {
    SoundIo* soundio = &si.pub;
    SoundIoPulseAudio* sipa = &si.backend_data.pulseaudio;

    sipa.device_scan_queued = true;

    sipa.main_loop = pa_threaded_mainloop_new();
    if (!sipa.main_loop) {
        destroy_pa(si);
        return SoundIoError.NoMem;
    }

    pa_mainloop_api* main_loop_api = pa_threaded_mainloop_get_api(sipa.main_loop);

    sipa.props = pa_proplist_new();
    if (!sipa.props) {
        destroy_pa(si);
        return SoundIoError.NoMem;
    }

    sipa.pulse_context = pa_context_new_with_proplist(main_loop_api, soundio.app_name, sipa.props);
    if (!sipa.pulse_context) {
        destroy_pa(si);
        return SoundIoError.NoMem;
    }

    pa_context_set_subscribe_callback(sipa.pulse_context, &subscribe_callback, si);
    pa_context_set_state_callback(sipa.pulse_context, &context_state_callback, si);

    if (auto err = pa_context_connect(sipa.pulse_context, null, cast(pa_context_flags_t)0, null)) {
        destroy_pa(si);
        return SoundIoError.InitAudioBackend;
    }

    if (pa_threaded_mainloop_start(sipa.main_loop)) {
        destroy_pa(si);
        return SoundIoError.NoMem;
    }

    pa_threaded_mainloop_lock(sipa.main_loop);

    // block until ready
    while (!sipa.ready_flag)
        pa_threaded_mainloop_wait(sipa.main_loop);

    if (sipa.connection_err) {
        pa_threaded_mainloop_unlock(sipa.main_loop);
        destroy_pa(si);
        return sipa.connection_err;
    }

    if (auto err = subscribe_to_events(si)) {
        pa_threaded_mainloop_unlock(sipa.main_loop);
        destroy_pa(si);
        return err;
    }

    pa_threaded_mainloop_unlock(sipa.main_loop);

    si.destroy = &destroy_pa;
    si.flush_events = &flush_events_pa;
    si.wait_events = &wait_events_pa;
    si.wakeup = &wakeup_pa;
    si.force_device_scan = &force_device_scan_pa;

    si.outstream_open = &outstream_open_pa;
    si.outstream_destroy = &outstream_destroy_pa;
    si.outstream_start = &outstream_start_pa;
    si.outstream_begin_write = &outstream_begin_write_pa;
    si.outstream_end_write = &outstream_end_write_pa;
    si.outstream_clear_buffer = &outstream_clear_buffer_pa;
    si.outstream_pause = &outstream_pause_pa;
    si.outstream_get_latency = &outstream_get_latency_pa;

    si.instream_open = &instream_open_pa;
    si.instream_destroy = &instream_destroy_pa;
    si.instream_start = &instream_start_pa;
    si.instream_begin_read = &instream_begin_read_pa;
    si.instream_end_read = &instream_end_read_pa;
    si.instream_pause = &instream_pause_pa;
    si.instream_get_latency = &instream_get_latency_pa;

    return 0;
}