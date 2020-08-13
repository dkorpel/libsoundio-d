module soundio.asio;

// include bassasio.h

// BASS_ASIO_FORMAT_16BITI just ran into a use-case tonight! Maybe. The caveat is that my use case might be pretty easy compared to what Andrei is asking for. My use case requires modifying the function signature a lot, but that can actually be exploited to make my solution easier. I probably only need to forward storage class. It's still kinda leading to code that feels wrong or isn't obvious, so maybe it will help your discussion.