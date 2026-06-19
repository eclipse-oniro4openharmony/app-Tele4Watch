import { TdChatMessageItem } from '../models/td/TdViewTypes';
import { createEmptyUiTextValue } from '../models/ui/UiTextValue';
import { MediaPlaybackTimerBadge } from './MediaPlaybackTimerBadge';
import {
  resolveInlineVideoPath,
  resolveInlineVideoPreviewPath,
  resolveMediaComponentSource
} from '../services/media/MediaSourceResolver';

const VIDEO_NOTE_PREVIEW_SIZE: number = 88;
const VIDEO_NOTE_PLAY_HIT_SIZE: number = 40;

/**
 * Renders the round inline preview for Telegram `messageVideoNote` messages.
 */
@Component
export struct VideoNoteMessageBubble {
  @Prop message: TdChatMessageItem = {
    'id': '',
    'chatId': '',
    'senderUserId': '',
    'senderChatId': undefined,
    'senderAvatarPath': undefined,
    'sendingState': undefined,
    'deliveryState': undefined,
    'kind': 'videoNote',
    'text': '',
    'textValue': createEmptyUiTextValue(),
    'caption': undefined,
    'mediaFileId': undefined,
    'mediaThumbFileId': undefined,
    'mediaMinithumbnailData': undefined,
    'mediaLocalPath': undefined,
    'mediaThumbPath': undefined,
    'mediaWidth': undefined,
    'mediaHeight': undefined,
    'mediaMimeType': undefined,
    'mediaIsAnimated': undefined,
    'mediaDurationSec': undefined,
    'voiceNoteWaveform': undefined,
    'voiceNoteIsListened': undefined,
    'isOutgoing': false,
    'date': 0
  };
  onMediaClick: (message: TdChatMessageItem) => void = (_message: TdChatMessageItem): void => {};
  private inlineVideoController: VideoController = new VideoController();
  @State private inlineVideoPlaying: boolean = false;
  @State private inlinePlaybackElapsedSec: number = 0;
  @State private inlineVideoPreviewHiddenAfterFinish: boolean = false;
  private inlineVideoPreviewMessageId: string = '';
  private inlinePlaybackTimerHandle: number = -1;

  private mediaVideoPath(): string {
    return resolveInlineVideoPath(this.message, false);
  }

  private videoPreviewPath(): string {
    return resolveInlineVideoPreviewPath(this.message, true);
  }

  private previewRadius(): number {
    return Math.floor(VIDEO_NOTE_PREVIEW_SIZE / 2);
  }

  private shouldShowVideoPlayOverlay(): boolean {
    return !this.inlineVideoPlaying && this.mediaVideoPath().length > 0;
  }

  private shouldShowVideoThumbnailPreview(): boolean {
    if (this.inlineVideoPreviewHiddenAfterFinish) {
      return false;
    }
    if (!this.shouldShowVideoPlayOverlay()) {
      return false;
    }
    return this.videoPreviewPath().length > 0;
  }

  private timerElapsedOrDurationSec(): number {
    if (this.inlineVideoPlaying && this.inlinePlaybackElapsedSec > 0) {
      return this.inlinePlaybackElapsedSec;
    }
    if (typeof this.message.mediaDurationSec === 'number' && this.message.mediaDurationSec > 0) {
      return this.message.mediaDurationSec;
    }
    return this.inlinePlaybackElapsedSec > 0 ? this.inlinePlaybackElapsedSec : 0;
  }

  private syncInlineVideoPreviewState(): void {
    const nextMessageId = typeof this.message.id === 'string' ? this.message.id : '';
    if (this.inlineVideoPreviewMessageId === nextMessageId) {
      return;
    }
    this.inlineVideoPreviewMessageId = nextMessageId;
    this.inlineVideoPreviewHiddenAfterFinish = false;
  }

  private stopInlinePlaybackTimer(resetElapsed: boolean): void {
    if (this.inlinePlaybackTimerHandle >= 0) {
      clearInterval(this.inlinePlaybackTimerHandle);
      this.inlinePlaybackTimerHandle = -1;
    }
    if (resetElapsed) {
      this.inlinePlaybackElapsedSec = 0;
    }
  }

  private startInlinePlaybackTimer(): void {
    this.stopInlinePlaybackTimer(true);
    this.inlinePlaybackTimerHandle = setInterval(() => {
      this.inlinePlaybackElapsedSec = this.inlinePlaybackElapsedSec + 1;
    }, 1000);
  }

  private stopInlineVideoPlayback(): void {
    this.stopInlinePlaybackTimer(true);
    this.inlineVideoPlaying = false;
    this.inlineVideoController.stop();
  }

