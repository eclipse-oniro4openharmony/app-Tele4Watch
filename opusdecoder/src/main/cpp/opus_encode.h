#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace opus_decoder {

struct VoiceRecordResult {
  bool success = false;
  std::string error;
  std::string outputPath;
  std::string mimeType;
  std::string containerFormat;
  std::string audioCodec;
  int durationSec = 0;
  int64_t durationMs = 0;
  int sampleRateHz = 0;
  int channelCount = 0;
  int32_t targetBitrateBps = 0;
  int64_t averageBitrateBps = 0;
  int64_t fileSizeBytes = 0;
  int64_t pageCount = 0;
  std::vector<uint8_t> waveform;
};

bool StartVoiceRecord(const std::string &outputPath, int sampleRateHz, std::string &error);
bool WriteVoiceFrame(const uint8_t *pcmBytes, size_t byteCount, std::string &error);
VoiceRecordResult StopVoiceRecord();

}  // namespace opus_decoder
