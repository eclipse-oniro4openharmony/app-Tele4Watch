#include "webk_media_bridge_tgcall_instance.h"

#include "real_tgcall_factory_registry.h"
#include "tgcall_logging.h"
#include "tgcalls/CryptoHelper.h"
#include "tgcalls/Instance.h"
#include "tgcalls/v2_4_0_0/Signaling_4_0_0.h"

#include <hilog/log.h>

#include <array>
#include <cstring>
#include <map>
#include <sstream>
#include <utility>

#include "third-party/json11.hpp"

namespace {
constexpr size_t kMessageKeySize = 16;
constexpr size_t kSequenceSize = 4;
constexpr const char *kInnerProtocolVersion = "10.0.0";

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
    const std::array<uint8_t, tgcalls::EncryptionKey::kSize> &key,
    bool keyIsOutgoing,
    uint32_t sequence) {
  std::vector<uint8_t> prepared;
  prepared.reserve(kSequenceSize + payload.size());
  WriteBigEndian32(prepared, sequence);
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
    const std::array<uint8_t, tgcalls::EncryptionKey::kSize> &key,
    bool keyIsOutgoing,
    std::vector<uint8_t> &payload,
    uint32_t &sequence) {
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

  sequence = ReadBigEndian32(decrypted.data());
  if (sequence == 0) {
    return false;
  }

  payload.assign(decrypted.begin() + kSequenceSize, decrypted.end());
  return true;
}

std::vector<std::string> Split(const std::string &value, char delimiter) {
  std::vector<std::string> result;
  std::string item;
  std::stringstream stream(value);
  while (std::getline(stream, item, delimiter)) {
    result.push_back(item);
  }
  return result;
}

std::string JoinLines(const std::vector<std::string> &lines) {
  std::string result;
  for (const std::string &line : lines) {
    if (line.empty()) {
      continue;
    }
    result += line;
    result += "\r\n";
  }
  return result;
}

std::string ToString(uint32_t value) {
  return std::to_string(static_cast<unsigned long long>(value));
}

void AddPayloadLines(std::vector<std::string> &lines, const tgcalls::signaling_4_0_0::MediaContent &content) {
  for (const tgcalls::signaling_4_0_0::PayloadType &payloadType : content.payloadTypes) {
    std::string rtpmap = "a=rtpmap:" + ToString(payloadType.id) + " " + payloadType.name + "/" +
        ToString(payloadType.clockrate);
    if (payloadType.channels != 0) {
      rtpmap += "/" + ToString(payloadType.channels);
    }
    lines.push_back(rtpmap);
    for (const tgcalls::signaling_4_0_0::FeedbackType &feedbackType : payloadType.feedbackTypes) {
      std::string line = "a=rtcp-fb:" + ToString(payloadType.id) + " " + feedbackType.type;
      if (!feedbackType.subtype.empty()) {
        line += " " + feedbackType.subtype;
      }
      lines.push_back(line);
    }
    if (!payloadType.parameters.empty()) {
      std::string fmtp;
      for (size_t index = 0; index < payloadType.parameters.size(); index += 1) {
        if (index > 0) {
          fmtp += ";";
        }
        fmtp += payloadType.parameters[index].first + "=" + payloadType.parameters[index].second;
      }
      lines.push_back("a=fmtp:" + ToString(payloadType.id) + " " + fmtp);
    }
  }
}

void AddSsrcLines(std::vector<std::string> &lines, const std::string &type, const tgcalls::signaling_4_0_0::MediaContent &content) {
  const std::string streamName = "stream" + ToString(content.ssrc);
  if (!content.ssrcGroups.empty()) {
    for (const tgcalls::signaling_4_0_0::SsrcGroup &group : content.ssrcGroups) {
      std::string groupLine = "a=ssrc-group:" + group.semantics;
      for (uint32_t ssrc : group.ssrcs) {
        groupLine += " " + ToString(ssrc);
      }
      lines.push_back(groupLine);
      for (uint32_t ssrc : group.ssrcs) {
        const std::string ssrcText = ToString(ssrc);
        lines.push_back("a=ssrc:" + ssrcText + " cname:stream" + ssrcText);
        lines.push_back("a=ssrc:" + ssrcText + " msid:" + streamName + " " + type + ssrcText);
        lines.push_back("a=ssrc:" + ssrcText + " mslabel:" + type + ssrcText);
        lines.push_back("a=ssrc:" + ssrcText + " label:" + type + ssrcText);
      }
    }
    return;
  }
  if (content.ssrc != 0) {
    const std::string ssrcText = ToString(content.ssrc);
    lines.push_back("a=ssrc:" + ssrcText + " cname:stream" + ssrcText);
    lines.push_back("a=ssrc:" + ssrcText + " msid:" + streamName + " " + type + ssrcText);
    lines.push_back("a=ssrc:" + ssrcText + " mslabel:" + type + ssrcText);
    lines.push_back("a=ssrc:" + ssrcText + " label:" + type + ssrcText);
  }
}

