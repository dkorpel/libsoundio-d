/// Translated from C to D
module soundio.util;

extern(C): nothrow: __gshared: // TODO: @nogc:

import core.stdc.stdarg;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.assert_;

@nogc void soundio_panic(const(char)* format, ...);
@nogc char* soundio_alloc_sprintf(int* len, const(char)* format, ...);

/// printf but to stderr instead of stdout
// Workaround for the fact that stderr is uninitialized (null) on MSVC Windows with betterC
// https://issues.dlang.org/show_bug.cgi?id=20532
@nogc void printf_stderr(const(char)* format, ...);

pragma(mangle, printf_stderr.mangleof)
void printf_stderr_fakenogc(const(char)* format, ...) {
    va_list ap;
    va_start(ap, format);
    if (stderr == null) {
        vprintf(format, ap);
    } else {
        vfprintf(stderr, format, ap);
    }
    va_end(ap);
}

// workaround for va_start not being @nogc
pragma(mangle, soundio_panic.mangleof)
void soundio_panic_fakenogc(const(char)* format, ...) {
    va_list ap;
    va_start(ap, format);
    if (stderr == null) {
        vprintf(format, ap);
        printf("\n");
    } else {
        vfprintf(stderr, format, ap);
        fprintf(stderr, "\n");
    }
    va_end(ap);
    abort();
}

pragma(mangle, soundio_alloc_sprintf.mangleof)
char* soundio_alloc_sprintf_fakenogc(int* len, const(char)* format, ...) {
    va_list ap;va_list ap2;
    va_start(ap, format);
    va_copy(ap2, ap);

    int len1 = vsnprintf(null, 0, format, ap);
    assert(len1 >= 0);

    size_t required_size = len1 + 1;
    char* mem = ALLOCATE!(char)(required_size);
    if (!mem)
        return null;

    int len2 = vsnprintf(mem, required_size, format, ap2);
    assert(len2 == len1);

    va_end(ap2);
    va_end(ap);

    if (len)
        *len = len1;
    return mem;
}

@nogc:

auto ALLOCATE_NONZERO(Type)(size_t count) {
    return cast(Type*) malloc((count) * Type.sizeof);
}

auto ALLOCATE(Type)(size_t count) {
    return cast(Type*) calloc(count, Type.sizeof);
}

auto REALLOCATE_NONZERO(Type)(void* old, size_t new_count) {
    return cast(Type*) realloc(old, new_count * Type.sizeof);
}

alias SOUNDIO_ATTR_NORETURN = typeof(assert(0));

//enum string ARRAY_LENGTH(string array) = ` (sizeof(array)/sizeof((array)[0]))`;

pragma(inline, true) static int soundio_int_min(int a, int b) {
    return (a <= b) ? a : b;
}

pragma(inline, true) static int soundio_int_max(int a, int b) {
    return (a >= b) ? a : b;
}

pragma(inline, true) static int soundio_int_clamp(int min_value, int value, int max_value) {
    return soundio_int_max(soundio_int_min(value, max_value), min_value);
}

pragma(inline, true) static double soundio_double_min(double a, double b) {
    return (a <= b) ? a : b;
}

pragma(inline, true) static double soundio_double_max(double a, double b) {
    return (a >= b) ? a : b;
}

pragma(inline, true) static double soundio_double_clamp(double min_value, double value, double max_value) {
    return soundio_double_max(soundio_double_min(value, max_value), min_value);
}

pragma(inline, true) static char* soundio_str_dupe(const(char)* str, int str_len) {
    char* out_ = ALLOCATE_NONZERO!char(str_len + 1);
    if (!out_)
        return null;
    memcpy(out_, str, str_len);
    out_[str_len] = 0;
    return out_;
}

pragma(inline, true) static bool soundio_streql(const(char)* str1, int str1_len, const(char)* str2, int str2_len) {
    if (str1_len != str2_len)
        return false;
    return memcmp(str1, str2, str1_len) == 0;
}

pragma(inline, true) static int ceil_dbl_to_int(double x) {
    const(double) truncation = cast(int)x;
    return cast(int) (truncation + (truncation < x));
}

pragma(inline, true) static double ceil_dbl(double x) {
    const(double) truncation = cast(long) x;
    const(double) ceiling = truncation + (truncation < x);
    return ceiling;
}
