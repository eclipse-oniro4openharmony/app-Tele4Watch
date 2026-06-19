import { hilog } from '@kit.PerformanceAnalysisKit';
import { TdChatMessageItem } from '../models/td/TdViewTypes';
import { MediaViewerPageState } from '../models/chat/MediaViewerPageState';
import { MediaViewerMediaKind } from '../models/chat/MediaViewerRouteParams';
import { MediaViewerContentSize } from '../models/media/MediaViewerContentTypes';
import {
  MediaViewerControlsOverlayController,
  MediaViewerControlsOverlaySnapshot
} from '../services/media/MediaViewerControlsOverlayController';
import {
  MediaViewerImageTransformConfig,
  MediaViewerImageTransformController,
  MediaViewerImageTransformSnapshot
} from '../services/media/MediaViewerImageTransformController';
import {
  MediaViewerPlaybackController,
  MediaViewerPlaybackPhase,
  MediaViewerPlaybackSnapshot
} from '../services/media/MediaViewerPlaybackController';
import { MediaViewerImageViewport } from '../ui/MediaViewerImageViewport';
import { MediaViewerVideoPlayer } from '../ui/MediaViewerVideoPlayer';
import {
  MediaViewerPageViewModel,
  MediaViewerRouteInput
} from '../viewmodel/MediaViewerPageViewModel';

const DOMAIN = 0x2026;
const TAG = 'MediaViewerPage';
const CONTROL_PANEL_VISIBLE_OPACITY = 1;
const IMAGE_TRANSFORM_RESET_ANIMATION_MS = 160;

@Entry
@Component
struct MediaViewer {
  private readonly viewModel: MediaViewerPageViewModel = new MediaViewerPageViewModel();
  private readonly initialPageState: MediaViewerPageState = this.viewModel.createInitialState();
  @State chatId: string = this.initialPageState.chatId;
  @State chatTitle: string = this.initialPageState.chatTitle;
  @State chatUsername: string = this.initialPageState.chatUsername;
  @State messageId: string = this.initialPageState.messageId;
  @State mediaKind: MediaViewerMediaKind = this.initialPageState.mediaKind;
  @State mediaFileId: number = this.initialPageState.mediaFileId;
  @State mediaThumbFileId: number = this.initialPageState.mediaThumbFileId;
  @State mediaFilePath: string = this.initialPageState.mediaFilePath;
  @State mediaThumbPath: string = this.initialPageState.mediaThumbPath;
  @State mediaMinithumbnailData: string = this.initialPageState.mediaMinithumbnailData;
  @State mediaMimeType: string = this.initialPageState.mediaMimeType;
  @State mediaIsAnimated: boolean = this.initialPageState.mediaIsAnimated;
  @State mediaDurationSec: number = this.initialPageState.mediaDurationSec;
  @State mediaWidth: number = this.initialPageState.mediaWidth;
  @State mediaHeight: number = this.initialPageState.mediaHeight;
  @State isRoundVideoNote: boolean = this.initialPageState.isRoundVideoNote;
  @State playbackPhase: MediaViewerPlaybackPhase = 'idle';
  @State playbackPositionMs: number = 0;
  @State playbackDurationMs: number = 0;
  @State playbackErrorMessage: string = '';
  @State controlPanelOpacity: number = CONTROL_PANEL_VISIBLE_OPACITY;
  @State controlPanelFadeDurationMs: number = 0;
  @State controlPanelInputEnabled: boolean = true;
  @State imageZoomScale: number = 1.0;
  @State imagePanOffsetX: number = 0;
  @State imagePanOffsetY: number = 0;
  @State imageTransformAnimationMs: number = 0;
  @State imageViewportWidth: number = 0;
  @State imageViewportHeight: number = 0;
  @State imagePanEnabled: boolean = false;
  private readonly playbackController: MediaViewerPlaybackController = new MediaViewerPlaybackController();
  private readonly imageTransformController: MediaViewerImageTransformController =
    new MediaViewerImageTransformController();
  private readonly controlsOverlayController: MediaViewerControlsOverlayController =
    new MediaViewerControlsOverlayController();
  private hasNavigatedToIndex: boolean = false;
  private activeDownloadFileId: number = 0;
  // Token for the chat-messages subscription on the TdClient fan-out hub. `0` means not subscribed.
  private chatMessagesSubscription: number = 0;

