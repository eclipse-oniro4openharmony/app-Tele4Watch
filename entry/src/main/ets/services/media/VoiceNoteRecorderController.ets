import { hilog } from '@kit.PerformanceAnalysisKit';
import { audio } from '@kit.AudioKit';
import fs from '@ohos.file.fs';
import { opusNativeBridge, VOICE_RECORDER_MAX_DURATION_SECONDS } from 'opusdecoder';
import { cloneArrayBuffer } from './ArrayBufferClone';

const DOMAIN = 0x2026;
const TAG = 'VoiceNoteRecorder';
const VOICE_NOTE_PREFERRED_SAMPLE_RATE_HZ: number = 48000;
const FRAME_WRITE_ERROR_MESSAGE: string = 'Voice note encoder rejected PCM frame.';
const START_ERROR_MESSAGE: string = 'Voice note encoder failed to start.';
const TOO_SHORT_ERROR_MESSAGE: string = 'Voice note is too short to send.';
const EMPTY_WAVEFORM_ERROR_MESSAGE: string = 'Voice note waveform is unavailable.';

export type VoiceNoteRecorderPhase = 'idle' | 'recording' | 'stopping' | 'error';

export interface VoiceNoteRecorderSnapshot {
  'phase': VoiceNoteRecorderPhase;
  'elapsedSeconds': number;
  'filePath': string;
  'errorMessage': string;
}

export interface VoiceNoteRecordingResult {
  'filePath': string;
  'durationSec': number;
  'waveform': ArrayBuffer;
}

export type VoiceNoteReadDataListener = (buffer: ArrayBuffer) => void;

export interface VoiceNoteAudioCapturer {
  'setReadDataListener': (listener: VoiceNoteReadDataListener | undefined) => void;
  'start': () => Promise<void>;
  'stop': () => Promise<void>;
  'release': () => Promise<void>;
}

export interface VoiceNoteAudioCapturerFactory {
  'createCapturer': () => Promise<VoiceNoteAudioCapturer>;
}

export interface VoiceNoteRecorderBridge {
  'startVoiceRecord': (outputPath: string, sampleRate: number) => boolean;
  'writeVoiceFrame': (pcm: ArrayBuffer, length: number) => boolean;
  'stopVoiceRecord': () => VoiceNoteNativeRecordResult;
}

export interface VoiceNoteNativeRecordResult {
  'durationSec': number;
  'waveform': ArrayBuffer;
}

export function createIdleVoiceNoteRecorderSnapshot(): VoiceNoteRecorderSnapshot {
  return {
    'phase': 'idle',
    'elapsedSeconds': 0,
    'filePath': '',
    'errorMessage': ''
  };
}

function buildErrorMessage(error: string | Error | Object): string {
  if (typeof error === 'string') {
    const trimmed = error.trim();
    if (trimmed.length > 0) {
      return trimmed;
    }
  }

  if (error instanceof Error && typeof error.message === 'string') {
    const trimmedMessage = error.message.trim();
    if (trimmedMessage.length > 0) {
      return trimmedMessage;
    }
  }

  return String(error);
}

class AudioKitVoiceNoteCapturer implements VoiceNoteAudioCapturer {
  private readonly capturer: audio.AudioCapturer;
  private readDataHandler: ((buffer: ArrayBuffer) => void) | undefined = undefined;

  constructor(capturer: audio.AudioCapturer) {
    this.capturer = capturer;
  }

  setReadDataListener(listener: VoiceNoteReadDataListener | undefined): void {
    if (this.readDataHandler) {
      try {
        this.capturer.off('readData', this.readDataHandler);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Recorder failed to unregister readData callback: %{public}s', buildErrorMessage(error));
      }
      this.readDataHandler = undefined;
    }

    if (!listener) {
      return;
    }

    this.readDataHandler = (buffer: ArrayBuffer): void => {
      listener(buffer);
    };
    try {
      this.capturer.on('readData', this.readDataHandler);
    } catch (error) {
      this.readDataHandler = undefined;
      throw new Error(buildErrorMessage(error));
    }
  }

  start(): Promise<void> {
    return this.capturer.start();
  }

  stop(): Promise<void> {
    return this.capturer.stop();
  }

  release(): Promise<void> {
    return this.capturer.release();
  }
}

