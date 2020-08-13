/// Translated from C to D
module soundio.os;

extern(C): @nogc: nothrow: __gshared:

public import soundio.soundio_internal;
public import soundio.util;

import core.stdc.stdlib: free;
import core.stdc.string;
import core.stdc.errno;

// You may rely on the size of this struct as part of the API and ABI.
struct SoundIoOsMirroredMemory {
    size_t capacity;
    char* address;
    void* priv;
}

//version (SOUNDIO_OS_WINDOWS) {
version (Windows) {
    public import core.sys.windows.windows;
    public import core.sys.windows.mmsystem;
    public import core.sys.windows.objbase;
    //import core.sys.windows.
    version = SOUNDIO_OS_WINDOWS;
    //public import mmsystem;
    //public import objbase;

    alias INIT_ONCE = void*;
    alias CONDITION_VARIABLE = void*;
    enum INIT_ONCE_STATIC_INIT = null;

    enum COINITBASE_MULTITHREADED = 0;
    alias COINIT = int; // C enum
    enum {
        COINIT_APARTMENTTHREADED  = 0x2,
        COINIT_MULTITHREADED      = COINITBASE_MULTITHREADED,
        COINIT_DISABLE_OLE1DDE    = 0x4,
        COINIT_SPEED_OVER_MEMORY  = 0x8,
    }

    extern(Windows) {
        BOOL SleepConditionVariableCS(CONDITION_VARIABLE* ConditionVariable, PCRITICAL_SECTION CriticalSection, DWORD dwMilliseconds);
        HRESULT CoInitializeEx(LPVOID, DWORD);
        void CoUninitialize();
        void InitializeConditionVariable(CONDITION_VARIABLE* ConditionVariable);
        void WakeConditionVariable(CONDITION_VARIABLE* ConditionVariable);
        BOOL InitOnceBeginInitialize(INIT_ONCE* lpInitOnce, DWORD dwFlags, BOOL* fPending, VOID** lpContext);
        BOOL InitOnceComplete(INIT_ONCE* lpInitOnce, DWORD dwFlags, VOID* lpContext);
        enum INIT_ONCE_ASYNC = 0x00000002UL;
    }

} else {
    public import core.sys.posix.pthread;
    public import core.sys.posix.unistd;
    public import core.sys.posix.sys.mman;
    enum MAP_ANONYMOUS = MAP_ANON;

    // commented out of core.sys.posix.stdlib
    extern(C) @nogc nothrow int mkstemp(char*);
}

version(FreeBSD) {
    version = SOUNDIO_OS_KQUEUE;
}
version(OSX) {
    version = SOUNDIO_OS_KQUEUE;
}

version(SOUNDIO_OS_KQUEUE) {
    public import core.sys.posix.sys.types;
    //public import core.sys.event;
    public import core.sys.posix.sys.time;
}

version (OSX) {
    public import mach.clock;
    public import mach.mach;
}

struct SoundIoOsThread {
    version (SOUNDIO_OS_WINDOWS) {
        HANDLE handle;
        DWORD id;
    } else {
        pthread_attr_t attr;
        bool attr_init;

        pthread_t id;
        bool running;
    }
    void* arg;
    extern(C) @nogc nothrow void function(void* arg) run;
}

struct SoundIoOsMutex {
    version (SOUNDIO_OS_WINDOWS) {
        CRITICAL_SECTION id;
    } else {
        pthread_mutex_t id;
        bool id_init;
    }
}

version (SOUNDIO_OS_KQUEUE) {
    static const(uintptr_t) notify_ident = 1;
    struct SoundIoOsCond {
        int kq_id;
    }
} else version (SOUNDIO_OS_WINDOWS) {
    struct SoundIoOsCond {
        CONDITION_VARIABLE id;
        CRITICAL_SECTION default_cs_id;
    }
} else {
    struct SoundIoOsCond {
        pthread_cond_t id;
        bool id_init;

        pthread_condattr_t attr;
        bool attr_init;

        pthread_mutex_t default_mutex_id;
        bool default_mutex_init;
    }
}

