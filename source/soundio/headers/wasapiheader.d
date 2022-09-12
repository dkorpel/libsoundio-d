/// C declarations of WASAPI that libsoundio uses
module soundio.headers.wasapiheader;

version(Windows):
extern(Windows): @nogc: nothrow: __gshared:

import core.sys.windows.windows;

enum DEVICE_STATE_ACTIVE =      0x00000001;
enum DEVICE_STATE_DISABLED =    0x00000002;
enum DEVICE_STATE_NOTPRESENT =  0x00000004;
enum DEVICE_STATE_UNPLUGGED =   0x00000008;
enum DEVICE_STATEMASK_ALL =     0x0000000f;

enum AUDCLNT_STREAMFLAGS_CROSSPROCESS             = 0x00010000;
enum AUDCLNT_STREAMFLAGS_LOOPBACK                 = 0x00020000;
enum AUDCLNT_STREAMFLAGS_EVENTCALLBACK            = 0x00040000;
enum AUDCLNT_STREAMFLAGS_NOPERSIST                = 0x00080000;
enum AUDCLNT_STREAMFLAGS_RATEADJUST               = 0x00100000;
enum AUDCLNT_STREAMFLAGS_PREVENT_LOOPBACK_CAPTURE = 0x01000000;
enum AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY      = 0x08000000;
enum AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM           = 0x80000000;
enum AUDCLNT_SESSIONFLAGS_EXPIREWHENUNOWNED       = 0x10000000;
enum AUDCLNT_SESSIONFLAGS_DISPLAY_HIDE            = 0x20000000;
enum AUDCLNT_SESSIONFLAGS_DISPLAY_HIDEWHENEXPIRED = 0x40000000;

// Error codes
enum FACILITY_AUDCLNT = 2185;
int AUDCLNT_ERR(int n) {return MAKE_HRESULT(SEVERITY_ERROR, FACILITY_AUDCLNT, n);}
int AUDCLNT_SUCCESS(int n) {return MAKE_SCODE(SEVERITY_SUCCESS, FACILITY_AUDCLNT, n);}
enum AUDCLNT_E_NOT_INITIALIZED =              AUDCLNT_ERR(0x001);
enum AUDCLNT_E_ALREADY_INITIALIZED =          AUDCLNT_ERR(0x002);
enum AUDCLNT_E_WRONG_ENDPOINT_TYPE =          AUDCLNT_ERR(0x003);
enum AUDCLNT_E_DEVICE_INVALIDATED =           AUDCLNT_ERR(0x004);
enum AUDCLNT_E_NOT_STOPPED =                  AUDCLNT_ERR(0x005);
enum AUDCLNT_E_BUFFER_TOO_LARGE =             AUDCLNT_ERR(0x006);
enum AUDCLNT_E_OUT_OF_ORDER =                 AUDCLNT_ERR(0x007);
enum AUDCLNT_E_UNSUPPORTED_FORMAT =           AUDCLNT_ERR(0x008);
enum AUDCLNT_E_INVALID_SIZE =                 AUDCLNT_ERR(0x009);
enum AUDCLNT_E_DEVICE_IN_USE =                AUDCLNT_ERR(0x00a);
enum AUDCLNT_E_BUFFER_OPERATION_PENDING =     AUDCLNT_ERR(0x00b);
enum AUDCLNT_E_THREAD_NOT_REGISTERED =        AUDCLNT_ERR(0x00c);
enum AUDCLNT_E_EXCLUSIVE_MODE_NOT_ALLOWED =   AUDCLNT_ERR(0x00e);
enum AUDCLNT_E_ENDPOINT_CREATE_FAILED =       AUDCLNT_ERR(0x00f);
enum AUDCLNT_E_SERVICE_NOT_RUNNING =          AUDCLNT_ERR(0x010);
enum AUDCLNT_E_EVENTHANDLE_NOT_EXPECTED =     AUDCLNT_ERR(0x011);
enum AUDCLNT_E_EXCLUSIVE_MODE_ONLY =          AUDCLNT_ERR(0x012);
enum AUDCLNT_E_BUFDURATION_PERIOD_NOT_EQUAL = AUDCLNT_ERR(0x013);
enum AUDCLNT_E_EVENTHANDLE_NOT_SET =          AUDCLNT_ERR(0x014);
enum AUDCLNT_E_INCORRECT_BUFFER_SIZE =        AUDCLNT_ERR(0x015);
enum AUDCLNT_E_BUFFER_SIZE_ERROR =            AUDCLNT_ERR(0x016);
enum AUDCLNT_E_CPUUSAGE_EXCEEDED =            AUDCLNT_ERR(0x017);
enum AUDCLNT_E_BUFFER_ERROR =                 AUDCLNT_ERR(0x018);
enum AUDCLNT_E_BUFFER_SIZE_NOT_ALIGNED =      AUDCLNT_ERR(0x019);
enum AUDCLNT_E_INVALID_DEVICE_PERIOD =        AUDCLNT_ERR(0x020);
enum AUDCLNT_E_INVALID_STREAM_FLAG =          AUDCLNT_ERR(0x021);
enum AUDCLNT_E_ENDPOINT_OFFLOAD_NOT_CAPABLE = AUDCLNT_ERR(0x022);
enum AUDCLNT_E_OUT_OF_OFFLOAD_RESOURCES =     AUDCLNT_ERR(0x023);
enum AUDCLNT_E_OFFLOAD_MODE_ONLY =            AUDCLNT_ERR(0x024);
enum AUDCLNT_E_NONOFFLOAD_MODE_ONLY =         AUDCLNT_ERR(0x025);
enum AUDCLNT_E_RESOURCES_INVALIDATED =        AUDCLNT_ERR(0x026);
enum AUDCLNT_E_RAW_MODE_UNSUPPORTED =         AUDCLNT_ERR(0x027);
enum AUDCLNT_E_ENGINE_PERIODICITY_LOCKED =    AUDCLNT_ERR(0x028);
enum AUDCLNT_E_ENGINE_FORMAT_LOCKED =         AUDCLNT_ERR(0x029);
enum AUDCLNT_E_HEADTRACKING_ENABLED =         AUDCLNT_ERR(0x030);
enum AUDCLNT_E_HEADTRACKING_UNSUPPORTED =     AUDCLNT_ERR(0x040);
enum AUDCLNT_S_BUFFER_EMPTY =                 AUDCLNT_SUCCESS(0x001);
enum AUDCLNT_S_THREAD_ALREADY_REGISTERED =    AUDCLNT_SUCCESS(0x002);
enum AUDCLNT_S_POSITION_STALLED =             AUDCLNT_SUCCESS(0x003);

