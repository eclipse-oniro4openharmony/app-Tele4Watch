#include "tgcall_native.h"

#include "base64_util.h"
#include "diagnostic_tgcall_instance.h"
#include "real_tgcall_factory_registry.h"
#include "tgcall_logging.h"
#include "tgcall_session.h"
#include "tgcalls/CryptoHelper.h"
#include "tgcalls/Instance.h"
#include "tgcalls/v2_4_0_0/Signaling_4_0_0.h"
#include "tgcalls/v2/Signaling.h"

#include <hilog/log.h>

#include <array>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {
constexpr size_t kKeySize = tgcall::kTgCallEncryptionKeySize;
constexpr size_t kMessageKeySize = 16;
constexpr size_t kSequenceSize = 4;

std::mutex g_sessionsMutex;
std::unordered_map<int32_t, tgcall::TgCallSession> g_sessions;
int32_t g_nextInstanceId = 1;

bool Check(napi_env env, napi_status status, const char *message) {
  if (status == napi_ok) {
    return true;
  }
  OH_LOG_Print(LOG_APP, LOG_ERROR, tgcall::kTgCallLogDomain, tgcall::kTgCallLogTag, "%{public}s (status=%{public}d)", message,
               static_cast<int>(status));
  napi_throw_error(env, nullptr, message);
  return false;
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

napi_value MakeStringArray(napi_env env, const std::vector<std::string> &values) {
  napi_value result = nullptr;
  if (!Check(env, napi_create_array_with_length(env, values.size(), &result), "Failed to create string array")) {
    return nullptr;
  }
  for (size_t index = 0; index < values.size(); index += 1) {
    napi_value item = nullptr;
    if (!Check(env,
               napi_create_string_utf8(env, values[index].c_str(), values[index].size(), &item),
               "Failed to create string array item")) {
      return nullptr;
    }
    if (!Check(env,
               napi_set_element(env, result, static_cast<uint32_t>(index), item),
               "Failed to set string array item")) {
      return nullptr;
    }
  }
  return result;
}

std::string JoinStrings(const std::vector<std::string> &values) {
  std::string result;
  for (size_t index = 0; index < values.size(); index += 1) {
    if (index > 0) {
      result += ",";
    }
    result += values[index];
  }
  return result;
}

bool ReadStringArgument(napi_env env, napi_value value, const char *name, std::string &result) {
  napi_valuetype valueType = napi_undefined;
  if (!Check(env, napi_typeof(env, value, &valueType), "Failed to read argument type")) {
    return false;
  }
  if (valueType != napi_string) {
    std::string message = std::string("Expected string argument: ") + name;
    napi_throw_type_error(env, nullptr, message.c_str());
    return false;
  }

  size_t valueLength = 0;
  if (!Check(env, napi_get_value_string_utf8(env, value, nullptr, 0, &valueLength), "Failed to read string length")) {
    return false;
  }

  std::vector<char> buffer(valueLength + 1, '\0');
  size_t copiedLength = 0;
  if (!Check(env,
             napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &copiedLength),
             "Failed to read string argument")) {
    return false;
  }
  result.assign(buffer.data(), copiedLength);
  return true;
}

bool ReadBooleanArgument(napi_env env, napi_value value, const char *name, bool &result) {
  napi_valuetype valueType = napi_undefined;
  if (!Check(env, napi_typeof(env, value, &valueType), "Failed to read argument type")) {
    return false;
  }
  if (valueType != napi_boolean) {
    std::string message = std::string("Expected boolean argument: ") + name;
    napi_throw_type_error(env, nullptr, message.c_str());
    return false;
  }
  if (!Check(env, napi_get_value_bool(env, value, &result), "Failed to read boolean argument")) {
    return false;
  }
  return true;
}