version (SOUNDIO_OS_WINDOWS) {
    static INIT_ONCE win32_init_once = INIT_ONCE_STATIC_INIT;
    static double win32_time_resolution;
    static SYSTEM_INFO win32_system_info;
} else {
    static bool initialized = false;
    static pthread_mutex_t init_mutex = PTHREAD_MUTEX_INITIALIZER;
    version (OSX) {
        static clock_serv_t cclock;
    }
}

static int page_size;

double soundio_os_get_time() {
    version (SOUNDIO_OS_WINDOWS) {
        ulong time;
        QueryPerformanceCounter(cast(LARGE_INTEGER*) &time);
        return time * win32_time_resolution;
    } else version (OSX) {
        mach_timespec_t mts;

        kern_return_t err = clock_get_time(cclock, &mts);
        assert(!err);

        double seconds = cast(double)mts.tv_sec;
        seconds += (cast(double)mts.tv_nsec) / 1000000000.0;

        return seconds;
    } else {
        timespec tms;
        clock_gettime(CLOCK_MONOTONIC, &tms);
        double seconds = cast(double)tms.tv_sec;
        seconds += (cast(double)tms.tv_nsec) / 1000000000.0;
        return seconds;
    }
}

version (SOUNDIO_OS_WINDOWS) {
    extern(Windows) static DWORD run_win32_thread(LPVOID userdata) {
        SoundIoOsThread* thread = cast(SoundIoOsThread*)userdata;
        HRESULT err = CoInitializeEx(null, COINIT_APARTMENTTHREADED);
        assert(err == S_OK);
        thread.run(thread.arg);
        CoUninitialize();
        return 0;
    }
} else {
    static void assert_no_err(int err) {
        assert(!err);
    }

    static void* run_pthread(void* userdata) {
        SoundIoOsThread* thread = cast(SoundIoOsThread*)userdata;
        thread.run(thread.arg);
        return null;
    }
}

private alias threadFunc = void function(void* arg);
private alias warningFunc = void function();
int soundio_os_thread_create(threadFunc run, void* arg, warningFunc emit_rtprio_warning, SoundIoOsThread** out_thread) {
    *out_thread = null;

    SoundIoOsThread* thread = ALLOCATE!SoundIoOsThread(1);
    if (!thread) {
        soundio_os_thread_destroy(thread);
        return SoundIoError.NoMem;
    }

    thread.run = run;
    thread.arg = arg;

version (SOUNDIO_OS_WINDOWS) {
    thread.handle = CreateThread(null, 0, &run_win32_thread, thread, 0, &thread.id);
    if (!thread.handle) {
        soundio_os_thread_destroy(thread);
        return SoundIoError.SystemResources;
    }
    if (emit_rtprio_warning) {
        if (!SetThreadPriority(thread.handle, THREAD_PRIORITY_TIME_CRITICAL)) {
            emit_rtprio_warning();
        }
    }
} else {
    if (auto err = pthread_attr_init(&thread.attr)) {
        soundio_os_thread_destroy(thread);
        return SoundIoError.NoMem;
    }
    thread.attr_init = true;

    if (emit_rtprio_warning) {
        int max_priority = sched_get_priority_max(SCHED_FIFO);
        if (max_priority == -1) {
            soundio_os_thread_destroy(thread);
            return SoundIoError.SystemResources;
        }

        if (auto err = pthread_attr_setschedpolicy(&thread.attr, SCHED_FIFO)) {
            soundio_os_thread_destroy(thread);
            return SoundIoError.SystemResources;
        }

        sched_param param;
        param.sched_priority = max_priority;
        if (auto err = pthread_attr_setschedparam(&thread.attr, &param)) {
            soundio_os_thread_destroy(thread);
            return SoundIoError.SystemResources;
        }

    }

    if (auto err = pthread_create(&thread.id, &thread.attr, &run_pthread, thread)) {
        if (err == EPERM && emit_rtprio_warning) {
            emit_rtprio_warning();
            err = pthread_create(&thread.id, null, &run_pthread, thread);
        }
        if (err) {
            soundio_os_thread_destroy(thread);
            return SoundIoError.NoMem;
        }
    }
    thread.running = true;
}

    *out_thread = thread;
    return 0;
}