class AudioKitVoiceNoteCapturerFactory implements VoiceNoteAudioCapturerFactory {
  async createCapturer(): Promise<VoiceNoteAudioCapturer> {
    const capturer = await audio.createAudioCapturer({
      'streamInfo': {
        'samplingRate': audio.AudioSamplingRate.SAMPLE_RATE_48000,
        'channels': audio.AudioChannel.CHANNEL_1,
        'sampleFormat': audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        'encodingType': audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      'capturerInfo': {
        'source': audio.SourceType.SOURCE_TYPE_MIC,
        'capturerFlags': 0
      }
    });
    return new AudioKitVoiceNoteCapturer(capturer);
  }
}

/**
 * Owns one page-scoped voice-note capture session and exposes a reactive snapshot.
 */
export class VoiceNoteRecorderController {
  private readonly capturerFactory: VoiceNoteAudioCapturerFactory;
  private readonly recorderBridge: VoiceNoteRecorderBridge;
  private listener: ((snapshot: VoiceNoteRecorderSnapshot) => void) | undefined = undefined;
  private snapshot: VoiceNoteRecorderSnapshot = createIdleVoiceNoteRecorderSnapshot();
  private operationChain: Promise<void> = Promise.resolve();
  private frameDrainPromise: Promise<void> = Promise.resolve();
  private capturer: VoiceNoteAudioCapturer | undefined = undefined;
  private activeFilePath: string = '';
  private nativeRecorderActive: boolean = false;
  private timerId: number = -1;
  private startedAtMs: number = 0;
  private cleanupAfterReadFailureScheduled: boolean = false;
  private frameDrainActive: boolean = false;
  private frameWriteFailureMessage: string = '';
  private pendingPcmFrames: Array<ArrayBuffer> = [];
  private pendingPcmFrameCursor: number = 0;
  private pendingPcmBytes: number = 0;
  private capturedPcmBytes: number = 0;
  private readCallbackCount: number = 0;
  private maxPendingPcmBytes: number = 0;

  constructor(
    capturerFactory?: VoiceNoteAudioCapturerFactory,
    recorderBridge?: VoiceNoteRecorderBridge
  ) {
    this.capturerFactory = capturerFactory ? capturerFactory : new AudioKitVoiceNoteCapturerFactory();
    this.recorderBridge = recorderBridge ? recorderBridge : opusNativeBridge;
  }

  setListener(listener: ((snapshot: VoiceNoteRecorderSnapshot) => void) | undefined): void {
    this.listener = listener;
    this.notifyListener();
  }

  getSnapshot(): VoiceNoteRecorderSnapshot {
    return {
      'phase': this.snapshot.phase,
      'elapsedSeconds': this.snapshot.elapsedSeconds,
      'filePath': this.snapshot.filePath,
      'errorMessage': this.snapshot.errorMessage
    };
  }

  start(filePath: string): Promise<boolean> {
    return this.enqueueWithResult<boolean>(async (): Promise<boolean> => {
      const normalizedFilePath = filePath.trim();
      if (normalizedFilePath.length === 0) {
        this.applyErrorState('Voice note output path is unavailable.', '');
        return false;
      }
      if (this.snapshot.phase === 'recording' || this.snapshot.phase === 'stopping') {
        hilog.warn(DOMAIN, TAG, 'Recorder start skipped because another session is active.');
        return false;
      }

      return this.startInternal(normalizedFilePath);
    }, false);
  }

