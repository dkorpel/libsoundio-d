/// Translated from C to D
module soundio.ring_buffer;

extern(C): @nogc: nothrow: __gshared:
import core.stdc.config: c_long, c_ulong;

import soundio.soundio_private;
import soundio.util;
import soundio.os;
import soundio.atomics;

import core.stdc.stdlib;
import core.atomic;

package struct SoundIoRingBuffer {
    SoundIoOsMirroredMemory mem;
    shared(size_t) write_offset; // was: SoundIoAtomicULong, but no 64-bit atomics supported on 32-bit windows
    shared(size_t) read_offset; // ditto
    int capacity;
}

SoundIoRingBuffer* soundio_ring_buffer_create(SoundIo* soundio, int requested_capacity) {
    SoundIoRingBuffer* rb = ALLOCATE!SoundIoRingBuffer(1);

    assert(requested_capacity > 0);

    if (!rb) {
        soundio_ring_buffer_destroy(rb);
        return null;
    }

    if (soundio_ring_buffer_init(rb, requested_capacity)) {
        soundio_ring_buffer_destroy(rb);
        return null;
    }

    return rb;
}

void soundio_ring_buffer_destroy(SoundIoRingBuffer* rb) {
    if (!rb)
        return;

    soundio_ring_buffer_deinit(rb);

    free(rb);
}

int soundio_ring_buffer_capacity(SoundIoRingBuffer* rb) {
    return rb.capacity;
}

char* soundio_ring_buffer_write_ptr(SoundIoRingBuffer* rb) {
    const write_offset = SOUNDIO_ATOMIC_LOAD(rb.write_offset);
    return rb.mem.address + (write_offset % rb.capacity);
}

void soundio_ring_buffer_advance_write_ptr(SoundIoRingBuffer* rb, int count) {
    SOUNDIO_ATOMIC_FETCH_ADD(rb.write_offset, count);
    assert(soundio_ring_buffer_fill_count(rb) >= 0);
}

char* soundio_ring_buffer_read_ptr(SoundIoRingBuffer* rb) {
    const read_offset = SOUNDIO_ATOMIC_LOAD(rb.read_offset);
    return rb.mem.address + (read_offset % rb.capacity);
}

void soundio_ring_buffer_advance_read_ptr(SoundIoRingBuffer* rb, int count) {
    SOUNDIO_ATOMIC_FETCH_ADD(rb.read_offset, count);
    assert(soundio_ring_buffer_fill_count(rb) >= 0);
}

int soundio_ring_buffer_fill_count(SoundIoRingBuffer* rb) {
    // Whichever offset we load first might have a smaller value. So we load
    // the read_offset first.
    auto read_offset = SOUNDIO_ATOMIC_LOAD(rb.read_offset);
    auto write_offset = SOUNDIO_ATOMIC_LOAD(rb.write_offset);
    int count = cast(int) (write_offset - read_offset);
    assert(count >= 0);
    assert(count <= rb.capacity);
    return count;
}

int soundio_ring_buffer_free_count(SoundIoRingBuffer* rb) {
    return rb.capacity - soundio_ring_buffer_fill_count(rb);
}

void soundio_ring_buffer_clear(SoundIoRingBuffer* rb) {
    auto read_offset = SOUNDIO_ATOMIC_LOAD(rb.read_offset);
    SOUNDIO_ATOMIC_STORE(rb.write_offset, read_offset);
}

int soundio_ring_buffer_init(SoundIoRingBuffer* rb, int requested_capacity) {
    if (auto err = soundio_os_init_mirrored_memory(&rb.mem, requested_capacity))
        return err;
    SOUNDIO_ATOMIC_STORE(rb.write_offset, 0);
    SOUNDIO_ATOMIC_STORE(rb.read_offset, 0);
    rb.capacity = cast(int) rb.mem.capacity;

    return 0;
}

void soundio_ring_buffer_deinit(SoundIoRingBuffer* rb) {
    soundio_os_deinit_mirrored_memory(&rb.mem);
}