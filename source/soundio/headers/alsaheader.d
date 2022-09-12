/// C declarations of ALSA that libsoundio uses
module soundio.headers.alsaheader;

@nogc nothrow:
extern(C): __gshared:


import core.stdc.config: c_long, c_ulong;
import core.sys.posix.poll;

// conf.h
int snd_config_update_free_global();
int snd_config_update();

// control.h
struct snd_ctl_t;
struct snd_ctl_card_info_t;
int snd_card_next(int* card);
char *snd_device_name_get_hint(const(void)* hint, const(char)* id);
int snd_device_name_hint(int card, const(char)* iface, void*** hints);
int snd_device_name_free_hint(void** hints);
int snd_ctl_open(snd_ctl_t** ctl, const(char)* name, int mode);
int snd_ctl_close(snd_ctl_t* ctl);
int snd_ctl_card_info(snd_ctl_t* ctl, snd_ctl_card_info_t* info);
int snd_ctl_pcm_next_device(snd_ctl_t* ctl, int* device);
int snd_ctl_pcm_info(snd_ctl_t* ctl, snd_pcm_info_t* info);
const(char)* snd_ctl_card_info_get_name(const(snd_ctl_card_info_t)* obj);


size_t snd_ctl_card_info_sizeof();
int snd_ctl_card_info_malloc(snd_ctl_card_info_t** ptr);
void snd_ctl_card_info_free(snd_ctl_card_info_t* obj);

// pcm.h
size_t snd_pcm_sw_params_sizeof();
size_t snd_pcm_hw_params_sizeof();
size_t snd_pcm_format_mask_sizeof();
size_t snd_pcm_info_sizeof();


int snd_pcm_sw_params_malloc(snd_pcm_sw_params_t** ptr);
void snd_pcm_sw_params_free(snd_pcm_sw_params_t* obj);
int snd_pcm_hw_params_malloc(snd_pcm_hw_params_t** ptr);
void snd_pcm_hw_params_free(snd_pcm_hw_params_t* obj);
int snd_pcm_format_mask_malloc(snd_pcm_format_mask_t** ptr);
void snd_pcm_format_mask_free(snd_pcm_format_mask_t* obj);
int snd_pcm_info_malloc(snd_pcm_info_t** ptr);
void snd_pcm_info_free(snd_pcm_info_t* obj);

int snd_pcm_open(snd_pcm_t** pcm, const(char)* name, snd_pcm_stream_t stream, int mode);

int snd_pcm_hw_params_any(snd_pcm_t* pcm, snd_pcm_hw_params_t* params);
void snd_pcm_free_chmaps(snd_pcm_chmap_query_t** maps);
int snd_pcm_format_mask_test(const(snd_pcm_format_mask_t)* mask, snd_pcm_format_t val);
int snd_pcm_hw_params_get_rate_min(const(snd_pcm_hw_params_t)* params, uint* val, int* dir);
int snd_pcm_hw_params_get_buffer_size_min(const(snd_pcm_hw_params_t)* params, snd_pcm_uframes_t* val);
int snd_pcm_hw_params_get_buffer_size_max(const(snd_pcm_hw_params_t)* params, snd_pcm_uframes_t* val);


void snd_pcm_format_mask_none(snd_pcm_format_mask_t* mask);
void snd_pcm_format_mask_set(snd_pcm_format_mask_t* mask, snd_pcm_format_t val);
int snd_pcm_hw_params_set_access(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, snd_pcm_access_t _access);
snd_pcm_chmap_query_t** snd_pcm_query_chmaps(snd_pcm_t* pcm);
int snd_pcm_close(snd_pcm_t* pcm);
snd_pcm_chmap_t* snd_pcm_get_chmap(snd_pcm_t* pcm);

int snd_pcm_hw_params_set_rate_resample(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, uint val);
int snd_pcm_hw_params_get_channels_min(const(snd_pcm_hw_params_t)* params, uint* val);
int snd_pcm_hw_params_set_channels_last(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, uint* val);
int snd_pcm_hw_params_set_rate_last(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, uint* val, int* dir);

int snd_pcm_hw_params_set_buffer_size_first(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, snd_pcm_uframes_t* val);