enum AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY	= 0x1;
enum AUDCLNT_BUFFERFLAGS_SILENT	= 0x2;
enum AUDCLNT_BUFFERFLAGS_TIMESTAMP_ERROR	= 0x4;

// IUnknown
struct IUnknown {
    IUnknownVtable* lpVtbl;
}

struct IUnknownVtable {
    private alias This_ = IUnknown*;
    extern(Windows): @nogc: nothrow:
    HRESULT function(This_, REFIID riid, void **ppvObject) QueryInterface;
    ULONG function(This_, ) AddRef;
    ULONG function(This_, ) Release;
}

ULONG IUnknown_AddRef(T)(T* x) {return x.lpVtbl.AddRef(x);}
ULONG IUnknown_Release(T)(T* x) {return x.lpVtbl.Release(x);}

// MMNotificationClient /////////////////////////////////////////////////////////////
struct IMMNotificationClient {
    IMMNotificationClientVtbl* lpVtbl;
}

struct IMMNotificationClientVtbl {
    private alias THIS_ = IMMNotificationClient*;
    extern(Windows): @nogc: nothrow:
    HRESULT function(THIS_ client, REFIID riid, void** ppv) QueryInterface;
    uint function(THIS_ client) AddRef;
    uint function(THIS_ client) Release;
    HRESULT function(THIS_ client, LPCWSTR wid, DWORD state) OnDeviceStateChanged;
    HRESULT function(THIS_ client, LPCWSTR wid) OnDeviceAdded;
    HRESULT function(THIS_ client, LPCWSTR wid) OnDeviceRemoved;
    HRESULT function(THIS_ client, EDataFlow flow, ERole role, LPCWSTR wid) OnDefaultDeviceChange;
    HRESULT function(THIS_ client, LPCWSTR wid, const(PROPERTYKEY) key) OnPropertyValueChanged;
}

// MMDevice /////////////////////////////////////////////////////////////
struct IMMDevice {
    IMMDeviceVtable* lpVtbl;
}

