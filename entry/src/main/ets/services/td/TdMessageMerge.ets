import { TdChatMessageItem } from './TdPayloadTypes';

/**
 * Copies media-related fields from a pending/local message row when the
 * confirmed TDLib row still lacks them.
 *
 * This keeps freshly sent voice notes playable before a later history/file
 * update rehydrates the canonical message payload.
 *
 * @param target Confirmed message row that may still miss local media fields.
 * @param fallback Pending/local message row used as the fallback source.
 * @returns Nothing.
 */
export function copyMissingMediaFieldsFromPendingMessage(
  target: TdChatMessageItem,
  fallback: TdChatMessageItem | undefined
): void {
  if (!fallback) {
    return;
  }

  if ((typeof target.mediaFileId !== 'number' || target.mediaFileId <= 0) &&
    typeof fallback.mediaFileId === 'number' && fallback.mediaFileId > 0) {
    target.mediaFileId = fallback.mediaFileId;
  }
  if ((typeof target.mediaThumbFileId !== 'number' || target.mediaThumbFileId <= 0) &&
    typeof fallback.mediaThumbFileId === 'number' && fallback.mediaThumbFileId > 0) {
    target.mediaThumbFileId = fallback.mediaThumbFileId;
  }
  if ((typeof target.mediaLocalPath !== 'string' || target.mediaLocalPath.trim().length === 0) &&
    typeof fallback.mediaLocalPath === 'string' && fallback.mediaLocalPath.trim().length > 0) {
    target.mediaLocalPath = fallback.mediaLocalPath;
  }
  if ((typeof target.mediaThumbPath !== 'string' || target.mediaThumbPath.trim().length === 0) &&
    typeof fallback.mediaThumbPath === 'string' && fallback.mediaThumbPath.trim().length > 0) {
    target.mediaThumbPath = fallback.mediaThumbPath;
  }
  if ((typeof target.mediaMinithumbnailData !== 'string' || target.mediaMinithumbnailData.trim().length === 0) &&
    typeof fallback.mediaMinithumbnailData === 'string' && fallback.mediaMinithumbnailData.trim().length > 0) {
    target.mediaMinithumbnailData = fallback.mediaMinithumbnailData;
  }
  if ((typeof target.mediaMimeType !== 'string' || target.mediaMimeType.trim().length === 0) &&
    typeof fallback.mediaMimeType === 'string' && fallback.mediaMimeType.trim().length > 0) {
    target.mediaMimeType = fallback.mediaMimeType;
  }
  if ((typeof target.mediaDurationSec !== 'number' || target.mediaDurationSec <= 0) &&
    typeof fallback.mediaDurationSec === 'number' && fallback.mediaDurationSec > 0) {
    target.mediaDurationSec = fallback.mediaDurationSec;
  }
  if ((!target.voiceNoteWaveform || target.voiceNoteWaveform.length === 0) &&
    fallback.voiceNoteWaveform && fallback.voiceNoteWaveform.length > 0) {
    target.voiceNoteWaveform = [...fallback.voiceNoteWaveform];
  }
}
