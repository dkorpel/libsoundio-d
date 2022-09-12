/// Translated from C to D
module soundio.atomics;

@nogc nothrow:
extern(C): __gshared:


import core.atomic;

// Simple wrappers around atomic values so that the compiler will catch it if
// I accidentally use operators such as +, -, += on them.
alias SoundIoAtomicLong = shared(long);
alias SoundIoAtomicInt = shared(int);
alias SoundIoAtomicBool = shared(bool);
alias SoundIoAtomicFlag = shared(bool);
alias SoundIoAtomicULong = shared(ulong);

alias SOUNDIO_ATOMIC_LOAD =      atomicLoad;
alias SOUNDIO_ATOMIC_STORE =     atomicStore;
alias SOUNDIO_ATOMIC_EXCHANGE =  atomicExchange;

version(LDC) {
	// atomicFetchAdd was added in dmd 2.089, but LDC is missing it in core.internal.atomic
	auto SOUNDIO_ATOMIC_FETCH_ADD(T)(ref T x, long count) {
		atomicOp!"+="(x, count);
		//llvm_atomic_fetch_add(T, count);
	}
} else {
	alias SOUNDIO_ATOMIC_FETCH_ADD = atomicFetchAdd;
}

enum SOUNDIO_ATOMIC_FLAG_INIT = SoundIoAtomicFlag.init;
bool SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(ref SoundIoAtomicFlag a) {
	// `cas` returns `true` if the store happened, so `a` was equal to `false`, so
	// the result of `cas` needs to be inverted
	return !cas(&a, /*value to compare to:*/ false, /*store if equal:*/ true);
}
void SOUNDIO_ATOMIC_FLAG_CLEAR(ref SoundIoAtomicFlag a) {
	atomicStore(a, false); //atomic_flag_test_and_set(&a.x);
}

unittest {
	SoundIoAtomicFlag f = SOUNDIO_ATOMIC_FLAG_INIT;
	assert(!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(f));
	assert(SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(f));
	SOUNDIO_ATOMIC_FLAG_CLEAR(f);
	assert(!SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(f));
	assert(SOUNDIO_ATOMIC_FLAG_TEST_AND_SET(f));
}