int snd_pcm_poll_descriptors_count(snd_pcm_t* pcm);
int snd_pcm_poll_descriptors(snd_pcm_t* pcm, pollfd* pfds, uint space);
int snd_pcm_poll_descriptors_revents(snd_pcm_t* pcm, pollfd* pfds, uint nfds, ushort* revents);
int snd_pcm_hw_params(snd_pcm_t* pcm, snd_pcm_hw_params_t* params);
int snd_pcm_sw_params_current(snd_pcm_t* pcm, snd_pcm_sw_params_t* params);
int snd_pcm_sw_params(snd_pcm_t* pcm, snd_pcm_sw_params_t* params);
int snd_pcm_prepare(snd_pcm_t* pcm);
int snd_pcm_reset(snd_pcm_t* pcm);
int snd_pcm_start(snd_pcm_t* pcm);
int snd_pcm_drop(snd_pcm_t* pcm);
int snd_pcm_pause(snd_pcm_t* pcm, int enable);
snd_pcm_state_t snd_pcm_state(snd_pcm_t* pcm);
int snd_pcm_delay(snd_pcm_t* pcm, snd_pcm_sframes_t* delayp);
int snd_pcm_resume(snd_pcm_t* pcm);
snd_pcm_sframes_t snd_pcm_avail(snd_pcm_t* pcm);
snd_pcm_sframes_t snd_pcm_avail_update(snd_pcm_t* pcm);
snd_pcm_sframes_t snd_pcm_readi(snd_pcm_t* pcm, void* buffer, snd_pcm_uframes_t size);
snd_pcm_sframes_t snd_pcm_readn(snd_pcm_t* pcm, void** bufs, snd_pcm_uframes_t size);
snd_pcm_chmap_query_t** snd_pcm_query_chmaps_from_hw(int card, int dev, int subdev, snd_pcm_stream_t stream);
int snd_pcm_set_chmap(snd_pcm_t* pcm, const(snd_pcm_chmap_t)* map);
const(char)* snd_pcm_info_get_name(const(snd_pcm_info_t)* obj);
void snd_pcm_info_set_device(snd_pcm_info_t* obj, uint val);
void snd_pcm_info_set_subdevice(snd_pcm_info_t* obj, uint val);
void snd_pcm_info_set_stream(snd_pcm_info_t* obj, snd_pcm_stream_t val);
int snd_pcm_hw_params_set_format(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, snd_pcm_format_t val);
int snd_pcm_hw_params_set_format_mask(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, snd_pcm_format_mask_t* mask);
void snd_pcm_hw_params_get_format_mask(snd_pcm_hw_params_t* params, snd_pcm_format_mask_t* mask);
int snd_pcm_hw_params_set_channels(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, uint val);
int snd_pcm_hw_params_set_rate(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, uint val, int dir);
int snd_pcm_hw_params_get_period_size(const(snd_pcm_hw_params_t)* params, snd_pcm_uframes_t* frames, int* dir);
int snd_pcm_hw_params_set_period_size_near(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, snd_pcm_uframes_t* val, int* dir);
int snd_pcm_hw_params_set_buffer_size_near(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, snd_pcm_uframes_t* val);
int snd_pcm_hw_params_set_buffer_size_last(snd_pcm_t* pcm, snd_pcm_hw_params_t* params, snd_pcm_uframes_t* val);
int snd_pcm_sw_params_set_avail_min(snd_pcm_t* pcm, snd_pcm_sw_params_t* params, snd_pcm_uframes_t val);
int snd_pcm_sw_params_set_start_threshold(snd_pcm_t* pcm, snd_pcm_sw_params_t* params, snd_pcm_uframes_t val);
int snd_pcm_mmap_begin(snd_pcm_t* pcm, const(snd_pcm_channel_area_t)** areas, snd_pcm_uframes_t* offset, snd_pcm_uframes_t* frames);
snd_pcm_sframes_t snd_pcm_mmap_commit(snd_pcm_t* pcm, snd_pcm_uframes_t offset, snd_pcm_uframes_t frames);
int snd_pcm_format_physical_width(snd_pcm_format_t format);
snd_pcm_sframes_t snd_pcm_writei(snd_pcm_t* pcm, const(void)* buffer, snd_pcm_uframes_t size);
snd_pcm_sframes_t snd_pcm_writen(snd_pcm_t* pcm, void** bufs, snd_pcm_uframes_t size);

