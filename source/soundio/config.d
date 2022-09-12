/// Translated from C to D
module soundio.config;

@nogc nothrow:
extern(C): __gshared:


package:

enum SOUNDIO_VERSION_MAJOR = 2;
enum SOUNDIO_VERSION_MINOR = 0;
enum SOUNDIO_VERSION_PATCH = 0;
enum SOUNDIO_VERSION_STRING = "2.0.0";

// Defined in dub.sdl subconfigurations
//#define SOUNDIO_HAVE_JACK
//#define SOUNDIO_HAVE_PULSEAUDIO
//#define SOUNDIO_HAVE_ALSA;
//#define SOUNDIO_HAVE_COREAUDIO
//#define SOUNDIO_HAVE_WASAPI
