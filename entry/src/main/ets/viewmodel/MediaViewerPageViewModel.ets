import { tdClient } from '../services/td/TdClient';
import { TdChatMessageItem } from '../services/td/TdPayloadTypes';
import { MediaViewerPageState } from '../models/chat/MediaViewerPageState';
import { MediaViewerMediaKind, MediaViewerRouteParams } from '../models/chat/MediaViewerRouteParams';
import { MediaViewerContentSize } from '../models/media/MediaViewerContentTypes';
import { MediaViewerPlaybackPhase, MediaViewerPlaybackRequest } from '../services/media/MediaViewerPlaybackController';

const WATCH_SCREEN_DIAMETER_PX: number = 466;
const WATCH_VIEWPORT_DIAMETER_VP: number = WATCH_SCREEN_DIAMETER_PX / 2;
const VIDEO_NOTE_MAX_SIZE_PX: number = 430;
const VIDEO_NOTE_MAX_SIZE: number = VIDEO_NOTE_MAX_SIZE_PX / 2;
const ROUND_SCREEN_SAFE_RECT: number = Math.floor(WATCH_VIEWPORT_DIAMETER_VP / Math.SQRT2);
const RECT_MEDIA_MAX_WIDTH: number = ROUND_SCREEN_SAFE_RECT;
const RECT_MEDIA_MAX_HEIGHT: number = ROUND_SCREEN_SAFE_RECT;

