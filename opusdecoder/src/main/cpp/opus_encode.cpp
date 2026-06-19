#include "opus_encode.h"

#include <ogg/ogg.h>
#include <opus.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <mutex>
#include <string>
#include <vector>

namespace {
constexpr size_t OPUS_SAMPLE_SIZE_BYTES = sizeof(opus_int16);
constexpr opus_int32 OPUS_RECORDING_BITRATE = 32000;
constexpr int OPUS_COMMENT_PADDING = 512;
constexpr int OPUS_WAVEFORM_SAMPLE_COUNT = 100;
constexpr int OPUS_WAVEFORM_BITSTREAM_LENGTH = (OPUS_WAVEFORM_SAMPLE_COUNT * 5) / 8 + 1;
constexpr int OPUS_MAX_OGG_DELAY = 0;
constexpr int OPUS_MAX_RECORDING_SECONDS = 90;

struct OpusHeader {
  int version = 1;
  int channels = 1;
  int preskip = 0;
  ogg_uint32_t inputSampleRate = 48000;
  int gain = 0;
  int channelMapping = 0;
  int nbStreams = 1;
  int nbCoupled = 0;
  unsigned char streamMap[255] {};
};

struct VoiceRecorderState {
  std::mutex mutex;
  bool streamInitialized = false;
  bool recordingActive = false;
  int sampleRateHz = 48000;
  int packetId = 0;
  int maxFrameBytes = 0;
  int minBytes = 0;
  int lastSegments = 0;
  int pendingPacketNo = 0;
  int pendingSizeSegments = 0;
  opus_int64 totalSamples = 0;
  opus_int64 bytesWritten = 0;
  opus_int64 pagesOut = 0;
  ogg_int64_t encodedGranulePos = 0;
  ogg_int64_t lastGranulePos = 0;
  ogg_int64_t pendingGranulePos = 0;
  FILE *outputFile = nullptr;
  OpusEncoder *encoder = nullptr;
  ogg_stream_state streamState {};
  OpusHeader header {};
  std::string outputPath;
  std::vector<unsigned char> packetBuffer;
  std::vector<unsigned char> pendingPacket;
  std::vector<unsigned char> pendingInputBytes;
  std::vector<int16_t> recordedSamples;
};

VoiceRecorderState g_voiceRecorderState;

size_t FrameSizeSamplesForSampleRate(int sampleRateHz) {
  if (sampleRateHz <= 0) {
    return 960;
  }

  const size_t frameSizeSamples = static_cast<size_t>(sampleRateHz / 50);
  if (frameSizeSamples == 0) {
    return 960;
  }
  return frameSizeSamples;
}

size_t FrameSizeBytesForSampleRate(int sampleRateHz) {
  return FrameSizeSamplesForSampleRate(sampleRateHz) * OPUS_SAMPLE_SIZE_BYTES;
}

int64_t ComputeDurationMs(opus_int64 totalSamples, int sampleRateHz) {
  if (totalSamples <= 0 || sampleRateHz <= 0) {
    return 0;
  }
  return static_cast<int64_t>(
      std::llround((static_cast<long double>(totalSamples) * 1000.0L) / static_cast<long double>(sampleRateHz)));
}

int64_t ComputeAverageBitrateBps(int64_t fileSizeBytes, opus_int64 totalSamples, int sampleRateHz) {
  if (fileSizeBytes <= 0 || totalSamples <= 0 || sampleRateHz <= 0) {
    return 0;
  }
  return static_cast<int64_t>(
      std::llround((static_cast<long double>(fileSizeBytes) * 8.0L * static_cast<long double>(sampleRateHz)) /
                   static_cast<long double>(totalSamples)));
}

void WriteUint16(std::vector<unsigned char> &buffer, uint16_t value) {
  buffer.push_back(static_cast<unsigned char>(value & 0xFFu));
  buffer.push_back(static_cast<unsigned char>((value >> 8) & 0xFFu));
}

void WriteUint32(std::vector<unsigned char> &buffer, uint32_t value) {
  buffer.push_back(static_cast<unsigned char>(value & 0xFFu));
  buffer.push_back(static_cast<unsigned char>((value >> 8) & 0xFFu));
  buffer.push_back(static_cast<unsigned char>((value >> 16) & 0xFFu));
  buffer.push_back(static_cast<unsigned char>((value >> 24) & 0xFFu));
}

void WriteChars(std::vector<unsigned char> &buffer, const char *text, size_t length) {
  for (size_t index = 0; index < length; index++) {
    buffer.push_back(static_cast<unsigned char>(text[index]));
  }
}

std::vector<unsigned char> BuildOpusHeaderPacket(const OpusHeader &header) {
  std::vector<unsigned char> packet;
  packet.reserve(64);
  WriteChars(packet, "OpusHead", 8);
  packet.push_back(static_cast<unsigned char>(header.version));
  packet.push_back(static_cast<unsigned char>(header.channels));
  WriteUint16(packet, static_cast<uint16_t>(header.preskip));
  WriteUint32(packet, static_cast<uint32_t>(header.inputSampleRate));
  WriteUint16(packet, static_cast<uint16_t>(header.gain));
  packet.push_back(static_cast<unsigned char>(header.channelMapping));

  if (header.channelMapping != 0) {
    packet.push_back(static_cast<unsigned char>(header.nbStreams));
    packet.push_back(static_cast<unsigned char>(header.nbCoupled));
    for (int index = 0; index < header.channels; index++) {
      packet.push_back(header.streamMap[index]);
    }
  }

  return packet;
}

std::vector<unsigned char> BuildOpusCommentPacket() {
  const char *vendor = opus_get_version_string();
  const size_t vendorLength = std::strlen(vendor);
  std::vector<unsigned char> packet;
  packet.reserve(32 + vendorLength + OPUS_COMMENT_PADDING);
  WriteChars(packet, "OpusTags", 8);
  WriteUint32(packet, static_cast<uint32_t>(vendorLength));
  WriteChars(packet, vendor, vendorLength);
  WriteUint32(packet, 0);

  const size_t paddedLength = ((packet.size() + OPUS_COMMENT_PADDING + 255) / 255) * 255 - 1;
  if (paddedLength > packet.size()) {
    packet.resize(paddedLength, 0);
  }
  return packet;
}

bool WriteOggPage(VoiceRecorderState &state, ogg_page *page, std::string &error) {
  if (state.outputFile == nullptr) {
    error = "Voice recorder output file is not open";
    return false;
  }

  const int writtenHeaderBytes =
      static_cast<int>(std::fwrite(page->header, sizeof(unsigned char), static_cast<size_t>(page->header_len), state.outputFile));
  const int writtenBodyBytes =
      static_cast<int>(std::fwrite(page->body, sizeof(unsigned char), static_cast<size_t>(page->body_len), state.outputFile));
  const int writtenBytes = writtenHeaderBytes + writtenBodyBytes;
  if (writtenBytes != page->header_len + page->body_len) {
    error = std::string("Failed to write OGG page: ") + std::strerror(errno);
    return false;
  }

  state.bytesWritten += writtenBytes;
  state.pagesOut++;
  return true;
}

void SetBits(uint8_t *bytes, int32_t bitOffset, int32_t value) {
  const size_t byteOffset = static_cast<size_t>(bitOffset / 8);
  const int bitShift = bitOffset % 8;
  const uint32_t encodedValue = static_cast<uint32_t>(value) << bitShift;
  bytes[byteOffset] |= static_cast<uint8_t>(encodedValue & 0xFFu);
  bytes[byteOffset + 1] |= static_cast<uint8_t>((encodedValue >> 8) & 0xFFu);
  bytes[byteOffset + 2] |= static_cast<uint8_t>((encodedValue >> 16) & 0xFFu);
  bytes[byteOffset + 3] |= static_cast<uint8_t>((encodedValue >> 24) & 0xFFu);
}

std::vector<uint8_t> BuildWaveform(const std::vector<int16_t> &samples) {
  std::array<uint16_t, OPUS_WAVEFORM_SAMPLE_COUNT> peaks {};
  const size_t bucketSize = std::max<size_t>(1, samples.size() / OPUS_WAVEFORM_SAMPLE_COUNT);
  size_t sampleIndex = 0;
  uint16_t peakSample = 0;
  int peakIndex = 0;

  for (size_t index = 0; index < samples.size(); index++) {
    int32_t sampleValue = static_cast<int32_t>(samples[index]);
    if (sampleValue < 0) {
      sampleValue = -sampleValue;
    }
    const uint16_t absoluteValue = static_cast<uint16_t>(sampleValue);
    if (absoluteValue > peakSample) {
      peakSample = absoluteValue;
    }
    if ((sampleIndex % bucketSize) == 0) {
      if (peakIndex < OPUS_WAVEFORM_SAMPLE_COUNT) {
        peaks[static_cast<size_t>(peakIndex)] = peakSample;
        peakIndex++;
      }
      peakSample = 0;
    }
    sampleIndex++;
  }

  int64_t peakSum = 0;
  for (int index = 0; index < OPUS_WAVEFORM_SAMPLE_COUNT; index++) {
    peakSum += peaks[static_cast<size_t>(index)];
  }

  uint16_t normalizedPeak = static_cast<uint16_t>((peakSum * 18) / (OPUS_WAVEFORM_SAMPLE_COUNT * 10));
  if (normalizedPeak < 2500) {
    normalizedPeak = 2500;
  }

  std::vector<uint8_t> bitstream(static_cast<size_t>(OPUS_WAVEFORM_BITSTREAM_LENGTH + 4), 0);
  for (int index = 0; index < OPUS_WAVEFORM_SAMPLE_COUNT; index++) {
    uint16_t clampedPeak = peaks[static_cast<size_t>(index)];
    if (clampedPeak > normalizedPeak) {
      clampedPeak = normalizedPeak;
    }
    const int32_t encodedValue = std::min<int32_t>(31, (static_cast<int32_t>(clampedPeak) * 31) / normalizedPeak);
    SetBits(bitstream.data(), index * 5, encodedValue & 31);
  }
  bitstream.resize(OPUS_WAVEFORM_BITSTREAM_LENGTH);
  return bitstream;
}

void ResetRecorderState(VoiceRecorderState &state) {
  state.streamInitialized = false;
  state.recordingActive = false;
  state.sampleRateHz = 48000;
  state.packetId = 0;
  state.maxFrameBytes = 0;
  state.minBytes = 0;
  state.lastSegments = 0;
  state.pendingPacketNo = 0;
  state.pendingSizeSegments = 0;
  state.totalSamples = 0;
  state.bytesWritten = 0;
  state.pagesOut = 0;
  state.encodedGranulePos = 0;
  state.lastGranulePos = 0;
  state.pendingGranulePos = 0;
  state.outputFile = nullptr;
  state.encoder = nullptr;
  std::memset(&state.streamState, 0, sizeof(ogg_stream_state));
  state.header = OpusHeader {};
  state.outputPath.clear();
  state.packetBuffer.clear();
  state.pendingPacket.clear();
  state.pendingInputBytes.clear();
  state.recordedSamples.clear();
}

void CleanupRecorderState(VoiceRecorderState &state, bool keepFile) {
  if (state.streamInitialized) {
    ogg_stream_clear(&state.streamState);
  }
  if (state.encoder != nullptr) {
    opus_encoder_destroy(state.encoder);
  }
  if (state.outputFile != nullptr) {
    std::fclose(state.outputFile);
  }
  const std::string outputPath = state.outputPath;
  ResetRecorderState(state);
  if (!keepFile && outputPath.length() > 0) {
    std::remove(outputPath.c_str());
  }
}

bool FlushOggStream(VoiceRecorderState &state, std::string &error) {
  ogg_page page {};
  while (ogg_stream_flush(&state.streamState, &page) != 0) {
    if (!WriteOggPage(state, &page, error)) {
      return false;
    }
  }
  return true;
}

bool CommitPendingPacket(VoiceRecorderState &state, bool endOfStream, std::string &error) {
  if (state.pendingPacket.empty()) {
    return true;
  }

  const size_t frameSizeSamples = FrameSizeSamplesForSampleRate(state.sampleRateHz);
  ogg_page page {};
  while ((((state.pendingSizeSegments <= 255) && (state.lastSegments + state.pendingSizeSegments > 255)) ||
          (state.pendingGranulePos - state.lastGranulePos > OPUS_MAX_OGG_DELAY)) &&
         ogg_stream_flush_fill(&state.streamState, &page, 255 * 255) != 0) {
    if (ogg_page_packets(&page) != 0) {
      state.lastGranulePos = ogg_page_granulepos(&page);
    }
    state.lastSegments -= page.header[26];
    if (!WriteOggPage(state, &page, error)) {
      return false;
    }
  }

  ogg_packet packet {};
  packet.packet = state.pendingPacket.data();
  packet.bytes = static_cast<long>(state.pendingPacket.size());
  packet.b_o_s = 0;
  packet.e_o_s = endOfStream ? 1 : 0;
  packet.granulepos = state.pendingGranulePos;
  packet.packetno = state.pendingPacketNo;
  ogg_stream_packetin(&state.streamState, &packet);
  state.lastSegments += state.pendingSizeSegments;

  while (((endOfStream ||
           (state.pendingGranulePos + static_cast<ogg_int64_t>(frameSizeSamples) * 48000 / state.sampleRateHz -
                state.lastGranulePos >
            OPUS_MAX_OGG_DELAY) ||
           (state.lastSegments >= 255))
              ? ogg_stream_flush_fill(&state.streamState, &page, 255 * 255)
              : ogg_stream_pageout_fill(&state.streamState, &page, 255 * 255)) != 0) {
    if (ogg_page_packets(&page) != 0) {
      state.lastGranulePos = ogg_page_granulepos(&page);
    }
    state.lastSegments -= page.header[26];
    if (!WriteOggPage(state, &page, error)) {
      return false;
    }
  }

  state.pendingPacket.clear();
  state.pendingPacketNo = 0;
  state.pendingSizeSegments = 0;
  state.pendingGranulePos = 0;
  return true;
}

bool EncodeFrame(VoiceRecorderState &state, const uint8_t *frameBytes, size_t actualSampleCount, std::string &error) {
  const size_t frameSizeSamples = FrameSizeSamplesForSampleRate(state.sampleRateHz);
  std::vector<opus_int16> pcmFrame(frameSizeSamples, 0);
  const size_t actualByteCount = actualSampleCount * OPUS_SAMPLE_SIZE_BYTES;
  if (actualByteCount > 0) {
    std::memcpy(pcmFrame.data(), frameBytes, actualByteCount);
  }

  const int encodedBytes = opus_encode(
      state.encoder,
      pcmFrame.data(),
      static_cast<int>(frameSizeSamples),
      state.packetBuffer.data(),
      state.maxFrameBytes / 10);
  if (encodedBytes < 0) {
    error = std::string("Opus encode failed: ") + opus_strerror(encodedBytes);
    return false;
  }

  if (!CommitPendingPacket(state, false, error)) {
    return false;
  }

  state.totalSamples += static_cast<opus_int64>(actualSampleCount);
  state.encodedGranulePos += static_cast<ogg_int64_t>(frameSizeSamples) * 48000 / state.sampleRateHz;
  state.pendingPacket.assign(state.packetBuffer.begin(), state.packetBuffer.begin() + encodedBytes);
  state.pendingPacketNo = 2 + state.packetId;
  state.pendingSizeSegments = (encodedBytes + 255) / 255;
  state.pendingGranulePos = state.encodedGranulePos;
  state.packetId++;
  state.minBytes = state.minBytes == 0 ? encodedBytes : std::min(state.minBytes, encodedBytes);
  return true;
}

void SeedRandomSerialIfNeeded() {
  static bool seeded = false;
  if (!seeded) {
    std::srand(static_cast<unsigned int>(std::time(nullptr)));
    seeded = true;
  }
}

bool AppendPcmSamples(VoiceRecorderState &state, const uint8_t *pcmBytes, size_t byteCount, std::string &error) {
  if ((byteCount % OPUS_SAMPLE_SIZE_BYTES) != 0) {
    error = "Voice frame byte length must contain full 16-bit PCM samples";
    return false;
  }

  const size_t sampleCount = byteCount / OPUS_SAMPLE_SIZE_BYTES;
  const size_t maxRecordedSamples = static_cast<size_t>(state.sampleRateHz) * static_cast<size_t>(OPUS_MAX_RECORDING_SECONDS);
  if (state.recordedSamples.size() + sampleCount > maxRecordedSamples) {
    error = "Voice recorder PCM buffer exceeded 90-second safety limit";
    return false;
  }

  const size_t previousSampleCount = state.recordedSamples.size();
  state.recordedSamples.resize(previousSampleCount + sampleCount);
  std::memcpy(state.recordedSamples.data() + previousSampleCount, pcmBytes, byteCount);
  return true;
}
}  // namespace

