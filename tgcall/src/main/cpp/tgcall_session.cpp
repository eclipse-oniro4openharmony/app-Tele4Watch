#include "tgcall_session.h"

#include "base64_util.h"
#include "tgcall_logging.h"
#include "third-party/json11.hpp"

#include <hilog/log.h>

#include <algorithm>
#include <cstring>
#include <iomanip>
#include <map>
#include <sstream>
#include <utility>
#include <vector>

namespace tgcall {
namespace {

uint64_t ParseUnsignedId(const std::string &value) {
  if (value.empty()) {
    return 0;
  }
  uint64_t result = 0;
  for (char character : value) {
    if (character < '0' || character > '9') {
      return 0;
    }
    result = result * 10 + static_cast<uint64_t>(character - '0');
  }
  return result;
}

std::string ReadJsonString(const json11::Json::object &object, const std::string &key) {
  const auto item = object.find(key);
  if (item == object.end() || !item->second.is_string()) {
    return "";
  }
  return item->second.string_value();
}

std::string ReadJsonStringFallback(
    const json11::Json::object &object,
    const std::string &primaryKey,
    const std::string &fallbackKey) {
  std::string result = ReadJsonString(object, primaryKey);
  if (!result.empty()) {
    return result;
  }
  return ReadJsonString(object, fallbackKey);
}

int ReadJsonInt(const json11::Json::object &object, const std::string &key) {
  const auto item = object.find(key);
  if (item == object.end() || !item->second.is_number()) {
    return 0;
  }
  return item->second.int_value();
}

bool ReadJsonBool(const json11::Json::object &object, const std::string &key) {
  const auto item = object.find(key);
  if (item == object.end() || !item->second.is_bool()) {
    return false;
  }
  return item->second.bool_value();
}

bool ReadJsonBoolFallback(
    const json11::Json::object &object,
    const std::string &primaryKey,
    const std::string &fallbackKey) {
  if (ReadJsonBool(object, primaryKey)) {
    return true;
  }
  return ReadJsonBool(object, fallbackKey);
}

std::string ReadServerType(const json11::Json::object &object) {
  const auto item = object.find("type");
  if (item == object.end()) {
    return "";
  }
  if (item->second.is_string()) {
    return item->second.string_value();
  }
  if (!item->second.is_object()) {
    return "";
  }
  return ReadJsonString(item->second.object_items(), "@type");
}

std::string BytesToHex(const std::vector<uint8_t> &bytes) {
  std::ostringstream stream;
  stream << std::hex << std::setfill('0');
  for (uint8_t byte : bytes) {
    stream << std::setw(2) << static_cast<int>(byte);
  }
  return stream.str();
}

std::vector<uint8_t> DecodePeerTagBytes(const std::string &peerTag) {
  std::vector<uint8_t> result;
  if (peerTag.empty()) {
    return result;
  }
  if (DecodeBase64(peerTag, result) && !result.empty()) {
    return result;
  }

  result.clear();
  result.reserve(peerTag.size());
  for (char character : peerTag) {
    result.push_back(static_cast<uint8_t>(character));
  }
  return result;
}

std::string DecodePeerTagPassword(const std::string &peerTag) {
  return BytesToHex(DecodePeerTagBytes(peerTag));
}

std::map<uint64_t, uint8_t> BuildReflectorIdMap(const json11::Json::array &servers) {
  std::vector<uint64_t> reflectorIds;
  for (const json11::Json &server : servers) {
    if (!server.is_object()) {
      continue;
    }
    const json11::Json::object &object = server.object_items();
    const std::string type = ReadJsonString(object, "type");
    if (type != "callServerTypeTelegramReflector") {
      continue;
    }
    const uint64_t serverId = ParseUnsignedId(ReadJsonString(object, "id"));
    if (serverId > 0) {
      reflectorIds.push_back(serverId);
    }
  }
  std::sort(reflectorIds.begin(), reflectorIds.end());
  reflectorIds.erase(std::unique(reflectorIds.begin(), reflectorIds.end()), reflectorIds.end());

  std::map<uint64_t, uint8_t> result;
  for (size_t index = 0; index < reflectorIds.size() && index < 255; index += 1) {
    result.emplace(reflectorIds[index], static_cast<uint8_t>(index + 1));
  }
  return result;
}

struct ParsedServerMapping {
  std::vector<tgcalls::RtcServer> rtcServers;
  std::vector<tgcalls::Endpoint> endpoints;
};

ParsedServerMapping ParseServers(const std::string &serversJson) {
  ParsedServerMapping result;
  if (serversJson.empty()) {
    return result;
  }

  std::string parseError;
  const json11::Json parsed = json11::Json::parse(serversJson, parseError);
  if (!parseError.empty() || !parsed.is_array()) {
    OH_LOG_Print(LOG_APP, LOG_WARN, kTgCallLogDomain, kTgCallLogTag,
                 "Failed to parse tgcall servers json error=%{public}s len=%{public}zu",
                 parseError.c_str(),
                 serversJson.size());
    return result;
  }

  const json11::Json::array &servers = parsed.array_items();
  const std::map<uint64_t, uint8_t> reflectorIdMap = BuildReflectorIdMap(servers);
  for (const json11::Json &server : servers) {
    if (!server.is_object()) {
      continue;
    }
    const json11::Json::object &object = server.object_items();
    const std::string type = ReadServerType(object);
    const std::string serverIdString = ReadJsonString(object, "id");
    const int port = ReadJsonInt(object, "port");
    if (port <= 0 || port > 65535) {
      OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
                   "Skipped tgcall server with invalid port type=%{public}s id=%{public}s port=%{public}d",
                   type.c_str(),
                   serverIdString.c_str(),
                   port);
      continue;
    }

    tgcalls::RtcServer rtcServer;
    const uint64_t serverId = ParseUnsignedId(serverIdString);
    const auto reflectorId = reflectorIdMap.find(serverId);
    rtcServer.id = reflectorId == reflectorIdMap.end() ? 0 : reflectorId->second;
    rtcServer.host = ReadJsonStringFallback(object, "ipAddress", "ip_address");
    if (rtcServer.host.empty()) {
      rtcServer.host = ReadJsonStringFallback(object, "ipv6Address", "ipv6_address");
    }
    rtcServer.port = static_cast<uint16_t>(port);

    if (type == "callServerTypeTelegramReflector") {
      rtcServer.login = "reflector";
      rtcServer.password = DecodePeerTagPassword(ReadJsonStringFallback(object, "peerTag", "peer_tag"));
      rtcServer.isTurn = true;
      rtcServer.isTcp = false;
      if (!rtcServer.host.empty() && !rtcServer.password.empty()) {
        result.rtcServers.push_back(rtcServer);

        tgcalls::Endpoint endpoint;
        endpoint.endpointId = static_cast<int64_t>(serverId);
        endpoint.host = tgcalls::EndpointHost{
            ReadJsonStringFallback(object, "ipAddress", "ip_address"),
            ReadJsonStringFallback(object, "ipv6Address", "ipv6_address")};
        endpoint.port = static_cast<uint16_t>(port);
        endpoint.type = tgcalls::EndpointType::UdpRelay;
        const std::vector<uint8_t> peerTagBytes = DecodePeerTagBytes(ReadJsonStringFallback(object, "peerTag", "peer_tag"));
        const size_t peerTagLength = std::min(peerTagBytes.size(), sizeof(endpoint.peerTag));
        if (peerTagLength > 0) {
          std::memcpy(endpoint.peerTag, peerTagBytes.data(), peerTagLength);
        }
        result.endpoints.push_back(std::move(endpoint));
      } else {
        OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
                     "Skipped Telegram reflector server id=%{public}s hostLen=%{public}zu peerTagLen=%{public}zu",
                     serverIdString.c_str(),
                     rtcServer.host.size(),
                     rtcServer.password.size());
      }
      continue;
    }