struct IMMDeviceVtable {
    extern(Windows): @nogc: nothrow:
    alias This_ = IMMDevice*;
    HRESULT function(This_, REFIID riid, void **ppvObject) QueryInterface;
    ULONG function(This_, ) AddRef;
    ULONG function(This_, ) Release;
    HRESULT function(This_, REFIID iid, DWORD dwClsCtx, PROPVARIANT *pActivationParams, void **ppInterface) Activate;
    HRESULT function(This_, DWORD stgmAccess, IPropertyStore **ppProperties) OpenPropertyStore;
    HRESULT function(This_, LPWSTR *ppstrId) GetId;
    HRESULT function(This_, DWORD *pdwState) GetState;
}
HRESULT IMMDevice_QueryInterface(T)(T* this_, REFIID riid, void **ppvObject) {return this_.lpVtbl.QueryInterface(this_,riid, ppvObject);}
ULONG IMMDevice_AddRef(T)(T* this_, ) {return this_.lpVtbl.AddRef(this_,);}
ULONG IMMDevice_Release(T)(T* this_, ) {return this_.lpVtbl.Release(this_,);}
HRESULT IMMDevice_Activate(T)(T* this_, REFIID iid, DWORD dwClsCtx, PROPVARIANT *pActivationParams, void **ppInterface) {return this_.lpVtbl.Activate(this_,iid, dwClsCtx, pActivationParams, ppInterface);}
HRESULT IMMDevice_OpenPropertyStore(T)(T* this_, DWORD stgmAccess, IPropertyStore **ppProperties) {return this_.lpVtbl.OpenPropertyStore(this_,stgmAccess, ppProperties);}
HRESULT IMMDevice_GetId(T)(T* this_, LPWSTR *ppstrId) {return this_.lpVtbl.GetId(this_,ppstrId);}
HRESULT IMMDevice_GetState(T)(T* this_, DWORD *pdwState) {return this_.lpVtbl.GetState(this_,pdwState);}

// MMDeviceEnumerator /////////////////////////////////////////////////////////////
struct IMMDeviceEnumerator {
    IMMDeviceEnumeratorVtable* lpVtbl;
}

struct IMMDeviceEnumeratorVtable {
    extern(Windows): @nogc: nothrow:
    alias This_ = IMMDeviceEnumerator*;
    HRESULT function(This_, REFIID riid, void **ppvObject) QueryInterface;
    ULONG function(This_, ) AddRef;
    ULONG function(This_, ) Release;
    HRESULT function(This_, EDataFlow dataFlow, DWORD dwStateMask, IMMDeviceCollection **ppDevices) EnumAudioEndpoints;
    HRESULT function(This_, EDataFlow dataFlow, ERole role, IMMDevice **ppEndpoint) GetDefaultAudioEndpoint;
    HRESULT function(This_, LPCWSTR pwstrId, IMMDevice **ppDevice) GetDevice;
    HRESULT function(This_, IMMNotificationClient *pClient) RegisterEndpointNotificationCallback;
    HRESULT function(This_, IMMNotificationClient *pClient) UnregisterEndpointNotificationCallback;
}
HRESULT IMMDeviceEnumerator_QueryInterface(T)(T* this_, REFIID riid, void **ppvObject) {return this_.lpVtbl.QueryInterface(this_,riid, ppvObject);}
ULONG IMMDeviceEnumerator_AddRef(T)(T* this_, ) {return this_.lpVtbl.AddRef(this_,);}
ULONG IMMDeviceEnumerator_Release(T)(T* this_, ) {return this_.lpVtbl.Release(this_,);}
HRESULT IMMDeviceEnumerator_EnumAudioEndpoints(T)(T* this_, EDataFlow dataFlow, DWORD dwStateMask, IMMDeviceCollection **ppDevices) {return this_.lpVtbl.EnumAudioEndpoints(this_,dataFlow, dwStateMask, ppDevices);}
HRESULT IMMDeviceEnumerator_GetDefaultAudioEndpoint(T)(T* this_, EDataFlow dataFlow, ERole role, IMMDevice **ppEndpoint) {return this_.lpVtbl.GetDefaultAudioEndpoint(this_,dataFlow, role, ppEndpoint);}
HRESULT IMMDeviceEnumerator_GetDevice(T)(T* this_, LPCWSTR pwstrId, IMMDevice **ppDevice) {return this_.lpVtbl.GetDevice(this_,pwstrId, ppDevice);}
HRESULT IMMDeviceEnumerator_RegisterEndpointNotificationCallback(T)(T* this_, IMMNotificationClient *pClient) {return this_.lpVtbl.RegisterEndpointNotificationCallback(this_,pClient);}
HRESULT IMMDeviceEnumerator_UnregisterEndpointNotificationCallback(T)(T* this_, IMMNotificationClient *pClient) {return this_.lpVtbl.UnregisterEndpointNotificationCallback(this_,pClient);}

struct IAudioSessionEvents;
struct AudioSessionState;

// AudioClockAdjustment //////////////////////////////////
struct IAudioClockAdjustment {
    IAudioClockAdjustmentVtable* lpVtbl;
}

struct IAudioClockAdjustmentVtable {
    private alias This_ = IAudioClockAdjustment*;
    extern(Windows): @nogc: nothrow:
    HRESULT function(This_, REFIID riid, void **ppvObject) QueryInterface;
    ULONG function(This_, ) AddRef;
    ULONG function(This_, ) Release;
    // there's more, not translated yet
}

