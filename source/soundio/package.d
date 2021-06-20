/// Translated from C to D
module soundio;

extern(C): @nogc: nothrow: __gshared:

public {
	import soundio.api;
}

// private imports to include them in compilation when doing `dmd -i soundio/package.d`
private {
	import soundio.api;
	import soundio.atomics;
	import soundio.channel_layout;
	import soundio.config;
	import soundio.list;
	import soundio.dummy;
	import soundio.os;
	import soundio.ring_buffer;
	import soundio.soundio;
	import soundio.soundio_internal;
	import soundio.soundio_private;
	import soundio.util;
}

version(SOUNDIO_HAVE_WASAPI) {
	pragma(lib, "Ole32.lib"); // CoCreateInstance, CoTaskMemFree, PropVariantClear
	import soundio.wasapi;
	import soundio.headers.wasapiheader;
}

version(SOUNDIO_HAVE_PULSEAUDIO) {
	pragma(lib, "pulse");
	import soundio.pulseaudio;
	import soundio.headers.pulseheader;
}

version(SOUNDIO_HAVE_ALSA) {
	pragma(lib, "asound");
	import soundio.alsa;
	import soundio.headers.alsaheader;
}

version(SOUNDIO_HAVE_JACK) {
	//pragma(lib, "jack"); what's it called?
	import soundio.jack;
	import soundio.headers.jackheader;
}