    if (type == "callServerTypeWebrtc") {
      const std::string username = ReadJsonString(object, "username");
      const std::string password = ReadJsonString(object, "password");
      const bool supportsTurn = ReadJsonBoolFallback(object, "supportsTurn", "supports_turn");
      const bool supportsStun = ReadJsonBoolFallback(object, "supportsStun", "supports_stun");
      OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
                   "Mapped WebRTC tgcall server id=%{public}s hostLen=%{public}zu port=%{public}d turn=%{public}d stun=%{public}d userLen=%{public}zu passLen=%{public}zu",
                   serverIdString.c_str(),
                   rtcServer.host.size(),
                   port,
                   supportsTurn ? 1 : 0,
                   supportsStun ? 1 : 0,
                   username.size(),
                   password.size());
      // #65 E4 diagnostics: list the JSON keys that actually crossed the ArkTS->native
      // boundary for this server (key names only — never credential values) so a missing
      // field is attributable to the producer side. Remove with task 4.4 C1 cleanup.
      {
        std::string keyList;
        for (const auto &entry : object) {
          if (!keyList.empty()) {
            keyList += ",";
          }
          keyList += entry.first;
        }
        OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
                     "WebRTC server diag id=%{public}s keys=%{public}s",
                     serverIdString.c_str(),
                     keyList.c_str());
      }
      if (!rtcServer.host.empty()) {
        rtcServer.login = username;
        rtcServer.password = password;
        rtcServer.isTurn = supportsTurn;
        rtcServer.isTcp = false;
        result.rtcServers.push_back(std::move(rtcServer));
      }
      continue;
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
                 "Skipped unsupported tgcall server type=%{public}s id=%{public}s",
                 type.c_str(),
                 serverIdString.c_str());
  }

  return result;
}

}  // namespace