namespace opus_decoder {

bool StartVoiceRecord(const std::string &outputPath, int sampleRateHz, std::string &error) {
  std::lock_guard<std::mutex> lock(g_voiceRecorderState.mutex);
  CleanupRecorderState(g_voiceRecorderState, false);

  if (outputPath.length() == 0) {
    error = "Voice record output path must not be empty";
    return false;
  }
  if (sampleRateHz <= 0) {
    error = "Voice record sample rate must be positive";
    return false;
  }

  SeedRandomSerialIfNeeded();

  g_voiceRecorderState.outputPath = outputPath;
  g_voiceRecorderState.sampleRateHz = sampleRateHz;
  g_voiceRecorderState.header.channels = 1;
  g_voiceRecorderState.header.channelMapping = 0;
  g_voiceRecorderState.header.inputSampleRate = static_cast<ogg_uint32_t>(sampleRateHz);
  g_voiceRecorderState.header.gain = 0;
  g_voiceRecorderState.header.nbStreams = 1;
  g_voiceRecorderState.outputFile = std::fopen(outputPath.c_str(), "wb");
  if (g_voiceRecorderState.outputFile == nullptr) {
    error = std::string("Failed to open Opus output '") + outputPath + "': " + std::strerror(errno);
    CleanupRecorderState(g_voiceRecorderState, false);
    return false;
  }

  int encoderError = OPUS_OK;
  g_voiceRecorderState.encoder = opus_encoder_create(sampleRateHz, 1, OPUS_APPLICATION_VOIP, &encoderError);
  if (encoderError != OPUS_OK || g_voiceRecorderState.encoder == nullptr) {
    error = std::string("Failed to create Opus encoder: ") + opus_strerror(encoderError);
    CleanupRecorderState(g_voiceRecorderState, false);
    return false;
  }

  g_voiceRecorderState.maxFrameBytes = (1275 * 3 + 7) * g_voiceRecorderState.header.nbStreams;
  g_voiceRecorderState.packetBuffer.resize(static_cast<size_t>(g_voiceRecorderState.maxFrameBytes));

  int controlResult = opus_encoder_ctl(g_voiceRecorderState.encoder, OPUS_SET_BITRATE(OPUS_RECORDING_BITRATE));
  if (controlResult != OPUS_OK) {
    error = std::string("Failed to configure Opus bitrate: ") + opus_strerror(controlResult);
    CleanupRecorderState(g_voiceRecorderState, false);
    return false;
  }

  controlResult = opus_encoder_ctl(g_voiceRecorderState.encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
  if (controlResult != OPUS_OK) {
    error = std::string("Failed to configure Opus signal type: ") + opus_strerror(controlResult);
    CleanupRecorderState(g_voiceRecorderState, false);
    return false;
  }

#ifdef OPUS_SET_LSB_DEPTH
  controlResult = opus_encoder_ctl(g_voiceRecorderState.encoder, OPUS_SET_LSB_DEPTH(16));
  if (controlResult != OPUS_OK) {
    error = std::string("Failed to configure Opus LSB depth: ") + opus_strerror(controlResult);
    CleanupRecorderState(g_voiceRecorderState, false);
    return false;
  }
#endif

  opus_int32 lookahead = 0;
  controlResult = opus_encoder_ctl(g_voiceRecorderState.encoder, OPUS_GET_LOOKAHEAD(&lookahead));
  if (controlResult != OPUS_OK) {
    error = std::string("Failed to read Opus lookahead: ") + opus_strerror(controlResult);
    CleanupRecorderState(g_voiceRecorderState, false);
    return false;
  }

  g_voiceRecorderState.header.preskip = static_cast<int>(lookahead * (48000.0 / sampleRateHz));
  if (ogg_stream_init(&g_voiceRecorderState.streamState, std::rand()) == -1) {
    error = "Failed to initialize OGG stream";
    CleanupRecorderState(g_voiceRecorderState, false);
    return false;
  }
  g_voiceRecorderState.streamInitialized = true;

  const std::vector<unsigned char> headerPacket = BuildOpusHeaderPacket(g_voiceRecorderState.header);
  ogg_packet oggHeaderPacket {};
  oggHeaderPacket.packet = const_cast<unsigned char *>(headerPacket.data());
  oggHeaderPacket.bytes = static_cast<long>(headerPacket.size());
  oggHeaderPacket.b_o_s = 1;
  oggHeaderPacket.e_o_s = 0;
  oggHeaderPacket.granulepos = 0;
  oggHeaderPacket.packetno = 0;
  ogg_stream_packetin(&g_voiceRecorderState.streamState, &oggHeaderPacket);
  if (!FlushOggStream(g_voiceRecorderState, error)) {
    CleanupRecorderState(g_voiceRecorderState, false);
    return false;
  }

  const std::vector<unsigned char> commentPacket = BuildOpusCommentPacket();
  ogg_packet oggCommentPacket {};
  oggCommentPacket.packet = const_cast<unsigned char *>(commentPacket.data());
  oggCommentPacket.bytes = static_cast<long>(commentPacket.size());
  oggCommentPacket.b_o_s = 0;
  oggCommentPacket.e_o_s = 0;
  oggCommentPacket.granulepos = 0;
  oggCommentPacket.packetno = 1;
  ogg_stream_packetin(&g_voiceRecorderState.streamState, &oggCommentPacket);
  if (!FlushOggStream(g_voiceRecorderState, error)) {
    CleanupRecorderState(g_voiceRecorderState, false);
    return false;
  }

  g_voiceRecorderState.recordingActive = true;
  return true;
}

bool WriteVoiceFrame(const uint8_t *pcmBytes, size_t byteCount, std::string &error) {
  std::lock_guard<std::mutex> lock(g_voiceRecorderState.mutex);
  if (!g_voiceRecorderState.recordingActive || g_voiceRecorderState.encoder == nullptr) {
    error = "Voice recorder is not active";
    return false;
  }
  if (byteCount == 0) {
    return true;
  }
  if ((byteCount % OPUS_SAMPLE_SIZE_BYTES) != 0) {
    error = "Voice frame byte length must contain full 16-bit PCM samples";
    return false;
  }

  if (!AppendPcmSamples(g_voiceRecorderState, pcmBytes, byteCount, error)) {
    return false;
  }

  g_voiceRecorderState.pendingInputBytes.insert(
      g_voiceRecorderState.pendingInputBytes.end(),
      pcmBytes,
      pcmBytes + byteCount);

  const size_t frameSizeSamples = FrameSizeSamplesForSampleRate(g_voiceRecorderState.sampleRateHz);
  const size_t frameSizeBytes = FrameSizeBytesForSampleRate(g_voiceRecorderState.sampleRateHz);
  size_t encodedOffset = 0;
  while (g_voiceRecorderState.pendingInputBytes.size() - encodedOffset >= frameSizeBytes) {
    if (!EncodeFrame(
            g_voiceRecorderState,
            g_voiceRecorderState.pendingInputBytes.data() + encodedOffset,
            frameSizeSamples,
            error)) {
      CleanupRecorderState(g_voiceRecorderState, false);
      return false;
    }
    encodedOffset += frameSizeBytes;
  }

  if (encodedOffset > 0) {
    if (encodedOffset < g_voiceRecorderState.pendingInputBytes.size()) {
      g_voiceRecorderState.pendingInputBytes.erase(
          g_voiceRecorderState.pendingInputBytes.begin(),
          g_voiceRecorderState.pendingInputBytes.begin() + static_cast<std::ptrdiff_t>(encodedOffset));
    } else {
      g_voiceRecorderState.pendingInputBytes.clear();
    }
  }

  return true;
}

VoiceRecordResult StopVoiceRecord() {
  std::lock_guard<std::mutex> lock(g_voiceRecorderState.mutex);
  VoiceRecordResult result;
  if (!g_voiceRecorderState.recordingActive || g_voiceRecorderState.encoder == nullptr) {
    result.error = "Voice recorder is not active";
    return result;
  }

  std::string error;
  if (!g_voiceRecorderState.pendingInputBytes.empty()) {
    const size_t remainingSampleCount = g_voiceRecorderState.pendingInputBytes.size() / OPUS_SAMPLE_SIZE_BYTES;
    if (!EncodeFrame(g_voiceRecorderState, g_voiceRecorderState.pendingInputBytes.data(), remainingSampleCount, error)) {
      result.error = error;
      CleanupRecorderState(g_voiceRecorderState, false);
      return result;
    }
    g_voiceRecorderState.pendingInputBytes.clear();
  }

  if (g_voiceRecorderState.pendingPacket.empty() || g_voiceRecorderState.recordedSamples.empty()) {
    result.error = "Voice recorder has no captured audio";
    CleanupRecorderState(g_voiceRecorderState, false);
    return result;
  }

  g_voiceRecorderState.pendingGranulePos =
      ((g_voiceRecorderState.totalSamples * 48000 + g_voiceRecorderState.sampleRateHz - 1) / g_voiceRecorderState.sampleRateHz) +
      g_voiceRecorderState.header.preskip;
  if (!CommitPendingPacket(g_voiceRecorderState, true, error)) {
    result.error = error;
    CleanupRecorderState(g_voiceRecorderState, false);
    return result;
  }
  if (!FlushOggStream(g_voiceRecorderState, error)) {
    result.error = error;
    CleanupRecorderState(g_voiceRecorderState, false);
    return result;
  }

  result.success = true;
  result.outputPath = g_voiceRecorderState.outputPath;
  result.mimeType = "audio/ogg";
  result.containerFormat = "ogg";
  result.audioCodec = "opus";
  result.durationSec = static_cast<int>(
      std::lround(static_cast<double>(g_voiceRecorderState.totalSamples) / g_voiceRecorderState.sampleRateHz));
  result.durationMs = ComputeDurationMs(g_voiceRecorderState.totalSamples, g_voiceRecorderState.sampleRateHz);
  result.sampleRateHz = g_voiceRecorderState.sampleRateHz;
  result.channelCount = g_voiceRecorderState.header.channels;
  result.targetBitrateBps = OPUS_RECORDING_BITRATE;
  result.averageBitrateBps = ComputeAverageBitrateBps(
      g_voiceRecorderState.bytesWritten,
      g_voiceRecorderState.totalSamples,
      g_voiceRecorderState.sampleRateHz);
  result.fileSizeBytes = g_voiceRecorderState.bytesWritten;
  result.pageCount = g_voiceRecorderState.pagesOut;
  result.waveform = BuildWaveform(g_voiceRecorderState.recordedSamples);
  CleanupRecorderState(g_voiceRecorderState, true);
  return result;
}

}  // namespace opus_decoder