  private redirectToIndexIfUnauthorized(state: string): void {
    const authStatePlan = this.viewModel.planAuthStateChange(state);
    if (authStatePlan.resetIndexNavigation) {
      this.hasNavigatedToIndex = false;
    }
    if (!authStatePlan.shouldNavigateToIndex || this.hasNavigatedToIndex) {
      return;
    }
    try {
      this.hasNavigatedToIndex = true;
      this.getUIContext().getRouter().replaceUrl({
        url: 'pages/Index'
      });
    } catch (error) {
      this.hasNavigatedToIndex = false;
      hilog.error(DOMAIN, TAG, 'Failed to redirect MediaViewer to Index: %{public}s', String(error));
    }
  }

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle enter: MediaViewer');
    this.hasNavigatedToIndex = false;
    const routeParams =
      this.viewModel.parseRouteParams(this.getUIContext().getRouter().getParams() as MediaViewerRouteInput);
    this.imageTransformController.setListener((snapshot: MediaViewerImageTransformSnapshot): void => {
      this.applyImageTransformSnapshot(snapshot);
    });
    this.controlsOverlayController.setListener((snapshot: MediaViewerControlsOverlaySnapshot): void => {
      this.applyControlsOverlaySnapshot(snapshot);
    });
    this.applyPageState(this.viewModel.applyRoute(this.currentPageState(), routeParams));

    this.chatMessagesSubscription = this.viewModel.subscribeChatMessages((chatId: string, items: TdChatMessageItem[]): void => {
      if (chatId !== this.chatId) {
        return;
      }
      const message = this.viewModel.findMessage(items, this.messageId);
      if (!message) {
        return;
      }
      const previousState = this.currentPageState();
      const nextPageState = this.viewModel.mergeMessageUpdate(previousState, message);
      this.applyPageState(nextPageState);
      if (previousState.mediaFilePath.length === 0 && nextPageState.mediaFilePath.length > 0) {
        this.activeDownloadFileId = 0;
      }
    });
    this.viewModel.setAuthStateListener((state: string): void => {
      this.redirectToIndexIfUnauthorized(state);
    });
    this.redirectToIndexIfUnauthorized(this.viewModel.getAuthorizationStateName());
    this.playbackController.setListener((snapshot: MediaViewerPlaybackSnapshot): void => {
      const previousPlaybackPhase = this.playbackPhase;
      if (this.playbackPhase !== snapshot.phase) {
        this.playbackPhase = snapshot.phase;
      }
      if (previousPlaybackPhase !== snapshot.phase) {
        this.controlsOverlayController.handlePlaybackPhase(snapshot.phase);
      }
      if (this.playbackPositionMs !== snapshot.positionMs) {
        this.playbackPositionMs = snapshot.positionMs;
      }
      if (this.playbackDurationMs !== snapshot.durationMs) {
        this.playbackDurationMs = snapshot.durationMs;
      }
      if (this.playbackErrorMessage !== snapshot.errorMessage) {
        this.playbackErrorMessage = snapshot.errorMessage;
      }
    });