std::shared_ptr<const std::array<uint8_t, kTgCallEncryptionKeySize>> DecodeEncryptionKeyBase64(
    const std::string &keyBase64) {
  std::vector<uint8_t> decoded;
  if (!DecodeBase64(keyBase64, decoded) || decoded.size() != kTgCallEncryptionKeySize) {
    return nullptr;
  }

  std::shared_ptr<std::array<uint8_t, kTgCallEncryptionKeySize>> result =
      std::make_shared<std::array<uint8_t, kTgCallEncryptionKeySize>>();
  std::memcpy(result->data(), decoded.data(), kTgCallEncryptionKeySize);
  return result;
}

tgcalls::Descriptor BuildDescriptor(
    const TgCallSession &session,
    std::shared_ptr<const std::array<uint8_t, kTgCallEncryptionKeySize>> encryptionKey,
    TgCallSignalingDataCallback signalingDataCallback,
    TgCallAudioLevelCallback audioLevelCallback) {
  tgcalls::Descriptor descriptor{
      session.protocolVersion,
      tgcalls::Config(),
      tgcalls::PersistentState(),
      std::vector<tgcalls::Endpoint>(),
      nullptr,
      std::vector<tgcalls::RtcServer>(),
      tgcalls::NetworkType::WiFi,
      tgcalls::EncryptionKey(std::move(encryptionKey), session.isOutgoing)};
  descriptor.config.enableP2P = session.allowP2p;
  descriptor.config.allowTCP = true;
  descriptor.config.enableAEC = true;
  descriptor.config.enableNS = true;
  descriptor.config.enableAGC = true;
  descriptor.config.maxApiLayer = 92;
  descriptor.config.customParameters = session.customParameters;
  ParsedServerMapping serverMapping = ParseServers(session.serversJson);
  descriptor.rtcServers = std::move(serverMapping.rtcServers);
  descriptor.endpoints = std::move(serverMapping.endpoints);
  descriptor.initialNetworkType = tgcalls::NetworkType::WiFi;
  OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
               "Mapped tgcall servers jsonLen=%{public}zu rtcServers=%{public}zu endpoints=%{public}zu allowP2p=%{public}d",
               session.serversJson.size(),
               descriptor.rtcServers.size(),
               descriptor.endpoints.size(),
               session.allowP2p ? 1 : 0);
  descriptor.stateUpdated = [version = session.protocolVersion](tgcalls::State state) {
    OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
                 "TgCall instance state version=%{public}s state=%{public}d",
                 version.c_str(),
                 static_cast<int>(state));
  };
  descriptor.signalBarsUpdated = [](int) {};
  descriptor.audioLevelUpdated = [callback = std::move(audioLevelCallback)](float level) {
    if (callback) {
      callback(level);
    }
  };
  descriptor.remoteBatteryLevelIsLowUpdated = [](bool isLow) {
    OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
                 "TgCall remote low battery=%{public}d",
                 isLow ? 1 : 0);
  };
  descriptor.remoteMediaStateUpdated = [](tgcalls::AudioState audioState, tgcalls::VideoState videoState) {
    OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
                 "TgCall remote media state audio=%{public}d video=%{public}d",
                 static_cast<int>(audioState),
                 static_cast<int>(videoState));
  };
  descriptor.remotePrefferedAspectRatioUpdated = [](float) {};
  descriptor.signalingDataEmitted = [callback = std::move(signalingDataCallback)](const std::vector<uint8_t> &data) {
    OH_LOG_Print(LOG_APP, LOG_DEBUG, kTgCallLogDomain, kTgCallLogTag,
                 "TgCall emitted signaling bytes=%{public}zu",
                 data.size());
    if (callback) {
      callback(data);
    }
  };
  return descriptor;
}

}  // namespace tgcall