void AddMediaSection(
    std::vector<std::string> &lines,
    const std::string &mediaType,
    uint32_t mid,
    const tgcalls::signaling_4_0_0::MediaContent &content) {
  std::string payloadIds;
  for (size_t index = 0; index < content.payloadTypes.size(); index += 1) {
    if (index > 0) {
      payloadIds += " ";
    }
    payloadIds += ToString(content.payloadTypes[index].id);
  }

  lines.push_back("m=" + mediaType + " 9 UDP/TLS/RTP/SAVPF " + payloadIds);
  lines.push_back("c=IN IP4 0.0.0.0");
  lines.push_back("a=rtcp:9 IN IP4 0.0.0.0");
  lines.push_back("a=ice-options:trickle");
  lines.push_back("a=mid:" + ToString(mid));
  lines.push_back("a=sendrecv");
  for (const webrtc::RtpExtension &extension : content.rtpExtensions) {
    lines.push_back("a=extmap:" + std::to_string(extension.id) + " " + extension.uri);
  }
  if (content.ssrc != 0) {
    lines.push_back("a=msid:stream" + ToString(content.ssrc) + " " + mediaType + ToString(content.ssrc));
  }
  lines.push_back("a=rtcp-mux");
  if (mediaType == "video") {
    lines.push_back("a=rtcp-rsize");
  }
  AddPayloadLines(lines, content);
  AddSsrcLines(lines, mediaType, content);
}

std::string BuildOfferSdpFromWebKInitialSetup(const tgcalls::signaling_4_0_0::InitialSetupMessage &setup) {
  std::vector<std::string> mids;
  uint32_t nextMid = 0;
  if (setup.audio.has_value()) {
    mids.push_back(ToString(nextMid++));
  }
  if (setup.video.has_value()) {
    mids.push_back(ToString(nextMid++));
  }
  if (setup.screencast.has_value()) {
    mids.push_back(ToString(nextMid++));
  }
  const uint32_t dataMid = nextMid++;
  mids.push_back(ToString(dataMid));

  std::vector<std::string> lines;
  lines.push_back("v=0");
  lines.push_back("o=- 1 2 IN IP4 127.0.0.1");
  lines.push_back("s=-");
  lines.push_back("t=0 0");
  for (const tgcalls::signaling_4_0_0::DtlsFingerprint &fingerprint : setup.fingerprints) {
    lines.push_back("a=fingerprint:" + fingerprint.hash + " " + fingerprint.fingerprint);
    lines.push_back("a=setup:" + fingerprint.setup);
  }
  lines.push_back("a=ice-ufrag:" + setup.ufrag);
  lines.push_back("a=ice-pwd:" + setup.pwd);
  std::string bundle = "a=group:BUNDLE";
  for (const std::string &mid : mids) {
    bundle += " " + mid;
  }
  lines.push_back(bundle);
  lines.push_back("a=extmap-allow-mixed");
  lines.push_back("a=msid-semantic: WMS *");

  uint32_t mid = 0;
  if (setup.audio.has_value()) {
    AddMediaSection(lines, "audio", mid++, setup.audio.value());
  }
  if (setup.video.has_value()) {
    AddMediaSection(lines, "video", mid++, setup.video.value());
  }
  if (setup.screencast.has_value()) {
    AddMediaSection(lines, "video", mid++, setup.screencast.value());
  }
  lines.push_back("m=application 9 UDP/DTLS/SCTP webrtc-datachannel");
  lines.push_back("c=IN IP4 0.0.0.0");
  lines.push_back("a=ice-options:trickle");
  lines.push_back("a=mid:" + ToString(dataMid));
  lines.push_back("a=sctp-port:5000");
  lines.push_back("a=max-message-size:262144");
  return JoinLines(lines);
}