// SimpleAudioVolume /////////////////////////////////////
struct ISimpleAudioVolume {
    ISimpleAudioVolumeVtable* lpVtbl;
}

struct ISimpleAudioVolumeVtable {
    extern(Windows): @nogc: nothrow:
    alias This_ = ISimpleAudioVolume*;
    HRESULT function(This_, REFIID riid, void **ppvObject) QueryInterface;
    ULONG function(This_, ) AddRef;
    ULONG function(This_, ) Release;
    HRESULT function(This_, float fLevel, LPCGUID EventContext) SetMasterVolume;
    HRESULT function(This_, float *pfLevel) GetMasterVolume;
    HRESULT function(This_, BOOL bMute, LPCGUID EventContext) SetMute;
    HRESULT function(This_, BOOL *pbMute) GetMute;
}
HRESULT ISimpleAudioVolume_QueryInterface(T)(T* this_, REFIID riid, void **ppvObject) {return this_.lpVtbl.QueryInterface(this_,riid, ppvObject);}
ULONG ISimpleAudioVolume_AddRef(T)(T* this_, ) {return this_.lpVtbl.AddRef(this_,);}
ULONG ISimpleAudioVolume_Release(T)(T* this_, ) {return this_.lpVtbl.Release(this_,);}
HRESULT ISimpleAudioVolume_SetMasterVolume(T)(T* this_, float fLevel, LPCGUID EventContext) {return this_.lpVtbl.SetMasterVolume(this_,fLevel, EventContext);}
HRESULT ISimpleAudioVolume_GetMasterVolume(T)(T* this_, float *pfLevel) {return this_.lpVtbl.GetMasterVolume(this_,pfLevel);}
HRESULT ISimpleAudioVolume_SetMute(T)(T* this_, BOOL bMute, LPCGUID EventContext) {return this_.lpVtbl.SetMute(this_,bMute, EventContext);}
HRESULT ISimpleAudioVolume_GetMute(T)(T* this_, BOOL *pbMute) {return this_.lpVtbl.GetMute(this_,pbMute);}

// AudioRenderClient //////////////////////////////////////
struct IAudioRenderClient {
    IAudioRenderClientVtable* lpVtbl;
}

struct IAudioRenderClientVtable {
    extern(Windows): @nogc: nothrow:
    alias This_ = IAudioRenderClient*;
    HRESULT function(This_, REFIID riid, void **ppvObject) QueryInterface;
    ULONG function(This_, ) AddRef;
    ULONG function(This_, ) Release;
    HRESULT function(This_, UINT32 NumFramesRequested, BYTE **ppData) GetBuffer;
    HRESULT function(This_, UINT32 NumFramesWritten, DWORD dwFlags) ReleaseBuffer;
}
HRESULT IAudioRenderClient_QueryInterface(T)(T* this_, REFIID riid, void **ppvObject) {return this_.lpVtbl.QueryInterface(this_,riid, ppvObject);}
ULONG IAudioRenderClient_AddRef(T)(T* this_, ) {return this_.lpVtbl.AddRef(this_,);}
ULONG IAudioRenderClient_Release(T)(T* this_, ) {return this_.lpVtbl.Release(this_,);}
HRESULT IAudioRenderClient_GetBuffer(T)(T* this_, UINT32 NumFramesRequested, BYTE **ppData) {return this_.lpVtbl.GetBuffer(this_,NumFramesRequested, ppData);}
HRESULT IAudioRenderClient_ReleaseBuffer(T)(T* this_, UINT32 NumFramesWritten, DWORD dwFlags) {return this_.lpVtbl.ReleaseBuffer(this_,NumFramesWritten, dwFlags);}

// MMDeviceCollection //////////////////////////////////////
struct IMMDeviceCollection {
    IMMDeviceCollectionVtable* lpVtbl;
}

struct IMMDeviceCollectionVtable {
    extern(Windows): @nogc: nothrow:
    alias This_ = IMMDeviceCollection*;
    HRESULT function(This_, REFIID riid, void **ppvObject) QueryInterface;
    ULONG function(This_, ) AddRef;
    ULONG function(This_, ) Release;
    HRESULT function(This_, UINT *pcDevices) GetCount;
    HRESULT function(This_, UINT nDevice, IMMDevice **ppDevice) Item;
}
HRESULT IMMDeviceCollection_QueryInterface(T)(T* this_, REFIID riid, void **ppvObject) {return this_.lpVtbl.QueryInterface(this_,riid, ppvObject);}
ULONG IMMDeviceCollection_AddRef(T)(T* this_, ) {return this_.lpVtbl.AddRef(this_,);}
ULONG IMMDeviceCollection_Release(T)(T* this_, ) {return this_.lpVtbl.Release(this_,);}
HRESULT IMMDeviceCollection_GetCount(T)(T* this_, UINT *pcDevices) {return this_.lpVtbl.GetCount(this_,pcDevices);}
HRESULT IMMDeviceCollection_Item(T)(T* this_, UINT nDevice, IMMDevice **ppDevice) {return this_.lpVtbl.Item(this_,nDevice, ppDevice);}