bool ReadInt32Argument(napi_env env, napi_value value, const char *name, int32_t &result) {
  napi_valuetype valueType = napi_undefined;
  if (!Check(env, napi_typeof(env, value, &valueType), "Failed to read argument type")) {
    return false;
  }
  if (valueType != napi_number) {
    std::string message = std::string("Expected number argument: ") + name;
    napi_throw_type_error(env, nullptr, message.c_str());
    return false;
  }
  if (!Check(env, napi_get_value_int32(env, value, &result), "Failed to read int32 argument")) {
    return false;
  }
  return true;
}

bool ReadCallbackArguments(napi_env env, napi_callback_info info, napi_value *args, size_t expectedArgc) {
  size_t argc = expectedArgc;
  if (!Check(env, napi_get_cb_info(env, info, &argc, args, nullptr, nullptr), "Failed to read callback info")) {
    return false;
  }
  if (argc < expectedArgc) {
    napi_throw_type_error(env, nullptr, "Missing required tgcall argument");
    return false;
  }
  return true;
}

bool SessionExistsLocked(int32_t instanceId) {
  return g_sessions.find(instanceId) != g_sessions.end();
}

int32_t AllocateInstanceIdLocked() {
  while (SessionExistsLocked(g_nextInstanceId)) {
    g_nextInstanceId++;
    if (g_nextInstanceId <= 0) {
      g_nextInstanceId = 1;
    }
  }

  const int32_t instanceId = g_nextInstanceId++;
  if (g_nextInstanceId <= 0) {
    g_nextInstanceId = 1;
  }
  return instanceId;
}

void WriteBigEndian32(std::vector<uint8_t> &buffer, uint32_t value) {
  buffer.push_back(static_cast<uint8_t>((value >> 24) & 0xff));
  buffer.push_back(static_cast<uint8_t>((value >> 16) & 0xff));
  buffer.push_back(static_cast<uint8_t>((value >> 8) & 0xff));
  buffer.push_back(static_cast<uint8_t>(value & 0xff));
}

uint32_t ReadBigEndian32(const uint8_t *buffer) {
  return (static_cast<uint32_t>(buffer[0]) << 24) |
         (static_cast<uint32_t>(buffer[1]) << 16) |
         (static_cast<uint32_t>(buffer[2]) << 8) |
         static_cast<uint32_t>(buffer[3]);
}

bool ConstTimeDifferent(const uint8_t *lhs, const uint8_t *rhs, size_t size) {
  uint8_t difference = 0;
  for (size_t i = 0; i < size; ++i) {
    difference = static_cast<uint8_t>(difference | (lhs[i] ^ rhs[i]));
  }
  return difference != 0;
}

std::vector<uint8_t> EncryptRawSignalingPacket(
    const std::vector<uint8_t> &payload,
    const std::array<uint8_t, kKeySize> &key,
    bool keyIsOutgoing) {
  std::vector<uint8_t> prepared;
  prepared.reserve(kSequenceSize + payload.size());
  WriteBigEndian32(prepared, 1);
  prepared.insert(prepared.end(), payload.begin(), payload.end());

  const int x = (keyIsOutgoing ? 0 : 8) + 128;
  const std::array<uint8_t, tgcalls::kSha256Size> messageKeyLarge = tgcalls::ConcatSHA256(
      tgcalls::MemorySpan{key.data() + 88 + x, 32},
      tgcalls::MemorySpan{prepared.data(), prepared.size()});

  std::array<uint8_t, kMessageKeySize> messageKey = {};
  std::memcpy(messageKey.data(), messageKeyLarge.data() + 8, messageKey.size());

  std::vector<uint8_t> result(kMessageKeySize + prepared.size());
  std::memcpy(result.data(), messageKey.data(), messageKey.size());
  tgcalls::AesKeyIv keyIv = tgcalls::PrepareAesKeyIv(key.data(), messageKey.data(), x);
  tgcalls::AesProcessCtr(
      tgcalls::MemorySpan{prepared.data(), prepared.size()},
      result.data() + kMessageKeySize,
      std::move(keyIv));
  return result;
}

