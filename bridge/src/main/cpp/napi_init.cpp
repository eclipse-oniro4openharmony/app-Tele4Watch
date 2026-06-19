#include "napi/native_api.h"
#include "td_bridge.h"

static napi_value InitBridgeModule(napi_env env, napi_value exports) {
  return td_bridge::Init(env, exports);
}

static napi_module g_bridgeModule = {
    1,
    0,
    nullptr,
    InitBridgeModule,
    "bridge",
    nullptr,
    {0},
};

extern "C" __attribute__((constructor)) void RegisterBridgeModule(void) {
  napi_module_register(&g_bridgeModule);
}