std::string Trim(const std::string &value) {
  size_t begin = 0;
  while (begin < value.size() && (value[begin] == ' ' || value[begin] == '\t' || value[begin] == '\r')) {
    begin += 1;
  }
  size_t end = value.size();
  while (end > begin && (value[end - 1] == ' ' || value[end - 1] == '\t' || value[end - 1] == '\r')) {
    end -= 1;
  }
  return value.substr(begin, end - begin);
}

uint32_t ParseUInt32(const std::string &value) {
  return static_cast<uint32_t>(std::strtoul(value.c_str(), nullptr, 10));
}

void ParseFmtpParameters(const std::string &value, tgcalls::signaling_4_0_0::PayloadType &payloadType) {
  const std::vector<std::string> parts = Split(value, ';');
  for (const std::string &part : parts) {
    const std::string item = Trim(part);
    const size_t delimiter = item.find('=');
    if (delimiter == std::string::npos) {
      continue;
    }
    payloadType.parameters.push_back(std::make_pair(item.substr(0, delimiter), item.substr(delimiter + 1)));
  }
}

struct ParsedMediaSection {
  std::string type;
  tgcalls::signaling_4_0_0::MediaContent content;
};

void ParseMediaLine(const std::string &line, ParsedMediaSection &section) {
  const std::vector<std::string> parts = Split(line, ' ');
  if (parts.empty()) {
    return;
  }
  section.type = parts[0].substr(2);
  for (size_t index = 3; index < parts.size(); index += 1) {
    tgcalls::signaling_4_0_0::PayloadType payloadType;
    payloadType.id = ParseUInt32(parts[index]);
    section.content.payloadTypes.push_back(std::move(payloadType));
  }
}

tgcalls::signaling_4_0_0::PayloadType *FindPayloadType(
    tgcalls::signaling_4_0_0::MediaContent &content,
    uint32_t id) {
  for (tgcalls::signaling_4_0_0::PayloadType &payloadType : content.payloadTypes) {
    if (payloadType.id == id) {
      return &payloadType;
    }
  }
  return nullptr;
}