void soundio_os_thread_destroy(SoundIoOsThread* thread) {
    if (!thread)
        return;

version (SOUNDIO_OS_WINDOWS) {
    if (thread.handle) {
        DWORD err = WaitForSingleObject(thread.handle, INFINITE);
        assert(err != WAIT_FAILED);
        BOOL ok = CloseHandle(thread.handle);
        assert(ok);
    }
} else {

    if (thread.running) {
        assert_no_err(pthread_join(thread.id, null));
    }

    if (thread.attr_init) {
        assert_no_err(pthread_attr_destroy(&thread.attr));
    }
}

    free(thread);
}

SoundIoOsMutex* soundio_os_mutex_create() {
    SoundIoOsMutex* mutex = ALLOCATE!SoundIoOsMutex( 1);
    if (!mutex) {
        soundio_os_mutex_destroy(mutex);
        return null;
    }

version (SOUNDIO_OS_WINDOWS) {
    InitializeCriticalSection(&mutex.id);
} else {
    if (auto err = pthread_mutex_init(&mutex.id, null)) {
        soundio_os_mutex_destroy(mutex);
        return null;
    }
    mutex.id_init = true;
}

    return mutex;
}

void soundio_os_mutex_destroy(SoundIoOsMutex* mutex) {
    if (!mutex)
        return;

version (SOUNDIO_OS_WINDOWS) {
    DeleteCriticalSection(&mutex.id);
} else {
    if (mutex.id_init) {
        assert_no_err(pthread_mutex_destroy(&mutex.id));
    }
}

    free(mutex);
}

void soundio_os_mutex_lock(SoundIoOsMutex* mutex) {
version (SOUNDIO_OS_WINDOWS) {
    EnterCriticalSection(&mutex.id);
} else {
    assert_no_err(pthread_mutex_lock(&mutex.id));
}
}

void soundio_os_mutex_unlock(SoundIoOsMutex* mutex) {
version (SOUNDIO_OS_WINDOWS) {
    LeaveCriticalSection(&mutex.id);
} else {
    assert_no_err(pthread_mutex_unlock(&mutex.id));
}
}

SoundIoOsCond* soundio_os_cond_create() {
    SoundIoOsCond* cond = ALLOCATE!SoundIoOsCond(1);

    if (!cond) {
        soundio_os_cond_destroy(cond);
        return null;
    }

version (SOUNDIO_OS_WINDOWS) {
    InitializeConditionVariable(&cond.id);
    InitializeCriticalSection(&cond.default_cs_id);
} else version (SOUNDIO_OS_KQUEUE) {
    cond.kq_id = kqueue();
    if (cond.kq_id == -1)
        return null;
} else {
    if (pthread_condattr_init(&cond.attr)) {
        soundio_os_cond_destroy(cond);
        return null;
    }
    cond.attr_init = true;

    if (pthread_condattr_setclock(&cond.attr, CLOCK_MONOTONIC)) {
        soundio_os_cond_destroy(cond);
        return null;
    }

    if (pthread_cond_init(&cond.id, &cond.attr)) {
        soundio_os_cond_destroy(cond);
        return null;
    }
    cond.id_init = true;

    if ((pthread_mutex_init(&cond.default_mutex_id, null))) {
        soundio_os_cond_destroy(cond);
        return null;
    }
    cond.default_mutex_init = true;
}

    return cond;
}

void soundio_os_cond_destroy(SoundIoOsCond* cond) {
    if (!cond)
        return;

version (SOUNDIO_OS_WINDOWS) {
    DeleteCriticalSection(&cond.default_cs_id);
} else version (SOUNDIO_OS_KQUEUE) {
    close(cond.kq_id);
} else {
    if (cond.id_init) {
        assert_no_err(pthread_cond_destroy(&cond.id));
    }

    if (cond.attr_init) {
        assert_no_err(pthread_condattr_destroy(&cond.attr));
    }
    if (cond.default_mutex_init) {
        assert_no_err(pthread_mutex_destroy(&cond.default_mutex_id));
    }
}

    free(cond);
}

