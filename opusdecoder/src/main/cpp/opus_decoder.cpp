#include "opus_decoder.h"

#include "opus_decode.h"
#include "opus_encode.h"

#include <hilog/log.h>

#include <cstring>
#include <string>
#include <vector>

namespace {
constexpr unsigned int OPUS_LOG_DOMAIN = 0x2026;
constexpr const char *OPUS_LOG_TAG = "OpusDecoder";

bool Check(napi_env env, napi_status status, const char *message) {
  if (status == napi_ok) {
    return true;
  }
  OH_LOG_Print(LOG_APP, LOG_ERROR, OPUS_LOG_DOMAIN, OPUS_LOG_TAG, "%{public}s (status=%{public}d)", message,
               static_cast<int>(status));
  napi_throw_error(env, nullptr, message);
  return false;
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

napi_value MakeBoolean(napi_env env, bool value) {
  napi_value result = nullptr;
  if (!Check(env, napi_get_boolean(env, value, &result), "Failed to create boolean result")) {
    return nullptr;
  }
  return result;
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

void ThrowError(napi_env env, const std::string &message) {
  napi_throw_error(env, nullptr, message.c_str());
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

bool ReadArrayBufferArg(napi_env env, napi_value value, void *&data, size_t &byteLength, const char *name) {
  bool isArrayBuffer = false;
  if (!Check(env, napi_is_arraybuffer(env, value, &isArrayBuffer), "Failed to inspect array buffer argument")) {
    return false;
  }
  if (!isArrayBuffer) {
    napi_throw_type_error(env, nullptr, name);
    return false;
  }
  return Check(env, napi_get_arraybuffer_info(env, value, &data, &byteLength), "Failed to read array buffer argument");
}

napi_value MakeVoiceRecordResult(napi_env env, const opus_decoder::VoiceRecordResult &result) {
  napi_value response = nullptr;
  if (!Check(env, napi_create_object(env, &response), "Failed to create voice-record result object")) {
    return nullptr;
  }

  napi_value duration = MakeInt32(env, result.durationSec);
  if (duration == nullptr) {
    return nullptr;
  }
  if (!Check(env,
             napi_set_named_property(env, response, "durationSec", duration),
             "Failed to attach voice-record duration")) {
    return nullptr;
  }

  void *waveformBytes = nullptr;
  napi_value waveform = nullptr;
  if (!Check(env,
             napi_create_arraybuffer(env, result.waveform.size(), &waveformBytes, &waveform),
             "Failed to create waveform array buffer")) {
    return nullptr;
  }
  if (!result.waveform.empty()) {
    std::memcpy(waveformBytes, result.waveform.data(), result.waveform.size());
  }
  if (!Check(env,
             napi_set_named_property(env, response, "waveform", waveform),
             "Failed to attach waveform array buffer")) {
    return nullptr;
  }

  return response;
}

napi_value DecodeOpusToWav(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr), "Failed to read callback info")) {
    return nullptr;
  }
  if (argc != 2) {
    napi_throw_type_error(env, nullptr, "decodeOpusToWav(inputPath, outputPath) requires 2 arguments");
    return nullptr;
  }

  std::string inputPath;
  if (!ReadStringArg(env, args[0], inputPath, "inputPath must be a string")) {
    return nullptr;
  }

  std::string outputPath;
  if (!ReadStringArg(env, args[1], outputPath, "outputPath must be a string")) {
    return nullptr;
  }

  OH_LOG_Print(LOG_APP,
               LOG_INFO,
               OPUS_LOG_DOMAIN,
               OPUS_LOG_TAG,
               "decodeOpusToWav input=%{public}s output=%{public}s",
               inputPath.c_str(),
               outputPath.c_str());

  const opus_decoder::OpusDecodeResult result = opus_decoder::DecodeOpusFileToWav(inputPath, outputPath);
  if (!result.success) {
    OH_LOG_Print(LOG_APP,
                 LOG_ERROR,
                 OPUS_LOG_DOMAIN,
                 OPUS_LOG_TAG,
                 "decodeOpusToWav failed: %{public}s",
                 result.error.c_str());
    ThrowError(env, result.error);
    return nullptr;
  }

  OH_LOG_Print(LOG_APP,
               LOG_INFO,
               OPUS_LOG_DOMAIN,
               OPUS_LOG_TAG,
               "decodeOpusToWav ok samples=%{public}lld channels=%{public}d sampleRate=%{public}d",
               static_cast<long long>(result.samplesPerChannel),
               result.channels,
               result.sampleRateHz);
  return MakeString(env, outputPath);
}

napi_value StartVoiceRecordNapi(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr), "Failed to read callback info")) {
    return nullptr;
  }
  if (argc != 2) {
    napi_throw_type_error(env, nullptr, "startVoiceRecord(outputPath, sampleRate) requires 2 arguments");
    return nullptr;
  }

  std::string outputPath;
  if (!ReadStringArg(env, args[0], outputPath, "outputPath must be a string")) {
    return nullptr;
  }

  int32_t sampleRate = 0;
  if (!ReadInt32Arg(env, args[1], sampleRate, "sampleRate must be a number")) {
    return nullptr;
  }

  std::string error;
  if (!opus_decoder::StartVoiceRecord(outputPath, sampleRate, error)) {
    ThrowError(env, error);
    return nullptr;
  }

  OH_LOG_Print(LOG_APP,
               LOG_INFO,
               OPUS_LOG_DOMAIN,
               OPUS_LOG_TAG,
               "startVoiceRecord output=%{public}s sampleRate=%{public}d",
               outputPath.c_str(),
               sampleRate);
  return MakeBoolean(env, true);
}