  stop(): Promise<VoiceNoteRecordingResult | undefined> {
    return this.enqueueWithResult<VoiceNoteRecordingResult | undefined>(
      async (): Promise<VoiceNoteRecordingResult | undefined> => {
        if (!this.capturer || this.activeFilePath.length === 0) {
          hilog.warn(DOMAIN, TAG, 'Recorder stop skipped: no active session.');
          return undefined;
        }

        this.updateElapsedSnapshot('stopping');
        this.stopElapsedTimer();

        const activeFilePath = this.activeFilePath;
        const activeCapturer = this.capturer;
        this.capturer = undefined;

        // Each cleanup step runs exactly once. Outer try/catch would re-release or
        // re-stop when a later step throws after earlier steps already succeeded.
        let firstFailure: string = '';

        try {
          activeCapturer.setReadDataListener(undefined);
        } catch (error) {
          hilog.warn(DOMAIN, TAG, 'Recorder failed to detach readData on stop: %{public}s',
            buildErrorMessage(error));
        }

        try {
          await activeCapturer.stop();
        } catch (error) {
          firstFailure = buildErrorMessage(error);
          hilog.warn(DOMAIN, TAG, 'Recorder capturer stop failed: %{public}s', firstFailure);
        }

        try {
          await this.awaitPendingFrameDrain();
        } catch (error) {
          const frameDrainError = buildErrorMessage(error);
          if (firstFailure.length === 0) {
            firstFailure = frameDrainError;
          }
          hilog.warn(DOMAIN, TAG, 'Recorder pending PCM drain failed: %{public}s', frameDrainError);
        }

        if (firstFailure.length === 0 && this.frameWriteFailureMessage.length > 0) {
          firstFailure = this.frameWriteFailureMessage;
        }

        try {
          await activeCapturer.release();
        } catch (error) {
          const releaseError = buildErrorMessage(error);
          if (firstFailure.length === 0) {
            firstFailure = releaseError;
          }
          hilog.warn(DOMAIN, TAG, 'Recorder capturer release failed: %{public}s', releaseError);
        }

        let nativeResult: VoiceNoteNativeRecordResult | undefined = undefined;
        if (this.nativeRecorderActive) {
          try {
            nativeResult = this.stopNativeRecorder();
          } catch (error) {
            const nativeError = buildErrorMessage(error);
            if (firstFailure.length === 0) {
              firstFailure = nativeError;
            }
            hilog.warn(DOMAIN, TAG, 'Recorder native stop failed: %{public}s', nativeError);
          }
        }

        this.activeFilePath = '';

        if (firstFailure.length > 0 || !nativeResult) {
          this.startedAtMs = 0;
          this.resetCaptureMetrics();
          this.deleteFileIfPresent(activeFilePath);
          const errorMessage = firstFailure.length > 0
            ? firstFailure
            : 'Voice note encoder returned no result.';
          this.applyErrorState(errorMessage, activeFilePath);
          return undefined;
        }

        const waveformLength = new Uint8Array(nativeResult.waveform).length;
        if (nativeResult.durationSec <= 0) {
          this.deleteFileIfPresent(activeFilePath);
          this.applyErrorState(TOO_SHORT_ERROR_MESSAGE, activeFilePath);
          return undefined;
        }
        if (waveformLength <= 0) {
          this.deleteFileIfPresent(activeFilePath);
          this.applyErrorState(EMPTY_WAVEFORM_ERROR_MESSAGE, activeFilePath);
          return undefined;
        }

        this.logSessionSummary(nativeResult.durationSec);
        this.startedAtMs = 0;
        this.resetCaptureMetrics();
        this.setSnapshot(createIdleVoiceNoteRecorderSnapshot());
        return {
          'filePath': activeFilePath,
          'durationSec': nativeResult.durationSec,
          'waveform': cloneArrayBuffer(nativeResult.waveform)
        };
      },
      undefined
    );
  }