bool DecryptRawSignalingPacket(
    const std::vector<uint8_t> &encrypted,
    const std::array<uint8_t, kKeySize> &key,
    bool keyIsOutgoing,
    std::vector<uint8_t> &payload) {
  if (encrypted.size() < kMessageKeySize + kSequenceSize) {
    return false;
  }

  const int x = (keyIsOutgoing ? 8 : 0) + 128;
  const uint8_t *messageKey = encrypted.data();
  const uint8_t *encryptedData = encrypted.data() + kMessageKeySize;
  const size_t encryptedSize = encrypted.size() - kMessageKeySize;

  std::vector<uint8_t> decrypted(encryptedSize);
  tgcalls::AesKeyIv keyIv = tgcalls::PrepareAesKeyIv(key.data(), messageKey, x);
  tgcalls::AesProcessCtr(
      tgcalls::MemorySpan{encryptedData, encryptedSize},
      decrypted.data(),
      std::move(keyIv));

  const std::array<uint8_t, tgcalls::kSha256Size> messageKeyLarge = tgcalls::ConcatSHA256(
      tgcalls::MemorySpan{key.data() + 88 + x, 32},
      tgcalls::MemorySpan{decrypted.data(), decrypted.size()});
  if (ConstTimeDifferent(messageKeyLarge.data() + 8, messageKey, kMessageKeySize)) {
    return false;
  }

  if (ReadBigEndian32(decrypted.data()) != 1) {
    return false;
  }

  payload.assign(decrypted.begin() + kSequenceSize, decrypted.end());
  return true;
}

bool RunRawSignalingCryptoProbe() {
  tgcalls::signaling::MediaStateMessage mediaState;
  mediaState.isMuted = true;
  mediaState.videoState = tgcalls::signaling::MediaStateMessage::VideoState::Inactive;
  const tgcalls::signaling::Message message{mediaState};
  const std::vector<uint8_t> serialized = message.serialize();

  std::array<uint8_t, kKeySize> key = {};
  for (size_t i = 0; i < key.size(); ++i) {
    key[i] = static_cast<uint8_t>((i * 31 + 7) & 0xff);
  }

  const std::vector<uint8_t> encrypted = EncryptRawSignalingPacket(serialized, key, true);
  std::vector<uint8_t> decrypted;
  if (!DecryptRawSignalingPacket(encrypted, key, false, decrypted)) {
    return false;
  }
  return tgcalls::signaling::Message::parse(decrypted).has_value();
}

// ADR-0008: thread-safe-function trampoline. Runs on the ArkTS JS thread; hands the
// instanceId to the JS notifier so CallSessionController drains drainSignalingData().
void EmittedSignalingNotifierCallJs(napi_env env, napi_value jsCallback, void * /*context*/, void *data) {
  if (env == nullptr || jsCallback == nullptr) {
    return;
  }
  const int32_t instanceId = static_cast<int32_t>(reinterpret_cast<intptr_t>(data));
  napi_value undefined = nullptr;
  napi_value arg = nullptr;
  napi_get_undefined(env, &undefined);
  napi_create_int32(env, instanceId, &arg);
  napi_call_function(env, undefined, jsCallback, 1, &arg, nullptr);
}

// M2.4.2: thread-safe-function trampoline for the outgoing-microphone level. `data` is a
// heap float allocated by the audioLevelUpdated lambda; this runs on the JS thread, hands
// the level to the JS callback, and frees it. napi_tsfn_release (not abort) is used for
// the guard below, so queued items always drain through here — no leak.
void AudioLevelNotifierCallJs(napi_env env, napi_value jsCallback, void * /*context*/, void *data) {
  std::unique_ptr<float> level(static_cast<float *>(data));
  if (env == nullptr || jsCallback == nullptr || level == nullptr) {
    return;
  }
  napi_value undefined = nullptr;
  napi_value arg = nullptr;
  napi_get_undefined(env, &undefined);
  napi_create_double(env, static_cast<double>(*level), &arg);
  napi_call_function(env, undefined, jsCallback, 1, &arg, nullptr);
}