struct snd_pcm_t;
struct snd_pcm_chmap_t {
	uint channels;
	uint[0] pos;
}

// C enum
alias snd_pcm_access_t = int;
enum {
	SND_PCM_ACCESS_MMAP_INTERLEAVED = 0,
	SND_PCM_ACCESS_MMAP_NONINTERLEAVED,
	SND_PCM_ACCESS_MMAP_COMPLEX,
	SND_PCM_ACCESS_RW_INTERLEAVED,
	SND_PCM_ACCESS_RW_NONINTERLEAVED,
	SND_PCM_ACCESS_LAST = SND_PCM_ACCESS_RW_NONINTERLEAVED
}

alias snd_pcm_uframes_t = c_ulong;
alias snd_pcm_sframes_t = c_long;

// C enum
alias snd_pcm_format_t = int;

// C enum
alias snd_pcm_stream_t = int;
enum {
	SND_PCM_STREAM_PLAYBACK = 0,
	SND_PCM_STREAM_CAPTURE,
	SND_PCM_STREAM_LAST = SND_PCM_STREAM_CAPTURE
}

// C enum
alias snd_pcm_state_t = int;
enum {
	SND_PCM_STATE_OPEN = 0,
	SND_PCM_STATE_SETUP,
	SND_PCM_STATE_PREPARED,
	SND_PCM_STATE_RUNNING,
	SND_PCM_STATE_XRUN,
	SND_PCM_STATE_DRAINING,
	SND_PCM_STATE_PAUSED,
	SND_PCM_STATE_SUSPENDED,
	SND_PCM_STATE_DISCONNECTED,
	SND_PCM_STATE_LAST = SND_PCM_STATE_DISCONNECTED
}

struct snd_pcm_chmap_query_t {
	//enum snd_pcm_chmap_type;
	//snd_pcm_chmap_type type;
	int type; // C enum
	snd_pcm_chmap_t map;
}

struct snd_pcm_channel_area_t {
	void* addr;
	uint first;
	uint step;
}

struct snd_pcm_format_mask_t;
struct snd_pcm_info_t;
struct snd_pcm_hw_params_t;
struct snd_pcm_sw_params_t;
enum {
	SND_CHMAP_UNKNOWN = 0,
	SND_CHMAP_NA,
	SND_CHMAP_MONO,
	SND_CHMAP_FL,
	SND_CHMAP_FR,
	SND_CHMAP_RL,
	SND_CHMAP_RR,
	SND_CHMAP_FC,
	SND_CHMAP_LFE,
	SND_CHMAP_SL,
	SND_CHMAP_SR,
	SND_CHMAP_RC,
	SND_CHMAP_FLC,
	SND_CHMAP_FRC,
	SND_CHMAP_RLC,
	SND_CHMAP_RRC,
	SND_CHMAP_FLW,
	SND_CHMAP_FRW,
	SND_CHMAP_FLH,
	SND_CHMAP_FCH,
	SND_CHMAP_FRH,
	SND_CHMAP_TC,
	SND_CHMAP_TFL,
	SND_CHMAP_TFR,
	SND_CHMAP_TFC,
	SND_CHMAP_TRL,
	SND_CHMAP_TRR,
	SND_CHMAP_TRC,
	SND_CHMAP_TFLC,
	SND_CHMAP_TFRC,
	SND_CHMAP_TSL,
	SND_CHMAP_TSR,
	SND_CHMAP_LLFE,
	SND_CHMAP_RLFE,
	SND_CHMAP_BC,
	SND_CHMAP_BLC,
	SND_CHMAP_BRC,
	SND_CHMAP_LAST = SND_CHMAP_BRC,
}