  cancel(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      await this.cancelInternal(true);
    });
  }

  release(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      await this.cancelInternal(true);
      if (this.snapshot.phase === 'error') {
        this.setSnapshot(createIdleVoiceNoteRecorderSnapshot());
      }
    });
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const nextOperation = this.operationChain.then(async (): Promise<void> => {
      try {
        await operation();
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'Recorder queued operation failed: %{public}s', buildErrorMessage(error));
        this.applyErrorState(buildErrorMessage(error), this.activeFilePath);
      }
    });
    this.operationChain = nextOperation.then((): void => {
      // Keep queue alive after failures.
    });
    return nextOperation;
  }

  private enqueueWithResult<T>(operation: () => Promise<T>, fallbackValue: T): Promise<T> {
    let resolvedValue: T = fallbackValue;
    const nextOperation = this.operationChain.then(async (): Promise<void> => {
      try {
        resolvedValue = await operation();
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'Recorder queued operation failed: %{public}s', buildErrorMessage(error));
        this.applyErrorState(buildErrorMessage(error), this.activeFilePath);
      }
    });
    this.operationChain = nextOperation.then((): void => {
      // Keep queue alive after failures.
    });
    return nextOperation.then((): T => {
      return resolvedValue;
    });
  }

  private async startInternal(filePath: string): Promise<boolean> {
    let createdCapturer: VoiceNoteAudioCapturer | undefined = undefined;
    try {
      this.cleanupAfterReadFailureScheduled = false;
      this.startedAtMs = 0;
      this.resetCaptureMetrics();
      createdCapturer = await this.capturerFactory.createCapturer();
      if (!this.recorderBridge.startVoiceRecord(filePath, VOICE_NOTE_PREFERRED_SAMPLE_RATE_HZ)) {
        throw new Error(START_ERROR_MESSAGE);
      }
      this.nativeRecorderActive = true;
      this.activeFilePath = filePath;
      this.capturer = createdCapturer;
      createdCapturer.setReadDataListener((buffer: ArrayBuffer): void => {
        this.handleReadData(buffer);
      });
      await createdCapturer.start();
      this.startedAtMs = Date.now();
      this.startElapsedTimer();
      this.setSnapshot({
        'phase': 'recording',
        'elapsedSeconds': 0,
        'filePath': filePath,
        'errorMessage': ''
      });
      hilog.info(
        DOMAIN,
        TAG,
        'Recorder started: %{public}s (sampleRateHz=%{public}d)',
        filePath,
        VOICE_NOTE_PREFERRED_SAMPLE_RATE_HZ
      );
      return true;
    } catch (error) {
      this.stopElapsedTimer();
      this.startedAtMs = 0;
      this.resetCaptureMetrics();
      if (createdCapturer) {
        await this.safeReleaseCapturer(createdCapturer, false);
      }
      this.safeStopNativeRecorder();
      this.activeFilePath = '';
      this.deleteFileIfPresent(filePath);
      this.applyErrorState(buildErrorMessage(error), filePath);
      return false;
    }
  }

  private handleReadData(buffer: ArrayBuffer): void {
    if (this.snapshot.phase !== 'recording' && this.snapshot.phase !== 'stopping') {
      return;
    }

    this.capturedPcmBytes += buffer.byteLength;
    this.readCallbackCount += 1;
    this.enqueuePcmFrame(cloneArrayBuffer(buffer));
    const elapsedSeconds = this.calculateElapsedSeconds();
    if (elapsedSeconds >= VOICE_RECORDER_MAX_DURATION_SECONDS) {
      hilog.info(DOMAIN, TAG, 'Recorder reached duration cap=%{public}d seconds.', elapsedSeconds);
    }
  }

  private handleReadFailure(errorMessage: string): void {
    if (this.cleanupAfterReadFailureScheduled) {
      return;
    }
    this.cleanupAfterReadFailureScheduled = true;
    this.stopElapsedTimer();
    this.applyErrorState(errorMessage, this.activeFilePath);
    void this.enqueue(async (): Promise<void> => {
      await this.cancelInternal(false);
      this.cleanupAfterReadFailureScheduled = false;
    });
  }

  private async cancelInternal(resetSnapshot: boolean): Promise<void> {
    const activeFilePath = this.activeFilePath;
    this.stopElapsedTimer();
    this.startedAtMs = 0;
    this.resetCaptureMetrics();

    const activeCapturer = this.capturer;
    this.capturer = undefined;
    this.activeFilePath = '';
    if (activeCapturer) {
      await this.safeReleaseCapturer(activeCapturer, true);
    }
    this.safeStopNativeRecorder();
    this.deleteFileIfPresent(activeFilePath);
    if (resetSnapshot) {
      this.setSnapshot(createIdleVoiceNoteRecorderSnapshot());
    }
  }

  private async safeReleaseCapturer(capturer: VoiceNoteAudioCapturer, shouldStop: boolean): Promise<void> {
    try {
      capturer.setReadDataListener(undefined);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Recorder failed to detach readData listener: %{public}s', buildErrorMessage(error));
    }

    if (shouldStop) {
      try {
        await capturer.stop();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Recorder capturer stop failed during cleanup: %{public}s', buildErrorMessage(error));
      }
    }

    try {
      await capturer.release();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Recorder capturer release failed during cleanup: %{public}s', buildErrorMessage(error));
    }
  }

  private stopNativeRecorder(): VoiceNoteNativeRecordResult {
    // try/finally guarantees the active flag is cleared even when the bridge
    // throws — otherwise safeStopNativeRecorder could retry a failed stop.
    try {
      return this.recorderBridge.stopVoiceRecord();
    } finally {
      this.nativeRecorderActive = false;
    }
  }

  private safeStopNativeRecorder(): void {
    if (!this.nativeRecorderActive) {
      return;
    }
    try {
      this.recorderBridge.stopVoiceRecord();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Recorder native stop failed during cleanup: %{public}s', buildErrorMessage(error));
    }
    this.nativeRecorderActive = false;
  }

  private startElapsedTimer(): void {
    this.stopElapsedTimer();
    this.timerId = setInterval((): void => {
      if (this.snapshot.phase !== 'recording') {
        return;
      }
      this.updateElapsedSnapshot('recording');
    }, 1000);
  }

  private stopElapsedTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private updateElapsedSnapshot(phase: VoiceNoteRecorderPhase): void {
    this.setSnapshot({
      'phase': phase,
      'elapsedSeconds': this.calculateElapsedSeconds(),
      'filePath': this.activeFilePath,
      'errorMessage': ''
    });
  }

  private calculateElapsedSeconds(): number {
    if (this.startedAtMs <= 0) {
      return 0;
    }
    const elapsedMs = Date.now() - this.startedAtMs;
    if (elapsedMs <= 0) {
      return 0;
    }
    return Math.floor(elapsedMs / 1000);
  }

  private applyErrorState(errorMessage: string, filePath: string): void {
    this.setSnapshot({
      'phase': 'error',
      'elapsedSeconds': this.calculateElapsedSeconds(),
      'filePath': filePath,
      'errorMessage': errorMessage
    });
  }

  private setSnapshot(snapshot: VoiceNoteRecorderSnapshot): void {
    this.snapshot = {
      'phase': snapshot.phase,
      'elapsedSeconds': snapshot.elapsedSeconds,
      'filePath': snapshot.filePath,
      'errorMessage': snapshot.errorMessage
    };
    this.notifyListener();
  }

  private logSessionSummary(nativeDurationSec: number): void {
    const capturedSamples = Math.floor(this.capturedPcmBytes / 2);
    const elapsedSeconds = this.calculateElapsedSeconds();
    const effectiveRateHz = elapsedSeconds > 0
      ? Math.round(capturedSamples / elapsedSeconds)
      : 0;
    hilog.info(
      DOMAIN,
      TAG,
      'Recorder session summary: sampleRateHz=%{public}d callbacks=%{public}d pcmBytes=%{public}d elapsedSec=%{public}d effectiveRateHz=%{public}d nativeDurationSec=%{public}d maxPendingPcmBytes=%{public}d',
      VOICE_NOTE_PREFERRED_SAMPLE_RATE_HZ,
      this.readCallbackCount,
      this.capturedPcmBytes,
      elapsedSeconds,
      effectiveRateHz,
      nativeDurationSec,
      this.maxPendingPcmBytes
    );
  }

  private resetCaptureMetrics(): void {
    this.frameWriteFailureMessage = '';
    this.pendingPcmFrames = [];
    this.pendingPcmFrameCursor = 0;
    this.pendingPcmBytes = 0;
    this.capturedPcmBytes = 0;
    this.readCallbackCount = 0;
    this.maxPendingPcmBytes = 0;
  }

  private enqueuePcmFrame(buffer: ArrayBuffer): void {
    this.pendingPcmFrames.push(buffer);
    this.pendingPcmBytes += buffer.byteLength;
    if (this.pendingPcmBytes > this.maxPendingPcmBytes) {
      this.maxPendingPcmBytes = this.pendingPcmBytes;
    }
    if (this.frameDrainActive) {
      return;
    }

    this.frameDrainActive = true;
    this.frameDrainPromise = Promise.resolve().then((): void => {
      this.drainPendingFrames();
    }).finally((): void => {
      this.frameDrainActive = false;
    });
  }

  private async awaitPendingFrameDrain(): Promise<void> {
    await this.frameDrainPromise;
  }

  private drainPendingFrames(): void {
    while (this.pendingPcmFrameCursor < this.pendingPcmFrames.length) {
      if (this.frameWriteFailureMessage.length > 0 || !this.nativeRecorderActive) {
        break;
      }

      const frame = this.pendingPcmFrames[this.pendingPcmFrameCursor];
      this.pendingPcmFrameCursor += 1;
      this.pendingPcmBytes -= frame.byteLength;

      try {
        const writeAccepted = this.recorderBridge.writeVoiceFrame(frame, frame.byteLength);
        if (!writeAccepted) {
          throw new Error(FRAME_WRITE_ERROR_MESSAGE);
        }
      } catch (error) {
        this.frameWriteFailureMessage = buildErrorMessage(error);
        this.handleReadFailure(this.frameWriteFailureMessage);
        break;
      }
    }

    if (this.pendingPcmFrameCursor >= this.pendingPcmFrames.length) {
      this.pendingPcmFrames = [];
      this.pendingPcmFrameCursor = 0;
      this.pendingPcmBytes = 0;
    }
  }

  private notifyListener(): void {
    if (!this.listener) {
      return;
    }
    this.listener(this.getSnapshot());
  }

  private deleteFileIfPresent(filePath: string): void {
    if (filePath.trim().length === 0) {
      return;
    }
    try {
      fs.statSync(filePath);
    } catch (_error) {
      return;
    }

    try {
      fs.unlinkSync(filePath);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Recorder temp-file cleanup failed for %{public}s: %{public}s',
        filePath, buildErrorMessage(error));
    }
  }
}
