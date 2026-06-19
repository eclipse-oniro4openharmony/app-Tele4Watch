import { hilog } from '@kit.PerformanceAnalysisKit';
import lottie, { AnimationItem } from '@ohos/lottie';
import resourceManager from '@ohos.resourceManager';
import { loadTgsLottieData } from '../viewmodel/TgsLottieViewModel';
import { TgsLottieLoadResult } from '../models/tgs/TgsViewTypes';
import { resolveString } from '../utils/ResourceTextResolver';

const DOMAIN = 0x2026;
const TAG = 'UserAvatar';

/**
 * Reusable user-avatar renderer.
 *
 * Rendering priority:
 * 1. Animated avatar via inline TGS/Lottie.
 * 2. Animated avatar via `Video` fallback.
 * 3. Static image.
 * 4. Initial-based fallback badge.
 */
@Component
export struct UserAvatar {
  /** Absolute local path to static avatar image. */
  @Prop imagePath: string = '';
  /** Absolute local path to animated avatar payload/file. */
  @Prop animationPath: string = '';
  /** Enables animated-avatar mode for this instance. */
  @Prop animateAvatar: boolean = false;
  /** Text source used to compute one-letter fallback initial. */
  @Prop fallbackText: string = '';
  /** Avatar circle diameter in vp. */
  @Prop avatarDiameter: number = 38;
  /** Fallback initial font size in fp. */
  @Prop fallbackInitialFontSize: number = 14;
  /** Maximum number of fallback initials rendered inside the badge. */
  @Prop fallbackMaxInitials: number = 1;
  /** Fallback badge background color. */
  @Prop fallbackBackgroundColor: ResourceColor = $r('app.color.contact_avatar_fallback_background');
  /** Optional gradient start color for fallback badge. */
  @Prop fallbackGradientStartColor: ResourceColor = $r('app.color.contact_avatar_fallback_background');
  /** Optional gradient end color for fallback badge. */
  @Prop fallbackGradientEndColor: ResourceColor = $r('app.color.contact_avatar_fallback_background');
  /** Enables gradient rendering for fallback badge. */
  @Prop fallbackUseGradient: boolean = false;
  /** Fallback initial text color. */
  @Prop fallbackFontColor: ResourceColor = $r('app.color.text_primary');
  /** Switches renderer to video path when TGS decode/render fails. */
  @State tgsLottieFallbackMode: boolean = false;
  private avatarVideoController: VideoController = new VideoController();
  private tgsCanvasRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private tgsCanvasRenderingContext: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.tgsCanvasRenderingSettings);
  private tgsAnimationItem: AnimationItem | null = null;
  private tgsAnimationName: string = '';
  private tgsAnimationPath: string = '';
  private tgsLoadingInProgress: boolean = false;

  private getResourceManager(): resourceManager.ResourceManager {
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      throw new Error('Host context unavailable.');
    }
    return hostContext.resourceManager;
  }

  private getString(resourceName: string, ...args: Array<string | number>): string {
    return resolveString(this.getResourceManager(), resourceName, ...args);
  }

  /**
   * Checks whether static avatar path is available.
   *
   * @returns `true` when `imagePath` is non-empty.
   */
  private hasImagePath(): boolean {
    return this.imagePath.trim().length > 0;
  }

  /**
   * Checks whether animated avatar path is available.
   *
   * @returns `true` when `animationPath` is non-empty.
   */
  private hasAnimationPath(): boolean {
    return this.animationPath.trim().length > 0;
  }

  /**
   * Normalizes local/remote path to ArkUI source format.
   *
   * @param path Raw absolute path or URI.
   * @returns Source value compatible with `Image`/`Video`.
   */
  private sourceFromPath(path: string): string {
    const trimmed = path.trim();
    if (trimmed.startsWith('file://') || trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return `file://${trimmed}`;
  }

  /**
   * Resolves static avatar image source.
   *
   * @returns Normalized static avatar source.
   */
  private avatarSource(): string {
    return this.sourceFromPath(this.imagePath);
  }

  /**
   * Resolves animated avatar media source.
   *
   * @returns Normalized animated avatar source.
   */
  private animationSource(): string {
    return this.sourceFromPath(this.animationPath);
  }

  /**
   * Resolves currently active animation path.
   *
   * @returns Trimmed path when animation is enabled and available; otherwise empty string.
   */
  private currentAnimationPath(): string {
    if (!this.animateAvatar || !this.hasAnimationPath()) {
      return '';
    }
    return this.animationPath.trim();
  }

  /**
   * Checks whether animated rendering should be attempted.
   *
   * @returns `true` when animation mode is enabled and path exists.
   */
  private shouldRenderAnimatedAvatar(): boolean {
    return this.animateAvatar && this.hasAnimationPath();
  }

  /**
   * Checks whether TGS/Lottie canvas should be rendered.
   *
   * @returns `true` when animation path exists and fallback mode is not active.
   */
  private shouldRenderTgsLottie(): boolean {
    const animationPath = this.currentAnimationPath();
    if (animationPath.length === 0) {
      return false;
    }
    if (!this.tgsLottieFallbackMode) {
      return true;
    }
    return this.tgsAnimationPath !== animationPath;
  }

  /**
   * Produces stable numeric signature for path-based instance naming.
   *
   * @param path Animation path used as hash source.
   * @returns Positive deterministic hash value.
   */
  private pathSignature(path: string): number {
    let hashValue = 0;
    const normalizedPath = path.trim();
    for (let index = 0; index < normalizedPath.length; index++) {
      hashValue = (hashValue * 33 + normalizedPath.charCodeAt(index)) % 2147483647;
    }
    return hashValue;
  }

  /**
   * Builds unique lottie instance name.
   *
   * @param path Animation source path.
   * @returns Stable animation name for lottie lifecycle API.
   */
  private tgsLottieAnimationNameFor(path: string): string {
    return `tgs-avatar-${this.pathSignature(path)}-${this.avatarDiameter}`;
  }

  /**
   * Formats TGS decode diagnostics to compact string.
   *
   * @param loadResult Result from TGS loader.
   * @returns One-line diagnostic details.
   */
  private tgsLoadDetail(loadResult: TgsLottieLoadResult): string {
    const sourceValue = typeof loadResult.source === 'string' ? loadResult.source : 'n/a';
    const decodeMsValue = typeof loadResult.decodeMs === 'number' ? String(loadResult.decodeMs) : 'n/a';
    const bytesValue = typeof loadResult.decompressedBytes === 'number' ? String(loadResult.decompressedBytes) : 'n/a';
    const chunkValue = typeof loadResult.chunkCount === 'number' ? String(loadResult.chunkCount) : 'n/a';
    const errorValue = typeof loadResult.error === 'string' ? loadResult.error : '';
    return `source=${sourceValue} decodeMs=${decodeMsValue} bytes=${bytesValue} chunks=${chunkValue} err=${errorValue}`;
  }

  /**
   * Stops and disposes inline TGS animation for avatar.
   *
   * @returns Nothing.
   */
  private destroyTgsLottieAnimation(): void {
    if (this.tgsAnimationItem) {
      this.tgsAnimationItem.removeEventListener('DOMLoaded');
      this.tgsAnimationItem = null;
    }
    if (this.tgsAnimationName.length > 0) {
      lottie.destroy(this.tgsAnimationName);
      this.tgsAnimationName = '';
    }
  }

  /**
   * Ensures avatar TGS animation exists and is playing when component is visible.
   *
   * @returns Nothing.
   */
  private ensureTgsLottieAnimation(): void {
    const tgsPath = this.currentAnimationPath();
    if (tgsPath.length === 0) {
      this.destroyTgsLottieAnimation();
      this.tgsAnimationPath = '';
      this.tgsLoadingInProgress = false;
      this.tgsLottieFallbackMode = false;
      return;
    }

    if (this.tgsAnimationPath !== tgsPath) {
      this.tgsLottieFallbackMode = false;
    }
    if (this.tgsAnimationPath === tgsPath && this.tgsAnimationItem) {
      this.tgsAnimationItem.resize();
      this.tgsAnimationItem.play();
      return;
    }
    if (this.tgsLoadingInProgress && this.tgsAnimationPath === tgsPath) {
      return;
    }

    this.tgsAnimationPath = tgsPath;
    this.tgsLoadingInProgress = true;
    this.loadTgsLottieAnimation(tgsPath);
  }

  /**
   * Loads parsed TGS payload and initializes Lottie canvas renderer for avatar.
   *
   * @param tgsPath Absolute local path to `.tgs` file.
   * @returns Promise resolved after load attempt finishes.
   */
  private async loadTgsLottieAnimation(tgsPath: string): Promise<void> {
    this.destroyTgsLottieAnimation();

    const loadResult = await loadTgsLottieData(tgsPath);
    if (this.tgsAnimationPath !== tgsPath) {
      this.tgsLoadingInProgress = false;
      return;
    }

    if (!loadResult.ok || !loadResult.animationData) {
      this.tgsLottieFallbackMode = true;
      this.tgsLoadingInProgress = false;
      hilog.info(DOMAIN, TAG, 'Avatar TGS load failed: %{public}s', this.tgsLoadDetail(loadResult));
      return;
    }

    try {
      this.tgsCanvasRenderingContext.imageSmoothingEnabled = true;
      this.tgsCanvasRenderingContext.imageSmoothingQuality = 'medium';
      this.tgsAnimationName = this.tgsLottieAnimationNameFor(tgsPath);
      this.tgsAnimationItem = lottie.loadAnimation({
        'container': this.tgsCanvasRenderingContext,
        'renderer': 'canvas',
        'loop': true,
        'autoplay': false,
        'name': this.tgsAnimationName,
        'animationData': loadResult.animationData
      });
      this.tgsAnimationItem.addEventListener('DOMLoaded', () => {
        if (!this.tgsAnimationItem) {
          return;
        }
        this.tgsAnimationItem.play();
      });
      this.tgsLottieFallbackMode = false;
      hilog.info(DOMAIN, TAG, 'Avatar TGS render ready: %{public}s', this.tgsLoadDetail(loadResult));
    } catch (error) {
      this.destroyTgsLottieAnimation();
      this.tgsLottieFallbackMode = true;
      hilog.error(DOMAIN, TAG, 'Avatar TGS render failed: %{public}s', String(error));
    }
    this.tgsLoadingInProgress = false;
  }

  /**
   * Resolves fallback initials.
   *
   * @returns Uppercase initials derived from `fallbackText` or resource fallback symbol.
   */
  private fallbackInitial(): string {
    const trimmed = this.fallbackText.trim();
    if (trimmed.length === 0) {
      return this.getString('common_unknown_label');
    }

    const normalizedParts = trimmed.split(/\s+/).filter((part: string) => part.length > 0);
    const maxInitials = this.fallbackMaxInitials > 1 ? this.fallbackMaxInitials : 1;
    if (normalizedParts.length >= 2) {
      let initials = '';
      const partsToUse = normalizedParts.length < maxInitials ? normalizedParts.length : maxInitials;
      for (let index = 0; index < partsToUse; index += 1) {
        const part = normalizedParts[index];
        initials += part.substring(0, 1).toUpperCase();
      }
      if (initials.length > 0) {
        return initials;
      }
    }

    const compact = trimmed.replace(/\s+/g, '');
    if (compact.length === 0) {
      return this.getString('common_unknown_label');
    }
    if (maxInitials > 1 && compact.length > 1) {
      return compact.substring(0, 2).toUpperCase();
    }
    return compact.substring(0, 1).toUpperCase();
  }

  /**
   * Renders avatar in best available mode for current input props.
   */
  build() {
    if (this.shouldRenderTgsLottie()) {
      Canvas(this.tgsCanvasRenderingContext)
        .width(this.avatarDiameter)
        .height(this.avatarDiameter)
        .borderRadius(this.avatarDiameter / 2)
        .backgroundColor($r('app.color.surface_transparent'))
        .onReady(() => {
          this.ensureTgsLottieAnimation();
        })
        .onAppear(() => {
          this.ensureTgsLottieAnimation();
        })
    } else if (this.shouldRenderAnimatedAvatar()) {
      Video({
        src: this.animationSource(),
        controller: this.avatarVideoController
      })
        .width(this.avatarDiameter)
        .height(this.avatarDiameter)
        .borderRadius(this.avatarDiameter / 2)
        .controls(false)
        .autoPlay(true)
        .objectFit(ImageFit.Cover)
        .onAppear(() => {
          this.avatarVideoController.start();
        })
        .onFinish(() => {
          this.avatarVideoController.start();
        })
    } else if (this.hasImagePath()) {
      Image(this.avatarSource())
        .width(this.avatarDiameter)
        .height(this.avatarDiameter)
        .borderRadius(this.avatarDiameter / 2)
        .objectFit(ImageFit.Cover)
    } else {
      Column() {
        Text(this.fallbackInitial())
          .fontSize(this.fallbackInitialFontSize)
          .fontColor(this.fallbackFontColor)
      }
      .width(this.avatarDiameter)
      .height(this.avatarDiameter)
      .borderRadius(this.avatarDiameter / 2)
      .linearGradient(this.fallbackUseGradient ? {
        direction: GradientDirection.LeftTop,
        colors: [[this.fallbackGradientStartColor, 0.0], [this.fallbackGradientEndColor, 1.0]]
      } : {
        direction: GradientDirection.LeftTop,
        colors: [[this.fallbackBackgroundColor, 0.0], [this.fallbackBackgroundColor, 1.0]]
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  /**
   * Disposes TGS animation resources when component leaves screen.
   */
  aboutToDisappear(): void {
    this.destroyTgsLottieAnimation();
  }
}
