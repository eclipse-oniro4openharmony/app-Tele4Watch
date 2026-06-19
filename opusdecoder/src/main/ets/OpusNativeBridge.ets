import opusDecoderModule, { OpusNativeBridge as NativeOpusBridgeModule } from 'libopusdecoder.so';

/**
 * Recorder duration cap aligned with the native PCM safety guard.
 */
export const VOICE_RECORDER_MAX_DURATION_SECONDS: number = 90;

export interface VoiceRecordResult {
  durationSec: number;
  waveform: ArrayBuffer;
}

class OpusNativeBridgeClient {
  private readonly nativeModule: NativeOpusBridgeModule = opusDecoderModule;

  decodeOpusToWav(inputPath: string, outputPath: string): string {
    return this.nativeModule.decodeOpusToWav(inputPath, outputPath);
  }

  startVoiceRecord(outputPath: string, sampleRate: number): boolean {
    return this.nativeModule.startVoiceRecord(outputPath, sampleRate);
  }

  /**
   * Writes one PCM frame chunk into the active recorder.
   *
   * The native encoder enforces a hard 90-second safety limit, so callers should
   * stop capture before exceeding `VOICE_RECORDER_MAX_DURATION_SECONDS`.
   */
  writeVoiceFrame(pcm: ArrayBuffer, length: number): boolean {
    return this.nativeModule.writeVoiceFrame(pcm, length);
  }

  stopVoiceRecord(): VoiceRecordResult {
    return this.nativeModule.stopVoiceRecord();
  }
}

export const opusNativeBridge: OpusNativeBridgeClient = new OpusNativeBridgeClient();