absl::optional<tgcalls::signaling_4_0_0::InitialSetupMessage> ParseWebKInitialSetupFromSdp(const std::string &sdp) {
  tgcalls::signaling_4_0_0::InitialSetupMessage result;
  std::vector<ParsedMediaSection> mediaSections;
  ParsedMediaSection *currentSection = nullptr;
  std::string fingerprintHash;
  std::string fingerprintValue;
  std::string setupValue;

  const std::vector<std::string> lines = Split(sdp, '\n');
  for (std::string rawLine : lines) {
    const std::string line = Trim(rawLine);
    if (line.empty()) {
      continue;
    }
    if (line.rfind("m=", 0) == 0) {
      ParsedMediaSection section;
      ParseMediaLine(line, section);
      if (section.type == "audio" || section.type == "video") {
        mediaSections.push_back(std::move(section));
        currentSection = &mediaSections.back();
      } else {
        currentSection = nullptr;
      }
      continue;
    }
    if (line.rfind("a=ice-ufrag:", 0) == 0) {
      result.ufrag = line.substr(12);
      continue;
    }
    if (line.rfind("a=ice-pwd:", 0) == 0) {
      result.pwd = line.substr(10);
      continue;
    }
    if (line.rfind("a=fingerprint:", 0) == 0) {
      const std::string value = line.substr(14);
      const size_t delimiter = value.find(' ');
      if (delimiter != std::string::npos) {
        fingerprintHash = value.substr(0, delimiter);
        fingerprintValue = value.substr(delimiter + 1);
      }
      continue;
    }
    if (line.rfind("a=setup:", 0) == 0) {
      setupValue = line.substr(8);
      continue;
    }
    if (currentSection == nullptr) {
      continue;
    }
    if (line.rfind("a=rtpmap:", 0) == 0) {
      const std::string value = line.substr(9);
      const size_t firstSpace = value.find(' ');
      if (firstSpace == std::string::npos) {
        continue;
      }
      tgcalls::signaling_4_0_0::PayloadType *payloadType =
          FindPayloadType(currentSection->content, ParseUInt32(value.substr(0, firstSpace)));
      if (payloadType == nullptr) {
        continue;
      }
      const std::vector<std::string> codecParts = Split(value.substr(firstSpace + 1), '/');
      if (codecParts.size() >= 2) {
        payloadType->name = codecParts[0];
        payloadType->clockrate = ParseUInt32(codecParts[1]);
        if (codecParts.size() >= 3) {
          payloadType->channels = ParseUInt32(codecParts[2]);
        }
      }
      continue;
    }
    if (line.rfind("a=rtcp-fb:", 0) == 0) {
      const std::string value = line.substr(10);
      const std::vector<std::string> parts = Split(value, ' ');
      if (parts.size() >= 2) {
        tgcalls::signaling_4_0_0::PayloadType *payloadType =
            FindPayloadType(currentSection->content, ParseUInt32(parts[0]));
        if (payloadType != nullptr) {
          tgcalls::signaling_4_0_0::FeedbackType feedbackType;
          feedbackType.type = parts[1];
          if (parts.size() >= 3) {
            feedbackType.subtype = parts[2];
          }
          payloadType->feedbackTypes.push_back(std::move(feedbackType));
        }
      }
      continue;
    }
    if (line.rfind("a=fmtp:", 0) == 0) {
      const std::string value = line.substr(7);
      const size_t firstSpace = value.find(' ');
      if (firstSpace != std::string::npos) {
        tgcalls::signaling_4_0_0::PayloadType *payloadType =
            FindPayloadType(currentSection->content, ParseUInt32(value.substr(0, firstSpace)));
        if (payloadType != nullptr) {
          ParseFmtpParameters(value.substr(firstSpace + 1), *payloadType);
        }
      }
      continue;
    }
    if (line.rfind("a=extmap:", 0) == 0) {
      const std::string value = line.substr(9);
      const size_t firstSpace = value.find(' ');
      if (firstSpace != std::string::npos) {
        webrtc::RtpExtension extension;
        extension.id = static_cast<int>(ParseUInt32(value.substr(0, firstSpace)));
        extension.uri = value.substr(firstSpace + 1);
        currentSection->content.rtpExtensions.push_back(std::move(extension));
      }
      continue;
    }
    if (line.rfind("a=ssrc-group:", 0) == 0) {
      const std::vector<std::string> parts = Split(line.substr(13), ' ');
      if (parts.size() >= 2) {
        tgcalls::signaling_4_0_0::SsrcGroup group;
        group.semantics = parts[0];
        for (size_t index = 1; index < parts.size(); index += 1) {
          group.ssrcs.push_back(ParseUInt32(parts[index]));
        }
        currentSection->content.ssrcGroups.push_back(std::move(group));
      }
      continue;
    }
    if (line.rfind("a=ssrc:", 0) == 0 && currentSection->content.ssrc == 0) {
      const std::string value = line.substr(7);
      const size_t delimiter = value.find(' ');
      currentSection->content.ssrc = ParseUInt32(delimiter == std::string::npos ? value : value.substr(0, delimiter));
    }
  }

  if (!fingerprintHash.empty() && !fingerprintValue.empty() && !setupValue.empty()) {
    tgcalls::signaling_4_0_0::DtlsFingerprint fingerprint;
    fingerprint.hash = fingerprintHash;
    fingerprint.setup = setupValue;
    fingerprint.fingerprint = fingerprintValue;
    result.fingerprints.push_back(std::move(fingerprint));
  }

  bool videoAssigned = false;
  for (const ParsedMediaSection &section : mediaSections) {
    if (section.type == "audio" && !result.audio.has_value()) {
      result.audio = section.content;
      continue;
    }
    if (section.type == "video" && !videoAssigned) {
      result.video = section.content;
      videoAssigned = true;
      continue;
    }
    if (section.type == "video" && !result.screencast.has_value()) {
      result.screencast = section.content;
    }
  }

  if (result.ufrag.empty() || result.pwd.empty() || result.fingerprints.empty() || !result.audio.has_value()) {
    return absl::nullopt;
  }
  return result;
}

std::string BuildJsonDescription(const std::string &type, const std::string &sdp) {
  json11::Json::object object;
  object.insert(std::make_pair("@type", json11::Json(type)));
  object.insert(std::make_pair("sdp", json11::Json(sdp)));
  return json11::Json(std::move(object)).dump();
}

