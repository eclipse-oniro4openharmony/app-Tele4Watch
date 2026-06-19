#pragma once

#include <string>

namespace opus_decoder {

struct OpusDecodeResult {
  bool success = false;
  std::string error;
  int64_t samplesPerChannel = 0;
  int channels = 0;
  int sampleRateHz = 48000;
};

OpusDecodeResult DecodeOpusFileToWav(const std::string &inputPath, const std::string &outputPath);

}  // namespace opus_decoder
