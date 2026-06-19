#pragma once

#include "tgcalls/Instance.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace tgcall {

constexpr size_t kTgCallEncryptionKeySize = 256;

struct TgCallSession {
  int32_t instanceId = 0;
  std::string protocolVersion;
  std::string serversJson;
  std::string encryptionKeyBase64;
  bool isOutgoing = false;
  bool allowP2p = false;
  std::string customParameters;
  size_t signalingPacketCount = 0;
  std::vector<std::string> emittedSignalingDataBase64;
  std::shared_ptr<tgcalls::Instance> instance;
  // ADR-0008: the emitted-signaling thread-safe function (native -> ArkTS push) is
  // intentionally NOT stored here. Its lifetime is owned by the signalingDataEmitted
  // lambda (see EmittedSignalingNotifier in tgcall_native.cpp), so it can never be
  // released while the networking thread is mid-call into it.
};

using TgCallSignalingDataCallback = std::function<void(const std::vector<uint8_t> &data)>;
using TgCallAudioLevelCallback = std::function<void(float level)>;

std::shared_ptr<const std::array<uint8_t, kTgCallEncryptionKeySize>> DecodeEncryptionKeyBase64(
    const std::string &keyBase64);

tgcalls::Descriptor BuildDescriptor(
    const TgCallSession &session,
    std::shared_ptr<const std::array<uint8_t, kTgCallEncryptionKeySize>> encryptionKey,
    TgCallSignalingDataCallback signalingDataCallback,
    TgCallAudioLevelCallback audioLevelCallback);

}  // namespace tgcall