// AudioCaptureClient ////////////////////////////////
struct IAudioCaptureClient {
    IAudioCaptureClientVtable* lpVtbl;
}

struct IAudioCaptureClientVtable {
    extern(Windows): @nogc: nothrow:
    alias This_ = IAudioCaptureClient*;
    HRESULT function(This_, REFIID riid, void **ppvObject) QueryInterface;
    ULONG function(This_, ) AddRef;
    ULONG function(This_, ) Release;
    HRESULT function(This_, BYTE **ppData, UINT32 *pNumFramesToRead, DWORD *pdwFlags, UINT64 *pu64DevicePosition, UINT64 *pu64QPCPosition) GetBuffer;
    HRESULT function(This_, UINT32 NumFramesRead) ReleaseBuffer;
    HRESULT function(This_, UINT32 *pNumFramesInNextPacket) GetNextPacketSize;
}
HRESULT IAudioCaptureClient_QueryInterface(T)(T* this_, REFIID riid, void **ppvObject) {return this_.lpVtbl.QueryInterface(this_,riid, ppvObject);}
ULONG IAudioCaptureClient_AddRef(T)(T* this_, ) {return this_.lpVtbl.AddRef(this_,);}
ULONG IAudioCaptureClient_Release(T)(T* this_, ) {return this_.lpVtbl.Release(this_,);}
HRESULT IAudioCaptureClient_GetBuffer(T)(T* this_, BYTE **ppData, UINT32 *pNumFramesToRead, DWORD *pdwFlags, UINT64 *pu64DevicePosition, UINT64 *pu64QPCPosition) {return this_.lpVtbl.GetBuffer(this_,ppData, pNumFramesToRead, pdwFlags, pu64DevicePosition, pu64QPCPosition);}
HRESULT IAudioCaptureClient_ReleaseBuffer(T)(T* this_, UINT32 NumFramesRead) {return this_.lpVtbl.ReleaseBuffer(this_,NumFramesRead);}
HRESULT IAudioCaptureClient_GetNextPacketSize(T)(T* this_, UINT32 *pNumFramesInNextPacket) {return this_.lpVtbl.GetNextPacketSize(this_,pNumFramesInNextPacket);}

// PropertyStore //////////////////////////////
struct IPropertyStore {
    IPropertyStoreVtable* lpVtbl;
}

struct IPropertyStoreVtable {
    extern(Windows): @nogc: nothrow:
    alias This_ = IPropertyStore*;
    HRESULT function(This_, REFIID riid, void **ppvObject) QueryInterface;
    ULONG function(This_, ) AddRef;
    ULONG function(This_, ) Release;
    HRESULT function(This_, DWORD *cProps) GetCount;
    HRESULT function(This_, DWORD iProp, PROPERTYKEY *pkey) GetAt;
    HRESULT function(This_, PROPERTYKEY* key, PROPVARIANT *pv) GetValue;
    HRESULT function(This_, PROPERTYKEY* key, PROPVARIANT* propvar) SetValue;
    HRESULT function(This_, ) Commit;
}
HRESULT IPropertyStore_QueryInterface(T)(T* this_, REFIID riid, void **ppvObject) {return this_.lpVtbl.QueryInterface(this_,riid, ppvObject);}
ULONG IPropertyStore_AddRef(T)(T* this_, ) {return this_.lpVtbl.AddRef(this_,);}
ULONG IPropertyStore_Release(T)(T* this_, ) {return this_.lpVtbl.Release(this_,);}
HRESULT IPropertyStore_GetCount(T)(T* this_, DWORD *cProps) {return this_.lpVtbl.GetCount(this_,cProps);}
HRESULT IPropertyStore_GetAt(T)(T* this_, DWORD iProp, PROPERTYKEY *pkey) {return this_.lpVtbl.GetAt(this_,iProp, pkey);}
HRESULT IPropertyStore_GetValue(T)(T* this_, PROPERTYKEY* key, PROPVARIANT *pv) {return this_.lpVtbl.GetValue(this_,key, pv);}
HRESULT IPropertyStore_SetValue(T)(T* this_, PROPERTYKEY* key, PROPVARIANT* propvar) {return this_.lpVtbl.SetValue(this_,key, propvar);}
HRESULT IPropertyStore_Commit(T)(T* this_, ) {return this_.lpVtbl.Commit(this_,);}