// ADR-0008 / M2.4.2: RAII owner of a thread-safe function. Captured (as a shared_ptr) by
// the native callback lambda that invokes it, so the TSFN lives exactly as long as the
// lambda — i.e. as long as the native instance whose thread invokes it. This makes the
// TSFN lifetime strictly contain every napi_call_threadsafe_function call site,
// eliminating the use-after-release window a session-field handle had.
struct TgCallTsfnGuard {
  napi_threadsafe_function tsfn = nullptr;

  explicit TgCallTsfnGuard(napi_threadsafe_function handle) : tsfn(handle) {}
  ~TgCallTsfnGuard() {
    if (tsfn != nullptr) {
      napi_release_threadsafe_function(tsfn, napi_tsfn_release);
    }
  }
  TgCallTsfnGuard(const TgCallTsfnGuard &) = delete;
  TgCallTsfnGuard &operator=(const TgCallTsfnGuard &) = delete;
};

void QueueEmittedSignalingData(
    int32_t instanceId,
    const std::vector<uint8_t> &data,
    napi_threadsafe_function notifier) {
  const std::string encodedData = tgcall::EncodeBase64(data);
  bool queued = false;
  {
    std::lock_guard<std::mutex> lock(g_sessionsMutex);
    auto session = g_sessions.find(instanceId);
    if (session == g_sessions.end()) {
      OH_LOG_Print(LOG_APP, LOG_WARN, tgcall::kTgCallLogDomain, tgcall::kTgCallLogTag,
                   "Dropped emitted signaling data for missing session instanceId=%{public}d bytes=%{public}zu",
                   instanceId,
                   data.size());
      return;
    }
    session->second.emittedSignalingDataBase64.push_back(encodedData);
    queued = true;
    OH_LOG_Print(LOG_APP, LOG_DEBUG, tgcall::kTgCallLogDomain, tgcall::kTgCallLogTag,
                 "Queued emitted signaling data instanceId=%{public}d bytes=%{public}zu pending=%{public}zu",
                 instanceId,
                 data.size(),
                 session->second.emittedSignalingDataBase64.size());
  }
  // Notify outside the lock — napi_call_threadsafe_function is safe from any thread and
  // must not be serialised behind g_sessionsMutex. `notifier` is owned by the calling
  // lambda's captured shared_ptr, so it cannot be released while this call is in flight.
  if (queued && notifier != nullptr) {
    napi_call_threadsafe_function(
        notifier,
        reinterpret_cast<void *>(static_cast<intptr_t>(instanceId)),
        napi_tsfn_nonblocking);
  }
}

// Erases a session. Caller must NOT hold g_sessionsMutex. Returns true when a session
// was removed. The thread-safe-function notifiers are not touched here — their lifetime
// is owned by the native callback lambdas that hold them (see TgCallTsfnGuard).
bool DestroySession(int32_t instanceId) {
  std::lock_guard<std::mutex> lock(g_sessionsMutex);
  return g_sessions.erase(instanceId) > 0;
}

napi_value RunRawSignalingCryptoProbeNapi(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  if (!Check(env, napi_get_cb_info(env, info, &argc, nullptr, nullptr, nullptr), "Failed to read callback info")) {
    return nullptr;
  }

  const bool result = RunRawSignalingCryptoProbe();
  return MakeBoolean(env, result);
}

napi_value RunFactoryRegistryProbeNapi(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  if (!Check(env, napi_get_cb_info(env, info, &argc, nullptr, nullptr, nullptr), "Failed to read callback info")) {
    return nullptr;
  }

  const bool registered = tgcall::EnsureRealTgCallFactoryRegistered();
  const std::vector<std::string> versions = tgcalls::Meta::Versions();
  const int maxLayer = tgcalls::Meta::MaxLayer();
  const std::string versionList = JoinStrings(versions);
  OH_LOG_Print(LOG_APP, LOG_INFO, tgcall::kTgCallLogDomain, tgcall::kTgCallLogTag,
               "TgCall real factory registry probe registered=%{public}d versions=%{public}zu maxLayer=%{public}d list=%{public}s",
               registered ? 1 : 0,
               versions.size(),
               maxLayer,
               versionList.c_str());
  return MakeBoolean(env, registered && !versions.empty());
}