enum {
	SND_PCM_FORMAT_UNKNOWN = -1,
	SND_PCM_FORMAT_S8 = 0,
	SND_PCM_FORMAT_U8,
	SND_PCM_FORMAT_S16_LE,
	SND_PCM_FORMAT_S16_BE,
	SND_PCM_FORMAT_U16_LE,
	SND_PCM_FORMAT_U16_BE,
	SND_PCM_FORMAT_S24_LE,
	SND_PCM_FORMAT_S24_BE,
	SND_PCM_FORMAT_U24_LE,
	SND_PCM_FORMAT_U24_BE,
	SND_PCM_FORMAT_S32_LE,
	SND_PCM_FORMAT_S32_BE,
	SND_PCM_FORMAT_U32_LE,
	SND_PCM_FORMAT_U32_BE,
	SND_PCM_FORMAT_FLOAT_LE,
	SND_PCM_FORMAT_FLOAT_BE,
	SND_PCM_FORMAT_FLOAT64_LE,
	SND_PCM_FORMAT_FLOAT64_BE,
	SND_PCM_FORMAT_IEC958_SUBFRAME_LE,
	SND_PCM_FORMAT_IEC958_SUBFRAME_BE,
	SND_PCM_FORMAT_MU_LAW,
	SND_PCM_FORMAT_A_LAW,
	SND_PCM_FORMAT_IMA_ADPCM,
	SND_PCM_FORMAT_MPEG,
	SND_PCM_FORMAT_GSM,
	SND_PCM_FORMAT_SPECIAL = 31,
	SND_PCM_FORMAT_S24_3LE = 32,
	SND_PCM_FORMAT_S24_3BE,
	SND_PCM_FORMAT_U24_3LE,
	SND_PCM_FORMAT_U24_3BE,
	SND_PCM_FORMAT_S20_3LE,
	SND_PCM_FORMAT_S20_3BE,
	SND_PCM_FORMAT_U20_3LE,
	SND_PCM_FORMAT_U20_3BE,
	SND_PCM_FORMAT_S18_3LE,
	SND_PCM_FORMAT_S18_3BE,
	SND_PCM_FORMAT_U18_3LE,
	SND_PCM_FORMAT_U18_3BE,
	SND_PCM_FORMAT_G723_24,
	SND_PCM_FORMAT_G723_24_1B,
	SND_PCM_FORMAT_G723_40,
	SND_PCM_FORMAT_G723_40_1B,
	SND_PCM_FORMAT_DSD_U8,
	SND_PCM_FORMAT_DSD_U16_LE,
	SND_PCM_FORMAT_DSD_U32_LE,
	SND_PCM_FORMAT_DSD_U16_BE,
	SND_PCM_FORMAT_DSD_U32_BE,
	SND_PCM_FORMAT_LAST = SND_PCM_FORMAT_DSD_U32_BE,
}
version(LittleEndian) {
	enum {
		SND_PCM_FORMAT_S16 = SND_PCM_FORMAT_S16_LE,
		SND_PCM_FORMAT_U16 = SND_PCM_FORMAT_U16_LE,
		SND_PCM_FORMAT_S24 = SND_PCM_FORMAT_S24_LE,
		SND_PCM_FORMAT_U24 = SND_PCM_FORMAT_U24_LE,
		SND_PCM_FORMAT_S32 = SND_PCM_FORMAT_S32_LE,
		SND_PCM_FORMAT_U32 = SND_PCM_FORMAT_U32_LE,
		SND_PCM_FORMAT_FLOAT = SND_PCM_FORMAT_FLOAT_LE,
		SND_PCM_FORMAT_FLOAT64 = SND_PCM_FORMAT_FLOAT64_LE,
		SND_PCM_FORMAT_IEC958_SUBFRAME = SND_PCM_FORMAT_IEC958_SUBFRAME_LE
	}
} else version(BigEndian) {
	enum {
		SND_PCM_FORMAT_S16 = SND_PCM_FORMAT_S16_BE,
		SND_PCM_FORMAT_U16 = SND_PCM_FORMAT_U16_BE,
		SND_PCM_FORMAT_S24 = SND_PCM_FORMAT_S24_BE,
		SND_PCM_FORMAT_U24 = SND_PCM_FORMAT_U24_BE,
		SND_PCM_FORMAT_S32 = SND_PCM_FORMAT_S32_BE,
		SND_PCM_FORMAT_U32 = SND_PCM_FORMAT_U32_BE,
		SND_PCM_FORMAT_FLOAT = SND_PCM_FORMAT_FLOAT_BE,
		SND_PCM_FORMAT_FLOAT64 = SND_PCM_FORMAT_FLOAT64_BE,
		SND_PCM_FORMAT_IEC958_SUBFRAME = SND_PCM_FORMAT_IEC958_SUBFRAME_BE
	}
} else {
	static assert(0, "cannot determine whether to compile for a little endian or big endian target");
}
