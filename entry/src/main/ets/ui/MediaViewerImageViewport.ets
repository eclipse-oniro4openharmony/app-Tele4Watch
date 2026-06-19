import { MediaViewerContentSize } from '../models/media/MediaViewerContentTypes';

/**
 * Renders fullscreen image content with watch-friendly pinch zoom, bounded pan and double-tap reset.
 */
@Component
export struct MediaViewerImageViewport {
  /** Renderable image source passed to ArkUI Image. */
  @Prop imageSource: string = '';

  /** Fitted image content size used as the default visual size. */
  @Prop contentSize: MediaViewerContentSize = { width: 0, height: 0 };

  /** Current clipping viewport; it grows with zoom until it reaches the full watch screen. */
  @Prop viewportSize: MediaViewerContentSize = { width: 0, height: 0 };

  /** Current image zoom scale owned by the page state. */
  @Prop imageZoomScale: number = 1.0;

  /** Current horizontal pan offset owned by the page state. */
  @Prop imagePanOffsetX: number = 0;

  /** Current vertical pan offset owned by the page state. */
  @Prop imagePanOffsetY: number = 0;

  /** Animation duration for transform and viewport changes. */
  @Prop imageTransformAnimationMs: number = 0;

  /** Whether one-finger pan should be registered for the zoomed image. */
  @Prop isPanEnabled: boolean = false;

  /** Callback executed when a pinch gesture starts. */
  onPinchStart: () => void = (): void => {};

  /** Callback executed when pinch scale changes. */
  onPinchUpdate: (scale: number) => void = (_scale: number): void => {};

  /** Callback executed when a pan gesture starts. */
  onPanStart: () => void = (): void => {};

  /** Callback executed when pan offset changes. */
  onPanUpdate: (offsetX: number, offsetY: number) => void = (_offsetX: number, _offsetY: number): void => {};

  /** Callback executed on double tap reset. */
  onReset: () => void = (): void => {};

  @Builder
  private buildImageContent(): void {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        Image(this.imageSource)
          .width(this.contentSize.width)
          .height(this.contentSize.height)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .scale({
            x: this.imageZoomScale,
            y: this.imageZoomScale,
            centerX: '50%',
            centerY: '50%'
          })
          .translate({
            x: this.imagePanOffsetX,
            y: this.imagePanOffsetY
          })
          .animation({ duration: this.imageTransformAnimationMs, curve: Curve.EaseInOut })
      }
      .width(this.viewportSize.width)
      .height(this.viewportSize.height)
      .clip(true)
      .animation({ duration: this.imageTransformAnimationMs, curve: Curve.EaseInOut })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildImageWithPanGesture(): void {
    Stack({ alignContent: Alignment.Center }) {
      this.buildImageContent()
    }
    .width('100%')
    .height('100%')
    .parallelGesture(
      GestureGroup(GestureMode.Parallel,
        PinchGesture({ fingers: 2 })
          .onActionStart((_event: GestureEvent): void => {
            this.onPinchStart();
          })
          .onActionUpdate((event: GestureEvent): void => {
            this.onPinchUpdate(event.scale);
          }),
        PanGesture({ fingers: 1, direction: PanDirection.All, distance: 8 })
          .onActionStart((_event: GestureEvent): void => {
            this.onPanStart();
          })
          .onActionUpdate((event: GestureEvent): void => {
            this.onPanUpdate(event.offsetX, event.offsetY);
          }),
        TapGesture({ count: 2, fingers: 1 })
          .onAction((_event: GestureEvent): void => {
            this.onReset();
          })
      )
    )
  }

  @Builder
  private buildImageWithoutPanGesture(): void {
    Stack({ alignContent: Alignment.Center }) {
      this.buildImageContent()
    }
    .width('100%')
    .height('100%')
    .parallelGesture(
      GestureGroup(GestureMode.Parallel,
        PinchGesture({ fingers: 2 })
          .onActionStart((_event: GestureEvent): void => {
            this.onPinchStart();
          })
          .onActionUpdate((event: GestureEvent): void => {
            this.onPinchUpdate(event.scale);
          }),
        TapGesture({ count: 2, fingers: 1 })
          .onAction((_event: GestureEvent): void => {
            this.onReset();
          })
      )
    )
  }

  /**
   * Renders the zoomable image viewport.
   */
  build() {
    if (this.isPanEnabled) {
      this.buildImageWithPanGesture()
    } else {
      this.buildImageWithoutPanGesture()
    }
  }
}