function normalizePath(value: string | undefined): string {
  if (typeof value !== 'string') {
    return '';
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : '';
}

function normalizeNumber(value: number | undefined): number {
  return typeof value === 'number' && value > 0 ? value : 0;
}

function normalizeMimeType(value: string | undefined): string {
  return normalizePath(value).toLowerCase();
}

export interface MediaViewerRouteInput {
  chatId?: string;
  chatTitle?: string;
  chatUsername?: string;
  messageId?: string;
  mediaKind?: MediaViewerMediaKind;
  mediaFileId?: number;
  mediaThumbFileId?: number;
  mediaFilePath?: string;
  mediaThumbPath?: string;
  mediaMinithumbnailData?: string;
  mediaMimeType?: string;
  mediaIsAnimated?: boolean;
  mediaDurationSec?: number;
  mediaWidth?: number;
  mediaHeight?: number;
  isRoundVideoNote?: boolean;
}

export interface MediaViewerAuthStatePlan {
  shouldNavigateToIndex: boolean;
  resetIndexNavigation: boolean;
}

export interface MediaViewerDownloadPlan {
  shouldDownload: boolean;
  fileId: number;
  priority: number;
}

/**
 * Creates the typed state scaffold for the routed media viewer page.
 */
export class MediaViewerPageViewModel {
  subscribeChatMessages(listener: (chatId: string, items: TdChatMessageItem[]) => void): number {
    return tdClient.subscribeChatMessages(listener);
  }

  unsubscribeChatMessages(token: number): void {
    tdClient.unsubscribeChatMessages(token);
  }

  setAuthStateListener(listener: (state: string) => void): void {
    tdClient.setAuthStateListener(listener);
  }

  getAuthorizationStateName(): string {
    return tdClient.getAuthorizationStateName();
  }

  downloadFile(fileId: number, priority: number): boolean {
    return tdClient.downloadFile(fileId, priority);
  }

  cancelDownloadFile(fileId: number): boolean {
    return tdClient.cancelDownloadFile(fileId);
  }

  createInitialState(): MediaViewerPageState {
    return {
      chatId: '',
      chatTitle: '',
      chatUsername: '',
      messageId: '',
      mediaKind: 'photo',
      mediaFileId: 0,
      mediaThumbFileId: 0,
      mediaFilePath: '',
      mediaThumbPath: '',
      mediaMinithumbnailData: '',
      mediaMimeType: '',
      mediaIsAnimated: false,
      mediaDurationSec: 0,
      mediaWidth: 0,
      mediaHeight: 0,
      isRoundVideoNote: false
    };
  }

  parseRouteParams(params: MediaViewerRouteInput | undefined): MediaViewerRouteParams {
    return {
      chatId: normalizePath(params?.chatId),
      chatTitle: normalizePath(params?.chatTitle),
      chatUsername: normalizePath(params?.chatUsername),
      messageId: normalizePath(params?.messageId),
      mediaKind: this.normalizeMediaKind(params?.mediaKind),
      mediaFileId: normalizeNumber(params?.mediaFileId),
      mediaThumbFileId: normalizeNumber(params?.mediaThumbFileId),
      mediaFilePath: normalizePath(params?.mediaFilePath),
      mediaThumbPath: normalizePath(params?.mediaThumbPath),
      mediaMinithumbnailData: normalizePath(params?.mediaMinithumbnailData),
      mediaMimeType: normalizePath(params?.mediaMimeType),
      mediaIsAnimated: params?.mediaIsAnimated === true,
      mediaDurationSec: normalizeNumber(params?.mediaDurationSec),
      mediaWidth: normalizeNumber(params?.mediaWidth),
      mediaHeight: normalizeNumber(params?.mediaHeight),
      isRoundVideoNote: params?.isRoundVideoNote === true
    };
  }

  applyRoute(currentState: MediaViewerPageState, params: MediaViewerRouteParams): MediaViewerPageState {
    return {
      chatId: params.chatId,
      chatTitle: params.chatTitle.length > 0 ? params.chatTitle : currentState.chatTitle,
      chatUsername: params.chatUsername,
      messageId: params.messageId,
      mediaKind: params.mediaKind,
      mediaFileId: normalizeNumber(params.mediaFileId),
      mediaThumbFileId: normalizeNumber(params.mediaThumbFileId),
      mediaFilePath: normalizePath(params.mediaFilePath),
      mediaThumbPath: normalizePath(params.mediaThumbPath),
      mediaMinithumbnailData: normalizePath(params.mediaMinithumbnailData),
      mediaMimeType: normalizePath(params.mediaMimeType),
      mediaIsAnimated: params.mediaIsAnimated,
      mediaDurationSec: normalizeNumber(params.mediaDurationSec),
      mediaWidth: normalizeNumber(params.mediaWidth),
      mediaHeight: normalizeNumber(params.mediaHeight),
      isRoundVideoNote: params.isRoundVideoNote
    };
  }

  planAuthStateChange(authState: string): MediaViewerAuthStatePlan {
    const safeState = authState.trim();
    return {
      shouldNavigateToIndex: safeState.length > 0 && safeState !== 'authorizationStateReady',
      resetIndexNavigation: safeState === 'authorizationStateReady'
    };
  }

  isVideoKind(kind: MediaViewerMediaKind): boolean {
    return kind === 'video' || kind === 'videoNote';
  }

  isImageKind(kind: MediaViewerMediaKind): boolean {
    return kind === 'photo' || kind === 'animation';
  }

  shouldRenderWithVideoSurface(currentState: MediaViewerPageState): boolean {
    if (currentState.mediaKind === 'video' || currentState.mediaKind === 'videoNote') {
      return true;
    }
    if (currentState.mediaKind !== 'animation') {
      return false;
    }
    if (currentState.mediaIsAnimated) {
      return true;
    }
    const mimeType = normalizeMimeType(currentState.mediaMimeType);
    if (mimeType.startsWith('video/')) {
      return true;
    }
    return this.isRenderableVideoPath(currentState.mediaFilePath);
  }

  shouldRenderWithImage(currentState: MediaViewerPageState): boolean {
    if (currentState.mediaKind === 'photo') {
      return true;
    }
    if (currentState.mediaKind !== 'animation') {
      return false;
    }
    if (currentState.mediaIsAnimated) {
      return false;
    }
    const mimeType = normalizeMimeType(currentState.mediaMimeType);
    if (mimeType.startsWith('image/')) {
      return true;
    }
    if (this.isRenderableImagePath(currentState.mediaFilePath)) {
      return true;
    }
    if (this.isRenderableImagePath(currentState.mediaThumbPath)) {
      return true;
    }
    return normalizePath(currentState.mediaMinithumbnailData).length > 0;
  }

  createMediaDownloadPlan(currentState: MediaViewerPageState): MediaViewerDownloadPlan {
    if (normalizePath(currentState.mediaFilePath).length > 0) {
      return {
        shouldDownload: false,
        fileId: 0,
        priority: 1
      };
    }
    const fileId = normalizeNumber(currentState.mediaFileId);
    return {
      shouldDownload: fileId > 0,
      fileId: fileId,
      priority: 1
    };
  }

  createPlaybackRequest(currentState: MediaViewerPageState): MediaViewerPlaybackRequest | undefined {
    const safeMessageId = normalizePath(currentState.messageId);
    const safeFilePath = normalizePath(currentState.mediaFilePath);
    if (safeMessageId.length === 0 || safeFilePath.length === 0) {
      return undefined;
    }
    return {
      'messageId': safeMessageId,
      'filePath': safeFilePath,
      'mimeType': normalizePath(currentState.mediaMimeType),
      'durationMs': normalizeNumber(currentState.mediaDurationSec) * 1000
    };
  }

  resolveImageSource(currentState: MediaViewerPageState): string {
    const mediaFilePath = normalizePath(currentState.mediaFilePath);
    if (mediaFilePath.length > 0) {
      return this.toMediaSource(mediaFilePath);
    }
    const mediaThumbPath = normalizePath(currentState.mediaThumbPath);
    if (mediaThumbPath.length > 0) {
      return this.toMediaSource(mediaThumbPath);
    }
    const mediaMinithumbnailData = normalizePath(currentState.mediaMinithumbnailData);
    if (mediaMinithumbnailData.length > 0) {
      return `data:image/jpeg;base64,${mediaMinithumbnailData}`;
    }
    return '';
  }

  /**
   * Resolves the preview source used before the video surface starts rendering.
   *
   * @param currentState current routed media viewer state.
   * @returns renderable preview source or an empty string when no preview exists.
   */
  resolveVideoPreviewSource(currentState: MediaViewerPageState): string {
    const mediaThumbPath = normalizePath(currentState.mediaThumbPath);
    if (mediaThumbPath.length > 0) {
      return this.toMediaSource(mediaThumbPath);
    }
    const mediaMinithumbnailData = normalizePath(currentState.mediaMinithumbnailData);
    if (mediaMinithumbnailData.length > 0) {
      return `data:image/jpeg;base64,${mediaMinithumbnailData}`;
    }
    return '';
  }

  calculateVideoContentSize(currentState: MediaViewerPageState): MediaViewerContentSize {
    if (currentState.isRoundVideoNote) {
      const size = currentState.mediaWidth > 0
        ? Math.min(currentState.mediaWidth, VIDEO_NOTE_MAX_SIZE)
        : VIDEO_NOTE_MAX_SIZE;
      return {
        width: size,
        height: size
      };
    }
    if (currentState.mediaWidth <= 0 || currentState.mediaHeight <= 0) {
      return {
        width: RECT_MEDIA_MAX_WIDTH,
        height: RECT_MEDIA_MAX_HEIGHT
      };
    }
    const scale = Math.min(
      RECT_MEDIA_MAX_WIDTH / currentState.mediaWidth,
      RECT_MEDIA_MAX_HEIGHT / currentState.mediaHeight,
      1.0
    );
    return {
      width: Math.round(currentState.mediaWidth * scale),
      height: Math.round(currentState.mediaHeight * scale)
    };
  }

  calculateImageContentSize(currentState: MediaViewerPageState): MediaViewerContentSize {
    if (currentState.mediaWidth <= 0 || currentState.mediaHeight <= 0) {
      return {
        width: RECT_MEDIA_MAX_WIDTH,
        height: RECT_MEDIA_MAX_HEIGHT
      };
    }
    const scale = Math.min(
      RECT_MEDIA_MAX_WIDTH / currentState.mediaWidth,
      RECT_MEDIA_MAX_HEIGHT / currentState.mediaHeight,
      1.0
    );
    return {
      width: Math.round(currentState.mediaWidth * scale),
      height: Math.round(currentState.mediaHeight * scale)
    };
  }

  calculateMediaViewportSize(currentState: MediaViewerPageState): MediaViewerContentSize {
    if (currentState.isRoundVideoNote) {
      return this.calculateVideoContentSize(currentState);
    }
    return {
      width: RECT_MEDIA_MAX_WIDTH,
      height: RECT_MEDIA_MAX_HEIGHT
    };
  }

  /**
   * Calculates the maximum square image viewport available on the round watch screen.
   *
   * @returns full media viewport size in vp.
   */
  calculateImageMaximumViewportSize(): MediaViewerContentSize {
    return {
      width: WATCH_VIEWPORT_DIAMETER_VP,
      height: WATCH_VIEWPORT_DIAMETER_VP
    };
  }

  shouldShowLoadingState(currentState: MediaViewerPageState, playbackPhase: MediaViewerPlaybackPhase): boolean {
    if (this.shouldRenderWithVideoSurface(currentState)) {
      return normalizePath(currentState.mediaFilePath).length === 0 && playbackPhase !== 'error';
    }
    if (this.shouldRenderWithImage(currentState)) {
      return normalizePath(currentState.mediaFilePath).length === 0 &&
        normalizePath(currentState.mediaThumbPath).length === 0 &&
        normalizePath(currentState.mediaMinithumbnailData).length === 0;
    }
    return false;
  }

  createMediaViewerRouteParams(
    chatId: string,
    chatTitle: string,
    chatUsername: string,
    message: TdChatMessageItem
  ): MediaViewerRouteParams | undefined {
    const mediaKind = this.toMediaViewerKind(message.kind);
    if (mediaKind === undefined) {
      return undefined;
    }
    return {
      chatId: chatId,
      chatTitle: chatTitle,
      chatUsername: chatUsername.trim().length > 0 ? chatUsername : '',
      messageId: message.id,
      mediaKind: mediaKind,
      mediaFileId: normalizeNumber(message.mediaFileId),
      mediaThumbFileId: normalizeNumber(message.mediaThumbFileId),
      mediaFilePath: normalizePath(message.mediaLocalPath),
      mediaThumbPath: normalizePath(message.mediaThumbPath),
      mediaMinithumbnailData: normalizePath(message.mediaMinithumbnailData),
      mediaMimeType: normalizePath(message.mediaMimeType),
      mediaIsAnimated: message.mediaIsAnimated === true,
      mediaDurationSec: normalizeNumber(message.mediaDurationSec),
      mediaWidth: normalizeNumber(message.mediaWidth),
      mediaHeight: normalizeNumber(message.mediaHeight),
      isRoundVideoNote: mediaKind === 'videoNote'
    };
  }

  findMessage(items: TdChatMessageItem[], messageId: string): TdChatMessageItem | undefined {
    const safeMessageId = messageId.trim();
    if (safeMessageId.length === 0) {
      return undefined;
    }
    for (const item of items) {
      if (item.id === safeMessageId) {
        return item;
      }
    }
    return undefined;
  }

  mergeMessageUpdate(currentState: MediaViewerPageState, message: TdChatMessageItem): MediaViewerPageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      messageId: currentState.messageId,
      mediaKind: currentState.mediaKind,
      mediaFileId: normalizeNumber(message.mediaFileId) > 0 ? normalizeNumber(message.mediaFileId) : currentState.mediaFileId,
      mediaThumbFileId: normalizeNumber(message.mediaThumbFileId) > 0
        ? normalizeNumber(message.mediaThumbFileId)
        : currentState.mediaThumbFileId,
      mediaFilePath: normalizePath(message.mediaLocalPath).length > 0
        ? normalizePath(message.mediaLocalPath)
        : currentState.mediaFilePath,
      mediaThumbPath: normalizePath(message.mediaThumbPath).length > 0
        ? normalizePath(message.mediaThumbPath)
        : currentState.mediaThumbPath,
      mediaMinithumbnailData: normalizePath(message.mediaMinithumbnailData).length > 0
        ? normalizePath(message.mediaMinithumbnailData)
        : currentState.mediaMinithumbnailData,
      mediaMimeType: normalizePath(message.mediaMimeType).length > 0
        ? normalizePath(message.mediaMimeType)
        : currentState.mediaMimeType,
      mediaIsAnimated: typeof message.mediaIsAnimated === 'boolean'
        ? message.mediaIsAnimated
        : currentState.mediaIsAnimated,
      mediaDurationSec: normalizeNumber(message.mediaDurationSec) > 0
        ? normalizeNumber(message.mediaDurationSec)
        : currentState.mediaDurationSec,
      mediaWidth: normalizeNumber(message.mediaWidth) > 0 ? normalizeNumber(message.mediaWidth) : currentState.mediaWidth,
      mediaHeight: normalizeNumber(message.mediaHeight) > 0 ? normalizeNumber(message.mediaHeight) : currentState.mediaHeight,
      isRoundVideoNote: currentState.isRoundVideoNote
    };
  }

  private toMediaViewerKind(kind: string | undefined): MediaViewerMediaKind | undefined {
    if (kind === 'photo' || kind === 'animation' || kind === 'video' || kind === 'videoNote') {
      return kind;
    }
    return undefined;
  }

  private normalizeMediaKind(kind: MediaViewerMediaKind | undefined): MediaViewerMediaKind {
    if (kind === 'animation' || kind === 'video' || kind === 'videoNote') {
      return kind;
    }
    return 'photo';
  }

  private toMediaSource(path: string): string {
    if (path.startsWith('file://') || path.startsWith('http://') || path.startsWith('https://') || path.startsWith('data:')) {
      return path;
    }
    return `file://${path}`;
  }

  private isRenderableImagePath(path: string): boolean {
    const safePath = normalizePath(path).toLowerCase();
    return safePath.endsWith('.gif')
      || safePath.endsWith('.jpg')
      || safePath.endsWith('.jpeg')
      || safePath.endsWith('.png')
      || safePath.endsWith('.webp')
      || safePath.endsWith('.bmp');
  }

  private isRenderableVideoPath(path: string): boolean {
    const safePath = normalizePath(path).toLowerCase();
    return safePath.endsWith('.mp4')
      || safePath.endsWith('.webm')
      || safePath.endsWith('.mkv');
  }

}
