#include "opus_decode.h"

#include <opusfile.h>

#include <array>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {
constexpr int WAV_SAMPLE_RATE_HZ = 48000;
constexpr int WAV_BITS_PER_SAMPLE = 16;
constexpr size_t PCM_FRAME_BATCH = 120 * 48;

void PutLittleEndian16(unsigned char *destination, uint16_t value) {
  destination[0] = static_cast<unsigned char>(value & 0xFFu);
  destination[1] = static_cast<unsigned char>((value >> 8) & 0xFFu);
}

void PutLittleEndian32(unsigned char *destination, uint32_t value) {
  destination[0] = static_cast<unsigned char>(value & 0xFFu);
  destination[1] = static_cast<unsigned char>((value >> 8) & 0xFFu);
  destination[2] = static_cast<unsigned char>((value >> 16) & 0xFFu);
  destination[3] = static_cast<unsigned char>((value >> 24) & 0xFFu);
}

std::array<unsigned char, 44> MakeWavHeader(int64_t samplesPerChannel, int channelCount) {
  std::array<unsigned char, 44> header = {
      'R', 'I', 'F', 'F', 0, 0, 0, 0, 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ',
      16,  0,   0,   0,   1, 0, 2, 0, 0,   0,   0,   0,   0,   0,   0,   0,
      4,   0,   16,  0,   'd', 'a', 't', 'a', 0, 0, 0, 0,
  };

  const int safeChannelCount = channelCount > 0 ? channelCount : 1;
  const uint32_t byteRate = static_cast<uint32_t>(WAV_SAMPLE_RATE_HZ * safeChannelCount * (WAV_BITS_PER_SAMPLE / 8));
  const uint16_t blockAlign = static_cast<uint16_t>(safeChannelCount * (WAV_BITS_PER_SAMPLE / 8));

  PutLittleEndian16(&header[20], 1);
  PutLittleEndian16(&header[22], static_cast<uint16_t>(safeChannelCount));
  PutLittleEndian32(&header[24], static_cast<uint32_t>(WAV_SAMPLE_RATE_HZ));
  PutLittleEndian32(&header[28], byteRate);
  PutLittleEndian16(&header[32], blockAlign);
  PutLittleEndian16(&header[34], static_cast<uint16_t>(WAV_BITS_PER_SAMPLE));

  if (samplesPerChannel > 0 && samplesPerChannel <= 0x1FFFFFF6LL) {
    const uint32_t dataSizeBytes = static_cast<uint32_t>(samplesPerChannel * blockAlign);
    PutLittleEndian32(&header[4], dataSizeBytes + 36u);
    PutLittleEndian32(&header[40], dataSizeBytes);
  } else {
    PutLittleEndian32(&header[4], 0x7FFFFFFFu);
    PutLittleEndian32(&header[40], 0x7FFFFFFFu);
  }

  return header;
}

bool WriteHeader(FILE *file, int64_t samplesPerChannel, int channelCount, std::string &error) {
  const std::array<unsigned char, 44> header = MakeWavHeader(samplesPerChannel, channelCount);
  if (fseek(file, 0, SEEK_SET) != 0) {
    error = std::string("Failed to seek WAV file: ") + std::strerror(errno);
    return false;
  }
  if (fwrite(header.data(), header.size(), 1, file) != 1) {
    error = std::string("Failed to write WAV header: ") + std::strerror(errno);
    return false;
  }
  return true;
}

std::string MakeOpusOpenError(const std::string &inputPath, int code) {
  return "Failed to open Opus file '" + inputPath + "': code=" + std::to_string(code);
}
}  // namespace

namespace opus_decoder {

OpusDecodeResult DecodeOpusFileToWav(const std::string &inputPath, const std::string &outputPath) {
  OpusDecodeResult result;

  int openResult = 0;
  OggOpusFile *opusFile = op_open_file(inputPath.c_str(), &openResult);
  if (opusFile == nullptr) {
    result.error = MakeOpusOpenError(inputPath, openResult);
    return result;
  }

  const int channelCount = op_channel_count(opusFile, -1);
  if (channelCount <= 0) {
    result.error = "Failed to determine Opus channel count";
    op_free(opusFile);
    return result;
  }

  FILE *wavFile = std::fopen(outputPath.c_str(), "wb");
  if (wavFile == nullptr) {
    result.error = std::string("Failed to open WAV output '") + outputPath + "': " + std::strerror(errno);
    op_free(opusFile);
    return result;
  }

  std::string writeError;
  if (!WriteHeader(wavFile, 0, channelCount, writeError)) {
    result.error = writeError;
    std::fclose(wavFile);
    op_free(opusFile);
    return result;
  }

  std::vector<opus_int16> pcmBuffer(static_cast<size_t>(PCM_FRAME_BATCH * channelCount), 0);
  std::vector<unsigned char> byteBuffer(static_cast<size_t>(PCM_FRAME_BATCH * channelCount * sizeof(opus_int16)), 0);

  int64_t samplesPerChannel = 0;
  int linkIndex = 0;

  for (;;) {
    const int frameCount = op_read(opusFile, pcmBuffer.data(), static_cast<int>(pcmBuffer.size()), &linkIndex);
    if (frameCount == OP_HOLE) {
      continue;
    }
    if (frameCount < 0) {
      result.error = "Failed to decode Opus stream: code=" + std::to_string(frameCount);
      std::fclose(wavFile);
      op_free(opusFile);
      return result;
    }
    if (frameCount == 0) {
      break;
    }

    const int currentChannelCount = op_channel_count(opusFile, linkIndex);
    if (currentChannelCount != channelCount) {
      result.error = "Changing Opus channel count is not supported";
      std::fclose(wavFile);
      op_free(opusFile);
      return result;
    }

    const int sampleCount = frameCount * channelCount;
    for (int index = 0; index < sampleCount; index++) {
      const uint16_t sampleBits = static_cast<uint16_t>(pcmBuffer[static_cast<size_t>(index)]);
      byteBuffer[static_cast<size_t>(index) * 2] = static_cast<unsigned char>(sampleBits & 0xFFu);
      byteBuffer[static_cast<size_t>(index) * 2 + 1] = static_cast<unsigned char>((sampleBits >> 8) & 0xFFu);
    }

    const size_t bytesToWrite = static_cast<size_t>(sampleCount) * sizeof(opus_int16);
    if (fwrite(byteBuffer.data(), bytesToWrite, 1, wavFile) != 1) {
      result.error = std::string("Failed to write WAV audio data: ") + std::strerror(errno);
      std::fclose(wavFile);
      op_free(opusFile);
      return result;
    }

    samplesPerChannel += frameCount;
  }

  if (!WriteHeader(wavFile, samplesPerChannel, channelCount, writeError)) {
    result.error = writeError;
    std::fclose(wavFile);
    op_free(opusFile);
    return result;
  }

  std::fclose(wavFile);
  op_free(opusFile);

  result.success = true;
  result.samplesPerChannel = samplesPerChannel;
  result.channels = channelCount;
  result.sampleRateHz = WAV_SAMPLE_RATE_HZ;
  return result;
}

}  // namespace opus_decoder
