import { hilog } from '@kit.PerformanceAnalysisKit';
import fs from '@ohos.file.fs';
import { VoiceNoteRecordingResult } from './VoiceNoteRecorderController';
import { cloneArrayBuffer } from './ArrayBufferClone';

const DOMAIN = 0x2026;
const TAG = 'VoiceNoteDraftStore';
const VOICE_NOTE_DIRECTORY_NAME: string = 'voice_notes';

export interface VoiceNoteDraftPayload {
  'filePath': string;
  'durationSec': number;
  'waveform': ArrayBuffer;
}

export abstract class VoiceNoteDraftStorageIO {
  abstract ensureDirectory(directoryPath: string): boolean;
  abstract deleteFileIfPresent(filePath: string): void;
}

class FileSystemVoiceNoteDraftStorageIO extends VoiceNoteDraftStorageIO {
  ensureDirectory(directoryPath: string): boolean {
    try {
      fs.mkdirSync(directoryPath);
      return true;
    } catch (_error) {
      try {
        fs.statSync(directoryPath);
        return true;
      } catch (_statError) {
        return false;
      }
    }
  }

  deleteFileIfPresent(filePath: string): void {
    const normalizedPath = filePath.trim();
    if (normalizedPath.length === 0) {
      return;
    }

    try {
      fs.statSync(normalizedPath);
    } catch (_error) {
      return;
    }

    try {
      fs.unlinkSync(normalizedPath);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Draft temp-file cleanup failed for %{public}s: %{public}s',
        normalizedPath, String(error));
    }
  }
}

/**
 * Owns one pending voice-note draft and its temporary-file lifecycle.
 */
export class VoiceNoteDraftStore {
  private readonly storageIO: VoiceNoteDraftStorageIO;
  private pendingFilePath: string = '';
  private pendingDurationSec: number = 0;
  private pendingWaveform: ArrayBuffer = new ArrayBuffer(0);

  constructor(storageIO?: VoiceNoteDraftStorageIO) {
    this.storageIO = storageIO ? storageIO : new FileSystemVoiceNoteDraftStorageIO();
  }

  createOutputPath(cacheDir: string): string {
    const normalizedCacheDir = cacheDir.trim();
    if (normalizedCacheDir.length === 0) {
      throw new Error('Cache directory is unavailable.');
    }

    const outputDirectory = `${normalizedCacheDir}/${VOICE_NOTE_DIRECTORY_NAME}`;
    if (!this.storageIO.ensureDirectory(outputDirectory)) {
      throw new Error('Voice note cache directory could not be created.');
    }

    const suffix = `${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
    return `${outputDirectory}/voice-note-${suffix}.oga`;
  }

  storePending(result: VoiceNoteRecordingResult): void {
    this.pendingFilePath = result.filePath;
    this.pendingDurationSec = result.durationSec;
    this.pendingWaveform = cloneArrayBuffer(result.waveform);
  }

  getPendingPayload(): VoiceNoteDraftPayload | undefined {
    const normalizedFilePath = this.pendingFilePath.trim();
    const waveformLength = new Uint8Array(this.pendingWaveform).length;
    if (normalizedFilePath.length === 0 || this.pendingDurationSec <= 0 || waveformLength <= 0) {
      return undefined;
    }

    return {
      'filePath': normalizedFilePath,
      'durationSec': this.pendingDurationSec,
      'waveform': cloneArrayBuffer(this.pendingWaveform)
    };
  }

  clearPending(deleteFile: boolean): void {
    const currentFilePath = this.pendingFilePath;
    this.pendingFilePath = '';
    this.pendingDurationSec = 0;
    this.pendingWaveform = new ArrayBuffer(0);
    if (deleteFile) {
      this.storageIO.deleteFileIfPresent(currentFilePath);
    }
  }
}
