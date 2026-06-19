import { TdChatMessageItem } from '../../models/td/TdViewTypes';

/**
 * Converts local paths and URI strings into sources accepted by ArkUI media components.
 *
 * @param path Local path or URI.
 * @returns Component-ready media source.
 */
export function resolveMediaComponentSource(path: string): string {
  const trimmed = path.trim();
  if (trimmed.startsWith('file://')
    || trimmed.startsWith('http://')
    || trimmed.startsWith('https://')
    || trimmed.startsWith('data:')) {
    return trimmed;
  }
  return `file://${trimmed}`;
}

/**
 * Checks if a path extension can be rendered by ArkUI Image.
 *
 * @param path Candidate media path.
 * @returns True when the path has a supported still-image extension.
 */
export function isRenderableImagePath(path: string): boolean {
  const lowerPath = path.toLowerCase();
  return lowerPath.endsWith('.gif')
    || lowerPath.endsWith('.jpg')
    || lowerPath.endsWith('.jpeg')
    || lowerPath.endsWith('.png')
    || lowerPath.endsWith('.webp')
    || lowerPath.endsWith('.bmp');
}

/**
 * Checks if a path extension can be rendered by ArkUI Video.
 *
 * @param path Candidate media path.
 * @returns True when the path has a supported video extension.
 */
export function isRenderableVideoPath(path: string): boolean {
  const lowerPath = path.toLowerCase();
  return lowerPath.endsWith('.mp4')
    || lowerPath.endsWith('.webm')
    || lowerPath.endsWith('.mkv');
}

/**
 * Resolves local video source for inline video playback.
 *
 * @param message Chat message with media metadata.
 * @param allowTgsFallback Whether TGS-like animated emoji may fall back to video extension.
 * @returns Local media path when playable as inline video.
 */
export function resolveInlineVideoPath(message: TdChatMessageItem, allowTgsFallback: boolean): string {
  if (typeof message.mediaLocalPath !== 'string' || message.mediaLocalPath.length === 0) {
    return '';
  }
  if (typeof message.mediaMimeType === 'string' && message.mediaMimeType.length > 0) {
    const mimeType = message.mediaMimeType.toLowerCase();
    if (mimeType.startsWith('video/')) {
      return message.mediaLocalPath;
    }
    if (mimeType === 'application/x-tgsticker') {
      return allowTgsFallback && isRenderableVideoPath(message.mediaLocalPath) ? message.mediaLocalPath : '';
    }
  }
  return isRenderableVideoPath(message.mediaLocalPath) ? message.mediaLocalPath : '';
}

/**
 * Resolves still preview source for inline video tiles.
 *
 * @param message Chat message with media metadata.
 * @param includeMinithumbnail Whether TDLib minithumbnail should be used as fallback.
 * @returns Image path or data URI for preview rendering.
 */
export function resolveInlineVideoPreviewPath(message: TdChatMessageItem, includeMinithumbnail: boolean): string {
  if (typeof message.mediaThumbPath === 'string' && message.mediaThumbPath.length > 0) {
    return message.mediaThumbPath;
  }
  if (includeMinithumbnail
    && typeof message.mediaMinithumbnailData === 'string'
    && message.mediaMinithumbnailData.trim().length > 0) {
    return `data:image/jpeg;base64,${message.mediaMinithumbnailData.trim()}`;
  }
  if (typeof message.mediaLocalPath === 'string'
    && message.mediaLocalPath.length > 0
    && isRenderableImagePath(message.mediaLocalPath)) {
    return message.mediaLocalPath;
  }
  return '';
}