napi_value RunWebKSignalingProbeNapi(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  if (!Check(env, napi_get_cb_info(env, info, &argc, nullptr, nullptr, nullptr), "Failed to read callback info")) {
    return nullptr;
  }

  tgcalls::signaling_4_0_0::MediaStateMessage mediaState;
  mediaState.isMuted = true;
  mediaState.videoState = tgcalls::signaling_4_0_0::MediaStateMessage::VideoState::Inactive;
  mediaState.videoRotation = tgcalls::signaling_4_0_0::MediaStateMessage::VideoRotation::Rotation0;
  mediaState.screencastState = tgcalls::signaling_4_0_0::MediaStateMessage::VideoState::Inactive;
  mediaState.isBatteryLow = false;

  tgcalls::signaling_4_0_0::Message message;
  message.data = mediaState;
  const std::vector<uint8_t> serialized = message.serialize();
  const absl::optional<tgcalls::signaling_4_0_0::Message> parsed =
      tgcalls::signaling_4_0_0::Message::parse(serialized);
  const bool passed = !serialized.empty() && parsed.has_value() &&
      absl::get_if<tgcalls::signaling_4_0_0::MediaStateMessage>(&parsed.value().data) != nullptr;

  OH_LOG_Print(LOG_APP, LOG_INFO, tgcall::kTgCallLogDomain, tgcall::kTgCallLogTag,
               "TgCall Web-K signaling 4.0.0 probe passed=%{public}d bytes=%{public}zu",
               passed ? 1 : 0,
               serialized.size());
  return MakeBoolean(env, passed);
}

napi_value GetSupportedVersionsNapi(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  if (!Check(env, napi_get_cb_info(env, info, &argc, nullptr, nullptr, nullptr), "Failed to read callback info")) {
    return nullptr;
  }

  tgcall::EnsureRealTgCallFactoryRegistered();
  return MakeStringArray(env, tgcalls::Meta::Versions());
}