void soundio_os_cond_signal(SoundIoOsCond* cond, SoundIoOsMutex* locked_mutex) {
version (SOUNDIO_OS_WINDOWS) {
    if (locked_mutex) {
        WakeConditionVariable(&cond.id);
    } else {
        EnterCriticalSection(&cond.default_cs_id);
        WakeConditionVariable(&cond.id);
        LeaveCriticalSection(&cond.default_cs_id);
    }
} else version (SOUNDIO_OS_KQUEUE) {
    kevent kev;
    timespec timeout = [ 0, 0 ];

    memset(&kev, 0, kev.sizeof);
    kev.ident = notify_ident;
    kev.filter = EVFILT_USER;
    kev.fflags = NOTE_TRIGGER;

    if (kevent(cond.kq_id, &kev, 1, null, 0, &timeout) == -1) {
        if (errno == EINTR)
            return;
        if (errno == ENOENT)
            return;
        assert(0); // kevent signal error
    }
} else {
    if (locked_mutex) {
        assert_no_err(pthread_cond_signal(&cond.id));
    } else {
        assert_no_err(pthread_mutex_lock(&cond.default_mutex_id));
        assert_no_err(pthread_cond_signal(&cond.id));
        assert_no_err(pthread_mutex_unlock(&cond.default_mutex_id));
    }
}
}

void soundio_os_cond_timed_wait(SoundIoOsCond* cond, SoundIoOsMutex* locked_mutex, double seconds) {
version (SOUNDIO_OS_WINDOWS) {
    CRITICAL_SECTION* target_cs;
    if (locked_mutex) {
        target_cs = &locked_mutex.id;
    } else {
        target_cs = &cond.default_cs_id;
        EnterCriticalSection(&cond.default_cs_id);
    }
    DWORD ms = cast(int) (seconds * 1000.0);
    SleepConditionVariableCS(&cond.id, target_cs, ms);
    if (!locked_mutex)
        LeaveCriticalSection(&cond.default_cs_id);
} else version (SOUNDIO_OS_KQUEUE) {
    kevent kev;
    kevent out_kev;

    if (locked_mutex)
        assert_no_err(pthread_mutex_unlock(&locked_mutex.id));

    memset(&kev, 0, kev.sizeof);
    kev.ident = notify_ident;
    kev.filter = EVFILT_USER;
    kev.flags = EV_ADD | EV_CLEAR;

    // this time is relative
    timespec timeout;
    timeout.tv_nsec = (seconds * 1000000000L);
    timeout.tv_sec  = timeout.tv_nsec / 1000000000L;
    timeout.tv_nsec = timeout.tv_nsec % 1000000000L;

    if (kevent(cond.kq_id, &kev, 1, &out_kev, 1, &timeout) == -1) {
        if (errno == EINTR)
            return;
        assert(0); // kevent wait error
    }
    if (locked_mutex)
        assert_no_err(pthread_mutex_lock(&locked_mutex.id));
} else {
    pthread_mutex_t* target_mutex;
    if (locked_mutex) {
        target_mutex = &locked_mutex.id;
    } else {
        target_mutex = &cond.default_mutex_id;
        assert_no_err(pthread_mutex_lock(target_mutex));
    }
    // this time is absolute
    timespec tms;
    clock_gettime(CLOCK_MONOTONIC, &tms);
    tms.tv_nsec += cast(long) (seconds * 1000000000L);
    tms.tv_sec += tms.tv_nsec / 1000000000L;
    tms.tv_nsec = tms.tv_nsec % 1000000000L;
    if (auto err = pthread_cond_timedwait(&cond.id, target_mutex, &tms)) {
        assert(err != EPERM);
        assert(err != EINVAL);
    }
    if (!locked_mutex)
        assert_no_err(pthread_mutex_unlock(target_mutex));
}
}