  private openMediaFromInlinePreview(): void {
    this.stopInlineVideoPlayback();
    this.onMediaClick(this.message);
  }

  private resetReusablePreviewState(): void {
    this.stopInlineVideoPlayback();
    this.inlineVideoPreviewMessageId = '';
    this.inlineVideoPreviewHiddenAfterFinish = false;
  }

  @Builder
  private buildPlayOverlay(): void {
    Column() {
      Image($r('app.media.chat_icon_play_white'))
        .width(16)
        .height(16)
    }
    .width(28)
    .height(28)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.surface_media_play_overlay_background'))
    .borderRadius(14)
  }

  /**
   * Stops inline playback before the video-note preview leaves the component tree.
   *
   * @returns Nothing.
   */
  aboutToDisappear(): void {
    this.stopInlineVideoPlayback();
  }

  /**
   * Resets per-message preview state when ArkUI reuses this component for another message.
   *
   * @returns Nothing.
   */
  aboutToReuse(): void {
    this.resetReusablePreviewState();
  }

  /**
   * Builds the round video-note preview with optional thumbnail, play overlay, and duration badge.
   *
   * @returns Nothing.
   */
  build() {
    RelativeContainer() {

      if (this.mediaVideoPath().length > 0) {

        Video({
          src: resolveMediaComponentSource(this.mediaVideoPath()),
          controller: this.inlineVideoController
        })
          .width(VIDEO_NOTE_PREVIEW_SIZE)
          .height(VIDEO_NOTE_PREVIEW_SIZE)
          .controls(false)
          .autoPlay(false)
          .objectFit(ImageFit.Cover)
          .borderRadius(this.previewRadius())
          .onAppear(() => {
            this.syncInlineVideoPreviewState();
            this.inlineVideoPlaying = false;
            this.stopInlinePlaybackTimer(true);
          })
          .onFinish(() => {
            this.inlineVideoPlaying = false;
            this.inlineVideoPreviewHiddenAfterFinish = true;
            this.stopInlinePlaybackTimer(true);
          })
          .onClick(() => {
            this.openMediaFromInlinePreview();
          })

        if (this.shouldShowVideoThumbnailPreview()) {
          Image(resolveMediaComponentSource(this.videoPreviewPath()))
            .width(VIDEO_NOTE_PREVIEW_SIZE)
            .height(VIDEO_NOTE_PREVIEW_SIZE)
            .objectFit(ImageFit.Cover)
            .borderRadius(this.previewRadius())
            .visibility(this.shouldShowVideoThumbnailPreview() ? Visibility.Visible : Visibility.Hidden)
            .onClick(() => {
              this.openMediaFromInlinePreview();
            })
        }

      } else if (this.videoPreviewPath().length > 0) {

        Image(resolveMediaComponentSource(this.videoPreviewPath()))
          .width(VIDEO_NOTE_PREVIEW_SIZE)
          .height(VIDEO_NOTE_PREVIEW_SIZE)
          .objectFit(ImageFit.Cover)
          .borderRadius(this.previewRadius())
          .onClick(() => {
            this.openMediaFromInlinePreview();
          })

      } else {

        Column() {}
        .width(VIDEO_NOTE_PREVIEW_SIZE)
        .height(VIDEO_NOTE_PREVIEW_SIZE)
        .backgroundColor($r('app.color.surface_media_placeholder_background'))
        .borderRadius(this.previewRadius())
        .onClick(() => {
          this.openMediaFromInlinePreview();
        })
      }

      if (this.shouldShowVideoPlayOverlay()) {

        Column() {
          this.buildPlayOverlay()
        }
        .width(VIDEO_NOTE_PLAY_HIT_SIZE)
        .height(VIDEO_NOTE_PLAY_HIT_SIZE)
        .onClick(() => {
          if (this.mediaVideoPath().length === 0) {
            return;
          }
          this.inlineVideoPlaying = true;
          this.startInlinePlaybackTimer();
          this.inlineVideoController.start();
        })
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }

      MediaPlaybackTimerBadge({
        elapsedSec: this.timerElapsedOrDurationSec(),
        mediaDurationSec: typeof this.message.mediaDurationSec === 'number' ? this.message.mediaDurationSec : 0
      })
        .alignRules({
          top: { anchor: '__container__', align: VerticalAlign.Top },
          left: { anchor: '__container__', align: HorizontalAlign.Start }
        })
    }
    .width(VIDEO_NOTE_PREVIEW_SIZE)
    .height(VIDEO_NOTE_PREVIEW_SIZE)
  }
}
