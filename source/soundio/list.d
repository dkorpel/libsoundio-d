module soundio.list;

extern(C): @nogc: nothrow: __gshared:

import soundio.util;
import soundio.soundio_internal;
import core.stdc.stdlib;

struct SOUNDIO_LIST(Type) {
    Type *items;
    int length;
    int capacity;

    void deinit() {
        free(this.items);
    }

    int ensure_capacity(int new_capacity) {
        int better_capacity = soundio_int_max(this.capacity, 16);
        while (better_capacity < new_capacity)
            better_capacity = better_capacity * 2;
        if (better_capacity != this.capacity) {
            Type *new_items = REALLOCATE_NONZERO!Type(this.items, better_capacity);
            if (!new_items)
                return SoundIoError.NoMem;
            this.items = new_items;
            this.capacity = better_capacity;
        }
        return 0;
    }

    int append(Type item) {
        int err = ensure_capacity(this.length + 1);
        if (err)
            return err;
        this.items[this.length] = item;
        this.length += 1;
        return 0;
    }

    Type val_at(int index) {
        assert(index >= 0);
        assert(index < this.length);
        return this.items[index];
    }

    /* remember that the pointer to this item is invalid after you
     * modify the length of the list
     */
    Type* ptr_at(int index) {
        assert(index >= 0);
        assert(index < this.length);
        return &this.items[index];
    }

    Type pop() {
        assert(this.length >= 1);
        this.length -= 1;
        return this.items[this.length];
    }

    int resize(int new_length) {
        assert(new_length >= 0);
        int err = ensure_capacity(new_length);
        if (err)
            return err;
        this.length = new_length;
        return 0;
    }

    int add_one() {
        return resize(this.length + 1);
    }

    Type last_val() {
        assert(this.length >= 1);
        return this.items[this.length - 1];
    }

    Type* last_ptr() {
        assert(this.length >= 1);
        return &this.items[this.length - 1];
    }

    void clear() {
        this.length = 0;
    }

    Type swap_remove(int index) {
        assert(index >= 0);
        assert(index < this.length);
        Type last = pop();
        if (index == this.length)
            return last;
        Type item = this.items[index];
        this.items[index] = last;
        return item;
    }
}
