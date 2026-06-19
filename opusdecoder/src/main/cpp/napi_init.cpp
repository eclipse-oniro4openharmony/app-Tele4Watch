#include "napi/native_api.h"
#include "opus_decoder.h"

static napi_value InitOpusDecoderModule(napi_env env, napi_value exports) {
  return opus_decoder::Init(env, exports);
}

static napi_module g_opusDecoderModule = {
    1,
    0,
    nullptr,
    InitOpusDecoderModule,
    "opusdecoder",
    nullptr,
    {0},
};

extern "C" __attribute__((constructor)) void RegisterOpusDecoderModule(void) {
  napi_module_register(&g_opusDecoderModule);
}
