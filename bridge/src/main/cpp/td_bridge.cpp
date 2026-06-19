#include "td_bridge.h"

#include "td/telegram/td_json_client.h"
#include <hilog/log.h>

#include <mutex>
#include <string>
#include <vector>

namespace {
constexpr unsigned int TD_LOG_DOMAIN = 0x2026;
constexpr const char *TD_LOG_TAG = "TdBridge";
constexpr size_t LOG_PREVIEW_MAX = 220;

std::mutex g_td_mutex;

std::string PreviewForLog(const std::string &value) {
  if (value.size() <= LOG_PREVIEW_MAX) {
    return value;
  }
  return value.substr(0, LOG_PREVIEW_MAX) + "...(truncated)";
}

bool Check(napi_env env, napi_status status, const char *message) {
  if (status == napi_ok) {
    return true;
  }
  OH_LOG_Print(LOG_APP, LOG_ERROR, TD_LOG_DOMAIN, TD_LOG_TAG, "%{public}s (status=%{public}d)", message,
               static_cast<int>(status));
  napi_throw_error(env, nullptr, message);
  return false;
}

bool ReadInt32Arg(napi_env env, napi_value value, int32_t &out, const char *name) {
  napi_valuetype type = napi_undefined;
  if (!Check(env, napi_typeof(env, value, &type), "Failed to read argument type")) {
    return false;
  }
  if (type != napi_number) {
    napi_throw_type_error(env, nullptr, name);
    return false;
  }
  return Check(env, napi_get_value_int32(env, value, &out), "Failed to read number argument");
}

bool ReadDoubleArg(napi_env env, napi_value value, double &out, const char *name) {
  napi_valuetype type = napi_undefined;
  if (!Check(env, napi_typeof(env, value, &type), "Failed to read argument type")) {
    return false;
  }
  if (type != napi_number) {
    napi_throw_type_error(env, nullptr, name);
    return false;
  }
  return Check(env, napi_get_value_double(env, value, &out), "Failed to read double argument");
}

bool ReadStringArg(napi_env env, napi_value value, std::string &out, const char *name) {
  napi_valuetype type = napi_undefined;
  if (!Check(env, napi_typeof(env, value, &type), "Failed to read argument type")) {
    return false;
  }
  if (type != napi_string) {
    napi_throw_type_error(env, nullptr, name);
    return false;
  }

  size_t size = 0;
  if (!Check(env, napi_get_value_string_utf8(env, value, nullptr, 0, &size), "Failed to read string length")) {
    return false;
  }

  std::vector<char> buffer(size + 1, 0);
  if (!Check(env,
             napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &size),
             "Failed to read string data")) {
    return false;
  }

  out.assign(buffer.data(), size);
  return true;
}

napi_value MakeInt32(napi_env env, int32_t value) {
  napi_value result = nullptr;
  if (!Check(env, napi_create_int32(env, value, &result), "Failed to create int32 result")) {
    return nullptr;
  }
  return result;
}

napi_value MakeString(napi_env env, const std::string &value) {
  napi_value result = nullptr;
  if (!Check(env,
             napi_create_string_utf8(env, value.c_str(), value.size(), &result),
             "Failed to create string result")) {
    return nullptr;
  }
  return result;
}

std::string CopyTdResult(const char *value) {
  if (value == nullptr) {
    return "";
  }
  return value;
}

napi_value CreateClientId(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  if (!Check(env, napi_get_cb_info(env, info, &argc, nullptr, nullptr, nullptr), "Failed to read callback info")) {
    return nullptr;
  }
  std::lock_guard<std::mutex> lock(g_td_mutex);
  int32_t clientId = td_create_client_id();
  OH_LOG_Print(LOG_APP, LOG_INFO, TD_LOG_DOMAIN, TD_LOG_TAG, "createClientId -> %{public}d", clientId);
  return MakeInt32(env, clientId);
}