    this.requestMediaDownloadIfNeeded();
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle leave: MediaViewer');
    this.controlsOverlayController.dispose();
    this.controlsOverlayController.setListener(undefined);
    this.imageTransformController.setListener(undefined);
    this.viewModel.unsubscribeChatMessages(this.chatMessagesSubscription);
    this.chatMessagesSubscription = 0;
    this.playbackController.setListener(undefined);
    this.playbackController.detachSurface();
    if (this.activeDownloadFileId > 0) {
      this.viewModel.cancelDownloadFile(this.activeDownloadFileId);
      this.activeDownloadFileId = 0;
    }
    void this.playbackController.release();
  }

  private currentPageState(): MediaViewerPageState {
    return {
      chatId: this.chatId,
      chatTitle: this.chatTitle,
      chatUsername: this.chatUsername,
      messageId: this.messageId,
      mediaKind: this.mediaKind,
      mediaFileId: this.mediaFileId,
      mediaThumbFileId: this.mediaThumbFileId,
      mediaFilePath: this.mediaFilePath,
      mediaThumbPath: this.mediaThumbPath,
      mediaMinithumbnailData: this.mediaMinithumbnailData,
      mediaMimeType: this.mediaMimeType,
      mediaIsAnimated: this.mediaIsAnimated,
      mediaDurationSec: this.mediaDurationSec,
      mediaWidth: this.mediaWidth,
      mediaHeight: this.mediaHeight,
      isRoundVideoNote: this.isRoundVideoNote
    };
  }

  private applyPageState(nextPageState: MediaViewerPageState): void {
    this.chatId = nextPageState.chatId;
    this.chatTitle = nextPageState.chatTitle;
    this.chatUsername = nextPageState.chatUsername;
    this.messageId = nextPageState.messageId;
    this.mediaKind = nextPageState.mediaKind;
    this.mediaFileId = nextPageState.mediaFileId;
    this.mediaThumbFileId = nextPageState.mediaThumbFileId;
    this.mediaFilePath = nextPageState.mediaFilePath;
    this.mediaThumbPath = nextPageState.mediaThumbPath;
    this.mediaMinithumbnailData = nextPageState.mediaMinithumbnailData;
    this.mediaMimeType = nextPageState.mediaMimeType;
    this.mediaIsAnimated = nextPageState.mediaIsAnimated;
    this.mediaDurationSec = nextPageState.mediaDurationSec;
    this.mediaWidth = nextPageState.mediaWidth;
    this.mediaHeight = nextPageState.mediaHeight;
    this.isRoundVideoNote = nextPageState.isRoundVideoNote;
    this.imageTransformController.syncConfig(this.currentImageTransformConfig());
  }

  private isVideoKind(): boolean {
    return this.viewModel.shouldRenderWithVideoSurface(this.currentPageState());
  }

  private isImageKind(): boolean {
    return this.viewModel.shouldRenderWithImage(this.currentPageState());
  }

  private requestMediaDownloadIfNeeded(): void {
    const downloadPlan = this.viewModel.createMediaDownloadPlan(this.currentPageState());
    if (!downloadPlan.shouldDownload) {
      return;
    }
    if (this.viewModel.downloadFile(downloadPlan.fileId, downloadPlan.priority)) {
      this.activeDownloadFileId = downloadPlan.fileId;
    }
  }

  private playMedia(): void {
    const request = this.viewModel.createPlaybackRequest(this.currentPageState());
    if (!request) {
      hilog.warn(DOMAIN, TAG, 'Play callback ignored: missing playback request');
      return;
    }
    this.playbackErrorMessage = '';
    void this.playbackController.play(request);
  }

  private pauseMedia(): void {
    if (this.playbackPhase !== 'playing') {
      hilog.warn(DOMAIN, TAG, 'Pause callback ignored: phase=%{public}s', this.playbackPhase);
      return;
    }
    void this.playbackController.pause();
  }

  private stopMedia(): void {
    if (!this.canStopMedia()) {
      hilog.warn(DOMAIN, TAG, 'Stop callback ignored: phase=%{public}s', this.playbackPhase);
      return;
    }
    void this.playbackController.stop();
  }

  private canStopMedia(): boolean {
    return this.playbackPhase === 'playing' || this.playbackPhase === 'paused';
  }

  private videoContentSize(): MediaViewerContentSize {
    return this.viewModel.calculateVideoContentSize(this.currentPageState());
  }

  private imageContentSize(): MediaViewerContentSize {
    return this.viewModel.calculateImageContentSize(this.currentPageState());
  }

  private mediaViewportSize(): MediaViewerContentSize {
    return this.viewModel.calculateMediaViewportSize(this.currentPageState());
  }

  private imageMaximumViewportSize(): MediaViewerContentSize {
    return this.viewModel.calculateImageMaximumViewportSize();
  }

  private resolvedImageSource(): string {
    return this.viewModel.resolveImageSource(this.currentPageState());
  }

  private resolvedVideoPreviewSource(): string {
    return this.viewModel.resolveVideoPreviewSource(this.currentPageState());
  }

  private videoContentWidth(): number {
    return this.videoContentSize().width;
  }

  private videoContentHeight(): number {
    return this.videoContentSize().height;
  }

  private imageViewportSize(): MediaViewerContentSize {
    return {
      width: this.imageViewportWidth,
      height: this.imageViewportHeight
    };
  }

  private currentImageTransformConfig(): MediaViewerImageTransformConfig {
    return {
      identity: this.imageIdentity(),
      contentSize: this.imageContentSize(),
      initialViewportSize: this.mediaViewportSize(),
      maximumViewportSize: this.imageMaximumViewportSize()
    };
  }

  private imageIdentity(): string {
    return `${this.messageId}:${this.mediaKind}:${this.resolvedImageSource()}:${this.mediaWidth}:${this.mediaHeight}`;
  }

  private applyImageTransformSnapshot(snapshot: MediaViewerImageTransformSnapshot): void {
    this.imageZoomScale = snapshot.scale;
    this.imagePanOffsetX = snapshot.offsetX;
    this.imagePanOffsetY = snapshot.offsetY;
    this.imageTransformAnimationMs = snapshot.animationDurationMs;
    this.imageViewportWidth = snapshot.viewportSize.width;
    this.imageViewportHeight = snapshot.viewportSize.height;
    this.imagePanEnabled = snapshot.isPanEnabled;
  }

  private applyControlsOverlaySnapshot(snapshot: MediaViewerControlsOverlaySnapshot): void {
    this.controlPanelOpacity = snapshot.opacity;
    this.controlPanelFadeDurationMs = snapshot.fadeDurationMs;
    this.controlPanelInputEnabled = snapshot.inputEnabled;
  }

  private startImagePinch(): void {
    this.imageTransformController.startPinch();
  }

  private updateImagePinch(scale: number): void {
    this.imageTransformController.updatePinch(scale);
  }

  private startImagePan(): void {
    this.imageTransformController.startPan();
  }

  private updateImagePan(offsetX: number, offsetY: number): void {
    this.imageTransformController.updatePan(offsetX, offsetY);
  }

  private resetImageTransformFromGesture(): void {
    this.imageTransformController.reset(IMAGE_TRANSFORM_RESET_ANIMATION_MS);
  }

  private playbackElapsedSec(): number {
    if (this.playbackPositionMs > 0) {
      return Math.floor(this.playbackPositionMs / 1000);
    }
    return 0;
  }

  private playbackElapsedMs(): number {
    return this.playbackPositionMs > 0 ? this.playbackPositionMs : 0;
  }

  private playbackDurationSec(): number {
    if (this.mediaDurationSec > 0) {
      return this.mediaDurationSec;
    }
    return this.playbackDurationMs > 0 ? Math.floor(this.playbackDurationMs / 1000) : 0;
  }

  private shouldRenderVideoSurface(): boolean {
    return this.playbackPhase === 'loading' || this.playbackPhase === 'playing' || this.playbackPhase === 'paused';
  }

  @Builder
  private buildMediaViewport(): void {
    Stack({ alignContent: Alignment.Center }) {

      if (this.isVideoKind()) {

        MediaViewerVideoPlayer({
          contentWidth: this.videoContentWidth(),
          contentHeight: this.videoContentHeight(),
          previewSource: this.resolvedVideoPreviewSource(),
          isRoundVideoNote: this.isRoundVideoNote,
          shouldRenderVideoSurface: this.shouldRenderVideoSurface(),
          canPlay: this.playbackPhase !== 'playing' && this.playbackPhase !== 'loading' && this.mediaFilePath.length > 0,
          canPause: this.playbackPhase === 'playing',
          canStop: this.canStopMedia(),
          elapsedSec: this.playbackElapsedSec(),
          elapsedMs: this.playbackElapsedMs(),
          mediaDurationSec: this.playbackDurationSec(),
          showMilliseconds: this.playbackDurationSec() <= 3600,
          controlPanelOpacity: this.controlPanelOpacity,
          controlPanelFadeDurationMs: this.controlPanelFadeDurationMs,
          controlPanelInputEnabled: this.controlPanelInputEnabled,
          onSurfaceLoaded: (surfaceId: string): void => {
            this.playbackController.attachSurface(surfaceId);
          },
          onSurfaceDestroyed: (): void => {
            this.playbackController.detachSurface();
          },
          onRevealControls: (): void => {
            this.controlsOverlayController.reveal();
          },
          onPlay: (): void => {
            this.playMedia();
          },
          onPause: (): void => {
            this.pauseMedia();
          },
          onStop: (): void => {
            this.stopMedia();
          }
        })

      } else if (this.isImageKind()) {

        if (this.resolvedImageSource().length > 0) {
          MediaViewerImageViewport({
            imageSource: this.resolvedImageSource(),
            contentSize: this.imageContentSize(),
            viewportSize: this.imageViewportSize(),
            imageZoomScale: this.imageZoomScale,
            imagePanOffsetX: this.imagePanOffsetX,
            imagePanOffsetY: this.imagePanOffsetY,
            imageTransformAnimationMs: this.imageTransformAnimationMs,
            isPanEnabled: this.imagePanEnabled,
            onPinchStart: (): void => {
              this.startImagePinch();
            },
            onPinchUpdate: (scale: number): void => {
              this.updateImagePinch(scale);
            },
            onPanStart: (): void => {
              this.startImagePan();
            },
            onPanUpdate: (offsetX: number, offsetY: number): void => {
              this.updateImagePan(offsetX, offsetY);
            },
            onReset: (): void => {
              this.resetImageTransformFromGesture();
            }
          })
        }

      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Column({ space: 10 }) {

        this.buildMediaViewport()

        if (this.viewModel.shouldShowLoadingState(this.currentPageState(), this.playbackPhase)) {
          Text($r('app.string.chat_message_loading_video'))
            .fontSize(12)
            .fontColor($r('app.color.media_viewer_loading_text'))
        }

        if (this.playbackPhase === 'error') {
          Text(this.playbackErrorMessage.length > 0 ? this.playbackErrorMessage : $r('app.string.common_error_label'))
            .fontSize(11)
            .fontColor($r('app.color.media_viewer_error_text'))
            .textAlign(TextAlign.Center)
            .width('90%')
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }
}