// MMEndpoint //////////////////////////////
struct IMMEndpoint {
    IMMEndpointVtable* lpVtbl;
}

struct IMMEndpointVtable {
    extern(Windows): @nogc: nothrow:
    alias This_ = IMMEndpoint*;
    HRESULT function(This_, REFIID riid, void **ppvObject) QueryInterface;
    ULONG function(This_, ) AddRef;
    ULONG function(This_, ) Release;
    HRESULT function(This_, EDataFlow *pDataFlow) GetDataFlow;
}
HRESULT IMMEndpoint_QueryInterface(T)(T* this_, REFIID riid, void **ppvObject) {return this_.lpVtbl.QueryInterface(this_,riid, ppvObject);}
ULONG IMMEndpoint_AddRef(T)(T* this_, ) {return this_.lpVtbl.AddRef(this_,);}
ULONG IMMEndpoint_Release(T)(T* this_, ) {return this_.lpVtbl.Release(this_,);}
HRESULT IMMEndpoint_GetDataFlow(T)(T* this_, EDataFlow *pDataFlow) {return this_.lpVtbl.GetDataFlow(this_,pDataFlow);}

// Audio Client //////////////////////////////
struct IAudioClient {
    IAudioClientVtable* lpVtbl;
}

struct IAudioClientVtable {
    extern(Windows): @nogc: nothrow:
    alias This_ = IAudioClient*;
    HRESULT function(This_, REFIID riid, void **ppvObject) QueryInterface;
    ULONG function(This_, ) AddRef;
    ULONG function(This_, ) Release;
    HRESULT function(This_, AUDCLNT_SHAREMODE ShareMode, DWORD StreamFlags, REFERENCE_TIME hnsBufferDuration, REFERENCE_TIME hnsPeriodicity, WAVEFORMATEX *pFormat, LPCGUID AudioSessionGuid) Initialize;
    HRESULT function(This_, UINT32 *pNumBufferFrames) GetBufferSize;
    HRESULT function(This_, REFERENCE_TIME *phnsLatency) GetStreamLatency;
    HRESULT function(This_, UINT32 *pNumPaddingFrames) GetCurrentPadding;
    HRESULT function(This_, AUDCLNT_SHAREMODE ShareMode, WAVEFORMATEX *pFormat, WAVEFORMATEX **ppClosestMatch) IsFormatSupported;
    HRESULT function(This_, WAVEFORMATEX **ppDeviceFormat) GetMixFormat;
    HRESULT function(This_, REFERENCE_TIME *phnsDefaultDevicePeriod, REFERENCE_TIME *phnsMinimumDevicePeriod) GetDevicePeriod;
    HRESULT function(This_, ) Start;
    HRESULT function(This_, ) Stop;
    HRESULT function(This_, ) Reset;
    HRESULT function(This_, HANDLE eventHandle) SetEventHandle;
    HRESULT function(This_, REFIID riid, void **ppv) GetService;
}
HRESULT IAudioClient_QueryInterface(T)(T* this_, REFIID riid, void **ppvObject) {return this_.lpVtbl.QueryInterface(this_,riid, ppvObject);}
ULONG IAudioClient_AddRef(T)(T* this_, ) {return this_.lpVtbl.AddRef(this_,);}
ULONG IAudioClient_Release(T)(T* this_, ) {return this_.lpVtbl.Release(this_,);}
HRESULT IAudioClient_Initialize(T)(T* this_, AUDCLNT_SHAREMODE ShareMode, DWORD StreamFlags, REFERENCE_TIME hnsBufferDuration, REFERENCE_TIME hnsPeriodicity, WAVEFORMATEX *pFormat, LPCGUID AudioSessionGuid) {return this_.lpVtbl.Initialize(this_,ShareMode, StreamFlags, hnsBufferDuration, hnsPeriodicity, pFormat, AudioSessionGuid);}
HRESULT IAudioClient_GetBufferSize(T)(T* this_, UINT32 *pNumBufferFrames) {return this_.lpVtbl.GetBufferSize(this_,pNumBufferFrames);}
HRESULT IAudioClient_GetStreamLatency(T)(T* this_, REFERENCE_TIME *phnsLatency) {return this_.lpVtbl.GetStreamLatency(this_,phnsLatency);}
HRESULT IAudioClient_GetCurrentPadding(T)(T* this_, UINT32 *pNumPaddingFrames) {return this_.lpVtbl.GetCurrentPadding(this_,pNumPaddingFrames);}
HRESULT IAudioClient_IsFormatSupported(T)(T* this_, AUDCLNT_SHAREMODE ShareMode, WAVEFORMATEX *pFormat, WAVEFORMATEX **ppClosestMatch) {return this_.lpVtbl.IsFormatSupported(this_,ShareMode, pFormat, ppClosestMatch);}
HRESULT IAudioClient_GetMixFormat(T)(T* this_, WAVEFORMATEX **ppDeviceFormat) {return this_.lpVtbl.GetMixFormat(this_,ppDeviceFormat);}
HRESULT IAudioClient_GetDevicePeriod(T)(T* this_, REFERENCE_TIME *phnsDefaultDevicePeriod, REFERENCE_TIME *phnsMinimumDevicePeriod) {return this_.lpVtbl.GetDevicePeriod(this_,phnsDefaultDevicePeriod, phnsMinimumDevicePeriod);}
HRESULT IAudioClient_Start(T)(T* this_, ) {return this_.lpVtbl.Start(this_,);}
HRESULT IAudioClient_Stop(T)(T* this_, ) {return this_.lpVtbl.Stop(this_,);}
HRESULT IAudioClient_Reset(T)(T* this_, ) {return this_.lpVtbl.Reset(this_,);}
HRESULT IAudioClient_SetEventHandle(T)(T* this_, HANDLE eventHandle) {return this_.lpVtbl.SetEventHandle(this_,eventHandle);}
HRESULT IAudioClient_GetService(T)(T* this_, REFIID riid, void **ppv) {return this_.lpVtbl.GetService(this_,riid, ppv);}