napi_value WriteVoiceFrameNapi(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr), "Failed to read callback info")) {
    return nullptr;
  }
  if (argc != 2) {
    napi_throw_type_error(env, nullptr, "writeVoiceFrame(pcm, length) requires 2 arguments");
    return nullptr;
  }

  void *frameBytes = nullptr;
  size_t frameByteLength = 0;
  if (!ReadArrayBufferArg(env, args[0], frameBytes, frameByteLength, "pcm must be an ArrayBuffer")) {
    return nullptr;
  }

  int32_t requestedByteLength = 0;
  if (!ReadInt32Arg(env, args[1], requestedByteLength, "length must be a number")) {
    return nullptr;
  }
  if (requestedByteLength < 0) {
    napi_throw_range_error(env, nullptr, "length must not be negative");
    return nullptr;
  }
  const size_t byteLength = static_cast<size_t>(requestedByteLength);
  if (byteLength > frameByteLength) {
    napi_throw_range_error(env, nullptr, "length must not exceed the ArrayBuffer byteLength");
    return nullptr;
  }

  std::string error;
  if (!opus_decoder::WriteVoiceFrame(static_cast<const uint8_t *>(frameBytes), byteLength, error)) {
    ThrowError(env, error);
    return nullptr;
  }

  return MakeBoolean(env, true);
}

napi_value StopVoiceRecordNapi(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  if (!Check(env, napi_get_cb_info(env, info, &argc, nullptr, nullptr, nullptr), "Failed to read callback info")) {
    return nullptr;
  }

  const opus_decoder::VoiceRecordResult result = opus_decoder::StopVoiceRecord();
  if (!result.success) {
    ThrowError(env, result.error);
    return nullptr;
  }

  OH_LOG_Print(LOG_APP,
               LOG_INFO,
               OPUS_LOG_DOMAIN,
               OPUS_LOG_TAG,
               "stopVoiceRecord path=%{public}s mime=%{public}s container=%{public}s codec=%{public}s "
               "sizeBytes=%{public}lld durationSec=%{public}d durationMs=%{public}lld sampleRateHz=%{public}d "
               "channels=%{public}d targetBitrateBps=%{public}d averageBitrateBps=%{public}lld pages=%{public}lld "
               "waveformBytes=%{public}zu",
               result.outputPath.c_str(),
               result.mimeType.c_str(),
               result.containerFormat.c_str(),
               result.audioCodec.c_str(),
               static_cast<long long>(result.fileSizeBytes),
               result.durationSec,
               static_cast<long long>(result.durationMs),
               result.sampleRateHz,
               result.channelCount,
               static_cast<int>(result.targetBitrateBps),
               static_cast<long long>(result.averageBitrateBps),
               static_cast<long long>(result.pageCount),
               result.waveform.size());
  return MakeVoiceRecordResult(env, result);
}
}  // namespace

namespace opus_decoder {
napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
      {"decodeOpusToWav", nullptr, DecodeOpusToWav, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"startVoiceRecord", nullptr, StartVoiceRecordNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"writeVoiceFrame", nullptr, WriteVoiceFrameNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"stopVoiceRecord", nullptr, StopVoiceRecordNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
  };

  if (!Check(env,
             napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties),
             "Failed to define NAPI exports")) {
    return nullptr;
  }
  OH_LOG_Print(LOG_APP, LOG_INFO, OPUS_LOG_DOMAIN, OPUS_LOG_TAG, "Opus decoder NAPI module initialized");
  return exports;
}
}  // namespace opus_decoder