std::string BuildJsonCandidate(const std::string &sdp) {
  json11::Json::object object;
  object.insert(std::make_pair("@type", json11::Json("candidate")));
  object.insert(std::make_pair("sdp", json11::Json(sdp)));
  object.insert(std::make_pair("mid", json11::Json("0")));
  object.insert(std::make_pair("mline", json11::Json(0)));
  return json11::Json(std::move(object)).dump();
}

}  // namespace

namespace tgcall {

WebKMediaBridgeTgCallInstance::WebKMediaBridgeTgCallInstance(tgcalls::Descriptor &&descriptor)
    : version_(descriptor.version),
      encryptionKey_(descriptor.encryptionKey.value),
      encryptionKeyIsOutgoing_(descriptor.encryptionKey.isOutgoing),
      outerSignalingDataEmitted_(std::move(descriptor.signalingDataEmitted)) {
  descriptor.version = kInnerProtocolVersion;
  descriptor.signalingDataEmitted = [this](const std::vector<uint8_t> &data) {
    handleInnerSignalingData(data);
  };

  if (EnsureRealTgCallFactoryRegistered()) {
    inner_ = tgcalls::Meta::Create(kInnerProtocolVersion, std::move(descriptor));
  }

  OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
               "Web-K media bridge created version=%{public}s inner=%{public}s available=%{public}d keyOutgoing=%{public}d",
               version_.c_str(),
               kInnerProtocolVersion,
               inner_ ? 1 : 0,
               encryptionKeyIsOutgoing_ ? 1 : 0);
}

bool WebKMediaBridgeTgCallInstance::isAvailable() const {
  return inner_ != nullptr && encryptionKey_ != nullptr;
}

void WebKMediaBridgeTgCallInstance::feedInnerJson(const std::string &json) {
  if (!inner_ || !encryptionKey_) {
    return;
  }
  uint32_t sequence = 0;
  {
    std::lock_guard<std::mutex> lock(sequenceMutex_);
    sequence = innerIncomingSequence_++;
  }
  const std::vector<uint8_t> payload(json.begin(), json.end());
  const std::vector<uint8_t> encrypted = EncryptRawSignalingPacket(
      payload,
      *encryptionKey_,
      !encryptionKeyIsOutgoing_,
      sequence);
  OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
               "Web-K media bridge feeding inner signaling typeBytes=%{public}zu encrypted=%{public}zu seq=%{public}u",
               payload.size(),
               encrypted.size(),
               sequence);
  inner_->receiveSignalingData(encrypted);
}

void WebKMediaBridgeTgCallInstance::emitWebKMessage(const tgcalls::signaling_4_0_0::Message &message) {
  if (!outerSignalingDataEmitted_ || !encryptionKey_) {
    return;
  }
  uint32_t sequence = 0;
  {
    std::lock_guard<std::mutex> lock(sequenceMutex_);
    sequence = webKOutgoingSequence_++;
  }
  const std::vector<uint8_t> payload = message.serialize();
  const std::vector<uint8_t> encrypted = EncryptRawSignalingPacket(
      payload,
      *encryptionKey_,
      encryptionKeyIsOutgoing_,
      sequence);
  OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
               "Web-K media bridge emitting outer signaling payload=%{public}zu encrypted=%{public}zu seq=%{public}u",
               payload.size(),
               encrypted.size(),
               sequence);
  outerSignalingDataEmitted_(encrypted);
}

void WebKMediaBridgeTgCallInstance::handleWebKMessage(const tgcalls::signaling_4_0_0::Message &message) {
  const tgcalls::signaling_4_0_0::InitialSetupMessage *initialSetup =
      absl::get_if<tgcalls::signaling_4_0_0::InitialSetupMessage>(&message.data);
  if (initialSetup != nullptr) {
    const std::string offerSdp = BuildOfferSdpFromWebKInitialSetup(*initialSetup);
    OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
                 "Web-K media bridge mapped outer InitialSetup to inner offer sdpBytes=%{public}zu audio=%{public}d video=%{public}d screencast=%{public}d",
                 offerSdp.size(),
                 initialSetup->audio.has_value() ? 1 : 0,
                 initialSetup->video.has_value() ? 1 : 0,
                 initialSetup->screencast.has_value() ? 1 : 0);
    feedInnerJson(BuildJsonDescription("offer", offerSdp));
    return;
  }

  const tgcalls::signaling_4_0_0::CandidatesMessage *candidates =
      absl::get_if<tgcalls::signaling_4_0_0::CandidatesMessage>(&message.data);
  if (candidates != nullptr) {
    for (const tgcalls::signaling_4_0_0::IceCandidate &candidate : candidates->iceCandidates) {
      feedInnerJson(BuildJsonCandidate(candidate.sdpString));
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
                 "Web-K media bridge mapped outer candidates to inner count=%{public}zu",
                 candidates->iceCandidates.size());
    return;
  }
}