napi_value StartCallInternal(napi_env env, napi_callback_info info, bool diagnosticOnly) {
  // Real calls take two extra arguments: arg[6] the emitted-signaling notifier
  // (ADR-0008) and arg[7] the audio-level notifier (M2.4.2). Diagnostic calls keep
  // the 6-argument signature — they never drive a live session.
  const size_t expectedArgc = diagnosticOnly ? 6 : 8;
  napi_value args[8] = {nullptr};
  if (!ReadCallbackArguments(env, info, args, expectedArgc)) {
    return nullptr;
  }

  tgcall::TgCallSession session;
  if (!ReadStringArgument(env, args[0], "protocolVersion", session.protocolVersion) ||
      !ReadStringArgument(env, args[1], "serversJson", session.serversJson) ||
      !ReadStringArgument(env, args[2], "encryptionKeyBase64", session.encryptionKeyBase64) ||
      !ReadBooleanArgument(env, args[3], "isOutgoing", session.isOutgoing) ||
      !ReadBooleanArgument(env, args[4], "allowP2p", session.allowP2p) ||
      !ReadStringArgument(env, args[5], "customParameters", session.customParameters)) {
    return nullptr;
  }
  std::shared_ptr<const std::array<uint8_t, kKeySize>> encryptionKey =
      tgcall::DecodeEncryptionKeyBase64(session.encryptionKeyBase64);
  if (!encryptionKey) {
    napi_throw_error(env, nullptr, "Invalid tgcall encryption key");
    return nullptr;
  }
  const std::string protocolVersion = session.protocolVersion;

  int32_t instanceId = 0;
  {
    std::lock_guard<std::mutex> lock(g_sessionsMutex);
    instanceId = AllocateInstanceIdLocked();
  }
  session.instanceId = instanceId;

  // ADR-0008 / M2.4.2: wrap the JS notifiers in thread-safe functions so native threads
  // can push to the ArkTS thread without polling. Each TSFN is owned by the native
  // callback lambda below (captured shared_ptr), so it lives exactly as long as the
  // lambda — there is no window where a native thread can call a released handle.
  std::shared_ptr<TgCallTsfnGuard> signalingNotifier;
  std::shared_ptr<TgCallTsfnGuard> audioLevelNotifier;
  if (!diagnosticOnly) {
    napi_value signalingAsyncName = nullptr;
    if (!Check(env,
               napi_create_string_utf8(env, "TgCallEmittedSignaling", NAPI_AUTO_LENGTH, &signalingAsyncName),
               "Failed to create tgcall async resource name")) {
      return nullptr;
    }
    napi_threadsafe_function signalingTsfn = nullptr;
    if (!Check(env,
               napi_create_threadsafe_function(
                   env, args[6], nullptr, signalingAsyncName,
                   /*max_queue_size=*/0, /*initial_thread_count=*/1,
                   nullptr, nullptr, nullptr,
                   EmittedSignalingNotifierCallJs, &signalingTsfn),
               "Failed to create tgcall signaling notifier")) {
      return nullptr;
    }
    signalingNotifier = std::make_shared<TgCallTsfnGuard>(signalingTsfn);

    napi_value audioLevelAsyncName = nullptr;
    if (!Check(env,
               napi_create_string_utf8(env, "TgCallAudioLevel", NAPI_AUTO_LENGTH, &audioLevelAsyncName),
               "Failed to create tgcall async resource name")) {
      return nullptr;
    }
    napi_threadsafe_function audioLevelTsfn = nullptr;
    if (!Check(env,
               napi_create_threadsafe_function(
                   env, args[7], nullptr, audioLevelAsyncName,
                   /*max_queue_size=*/0, /*initial_thread_count=*/1,
                   nullptr, nullptr, nullptr,
                   AudioLevelNotifierCallJs, &audioLevelTsfn),
               "Failed to create tgcall audio level notifier")) {
      return nullptr;
    }
    audioLevelNotifier = std::make_shared<TgCallTsfnGuard>(audioLevelTsfn);
  }

  tgcalls::Descriptor descriptor = tgcall::BuildDescriptor(
      session,
      encryptionKey,
      [instanceId, signalingNotifier](const std::vector<uint8_t> &data) {
        QueueEmittedSignalingData(
            instanceId, data,
            signalingNotifier ? signalingNotifier->tsfn : nullptr);
      },
      [audioLevelNotifier](float level) {
        if (!audioLevelNotifier || audioLevelNotifier->tsfn == nullptr) {
          return;
        }
        // Heap float owned by AudioLevelNotifierCallJs, which frees it on the JS thread.
        auto *payload = new float(level);
        if (napi_call_threadsafe_function(
                audioLevelNotifier->tsfn, payload, napi_tsfn_nonblocking) != napi_ok) {
          delete payload;
        }
      });
  {
    std::lock_guard<std::mutex> lock(g_sessionsMutex);
    g_sessions.emplace(instanceId, std::move(session));
  }
  std::shared_ptr<tgcalls::Instance> instance;
  if (diagnosticOnly) {
    instance = std::make_shared<tgcall::DiagnosticTgCallInstance>(std::move(descriptor));
  } else {
    const bool registered = tgcall::EnsureRealTgCallFactoryRegistered();
    const std::vector<std::string> versions = tgcalls::Meta::Versions();
    if (!registered || versions.empty()) {
      DestroySession(instanceId);
      OH_LOG_Print(LOG_APP, LOG_ERROR, tgcall::kTgCallLogDomain, tgcall::kTgCallLogTag,
                   "TgCall real session cannot start: factory unavailable registered=%{public}d versions=%{public}zu",
                   registered ? 1 : 0,
                   versions.size());
      napi_throw_error(env, nullptr, "TgCall real factory unavailable");
      return nullptr;
    }
    std::unique_ptr<tgcalls::Instance> realInstance = tgcalls::Meta::Create(protocolVersion, std::move(descriptor));
    instance = std::shared_ptr<tgcalls::Instance>(std::move(realInstance));
    if (!instance) {
      const std::string versionList = JoinStrings(versions);
      DestroySession(instanceId);
      OH_LOG_Print(LOG_APP, LOG_ERROR, tgcall::kTgCallLogDomain, tgcall::kTgCallLogTag,
                   "TgCall real session unsupported version=%{public}s supported=%{public}s",
                   protocolVersion.c_str(),
                   versionList.c_str());
      napi_throw_error(env, nullptr, "Unsupported tgcall protocol version");
      return nullptr;
    }
  }
  if (!instance) {
    DestroySession(instanceId);
    napi_throw_error(env, nullptr, "Unsupported tgcall protocol version");
    return nullptr;
  }
  {
    std::lock_guard<std::mutex> lock(g_sessionsMutex);
    auto storedSession = g_sessions.find(instanceId);
    if (storedSession != g_sessions.end()) {
      storedSession->second.instance = instance;
    }
  }

  OH_LOG_Print(LOG_APP, LOG_INFO, tgcall::kTgCallLogDomain, tgcall::kTgCallLogTag,
               "TgCall %{public}s session started instanceId=%{public}d version=%{public}s",
               diagnosticOnly ? "diagnostic" : "real",
               instanceId,
               protocolVersion.c_str());
  return MakeInt32(env, instanceId);
}

