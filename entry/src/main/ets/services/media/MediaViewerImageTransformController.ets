import { MediaViewerContentSize, MediaViewerImageTransform } from '../../models/media/MediaViewerContentTypes';

const IMAGE_TRANSFORM_MIN_SCALE: number = 1.0;
const IMAGE_TRANSFORM_MAX_SCALE: number = 4.0;
const IMAGE_PAN_ACTIVE_SCALE_THRESHOLD: number = 1.001;

export interface MediaViewerImageTransformConfig {
  identity: string;
  contentSize: MediaViewerContentSize;
  initialViewportSize: MediaViewerContentSize;
  maximumViewportSize: MediaViewerContentSize;
}

export interface MediaViewerImageTransformSnapshot {
  scale: number;
  offsetX: number;
  offsetY: number;
  animationDurationMs: number;
  viewportSize: MediaViewerContentSize;
  isPanEnabled: boolean;
}

function createEmptyContentSize(): MediaViewerContentSize {
  return {
    width: 0,
    height: 0
  };
}

function cloneContentSize(size: MediaViewerContentSize): MediaViewerContentSize {
  return {
    width: size.width,
    height: size.height
  };
}

function createDefaultConfig(): MediaViewerImageTransformConfig {
  return {
    identity: '',
    contentSize: createEmptyContentSize(),
    initialViewportSize: createEmptyContentSize(),
    maximumViewportSize: createEmptyContentSize()
  };
}

function cloneConfig(config: MediaViewerImageTransformConfig): MediaViewerImageTransformConfig {
  return {
    identity: config.identity,
    contentSize: cloneContentSize(config.contentSize),
    initialViewportSize: cloneContentSize(config.initialViewportSize),
    maximumViewportSize: cloneContentSize(config.maximumViewportSize)
  };
}

function clampNumber(value: number, minimum: number, maximum: number): number {
  if (value < minimum) {
    return minimum;
  }
  if (value > maximum) {
    return maximum;
  }
  return value;
}

function calculateImagePanLimit(contentLength: number, viewportLength: number, scale: number): number {
  const scaledContentLength = Math.max(contentLength, 0) * scale;
  const safeViewportLength = Math.max(viewportLength, 0);
  return Math.max(0, (scaledContentLength - safeViewportLength) / 2);
}

/**
 * Calculates the clipping viewport for a zoomed image.
 *
 * @param initialViewportSize default safe viewport size in vp.
 * @param maximumViewportSize maximum screen viewport size in vp.
 * @param scale current image zoom scale.
 * @returns viewport size that grows with the image until it reaches the full screen.
 */
export function calculateMediaViewerImageViewportSizeForScale(
  initialViewportSize: MediaViewerContentSize,
  maximumViewportSize: MediaViewerContentSize,
  scale: number
): MediaViewerContentSize {
  const safeScale = clampNumber(scale, IMAGE_TRANSFORM_MIN_SCALE, IMAGE_TRANSFORM_MAX_SCALE);
  return {
    width: Math.round(Math.min(initialViewportSize.width * safeScale, maximumViewportSize.width)),
    height: Math.round(Math.min(initialViewportSize.height * safeScale, maximumViewportSize.height))
  };
}

/**
 * Clamps an image transform to the supported zoom range and current viewport bounds.
 *
 * @param transform requested transform from gesture state.
 * @param contentSize fitted image content size in vp.
 * @param initialViewportSize default safe viewport size in vp.
 * @param maximumViewportSize maximum screen viewport size in vp.
 * @returns transform safe to apply to the rendered image.
 */
export function clampMediaViewerImageTransform(
  transform: MediaViewerImageTransform,
  contentSize: MediaViewerContentSize,
  initialViewportSize: MediaViewerContentSize,
  maximumViewportSize: MediaViewerContentSize
): MediaViewerImageTransform {
  const scale = clampNumber(transform.scale, IMAGE_TRANSFORM_MIN_SCALE, IMAGE_TRANSFORM_MAX_SCALE);
  const viewportSize = calculateMediaViewerImageViewportSizeForScale(initialViewportSize, maximumViewportSize, scale);
  const horizontalLimit = calculateImagePanLimit(contentSize.width, viewportSize.width, scale);
  const verticalLimit = calculateImagePanLimit(contentSize.height, viewportSize.height, scale);
  return {
    scale: scale,
    offsetX: clampNumber(transform.offsetX, -horizontalLimit, horizontalLimit),
    offsetY: clampNumber(transform.offsetY, -verticalLimit, verticalLimit)
  };
}

/**
 * Provides the default image transform used when opening or resetting the viewer.
 *
 * @returns start transform matching the default fitted image state.
 */
export function createInitialMediaViewerImageTransform(): MediaViewerImageTransform {
  return {
    scale: IMAGE_TRANSFORM_MIN_SCALE,
    offsetX: 0,
    offsetY: 0
  };
}

