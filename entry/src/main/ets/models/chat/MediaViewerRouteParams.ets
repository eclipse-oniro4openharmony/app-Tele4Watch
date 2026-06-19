export type MediaViewerMediaKind = 'photo' | 'animation' | 'video' | 'videoNote';

/**
 * Router params accepted by the media viewer page.
 */
export interface MediaViewerRouteParams {
  chatId: string;
  chatTitle: string;
  chatUsername: string;
  messageId: string;
  mediaKind: MediaViewerMediaKind;
  mediaFileId: number;
  mediaThumbFileId: number;
  mediaFilePath: string;
  mediaThumbPath: string;
  mediaMinithumbnailData: string;
  mediaMimeType: string;
  mediaIsAnimated: boolean;
  mediaDurationSec: number;
  mediaWidth: number;
  mediaHeight: number;
  isRoundVideoNote: boolean;
}
