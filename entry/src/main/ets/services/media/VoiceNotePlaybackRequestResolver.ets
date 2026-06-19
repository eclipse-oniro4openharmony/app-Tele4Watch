import { hilog } from '@kit.PerformanceAnalysisKit';
import fs from '@ohos.file.fs';
import { opusNativeBridge } from 'opusdecoder';
import { TdChatMessageItem } from '../td/TdPayloadTypes';
import { VoiceNotePlaybackRequest } from './VoiceNotePlaybackController';

const DOMAIN = 0x2026;
const TAG = 'VoiceNoteRequestResolver';
const DECODED_VOICE_NOTE_SUFFIX = '.decoded.wav';
const MAX_DECODED_VOICE_NOTE_CACHE_FILES = 8;

interface DecodedVoiceNoteCacheEntry {
  'path': string;
  'mtime': number;
}

interface VoiceNotePlaybackTarget {
  'filePath': string;
  'mimeType': string;
}

/**
 * Resolves a TD voice-note message into a playback request and owns decode/cache details.
 */
export class VoiceNotePlaybackRequestResolver {
  /**
   * Creates a player-ready request for one voice note.
   *
   * @param message The source chat message.
   * @returns Promise resolving to a playback request.
   */
  createPlaybackRequest(message: TdChatMessageItem): Promise<VoiceNotePlaybackRequest> {
    return new Promise<VoiceNotePlaybackRequest>((resolve: (request: VoiceNotePlaybackRequest) => void): void => {
      setTimeout((): void => {
        resolve(this.createPlaybackRequestSync(message));
      }, 0);
    });
  }

  private createPlaybackRequestSync(message: TdChatMessageItem): VoiceNotePlaybackRequest {
    const mimeType = typeof message.mediaMimeType === 'string' ? message.mediaMimeType.trim() : '';
    const mediaLocalPath = typeof message.mediaLocalPath === 'string' ? message.mediaLocalPath.trim() : '';
    const durationMs = typeof message.mediaDurationSec === 'number' && message.mediaDurationSec > 0
      ? message.mediaDurationSec * 1000
      : 0;
    const playbackTarget = this.resolvePlaybackTarget(mediaLocalPath, mimeType);

    hilog.debug(
      DOMAIN,
      TAG,
      'Voice note request resolved (messageId=%{public}s, path=%{public}s, mime=%{public}s, durationMs=%{public}d)',
      message.id,
      playbackTarget.filePath,
      playbackTarget.mimeType,
      durationMs
    );
    return {
      'messageId': message.id,
      'filePath': playbackTarget.filePath,
      'mimeType': playbackTarget.mimeType,
      'durationMs': durationMs
    };
  }

  private resolvePlaybackTarget(mediaLocalPath: string, mimeType: string): VoiceNotePlaybackTarget {
    if (mimeType !== 'audio/ogg' || mediaLocalPath.length === 0) {
      return {
        'filePath': mediaLocalPath,
        'mimeType': mimeType
      };
    }

    try {
      return {
        'filePath': this.decodeVoiceNoteToWav(mediaLocalPath),
        'mimeType': 'audio/wav'
      };
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Voice note decode failed for %{public}s: %{public}s', mediaLocalPath, String(error));
      return {
        'filePath': mediaLocalPath,
        'mimeType': mimeType
      };
    }
  }

  private decodeVoiceNoteToWav(inputPath: string): string {
    const outputPath = `${inputPath}${DECODED_VOICE_NOTE_SUFFIX}`;
    if (this.isDecodedVoiceNoteFresh(inputPath, outputPath)) {
      this.cleanupDecodedVoiceNoteCache(outputPath);
      hilog.debug(DOMAIN, TAG, 'Voice note decode reuse: input=%{public}s output=%{public}s', inputPath, outputPath);
      return outputPath;
    }

    const decodedPath = opusNativeBridge.decodeOpusToWav(inputPath, outputPath);
    this.cleanupDecodedVoiceNoteCache(decodedPath);
    hilog.info(DOMAIN, TAG, 'Voice note decode success: input=%{public}s output=%{public}s', inputPath, decodedPath);
    return decodedPath;
  }

  private cleanupDecodedVoiceNoteCache(protectedPath: string): void {
    const parentDirectory = this.parentDirectoryPath(protectedPath);
    if (parentDirectory.length === 0) {
      return;
    }

    const decodedEntries = this.collectDecodedVoiceNoteCacheEntries(parentDirectory);
    if (decodedEntries.length <= MAX_DECODED_VOICE_NOTE_CACHE_FILES) {
      return;
    }

    let preservedCount = 0;
    for (const entry of decodedEntries) {
      if (entry.path === protectedPath) {
        preservedCount += 1;
        continue;
      }
      if (preservedCount < MAX_DECODED_VOICE_NOTE_CACHE_FILES - 1) {
        preservedCount += 1;
        continue;
      }

      try {
        fs.unlinkSync(entry.path);
        hilog.debug(DOMAIN, TAG, 'Voice note cache cleanup removed: %{public}s', entry.path);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Voice note cache cleanup failed for %{public}s: %{public}s', entry.path, String(error));
      }
    }
  }

  private collectDecodedVoiceNoteCacheEntries(directoryPath: string): DecodedVoiceNoteCacheEntry[] {
    let fileNames: string[];
    try {
      fileNames = fs.listFileSync(directoryPath);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Voice note cache list failed for %{public}s: %{public}s', directoryPath, String(error));
      return [];
    }

    const entries: DecodedVoiceNoteCacheEntry[] = [];
    for (const fileName of fileNames) {
      if (!fileName.endsWith(DECODED_VOICE_NOTE_SUFFIX)) {
        continue;
      }
      const fullPath = `${directoryPath}/${fileName}`;
      try {
        const stat = fs.statSync(fullPath);
        entries.push({
          'path': fullPath,
          'mtime': stat.mtime
        });
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Voice note cache stat failed for %{public}s: %{public}s', fullPath, String(error));
      }
    }

    entries.sort((left: DecodedVoiceNoteCacheEntry, right: DecodedVoiceNoteCacheEntry): number => {
      if (left.mtime === right.mtime) {
        return 0;
      }
      return left.mtime > right.mtime ? -1 : 1;
    });
    return entries;
  }

  private parentDirectoryPath(filePath: string): string {
    const lastSeparatorIndex = filePath.lastIndexOf('/');
    if (lastSeparatorIndex <= 0) {
      return '';
    }
    return filePath.substring(0, lastSeparatorIndex);
  }

  private fileExists(filePath: string): boolean {
    try {
      fs.statSync(filePath);
      return true;
    } catch (_error) {
      return false;
    }
  }

  private isDecodedVoiceNoteFresh(inputPath: string, outputPath: string): boolean {
    if (!this.fileExists(outputPath)) {
      return false;
    }

    try {
      const sourceStat = fs.statSync(inputPath);
      const outputStat = fs.statSync(outputPath);
      return outputStat.mtime >= sourceStat.mtime;
    } catch (_error) {
      return false;
    }
  }
}