function createSnapshotFromTransform(
  transform: MediaViewerImageTransform,
  config: MediaViewerImageTransformConfig,
  animationDurationMs: number
): MediaViewerImageTransformSnapshot {
  return {
    scale: transform.scale,
    offsetX: transform.offsetX,
    offsetY: transform.offsetY,
    animationDurationMs: animationDurationMs,
    viewportSize: calculateMediaViewerImageViewportSizeForScale(
      config.initialViewportSize,
      config.maximumViewportSize,
      transform.scale
    ),
    isPanEnabled: transform.scale > IMAGE_PAN_ACTIVE_SCALE_THRESHOLD
  };
}

/**
 * Owns MediaViewer image zoom/pan state independently from ArkUI rendering.
 */
export class MediaViewerImageTransformController {
  private listener: ((snapshot: MediaViewerImageTransformSnapshot) => void) | undefined = undefined;
  private config: MediaViewerImageTransformConfig = createDefaultConfig();
  private snapshot: MediaViewerImageTransformSnapshot = createSnapshotFromTransform(
    createInitialMediaViewerImageTransform(),
    createDefaultConfig(),
    0
  );
  private pinchStartScale: number = 1.0;
  private pinchStartOffsetX: number = 0;
  private pinchStartOffsetY: number = 0;
  private panStartOffsetX: number = 0;
  private panStartOffsetY: number = 0;

  /**
   * Sets a listener for transform snapshot changes.
   *
   * @param listener callback receiving a cloned transform snapshot.
   */
  setListener(listener: ((snapshot: MediaViewerImageTransformSnapshot) => void) | undefined): void {
    this.listener = listener;
    this.notifyListener();
  }

  /**
   * Returns the current image transform snapshot.
   *
   * @returns cloned current snapshot.
   */
  getSnapshot(): MediaViewerImageTransformSnapshot {
    return this.cloneSnapshot(this.snapshot);
  }

  /**
   * Applies current media geometry. Identity changes reset the transform.
   *
   * @param config current media geometry and identity.
   */
  syncConfig(config: MediaViewerImageTransformConfig): void {
    const previousIdentity = this.config.identity;
    this.config = cloneConfig(config);
    if (previousIdentity !== this.config.identity) {
      this.reset(0);
      return;
    }
    this.applyTransform({
      scale: this.snapshot.scale,
      offsetX: this.snapshot.offsetX,
      offsetY: this.snapshot.offsetY
    }, 0);
  }

  /**
   * Captures the start transform for a pinch gesture.
   */
  startPinch(): void {
    this.pinchStartScale = this.snapshot.scale;
    this.pinchStartOffsetX = this.snapshot.offsetX;
    this.pinchStartOffsetY = this.snapshot.offsetY;
  }

  /**
   * Applies a pinch scale delta.
   *
   * @param scale pinch scale reported by ArkUI.
   */
  updatePinch(scale: number): void {
    this.applyTransform({
      scale: this.pinchStartScale * scale,
      offsetX: this.pinchStartOffsetX,
      offsetY: this.pinchStartOffsetY
    }, 0);
  }

  /**
   * Captures the start transform for a pan gesture.
   */
  startPan(): void {
    this.panStartOffsetX = this.snapshot.offsetX;
    this.panStartOffsetY = this.snapshot.offsetY;
  }

  /**
   * Applies a pan offset delta.
   *
   * @param offsetX horizontal pan offset from ArkUI.
   * @param offsetY vertical pan offset from ArkUI.
   */
  updatePan(offsetX: number, offsetY: number): void {
    if (!this.snapshot.isPanEnabled) {
      this.reset(0);
      return;
    }
    this.applyTransform({
      scale: this.snapshot.scale,
      offsetX: this.panStartOffsetX + offsetX,
      offsetY: this.panStartOffsetY + offsetY
    }, 0);
  }

  /**
   * Resets image transform to the initial state.
   *
   * @param animationDurationMs animation duration for the reset transition.
   */
  reset(animationDurationMs: number): void {
    this.applyTransform(createInitialMediaViewerImageTransform(), animationDurationMs);
  }

  private applyTransform(transform: MediaViewerImageTransform, animationDurationMs: number): void {
    const clampedTransform = clampMediaViewerImageTransform(
      transform,
      this.config.contentSize,
      this.config.initialViewportSize,
      this.config.maximumViewportSize
    );
    this.snapshot = createSnapshotFromTransform(clampedTransform, this.config, animationDurationMs);
    this.notifyListener();
  }

  private cloneSnapshot(snapshot: MediaViewerImageTransformSnapshot): MediaViewerImageTransformSnapshot {
    return {
      scale: snapshot.scale,
      offsetX: snapshot.offsetX,
      offsetY: snapshot.offsetY,
      animationDurationMs: snapshot.animationDurationMs,
      viewportSize: cloneContentSize(snapshot.viewportSize),
      isPanEnabled: snapshot.isPanEnabled
    };
  }

  private notifyListener(): void {
    if (!this.listener) {
      return;
    }
    this.listener(this.getSnapshot());
  }
}
