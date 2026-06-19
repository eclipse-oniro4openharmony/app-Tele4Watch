#pragma once

#include "tgcalls/Instance.h"
#include "tgcalls/v2_4_0_0/Signaling_4_0_0.h"

#include <array>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace tgcall {

class WebKMediaBridgeTgCallInstance final : public tgcalls::Instance {
public:
  explicit WebKMediaBridgeTgCallInstance(tgcalls::Descriptor &&descriptor);
  ~WebKMediaBridgeTgCallInstance() override = default;

  bool isAvailable() const;

  void setNetworkType(tgcalls::NetworkType networkType) override;
  void setMuteMicrophone(bool muteMicrophone) override;
  void setAudioOutputGainControlEnabled(bool enabled) override;
  void setEchoCancellationStrength(int strength) override;
  bool supportsVideo() override;
  void setIncomingVideoOutput(std::weak_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>> sink) override;
  void setAudioInputDevice(std::string id) override;
  void setAudioOutputDevice(std::string id) override;
  void setInputVolume(float level) override;
  void setOutputVolume(float level) override;
  void setAudioOutputDuckingEnabled(bool enabled) override;
  void setIsLowBatteryLevel(bool isLowBatteryLevel) override;
  std::string getLastError() override;
  std::string getDebugInfo() override;
  int64_t getPreferredRelayId() override;
  tgcalls::TrafficStats getTrafficStats() override;
  tgcalls::PersistentState getPersistentState() override;
  void receiveSignalingData(const std::vector<uint8_t> &data) override;
  void setVideoCapture(std::shared_ptr<tgcalls::VideoCaptureInterface> videoCapture) override;
  void sendVideoDeviceUpdated() override;
  void setRequestedVideoAspect(float aspect) override;
  void stop(std::function<void(tgcalls::FinalState)> completion) override;

private:
  void handleInnerSignalingData(const std::vector<uint8_t> &data);
  void feedInnerJson(const std::string &json);
  void emitWebKMessage(const tgcalls::signaling_4_0_0::Message &message);
  void handleWebKMessage(const tgcalls::signaling_4_0_0::Message &message);
  void handleInnerJson(const std::string &json);

  std::string version_;
  std::shared_ptr<const std::array<uint8_t, tgcalls::EncryptionKey::kSize>> encryptionKey_;
  bool encryptionKeyIsOutgoing_ = false;
  std::function<void(const std::vector<uint8_t> &)> outerSignalingDataEmitted_;
  std::unique_ptr<tgcalls::Instance> inner_;
  mutable std::mutex sequenceMutex_;
  uint32_t innerIncomingSequence_ = 1;
  uint32_t webKOutgoingSequence_ = 1;
};

}  // namespace tgcall