napi_value StartCallNapi(napi_env env, napi_callback_info info) {
  return StartCallInternal(env, info, /*diagnosticOnly=*/false);
}

napi_value StartDiagnosticCallNapi(napi_env env, napi_callback_info info) {
  return StartCallInternal(env, info, true);
}

napi_value FeedSignalingDataNapi(napi_env env, napi_callback_info info) {
  napi_value args[2] = {nullptr};
  if (!ReadCallbackArguments(env, info, args, 2)) {
    return nullptr;
  }

  int32_t instanceId = 0;
  std::string dataBase64;
  if (!ReadInt32Argument(env, args[0], "instanceId", instanceId) ||
      !ReadStringArgument(env, args[1], "dataBase64", dataBase64)) {
    return nullptr;
  }

  std::vector<uint8_t> data;
  if (!tgcall::DecodeBase64(dataBase64, data)) {
    napi_throw_type_error(env, nullptr, "Invalid tgcall signaling data");
    return nullptr;
  }

  std::shared_ptr<tgcalls::Instance> instance;
  {
    std::lock_guard<std::mutex> lock(g_sessionsMutex);
    auto session = g_sessions.find(instanceId);
    if (session == g_sessions.end()) {
      napi_throw_range_error(env, nullptr, "TgCall session does not exist");
      return nullptr;
    }
    session->second.signalingPacketCount += 1;
    instance = session->second.instance;
  }
  if (instance) {
    instance->receiveSignalingData(data);
  }

  napi_value result = nullptr;
  Check(env, napi_get_undefined(env, &result), "Failed to create undefined result");
  return result;
}

napi_value DrainSignalingDataNapi(napi_env env, napi_callback_info info) {
  napi_value args[1] = {nullptr};
  if (!ReadCallbackArguments(env, info, args, 1)) {
    return nullptr;
  }

  int32_t instanceId = 0;
  if (!ReadInt32Argument(env, args[0], "instanceId", instanceId)) {
    return nullptr;
  }

  std::vector<std::string> emittedData;
  {
    std::lock_guard<std::mutex> lock(g_sessionsMutex);
    auto session = g_sessions.find(instanceId);
    if (session == g_sessions.end()) {
      napi_throw_range_error(env, nullptr, "TgCall session does not exist");
      return nullptr;
    }
    emittedData = std::move(session->second.emittedSignalingDataBase64);
    session->second.emittedSignalingDataBase64.clear();
  }

  return MakeStringArray(env, emittedData);
}