void soundio_os_cond_wait(SoundIoOsCond* cond, SoundIoOsMutex* locked_mutex) {
version (SOUNDIO_OS_WINDOWS) {
    CRITICAL_SECTION* target_cs;
    if (locked_mutex) {
        target_cs = &locked_mutex.id;
    } else {
        target_cs = &cond.default_cs_id;
        EnterCriticalSection(&cond.default_cs_id);
    }
    SleepConditionVariableCS(&cond.id, target_cs, INFINITE);
    if (!locked_mutex)
        LeaveCriticalSection(&cond.default_cs_id);
} else version (SOUNDIO_OS_KQUEUE) {
    kevent kev;
    kevent out_kev;

    if (locked_mutex)
        assert_no_err(pthread_mutex_unlock(&locked_mutex.id));

    memset(&kev, 0, kev.sizeof);
    kev.ident = notify_ident;
    kev.filter = EVFILT_USER;
    kev.flags = EV_ADD | EV_CLEAR;

    if (kevent(cond.kq_id, &kev, 1, &out_kev, 1, null) == -1) {
        if (errno == EINTR)
            return;
        assert(0); // kevent wait error
    }
    if (locked_mutex)
        assert_no_err(pthread_mutex_lock(&locked_mutex.id));
} else {
    pthread_mutex_t* target_mutex;
    if (locked_mutex) {
        target_mutex = &locked_mutex.id;
    } else {
        target_mutex = &cond.default_mutex_id;
        assert_no_err(pthread_mutex_lock(&cond.default_mutex_id));
    }
    if (auto err = pthread_cond_wait(&cond.id, target_mutex)) {
        assert(err != EPERM);
        assert(err != EINVAL);
    }
    if (!locked_mutex)
        assert_no_err(pthread_mutex_unlock(&cond.default_mutex_id));
}
}

static int internal_init() {
version (SOUNDIO_OS_WINDOWS) {
    ulong frequency;
    if (QueryPerformanceFrequency(cast(LARGE_INTEGER*) &frequency)) {
        win32_time_resolution = 1.0 / cast(double) frequency;
    } else {
        return SoundIoError.SystemResources;
    }
    GetSystemInfo(&win32_system_info);
    page_size = win32_system_info.dwAllocationGranularity;
} else {
    page_size = cast(int) sysconf(_SC_PAGESIZE);
version (OSX) {
    host_get_clock_service(mach_host_self(), SYSTEM_CLOCK, &cclock);
}
}
    return 0;
}

int soundio_os_init() {
version (SOUNDIO_OS_WINDOWS) {
    PVOID lpContext;
    BOOL pending;

    if (!InitOnceBeginInitialize(&win32_init_once, INIT_ONCE_ASYNC, &pending, &lpContext))
        return SoundIoError.SystemResources;

    if (!pending)
        return 0;

    if (auto err = internal_init())
        return err;

    if (!InitOnceComplete(&win32_init_once, INIT_ONCE_ASYNC, null))
        return SoundIoError.SystemResources;
} else {
    assert_no_err(pthread_mutex_lock(&init_mutex));
    if (initialized) {
        assert_no_err(pthread_mutex_unlock(&init_mutex));
        return 0;
    }
    initialized = true;
    if (auto err = internal_init())
        return err;
    assert_no_err(pthread_mutex_unlock(&init_mutex));
}

    return 0;
}

int soundio_os_page_size() {
    return page_size;
}

pragma(inline, true) static size_t ceil_dbl_to_size_t(double x) {
    const(double) truncation = cast(size_t)x;
    return cast(size_t) (truncation + (truncation < x));
}

