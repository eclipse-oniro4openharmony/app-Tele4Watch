import { MediaPlaybackTimerBadge } from './MediaPlaybackTimerBadge';
import { MediaViewerPlaybackControlPanel } from './MediaViewerPlaybackControlPanel';

const CONTROL_PANEL_HIDDEN_OPACITY = 0;

/**
 * Renders fullscreen video/animation media with preview, native surface and playback controls overlay.
 */
@Component
export struct MediaViewerVideoPlayer {
  /** Width of the video surface and preview in vp. */
  @Prop contentWidth: number = 0;

  /** Height of the video surface and preview in vp. */
  @Prop contentHeight: number = 0;

  /** Renderable preview source for the image shown before the native surface is active. */
  @Prop previewSource: string = '';

  /** Whether the content is a round video note. */
  @Prop isRoundVideoNote: boolean = false;

  /** Whether the native video surface should be visible above the preview. */
  @Prop shouldRenderVideoSurface: boolean = false;

  /** Whether play is currently allowed. */
  @Prop canPlay: boolean = false;

  /** Whether pause is currently allowed. */
  @Prop canPause: boolean = false;

  /** Whether stop is currently allowed. */
  @Prop canStop: boolean = false;

  /** Elapsed playback seconds for the timer badge. */
  @Prop elapsedSec: number = 0;

  /** Elapsed playback milliseconds for the timer badge. */
  @Prop elapsedMs: number = 0;

  /** Total media duration in seconds. */
  @Prop mediaDurationSec: number = 0;

  /** Whether the timer badge should include milliseconds. */
  @Prop showMilliseconds: boolean = false;

  /** Control panel opacity driven by the parent state machine. */
  @Prop controlPanelOpacity: number = 1;

  /** Control panel fade animation duration in milliseconds. */
  @Prop controlPanelFadeDurationMs: number = 0;

  /** Whether playback controls should accept input. */
  @Prop controlPanelInputEnabled: boolean = true;

  /** Callback executed when the XComponent surface becomes available. */
  onSurfaceLoaded: (surfaceId: string) => void = (_surfaceId: string): void => {};

  /** Callback executed when the XComponent surface is destroyed. */
  onSurfaceDestroyed: () => void = (): void => {};

  /** Callback executed when the user taps the video overlay. */
  onRevealControls: () => void = (): void => {};

  /** Callback executed when the user taps play. */
  onPlay: () => void = (): void => {};

  /** Callback executed when the user taps pause. */
  onPause: () => void = (): void => {};

  /** Callback executed when the user taps stop. */
  onStop: () => void = (): void => {};

  private readonly xComponentController: XComponentController = new XComponentController();

  private videoBorderRadius(): number {
    return this.isRoundVideoNote ? Math.floor(this.contentWidth / 2) : 18;
  }

  @Builder
  private buildVideoSurface(): void {
    XComponent({ id: 'media_viewer_surface', type: XComponentType.SURFACE, controller: this.xComponentController })
      .width(this.contentWidth)
      .height(this.contentHeight)
      .backgroundColor($r('app.color.media_viewer_surface_background'))
      .borderRadius(this.videoBorderRadius())
      .onLoad(() => {
        const surfaceId = this.xComponentController.getXComponentSurfaceId();
        this.onSurfaceLoaded(surfaceId);
      })
      .onDestroy(() => {
        this.onSurfaceDestroyed();
      })
  }

  @Builder
  private buildVideoPreviewContent(): void {
    if (this.previewSource.length > 0) {
      Image(this.previewSource)
        .width(this.contentWidth)
        .height(this.contentHeight)
        .objectFit(this.isRoundVideoNote ? ImageFit.Cover : ImageFit.Contain)
        .borderRadius(this.videoBorderRadius())
        .draggable(false)
    } else {
      Column() {}
        .width(this.contentWidth)
        .height(this.contentHeight)
        .backgroundColor($r('app.color.surface_media_placeholder_background'))
        .borderRadius(this.videoBorderRadius())
    }
  }

  @Builder
  private buildVideoOverlay(): void {
    RelativeContainer() {
      MediaPlaybackTimerBadge({
        elapsedSec: this.elapsedSec,
        elapsedMs: this.elapsedMs,
        mediaDurationSec: this.mediaDurationSec,
        showMilliseconds: this.showMilliseconds
      })
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Top },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .margin({ top: 40 })

      MediaViewerPlaybackControlPanel({
        canPlay: this.canPlay,
        canPause: this.canPause,
        canStop: this.canStop,
        onPlay: (): void => {
          this.onPlay();
        },
        onPause: (): void => {
          this.onPause();
        },
        onStop: (): void => {
          this.onStop();
        }
      })
        .enabled(this.controlPanelInputEnabled)
        .visibility(this.controlPanelInputEnabled || this.controlPanelOpacity > CONTROL_PANEL_HIDDEN_OPACITY ?
          Visibility.Visible :
          Visibility.Hidden)
        .opacity(this.controlPanelOpacity)
        .animation({ duration: this.controlPanelFadeDurationMs, curve: Curve.EaseInOut })
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Bottom },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .margin({ bottom: 85 })
    }
    .width('100%')
    .height('100%')
    .onClick((): void => {
      this.onRevealControls();
    })
  }

  /**
   * Renders the video player surface stack.
   */
  build() {
    Stack({ alignContent: Alignment.Center }) {
      this.buildVideoPreviewContent()
      if (this.shouldRenderVideoSurface) {
        this.buildVideoSurface()
      }
      this.buildVideoOverlay()
    }
    .width('100%')
    .height('100%')
  }
}