napi_value SetMuteMicrophoneNapi(napi_env env, napi_callback_info info) {
  napi_value args[2] = {nullptr};
  if (!ReadCallbackArguments(env, info, args, 2)) {
    return nullptr;
  }

  int32_t instanceId = 0;
  bool muted = false;
  if (!ReadInt32Argument(env, args[0], "instanceId", instanceId) ||
      !ReadBooleanArgument(env, args[1], "muted", muted)) {
    return nullptr;
  }

  std::shared_ptr<tgcalls::Instance> instance;
  {
    std::lock_guard<std::mutex> lock(g_sessionsMutex);
    auto session = g_sessions.find(instanceId);
    if (session == g_sessions.end()) {
      napi_throw_range_error(env, nullptr, "TgCall session does not exist");
      return nullptr;
    }
    instance = session->second.instance;
  }
  if (instance) {
    instance->setMuteMicrophone(muted);
    OH_LOG_Print(LOG_APP, LOG_INFO, tgcall::kTgCallLogDomain, tgcall::kTgCallLogTag,
                 "TgCall setMuteMicrophone instanceId=%{public}d muted=%{public}d",
                 instanceId,
                 muted ? 1 : 0);
  }

  napi_value result = nullptr;
  Check(env, napi_get_undefined(env, &result), "Failed to create undefined result");
  return result;
}

napi_value StopCallNapi(napi_env env, napi_callback_info info) {
  napi_value args[1] = {nullptr};
  if (!ReadCallbackArguments(env, info, args, 1)) {
    return nullptr;
  }

  int32_t instanceId = 0;
  if (!ReadInt32Argument(env, args[0], "instanceId", instanceId)) {
    return nullptr;
  }

  bool removed = false;
  size_t signalingPacketCount = 0;
  std::shared_ptr<tgcalls::Instance> instance;
  {
    std::lock_guard<std::mutex> lock(g_sessionsMutex);
    auto session = g_sessions.find(instanceId);
    removed = session != g_sessions.end();
    if (removed) {
      signalingPacketCount = session->second.signalingPacketCount;
      instance = session->second.instance;
      g_sessions.erase(session);
    }
  }

  // ADR-0008: the emitted-signaling thread-safe function is not released here — it is
  // owned by the instance's signalingDataEmitted lambda and finalises when the instance
  // (and its networking thread) is destroyed, after instance->stop() completes.
  if (instance) {
    instance->stop([](tgcalls::FinalState finalState) {
      OH_LOG_Print(LOG_APP, LOG_INFO, tgcall::kTgCallLogDomain, tgcall::kTgCallLogTag,
                   "TgCall final state debugLen=%{public}zu suggested=%{public}d",
                   finalState.debugLog.size(),
                   finalState.isRatingSuggested ? 1 : 0);
    });
  }

  if (removed) {
    OH_LOG_Print(LOG_APP, LOG_INFO, tgcall::kTgCallLogDomain, tgcall::kTgCallLogTag,
                 "TgCall session stopped instanceId=%{public}d packets=%{public}zu",
                 instanceId, signalingPacketCount);
  }

  napi_value result = nullptr;
  Check(env, napi_get_undefined(env, &result), "Failed to create undefined result");
  return result;
}
}  // namespace

namespace tgcall {
napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
      {"runRawSignalingCryptoProbe", nullptr, RunRawSignalingCryptoProbeNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"runFactoryRegistryProbe", nullptr, RunFactoryRegistryProbeNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"runWebKSignalingProbe", nullptr, RunWebKSignalingProbeNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"getSupportedVersions", nullptr, GetSupportedVersionsNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"startCall", nullptr, StartCallNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"startDiagnosticCall", nullptr, StartDiagnosticCallNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"feedSignalingData", nullptr, FeedSignalingDataNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"drainSignalingData", nullptr, DrainSignalingDataNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"setMuteMicrophone", nullptr, SetMuteMicrophoneNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"stopCall", nullptr, StopCallNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
  };

  if (!Check(env,
             napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties),
             "Failed to define NAPI exports")) {
    return nullptr;
  }
  OH_LOG_Print(LOG_APP, LOG_INFO, tgcall::kTgCallLogDomain, tgcall::kTgCallLogTag, "TgCall NAPI module initialized");
  return exports;
}
}  // namespace tgcall