// AudioSessionControl ///////////////////////
struct IAudioSessionControl {
    IAudioSessionControlVtable* lpVtbl;
}

struct IAudioSessionControlVtable {
    extern(Windows): @nogc: nothrow:
    alias This_ = IAudioSessionControl*;
    HRESULT function(This_, REFIID riid, void **ppvObject) QueryInterface;
    ULONG function(This_, ) AddRef;
    ULONG function(This_, ) Release;
    HRESULT function(This_, AudioSessionState *pRetVal) GetState;
    HRESULT function(This_, LPWSTR *pRetVal) GetDisplayName;
    HRESULT function(This_, LPCWSTR Value, LPCGUID EventContext) SetDisplayName;
    HRESULT function(This_, LPWSTR *pRetVal) GetIconPath;
    HRESULT function(This_, LPCWSTR Value, LPCGUID EventContext) SetIconPath;
    HRESULT function(This_, GUID *pRetVal) GetGroupingParam;
    HRESULT function(This_, LPCGUID Override, LPCGUID EventContext) SetGroupingParam;
    HRESULT function(This_, IAudioSessionEvents *NewNotifications) RegisterAudioSessionNotification;
    HRESULT function(This_, IAudioSessionEvents *NewNotifications) UnregisterAudioSessionNotification;
}
HRESULT IAudioSessionControl_QueryInterface(T)(T* this_, REFIID riid, void **ppvObject) {return this_.lpVtbl.QueryInterface(this_,riid, ppvObject);}
ULONG IAudioSessionControl_AddRef(T)(T* this_, ) {return this_.lpVtbl.AddRef(this_,);}
ULONG IAudioSessionControl_Release(T)(T* this_, ) {return this_.lpVtbl.Release(this_,);}
HRESULT IAudioSessionControl_GetState(T)(T* this_, AudioSessionState *pRetVal) {return this_.lpVtbl.GetState(this_,pRetVal);}
HRESULT IAudioSessionControl_GetDisplayName(T)(T* this_, LPWSTR *pRetVal) {return this_.lpVtbl.GetDisplayName(this_,pRetVal);}
HRESULT IAudioSessionControl_SetDisplayName(T)(T* this_, LPCWSTR Value, LPCGUID EventContext) {return this_.lpVtbl.SetDisplayName(this_,Value, EventContext);}
HRESULT IAudioSessionControl_GetIconPath(T)(T* this_, LPWSTR *pRetVal) {return this_.lpVtbl.GetIconPath(this_,pRetVal);}
HRESULT IAudioSessionControl_SetIconPath(T)(T* this_, LPCWSTR Value, LPCGUID EventContext) {return this_.lpVtbl.SetIconPath(this_,Value, EventContext);}
HRESULT IAudioSessionControl_GetGroupingParam(T)(T* this_, GUID *pRetVal) {return this_.lpVtbl.GetGroupingParam(this_,pRetVal);}
HRESULT IAudioSessionControl_SetGroupingParam(T)(T* this_, LPCGUID Override, LPCGUID EventContext) {return this_.lpVtbl.SetGroupingParam(this_,Override, EventContext);}
HRESULT IAudioSessionControl_RegisterAudioSessionNotification(T)(T* this_, IAudioSessionEvents *NewNotifications) {return this_.lpVtbl.RegisterAudioSessionNotification(this_,NewNotifications);}
HRESULT IAudioSessionControl_UnregisterAudioSessionNotification(T)(T* this_, IAudioSessionEvents *NewNotifications) {return this_.lpVtbl.UnregisterAudioSessionNotification(this_,NewNotifications);}