void WebKMediaBridgeTgCallInstance::receiveSignalingData(const std::vector<uint8_t> &data) {
  if (!encryptionKey_) {
    return;
  }
  std::vector<uint8_t> payload;
  uint32_t sequence = 0;
  if (!DecryptRawSignalingPacket(data, *encryptionKey_, encryptionKeyIsOutgoing_, payload, sequence)) {
    OH_LOG_Print(LOG_APP, LOG_WARN, kTgCallLogDomain, kTgCallLogTag,
                 "Web-K media bridge failed to decrypt outer signaling bytes=%{public}zu",
                 data.size());
    return;
  }
  const absl::optional<tgcalls::signaling_4_0_0::Message> parsed =
      tgcalls::signaling_4_0_0::Message::parse(payload);
  if (!parsed.has_value()) {
    OH_LOG_Print(LOG_APP, LOG_WARN, kTgCallLogDomain, kTgCallLogTag,
                 "Web-K media bridge failed to parse outer signaling seq=%{public}u bytes=%{public}zu",
                 sequence,
                 payload.size());
    return;
  }
  handleWebKMessage(parsed.value());
}

void WebKMediaBridgeTgCallInstance::handleInnerSignalingData(const std::vector<uint8_t> &data) {
  if (!encryptionKey_) {
    return;
  }
  std::vector<uint8_t> payload;
  uint32_t sequence = 0;
  if (!DecryptRawSignalingPacket(data, *encryptionKey_, !encryptionKeyIsOutgoing_, payload, sequence)) {
    OH_LOG_Print(LOG_APP, LOG_WARN, kTgCallLogDomain, kTgCallLogTag,
                 "Web-K media bridge failed to decrypt inner signaling bytes=%{public}zu",
                 data.size());
    return;
  }
  handleInnerJson(std::string(payload.begin(), payload.end()));
}

void WebKMediaBridgeTgCallInstance::handleInnerJson(const std::string &json) {
  std::string error;
  const json11::Json parsed = json11::Json::parse(json, error);
  if (!error.empty() || !parsed.is_object()) {
    return;
  }
  const json11::Json::object &object = parsed.object_items();
  const auto type = object.find("@type");
  if (type == object.end() || !type->second.is_string()) {
    return;
  }
  const std::string typeValue = type->second.string_value();
  if (typeValue == "answer" || typeValue == "offer") {
    const auto sdp = object.find("sdp");
    if (sdp == object.end() || !sdp->second.is_string()) {
      return;
    }
    const absl::optional<tgcalls::signaling_4_0_0::InitialSetupMessage> mapped =
        ParseWebKInitialSetupFromSdp(sdp->second.string_value());
    if (!mapped.has_value()) {
      OH_LOG_Print(LOG_APP, LOG_WARN, kTgCallLogDomain, kTgCallLogTag,
                   "Web-K media bridge failed to map inner SDP type=%{public}s bytes=%{public}zu",
                   typeValue.c_str(),
                   sdp->second.string_value().size());
      return;
    }
    tgcalls::signaling_4_0_0::Message message;
    message.data = mapped.value();
    OH_LOG_Print(LOG_APP, LOG_INFO, kTgCallLogDomain, kTgCallLogTag,
                 "Web-K media bridge mapped inner %{public}s to outer InitialSetup audio=%{public}d video=%{public}d screencast=%{public}d",
                 typeValue.c_str(),
                 mapped->audio.has_value() ? 1 : 0,
                 mapped->video.has_value() ? 1 : 0,
                 mapped->screencast.has_value() ? 1 : 0);
    emitWebKMessage(message);
    return;
  }
  if (typeValue == "candidate") {
    const auto sdp = object.find("sdp");
    if (sdp == object.end() || !sdp->second.is_string()) {
      return;
    }
    tgcalls::signaling_4_0_0::CandidatesMessage candidates;
    tgcalls::signaling_4_0_0::IceCandidate candidate;
    candidate.sdpString = sdp->second.string_value();
    candidates.iceCandidates.push_back(std::move(candidate));
    tgcalls::signaling_4_0_0::Message message;
    message.data = std::move(candidates);
    emitWebKMessage(message);
  }
}