napi_value Send(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr), "Failed to read callback info")) {
    return nullptr;
  }
  if (argc != 2) {
    napi_throw_type_error(env, nullptr, "send(clientId, requestJson) requires 2 arguments");
    return nullptr;
  }

  int32_t clientId = 0;
  if (!ReadInt32Arg(env, args[0], clientId, "clientId must be a number")) {
    return nullptr;
  }

  std::string requestJson;
  if (!ReadStringArg(env, args[1], requestJson, "requestJson must be a string")) {
    return nullptr;
  }

  std::string preview = PreviewForLog(requestJson);
  std::lock_guard<std::mutex> lock(g_td_mutex);
  OH_LOG_Print(LOG_APP, LOG_DEBUG, TD_LOG_DOMAIN, TD_LOG_TAG, "send client=%{public}d req=%{public}s", clientId,
               preview.c_str());
  td_send(clientId, requestJson.c_str());

  napi_value result = nullptr;
  if (!Check(env, napi_get_undefined(env, &result), "Failed to create undefined result")) {
    return nullptr;
  }
  return result;
}

napi_value Receive(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr), "Failed to read callback info")) {
    return nullptr;
  }

  double timeoutSeconds = 0.0;
  if (argc == 1 && !ReadDoubleArg(env, args[0], timeoutSeconds, "timeoutSeconds must be a number")) {
    return nullptr;
  }

  std::lock_guard<std::mutex> lock(g_td_mutex);
  const char *raw = td_receive(timeoutSeconds);
  std::string response = CopyTdResult(raw);
  if (!response.empty()) {
    std::string preview = PreviewForLog(response);
    OH_LOG_Print(LOG_APP, LOG_DEBUG, TD_LOG_DOMAIN, TD_LOG_TAG, "receive timeout=%{public}.3f -> %{public}s",
                 timeoutSeconds, preview.c_str());
  }
  return MakeString(env, response);
}

napi_value Execute(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr), "Failed to read callback info")) {
    return nullptr;
  }
  if (argc != 1) {
    napi_throw_type_error(env, nullptr, "execute(requestJson) requires 1 argument");
    return nullptr;
  }

  std::string requestJson;
  if (!ReadStringArg(env, args[0], requestJson, "requestJson must be a string")) {
    return nullptr;
  }

  std::string requestPreview = PreviewForLog(requestJson);
  std::lock_guard<std::mutex> lock(g_td_mutex);
  OH_LOG_Print(LOG_APP, LOG_DEBUG, TD_LOG_DOMAIN, TD_LOG_TAG, "execute req=%{public}s", requestPreview.c_str());
  const char *raw = td_execute(requestJson.c_str());
  std::string response = CopyTdResult(raw);
  std::string responsePreview = PreviewForLog(response);
  OH_LOG_Print(LOG_APP, LOG_DEBUG, TD_LOG_DOMAIN, TD_LOG_TAG, "execute resp=%{public}s", responsePreview.c_str());
  return MakeString(env, response);
}

napi_value SetLogVerbosityLevel(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr), "Failed to read callback info")) {
    return nullptr;
  }
  if (argc != 1) {
    napi_throw_type_error(env, nullptr, "setLogVerbosityLevel(level) requires 1 argument");
    return nullptr;
  }

  int32_t level = 0;
  if (!ReadInt32Arg(env, args[0], level, "level must be a number")) {
    return nullptr;
  }

  std::string request =
      std::string("{\"@type\":\"setLogVerbosityLevel\",\"new_verbosity_level\":") + std::to_string(level) + "}";

  std::lock_guard<std::mutex> lock(g_td_mutex);
  OH_LOG_Print(LOG_APP, LOG_INFO, TD_LOG_DOMAIN, TD_LOG_TAG, "setLogVerbosityLevel -> %{public}d", level);
  const char *raw = td_execute(request.c_str());
  return MakeString(env, CopyTdResult(raw));
}
}  // namespace

namespace td_bridge {
napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
      {"createClientId", nullptr, CreateClientId, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"send", nullptr, Send, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"receive", nullptr, Receive, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"execute", nullptr, Execute, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"setLogVerbosityLevel", nullptr, SetLogVerbosityLevel, nullptr, nullptr, nullptr, napi_default, nullptr},
  };

  if (!Check(env,
             napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties),
             "Failed to define NAPI exports")) {
    return nullptr;
  }
  OH_LOG_Print(LOG_APP, LOG_INFO, TD_LOG_DOMAIN, TD_LOG_TAG, "TD bridge NAPI module initialized");
  return exports;
}
}  // namespace td_bridge