int soundio_os_init_mirrored_memory(SoundIoOsMirroredMemory* mem, size_t requested_capacity) {
    size_t actual_capacity = ceil_dbl_to_size_t(requested_capacity / cast(double)page_size) * page_size;

    version (SOUNDIO_OS_WINDOWS) {
        BOOL ok;
        HANDLE hMapFile = CreateFileMapping(INVALID_HANDLE_VALUE, null, PAGE_READWRITE, 0, cast(int) (actual_capacity * 2), null);
        if (!hMapFile)
            return SoundIoError.NoMem;

        for (;;) {
            // find a free address space with the correct size
            char* address = cast(char*)MapViewOfFile(hMapFile, FILE_MAP_ALL_ACCESS, 0, 0, actual_capacity * 2);
            if (!address) {
                ok = CloseHandle(hMapFile);
                assert(ok);
                return SoundIoError.NoMem;
            }

            // found a big enough address space. hopefully it will remain free
            // while we map to it. if not, we'll try again.
            ok = UnmapViewOfFile(address);
            assert(ok);

            char* addr1 = cast(char*)MapViewOfFileEx(hMapFile, FILE_MAP_ALL_ACCESS, 0, 0, actual_capacity, address);
            if (addr1 != address) {
                DWORD err = GetLastError();
                if (err == ERROR_INVALID_ADDRESS) {
                    continue;
                } else {
                    ok = CloseHandle(hMapFile);
                    assert(ok);
                    return SoundIoError.NoMem;
                }
            }

            char* addr2 = cast(char*)MapViewOfFileEx(hMapFile, FILE_MAP_WRITE, 0, 0,
                    actual_capacity, address + actual_capacity);
            if (addr2 != address + actual_capacity) {
                ok = UnmapViewOfFile(addr1);
                assert(ok);

                DWORD err = GetLastError();
                if (err == ERROR_INVALID_ADDRESS) {
                    continue;
                } else {
                    ok = CloseHandle(hMapFile);
                    assert(ok);
                    return SoundIoError.NoMem;
                }
            }

            mem.priv = hMapFile;
            mem.address = address;
            break;
        }
    } else {
        char[32] shm_path = "/dev/shm/soundio-XXXXXX\0";
        char[32] tmp_path = "/tmp/soundio-XXXXXX\0";
        char* chosen_path;

        int fd = mkstemp(shm_path.ptr);
        if (fd < 0) {
            fd = mkstemp(tmp_path.ptr);
            if (fd < 0) {
                return SoundIoError.SystemResources;
            } else {
                chosen_path = tmp_path.ptr;
            }
        } else {
            chosen_path = shm_path.ptr;
        }

        if (unlink(chosen_path)) {
            close(fd);
            return SoundIoError.SystemResources;
        }

        if (ftruncate(fd, actual_capacity)) {
            close(fd);
            return SoundIoError.SystemResources;
        }

        char* address = cast(char*)mmap(null, actual_capacity * 2, PROT_NONE, MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
        if (address == MAP_FAILED) {
            close(fd);
            return SoundIoError.NoMem;
        }

        char* other_address = cast(char*)mmap(address, actual_capacity, PROT_READ|PROT_WRITE,
                MAP_FIXED|MAP_SHARED, fd, 0);
        if (other_address != address) {
            munmap(address, 2 * actual_capacity);
            close(fd);
            return SoundIoError.NoMem;
        }

        other_address = cast(char*)mmap(address + actual_capacity, actual_capacity,
                PROT_READ|PROT_WRITE, MAP_FIXED|MAP_SHARED, fd, 0);
        if (other_address != address + actual_capacity) {
            munmap(address, 2 * actual_capacity);
            close(fd);
            return SoundIoError.NoMem;
        }

        mem.address = address;

        if (close(fd))
            return SoundIoError.SystemResources;
    }

    mem.capacity = actual_capacity;
    return 0;
}

void soundio_os_deinit_mirrored_memory(SoundIoOsMirroredMemory* mem) {
    if (!mem.address)
        return;
    version (SOUNDIO_OS_WINDOWS) {
        BOOL ok;
        ok = UnmapViewOfFile(mem.address);
        assert(ok);
        ok = UnmapViewOfFile(mem.address + mem.capacity);
        assert(ok);
        ok = CloseHandle(cast(HANDLE)mem.priv);
        assert(ok);
    } else {
        int err = munmap(mem.address, 2 * mem.capacity);
        assert(!err);
    }
    mem.address = null;
}