declare module 'libopusdecoder.so' {
  export interface VoiceRecordResult {
    durationSec: number;
    waveform: ArrayBuffer;
  }

  export interface OpusNativeBridge {
    decodeOpusToWav(inputPath: string, outputPath: string): string;
    startVoiceRecord(outputPath: string, sampleRate: number): boolean;
    writeVoiceFrame(pcm: ArrayBuffer, length: number): boolean;
    stopVoiceRecord(): VoiceRecordResult;
  }

  const opusNativeBridge: OpusNativeBridge;
  export default opusNativeBridge;
}
