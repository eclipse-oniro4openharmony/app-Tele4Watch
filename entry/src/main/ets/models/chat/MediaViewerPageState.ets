import { MediaViewerMediaKind } from './MediaViewerRouteParams';

/**
 * Describes the presentation-safe state consumed by the routed media viewer page.
 */
export interface MediaViewerPageState {
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