// PropVariant /////////////////////////
HRESULT PropVariantClear(PROPVARIANT* pvar);
pragma(inline, true) void PropVariantInit(PROPVARIANT* pvar ) {
    import core.stdc.string: memset;
    memset(pvar, 0, PROPVARIANT.sizeof);
}

struct BLOB {
    ULONG cbSize;
    BYTE *pBlobData;
}

struct PROPVARIANT {
    ushort vt; // VARTYPE
    ushort wReserved1;
    ushort wReserved2;
    ushort wReserved3;
    union {
        CHAR cVal;
        UCHAR bVal;
        SHORT iVal;
        USHORT uiVal;
        LONG lVal;
        ULONG ulVal;
        INT intVal;
        UINT uintVal;
        LARGE_INTEGER hVal;
        ULARGE_INTEGER uhVal;
        FLOAT fltVal;
        // ... many more omitted
        LPWSTR pwszVal;
        BLOB blob;
    }
}
static assert(PROPVARIANT.sizeof == (size_t.sizeof == 4) ? 16 : 24);
static assert(PROPVARIANT.pwszVal.offsetof == 8);

alias REFERENCE_TIME = long;

struct PROPERTYKEY {
    GUID fmtid;
    DWORD pid;
}

PROPERTYKEY PKEY_Device_FriendlyName = PROPERTYKEY(
    GUID(0xa45c254e, 0xdf1c, 0x4efd, [0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0]),
    14
);

PROPERTYKEY PKEY_AudioEngine_DeviceFormat = PROPERTYKEY(
    GUID(0xf19f064d, 0x82c, 0x4e27, [0xbc, 0x73, 0x68, 0x82, 0xa1, 0xbb, 0x8e, 0x4c]),
    0
);

enum WAVE_FORMAT_EXTENSIBLE = 0xFFFE;

struct WAVEFORMATEX {
    align(2):
    WORD  wFormatTag;
    WORD  nChannels;
    DWORD nSamplesPerSec;
    DWORD nAvgBytesPerSec;
    WORD  nBlockAlign;
    WORD  wBitsPerSample;
    WORD  cbSize;
}
static assert(WAVEFORMATEX.sizeof == 18);

struct WAVEFORMATEXTENSIBLE {
    WAVEFORMATEX    Format;
    struct USamples {
        union {
            WORD wValidBitsPerSample;
            WORD wSamplesPerBlock;
            WORD wReserved;
        }
    }
    USamples Samples;
    DWORD           dwChannelMask;
    GUID            SubFormat;
}

static assert(WAVEFORMATEXTENSIBLE.sizeof == 40);

alias AUDCLNT_SHAREMODE = int; // C enum
enum {
    AUDCLNT_SHAREMODE_SHARED,
    AUDCLNT_SHAREMODE_EXCLUSIVE
}

alias EDataFlow = int;
enum {
    eRender	= 0,
    eCapture = ( eRender + 1 ) ,
    eAll = ( eCapture + 1 ) ,
    EDataFlow_enum_count	= ( eAll + 1 )
}
alias ERole = int;
enum {
    eConsole	= 0,
    eMultimedia	= ( eConsole + 1 ) ,
    eCommunications	= ( eMultimedia + 1 ) ,
    ERole_enum_count	= ( eCommunications + 1 )
}

// ksmedia.h
enum SPEAKER_FRONT_LEFT            = 0x1;
enum SPEAKER_FRONT_RIGHT           = 0x2;
enum SPEAKER_FRONT_CENTER          = 0x4;
enum SPEAKER_LOW_FREQUENCY         = 0x8;
enum SPEAKER_BACK_LEFT             = 0x10;
enum SPEAKER_BACK_RIGHT            = 0x20;
enum SPEAKER_FRONT_LEFT_OF_CENTER  = 0x40;
enum SPEAKER_FRONT_RIGHT_OF_CENTER = 0x80;
enum SPEAKER_BACK_CENTER           = 0x100;
enum SPEAKER_SIDE_LEFT             = 0x200;
enum SPEAKER_SIDE_RIGHT            = 0x400;
enum SPEAKER_TOP_CENTER            = 0x800;
enum SPEAKER_TOP_FRONT_LEFT        = 0x1000;
enum SPEAKER_TOP_FRONT_CENTER      = 0x2000;
enum SPEAKER_TOP_FRONT_RIGHT       = 0x4000;
enum SPEAKER_TOP_BACK_LEFT         = 0x8000;
enum SPEAKER_TOP_BACK_CENTER       = 0x10000;
enum SPEAKER_TOP_BACK_RIGHT        = 0x20000;