void WebKMediaBridgeTgCallInstance::setNetworkType(tgcalls::NetworkType networkType) {
  if (inner_) {
    inner_->setNetworkType(networkType);
  }
}

void WebKMediaBridgeTgCallInstance::setMuteMicrophone(bool muteMicrophone) {
  if (inner_) {
    inner_->setMuteMicrophone(muteMicrophone);
  }
}

void WebKMediaBridgeTgCallInstance::setAudioOutputGainControlEnabled(bool enabled) {
  if (inner_) {
    inner_->setAudioOutputGainControlEnabled(enabled);
  }
}

void WebKMediaBridgeTgCallInstance::setEchoCancellationStrength(int strength) {
  if (inner_) {
    inner_->setEchoCancellationStrength(strength);
  }
}

bool WebKMediaBridgeTgCallInstance::supportsVideo() {
  return inner_ ? inner_->supportsVideo() : false;
}

void WebKMediaBridgeTgCallInstance::setIncomingVideoOutput(std::weak_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>> sink) {
  if (inner_) {
    inner_->setIncomingVideoOutput(sink);
  }
}

void WebKMediaBridgeTgCallInstance::setAudioInputDevice(std::string id) {
  if (inner_) {
    inner_->setAudioInputDevice(std::move(id));
  }
}

void WebKMediaBridgeTgCallInstance::setAudioOutputDevice(std::string id) {
  if (inner_) {
    inner_->setAudioOutputDevice(std::move(id));
  }
}

void WebKMediaBridgeTgCallInstance::setInputVolume(float level) {
  if (inner_) {
    inner_->setInputVolume(level);
  }
}

void WebKMediaBridgeTgCallInstance::setOutputVolume(float level) {
  if (inner_) {
    inner_->setOutputVolume(level);
  }
}

void WebKMediaBridgeTgCallInstance::setAudioOutputDuckingEnabled(bool enabled) {
  if (inner_) {
    inner_->setAudioOutputDuckingEnabled(enabled);
  }
}

void WebKMediaBridgeTgCallInstance::setIsLowBatteryLevel(bool isLowBatteryLevel) {
  if (inner_) {
    inner_->setIsLowBatteryLevel(isLowBatteryLevel);
  }
}

std::string WebKMediaBridgeTgCallInstance::getLastError() {
  return inner_ ? inner_->getLastError() : "Web-K media bridge inner unavailable";
}

std::string WebKMediaBridgeTgCallInstance::getDebugInfo() {
  return inner_ ? inner_->getDebugInfo() : "";
}

int64_t WebKMediaBridgeTgCallInstance::getPreferredRelayId() {
  return inner_ ? inner_->getPreferredRelayId() : 0;
}

tgcalls::TrafficStats WebKMediaBridgeTgCallInstance::getTrafficStats() {
  return inner_ ? inner_->getTrafficStats() : tgcalls::TrafficStats{};
}

tgcalls::PersistentState WebKMediaBridgeTgCallInstance::getPersistentState() {
  return inner_ ? inner_->getPersistentState() : tgcalls::PersistentState{};
}

void WebKMediaBridgeTgCallInstance::setVideoCapture(std::shared_ptr<tgcalls::VideoCaptureInterface> videoCapture) {
  if (inner_) {
    inner_->setVideoCapture(std::move(videoCapture));
  }
}

void WebKMediaBridgeTgCallInstance::sendVideoDeviceUpdated() {
  if (inner_) {
    inner_->sendVideoDeviceUpdated();
  }
}

void WebKMediaBridgeTgCallInstance::setRequestedVideoAspect(float aspect) {
  if (inner_) {
    inner_->setRequestedVideoAspect(aspect);
  }
}

void WebKMediaBridgeTgCallInstance::stop(std::function<void(tgcalls::FinalState)> completion) {
  if (inner_) {
    inner_->stop(std::move(completion));
    return;
  }
  if (completion) {
    completion(tgcalls::FinalState{});
  }
}

}  // namespace tgcall
