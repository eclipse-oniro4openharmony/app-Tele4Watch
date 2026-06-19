import { TdChatMessageItem } from '../models/td/TdViewTypes';
import { ArcListItem } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import lottie, { AnimationItem } from '@ohos/lottie';
import resourceManager from '@ohos.resourceManager';
import { clearTgsLottieCache, loadTgsLottieData } from '../viewmodel/TgsLottieViewModel';
import { MediaPlaybackTimerBadge } from './MediaPlaybackTimerBadge';
import {
  isRenderableImagePath,
  resolveInlineVideoPath,
  resolveInlineVideoPreviewPath,
  resolveMediaComponentSource
} from '../services/media/MediaSourceResolver';
import { UserAvatar } from './UserAvatar';
import { VoiceNoteMessageBubble } from './VoiceNoteMessageBubble';
import { VideoNoteMessageBubble } from './VideoNoteMessageBubble';
import { avatarFallbackGradientEndColor, avatarFallbackGradientStartColor } from './AvatarFallbackPalette';
import { resolveString } from '../utils/ResourceTextResolver';
import { splitCallDurationParts } from '../utils/CallDurationFormatter';
import { UiTextValue, createEmptyUiTextValue } from '../models/ui/UiTextValue';
import { VoiceNotePlaybackSnapshot } from '../services/media/VoiceNotePlaybackController';

const DOMAIN = 0x2026;
const TAG = 'ChatMessageListItem';
const TGS_ACTIVE_ANIMATION_LIMIT = 2;
const tgsActiveAnimationSlots: Set<string> = new Set<string>();

/**
 * Renders one chat timeline row, including text, media and voice-note message variants.
 */
@Component
export struct ChatMessageListItem {
  message: TdChatMessageItem = {
    'id': '',
    'chatId': '',
    'senderUserId': '',
    'senderChatId': undefined,
    'senderAvatarPath': undefined,
    'sendingState': undefined,
    'deliveryState': undefined,
    'kind': 'text',
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
    'isOutgoing': false,
    'date': 0
  };
  senderLabel: string = '';
  senderAvatarPaletteIndex: number = 0;
  timeLabel: string = '';
  onAvatarClick: () => void = (): void => {};
  @Prop voiceNotePlayback: VoiceNotePlaybackSnapshot = {
    'messageId': '',
    'phase': 'idle',
    'positionMs': 0,
    'durationMs': 0,
    'errorMessage': ''
  };
  onVoiceNoteToggle: (message: TdChatMessageItem) => void = (_message: TdChatMessageItem): void => {};
  onMediaClick: (message: TdChatMessageItem) => void = (_message: TdChatMessageItem): void => {};
  private inlineVideoController: VideoController = new VideoController();
  @State tgsLottieFallbackMode: boolean = false;
  @State tgsSlotBlocked: boolean = false;
  @State inlineVideoPlaying: boolean = false;
  @State inlineGifPlaying: boolean = false;
  @State inlinePlaybackElapsedSec: number = 0;
  @State inlineVideoPreviewHiddenAfterFinish: boolean = false;
  private inlineVideoPreviewMessageId: string = '';
  private inlinePlaybackTimerHandle: number = -1;
  private tgsCanvasRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private tgsCanvasRenderingContext: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.tgsCanvasRenderingSettings);
  private tgsAnimationItem: AnimationItem | null = null;
  private tgsAnimationName: string = '';
  private tgsAnimationPath: string = '';
  private tgsSlotKey: string = '';
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

  private avatarSource(path: string): string {
    return resolveMediaComponentSource(path);
  }

  private senderAvatarPath(): string {
    if (typeof this.message.senderAvatarPath === 'string' && this.message.senderAvatarPath.length > 0) {
      return this.message.senderAvatarPath;
    }
    return '';
  }

  private canOpenSenderProfile(): boolean {
    return typeof this.message.senderUserId === 'string' && this.message.senderUserId.length > 0;
  }

  @Builder
  private buildSenderAvatar(): void {
    Column() {
      UserAvatar({
        imagePath: this.senderAvatarPath(),
        fallbackText: this.senderLabel,
        avatarDiameter: 28,
        fallbackInitialFontSize: 11,
        fallbackMaxInitials: 2,
        fallbackBackgroundColor: $r('app.color.contact_avatar_fallback_background'),
        fallbackGradientStartColor: avatarFallbackGradientStartColor(this.senderAvatarPaletteIndex),
        fallbackGradientEndColor: avatarFallbackGradientEndColor(this.senderAvatarPaletteIndex),
        fallbackUseGradient: true
      })
    }
    .onClick(() => {
      if (!this.canOpenSenderProfile()) {
        return;
      }
      this.onAvatarClick();
    })
  }

  private resolveUiText(textValue: UiTextValue | undefined): string {
    if (!textValue) {
      return '';
    }
    if (textValue.rawText.length > 0) {
      return textValue.rawText;
    }
    if (textValue.resourceName.length === 0) {
      return '';
    }
    return this.getString(textValue.resourceName, ...textValue.args);
  }

  private serviceEventText(): string {
    const resolvedText = this.resolveUiText(this.message.textValue);
    if (resolvedText.length > 0) {
      return resolvedText;
    }
    return this.message.text;
  }

  private hasServiceEventPreview(): boolean {
    return this.mediaPath().length > 0;
  }

  private serviceEventPreviewHeight(): number {
    const defaultHeight = 60;
    const maxHeight = 74;
    const rawWidth = this.message.mediaWidth;
    const rawHeight = this.message.mediaHeight;
    if (typeof rawWidth !== 'number' || typeof rawHeight !== 'number' || rawWidth <= 0 || rawHeight <= 0) {
      return defaultHeight;
    }

    const baseWidth = 84;
    const estimatedHeight = Math.round((baseWidth * rawHeight) / rawWidth);
    if (estimatedHeight < 42) {
      return 42;
    }
    if (estimatedHeight > maxHeight) {
      return maxHeight;
    }
    return estimatedHeight;
  }

  private resolvedTimeLabel(): string {
    if (this.timeLabel.length > 0) {
      return this.timeLabel;
    }
    return this.getString('common_time_placeholder');
  }

  private bubbleBackgroundColor(): ResourceColor {
    if (this.message.isOutgoing) {
      return $r('app.color.chat_message_bubble_outgoing_background');
    }
    return $r('app.color.chat_message_bubble_incoming_background');
  }

  private bubbleGradientStartColor(): ResourceColor {
    if (this.message.isOutgoing) {
      return $r('app.color.chat_message_bubble_outgoing_gradient_start');
    }
    return $r('app.color.chat_message_bubble_incoming_gradient_start');
  }

  private bubbleGradientEndColor(): ResourceColor {
    if (this.message.isOutgoing) {
      return $r('app.color.chat_message_bubble_outgoing_gradient_end');
    }
    return $r('app.color.chat_message_bubble_incoming_gradient_end');
  }

  private timeTextColor(): ResourceColor {
    if (this.message.isOutgoing) {
      return $r('app.color.chat_message_meta_outgoing');
    }
    return $r('app.color.chat_message_meta_incoming');
  }

  private timeTextAlign(): TextAlign {
    if (this.message.isOutgoing) {
      return TextAlign.End;
    }
    return TextAlign.Start;
  }

  private shouldShowDeliveryState(): boolean {
    if (!this.message.isOutgoing) {
      return false;
    }
    return typeof this.message.deliveryState === 'string' && this.message.deliveryState.length > 0;
  }

  @Builder
  private buildDeliveryStateIcon(): void {
    if (this.message.deliveryState === 'read') {
      Row({ space: 1 }) {
        Image($r('app.media.chat_status_check'))
          .width(13)
          .height(13)
          .objectFit(ImageFit.Contain)
        Image($r('app.media.chat_status_halfcheck'))
          .width(13)
          .height(13)
          .objectFit(ImageFit.Contain)
      }
      .height(13)
    } else if (this.message.deliveryState === 'sent') {
      Image($r('app.media.chat_status_check'))
        .width(13)
        .height(13)
        .objectFit(ImageFit.Contain)
    } else if (this.message.deliveryState === 'failed') {
      Image($r('app.media.chat_status_warning'))
        .width(9)
        .height(13)
        .objectFit(ImageFit.Contain)
    } else if (this.message.deliveryState === 'pending') {
      Image($r('app.media.chat_status_pending_clock'))
        .width(12)
        .height(12)
        .objectFit(ImageFit.Contain)
    }
  }

  @Builder
  private buildMessageMetaRow(): void {
    Row({ space: 5 }) {
      Text(this.resolvedTimeLabel())
        .fontSize(10)
        .fontColor(this.timeTextColor())
        .textAlign(this.timeTextAlign())

      if (this.shouldShowDeliveryState()) {
        this.buildDeliveryStateIcon()
      }
    }
    .width('100%')
    .justifyContent(this.message.isOutgoing ? FlexAlign.End : FlexAlign.Start)
    .alignItems(VerticalAlign.Center)
  }

  private messageKind(): string {
    if (typeof this.message.kind === 'string' && this.message.kind.length > 0) {
      return this.message.kind;
    }
    return 'text';
  }

  private isServiceEventMessage(): boolean {
    return this.messageKind() === 'serviceEvent';
  }

  private isCallEventMessage(): boolean {
    return this.messageKind() === 'callEvent';
  }

  /**
   * Returns the `TdCallEventStatus` carried by the current message, with
   * `'answered'` as the safe default when the field is missing (defensive —
   * the parser always sets it for `messageCall`).
   */
  private callEventStatus(): string {
    const status = this.message.callEventStatus;
    if (typeof status === 'string' && status.length > 0) {
      return status;
    }
    return 'answered';
  }

  /**
   * Maps the current call-event status × direction × video flag onto a
   * localised title string.
   */
  private callEventTitleResource(): ResourceStr {
    const status = this.callEventStatus();
    const isOutgoing = this.message.isOutgoing;
    const isVideo = this.message.callEventIsVideo === true;
    if (status === 'missed') {
      return isVideo
        ? $r('app.string.chat_call_event_title_missed_video')
        : $r('app.string.chat_call_event_title_missed');
    }
    if (status === 'declined') {
      return isVideo
        ? $r('app.string.chat_call_event_title_declined_video')
        : $r('app.string.chat_call_event_title_declined');
    }
    if (status === 'cancelled') {
      return isVideo
        ? $r('app.string.chat_call_event_title_cancelled_video')
        : $r('app.string.chat_call_event_title_cancelled');
    }
    // answered
    if (isOutgoing) {
      return isVideo
        ? $r('app.string.chat_call_event_title_outgoing_video')
        : $r('app.string.chat_call_event_title_outgoing');
    }
    return isVideo
      ? $r('app.string.chat_call_event_title_incoming_video')
      : $r('app.string.chat_call_event_title_incoming');
  }

  /**
   * Picks the trailing phone-icon asset for the call bubble. Outgoing
   * bubbles use the existing white-stroke `profile_call_icon.svg` (kontrast
   * z accent purple/blue tła), incoming/missed/declined/cancelled bubbles
   * use the accent-blue variant so the icon stays legible on the dark
   * incoming bubble background.
   */
  private callEventPhoneIconResource(): Resource {
    if (this.message.isOutgoing) {
      return $r('app.media.profile_call_icon');
    }
    return $r('app.media.chat_icon_call_event_accent');
  }

  /**
   * Picks the arrow SVG asset matching call direction × status colour.
   * Outgoing call uses ↗, incoming/missed/declined uses ↙; status drives
   * green (`answered`) vs red (`missed` / `declined` / outgoing `cancelled`).
   */
  private callEventArrowResource(): Resource {
    const status = this.callEventStatus();
    const isOutgoing = this.message.isOutgoing;
    const isFailure = status === 'missed' || status === 'declined' || status === 'cancelled';
    if (isOutgoing) {
      return isFailure
        ? $r('app.media.chat_icon_call_arrow_outgoing_red')
        : $r('app.media.chat_icon_call_arrow_outgoing_green');
    }
    return isFailure
      ? $r('app.media.chat_icon_call_arrow_incoming_red')
      : $r('app.media.chat_icon_call_arrow_incoming_green');
  }

  /**
   * Builds the "HH:MM" or "HH:MM, X seconds" / "HH:MM, M min X seconds"
   * label for the call bubble bottom row, depending on `callEventDurationSec`.
   * The HH:MM portion comes from `timeLabel` (formatted by the parent
   * ChatDetails view), the duration suffix from the resolved resources.
   */
  private callEventTimeDurationText(): string {
    const time = this.resolvedTimeLabel();
    const durationSec = typeof this.message.callEventDurationSec === 'number'
      ? this.message.callEventDurationSec
      : 0;
    if (durationSec <= 0) {
      return time;
    }
    const parts = splitCallDurationParts(durationSec);
    const durationText = parts.minutes > 0
      ? this.getString('chat_call_event_duration_minutes_seconds_format', parts.minutes, parts.seconds)
      : this.getString('chat_call_event_duration_seconds_format', parts.seconds);
    return this.getString('chat_call_event_time_with_duration_format', time, durationText);
  }

  private isMediaMessage(): boolean {
    const kind = this.messageKind();
    return kind === 'photo'
      || kind === 'animation'
      || kind === 'video'
      || kind === 'sticker'
      || kind === 'animatedEmoji';
  }

  private isVoiceNoteMessage(): boolean {
    return this.messageKind() === 'voiceNote';
  }

  private isVideoNoteMessage(): boolean {
    return this.messageKind() === 'videoNote';
  }

  private isStickerMessage(): boolean {
    const kind = this.messageKind();
    return kind === 'sticker' || kind === 'animatedEmoji';
  }

  private isAnimatedEmojiMessage(): boolean {
    return this.messageKind() === 'animatedEmoji';
  }

  /**
   * Checks whether current message kind can be rendered as TGS/Lottie.
   *
   * @returns True for sticker-like TGS kinds.
   */
  private isTgsMessageKind(): boolean {
    const kind = this.messageKind();
    return kind === 'animatedEmoji' || kind === 'sticker';
  }

  private isTgsMimeType(): boolean {
    if (typeof this.message.mediaMimeType !== 'string') {
      return false;
    }
    return this.message.mediaMimeType.toLowerCase() === 'application/x-tgsticker';
  }

  private currentTgsPath(): string {
    if (!this.isTgsMessageKind() || !this.isTgsMimeType()) {
      return '';
    }
    if (typeof this.message.mediaLocalPath !== 'string') {
      return '';
    }
    const trimmedPath = this.message.mediaLocalPath.trim();
    if (trimmedPath.length === 0) {
      return '';
    }
    if (!trimmedPath.toLowerCase().endsWith('.tgs')) {
      return '';
    }
    return trimmedPath;
  }

  /**
   * Computes whether TGS canvas should be rendered for current item.
   *
   * @returns True when message has eligible TGS source and slot is available.
   */
  private shouldRenderTgsLottie(): boolean {
    const tgsPath = this.currentTgsPath();
    if (tgsPath.length === 0) {
      return false;
    }
    if (this.tgsSlotBlocked) {
      return false;
    }
    if (!this.tgsLottieFallbackMode) {
      return true;
    }
    return this.tgsAnimationPath !== tgsPath;
  }

  private tgsLottieAnimationNameFor(path: string): string {
    return `tgs-media-${this.message.id}-${path.length}`;
  }

  /**
   * Builds stable slot identifier for active animation limiter.
   *
   * @param path Current TGS file path.
   * @returns Unique slot key for message/path pair.
   */
  private tgsSlotId(path: string): string {
    return `${this.message.id}:${path}`;
  }

  /**
   * Releases currently held global animation slot.
   *
   * @returns Nothing.
   */
  private releaseTgsSlot(): void {
    if (this.tgsSlotKey.length === 0) {
      return;
    }
    tgsActiveAnimationSlots.delete(this.tgsSlotKey);
    this.tgsSlotKey = '';
  }

  /**
   * Attempts to acquire one global active-animation slot for this list item.
   *
   * @param path Current TGS path.
   * @returns True when slot is acquired or already held by this item.
   */
  private tryAcquireTgsSlot(path: string): boolean {
    const nextSlotId = this.tgsSlotId(path);
    if (this.tgsSlotKey === nextSlotId && tgsActiveAnimationSlots.has(nextSlotId)) {
      return true;
    }

    if (this.tgsSlotKey.length > 0 && this.tgsSlotKey !== nextSlotId) {
      tgsActiveAnimationSlots.delete(this.tgsSlotKey);
      this.tgsSlotKey = '';
    }

    if (tgsActiveAnimationSlots.size >= TGS_ACTIVE_ANIMATION_LIMIT) {
      return false;
    }

    tgsActiveAnimationSlots.add(nextSlotId);
    this.tgsSlotKey = nextSlotId;
    return true;
  }

  /**
   * Stops and disposes inline TGS animation for this list item.
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
    this.releaseTgsSlot();
  }

  /**
   * Ensures inline TGS animation exists and is playing when item is visible.
   *
   * @returns Nothing.
   */
  private ensureTgsLottieAnimation(): void {
    const tgsPath = this.currentTgsPath();
    if (tgsPath.length === 0) {
      this.destroyTgsLottieAnimation();
      this.tgsAnimationPath = '';
      this.tgsLoadingInProgress = false;
      this.tgsLottieFallbackMode = false;
      this.tgsSlotBlocked = false;
      return;
    }

    if (this.tgsAnimationPath !== tgsPath) {
      this.tgsLottieFallbackMode = false;
    }

    if (!this.tryAcquireTgsSlot(tgsPath)) {
      this.tgsSlotBlocked = true;
      return;
    }
    this.tgsSlotBlocked = false;

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
   * Loads parsed TGS payload and initializes Lottie canvas renderer.
   *
   * @param tgsPath Absolute local path to `.tgs` file.
   * @returns Promise that resolves when load attempt finishes.
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
      this.releaseTgsSlot();
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
        'contentMode': 'Contain',
        'frameRate': 30,
        'autoSkip': true,
        'animationData': loadResult.animationData
      });
      this.tgsAnimationItem.addEventListener('DOMLoaded', () => {
        if (!this.tgsAnimationItem) {
          return;
        }
        this.tgsAnimationItem.play();
      });
      this.tgsLottieFallbackMode = false;
    } catch (error) {
      this.destroyTgsLottieAnimation();
      // Drop cached payload for this file to force fresh decode on next attempt.
      clearTgsLottieCache(tgsPath);
      this.tgsLottieFallbackMode = true;
      this.releaseTgsSlot();
      hilog.error(DOMAIN, TAG, 'TGS Lottie render failed id=%{public}s err=%{public}s', this.message.id, String(error));
    }

    this.tgsLoadingInProgress = false;
  }

  private canRenderMainMediaAsVideo(): boolean {
    return resolveInlineVideoPath(this.message, this.isAnimatedEmojiMessage()).length > 0;
  }

  private mediaVideoPath(): string {
    return resolveInlineVideoPath(this.message, this.isAnimatedEmojiMessage());
  }

  private canRenderMainMediaAsImage(): boolean {
    if (typeof this.message.mediaLocalPath !== 'string' || this.message.mediaLocalPath.length === 0) {
      return false;
    }
    if (this.canRenderMainMediaAsVideo()) {
      return false;
    }

    if (this.messageKind() === 'photo') {
      return true;
    }
    if (this.messageKind() === 'sticker' || this.isAnimatedEmojiMessage()) {
      if (typeof this.message.mediaMimeType === 'string' && this.message.mediaMimeType.length > 0) {
        const mimeType = this.message.mediaMimeType.toLowerCase();
        if (mimeType.startsWith('image/')) {
          return true;
        }
        return false;
      }
      return isRenderableImagePath(this.message.mediaLocalPath);
    }

    if (this.messageKind() !== 'animation') {
      return isRenderableImagePath(this.message.mediaLocalPath);
    }

    if (typeof this.message.mediaMimeType === 'string' && this.message.mediaMimeType.length > 0) {
      const mimeType = this.message.mediaMimeType.toLowerCase();
      if (mimeType === 'image/gif' || mimeType.startsWith('image/')) {
        return true;
      }
      return false;
    }

    return isRenderableImagePath(this.message.mediaLocalPath);
  }

  private mediaPath(): string {
    if (this.canRenderMainMediaAsImage()) {
      if (typeof this.message.mediaLocalPath === 'string') {
        return this.message.mediaLocalPath;
      }
    }

    if (typeof this.message.mediaThumbPath === 'string' && this.message.mediaThumbPath.length > 0) {
      return this.message.mediaThumbPath;
    }

    if (typeof this.message.mediaLocalPath === 'string' && this.message.mediaLocalPath.length > 0) {
      if (isRenderableImagePath(this.message.mediaLocalPath)) {
        return this.message.mediaLocalPath;
      }
    }

    return '';
  }

  private bubbleWidth(): string {
    if (this.isStickerMessage()) {
      return this.message.isOutgoing ? '62%' : '64%';
    }
    if (this.isVideoNoteMessage()) {
      return this.message.isOutgoing ? '74%' : '76%';
    }
    if (this.isVoiceNoteMessage()) {
      return this.message.isOutgoing ? '76%' : '78%';
    }
    if (this.isMediaMessage()) {
      return this.message.isOutgoing ? '74%' : '76%';
    }
    return this.message.isOutgoing ? '71%' : '73%';
  }

  private shouldRenderCaption(): boolean {
    return this.captionText().length > 0;
  }

  private captionText(): string {
    if (typeof this.message.caption !== 'string') {
      return '';
    }
    const trimmedCaption = this.message.caption.trim();
    if (trimmedCaption.length === 0) {
      return '';
    }
    return this.message.caption;
  }

  private mediaPreviewHeight(): number {
    if (this.isStickerMessage()) {
      const stickerDefaultHeight = 74;
      const stickerWidth = this.message.mediaWidth;
      const stickerHeight = this.message.mediaHeight;
      if (typeof stickerWidth !== 'number' || typeof stickerHeight !== 'number' || stickerWidth <= 0 || stickerHeight <= 0) {
        return stickerDefaultHeight;
      }

      const baseStickerWidth = 82;
      const estimatedStickerHeight = Math.round((baseStickerWidth * stickerHeight) / stickerWidth);
      if (estimatedStickerHeight < 56) {
        return 56;
      }
      if (estimatedStickerHeight > 92) {
        return 92;
      }
      return estimatedStickerHeight;
    }

    const defaultHeight = 78;
    const maxHeight = 100;
    const rawWidth = this.message.mediaWidth;
    const rawHeight = this.message.mediaHeight;
    if (typeof rawWidth !== 'number' || typeof rawHeight !== 'number' || rawWidth <= 0 || rawHeight <= 0) {
      return defaultHeight;
    }

    const baseWidth = 104;
    const estimatedHeight = Math.round((baseWidth * rawHeight) / rawWidth);
    if (estimatedHeight < 44) {
      return 44;
    }
    if (estimatedHeight > maxHeight) {
      return maxHeight;
    }
    return estimatedHeight;
  }

  private mediaPlaceholderText(): string {
    if (this.isAnimatedEmojiMessage()) {
      return this.getString('chat_message_loading_emoji');
    }
    if (this.messageKind() === 'animation') {
      return this.getString('chat_message_loading_gif');
    }
    if (this.messageKind() === 'video') {
      return this.getString('chat_message_loading_video');
    }
    if (this.messageKind() === 'sticker') {
      return this.getString('chat_message_loading_sticker');
    }
    return this.getString('chat_message_loading_image');
  }

  private mediaVideoBadgeText(): string {
    if (this.isAnimatedEmojiMessage()) {
      return this.getString('chat_message_badge_emoji');
    }
    if (this.messageKind() === 'animation') {
      return this.getString('chat_message_badge_gif');
    }
    if (this.messageKind() === 'sticker') {
      return this.getString('chat_message_badge_sticker');
    }
    return this.getString('chat_message_badge_video');
  }

  private currentMediaRenderMode(): string {
    if (this.shouldRenderTgsLottie()) {
      return 'tgs-lottie';
    }
    if (this.mediaVideoPath().length > 0) {
      return 'video-main';
    }
    if (this.canRenderMainMediaAsImage()) {
      return 'image-main';
    }
    if (typeof this.message.mediaThumbPath === 'string' && this.message.mediaThumbPath.length > 0) {
      return 'image-thumb';
    }
    if (typeof this.message.mediaLocalPath === 'string' && this.message.mediaLocalPath.length > 0
      && isRenderableImagePath(this.message.mediaLocalPath)) {
      return 'image-main-fallback';
    }
    return 'placeholder';
  }

  private shouldShowMediaTypeBadge(): boolean {
    return !this.isAnimatedEmojiMessage();
  }

  private shouldLoopInlineVideo(): boolean {
    return this.isAnimatedEmojiMessage();
  }

  /**
   * Resets per-message inline video preview flags when list item gets rebound.
   *
   * @returns Nothing.
   */
  private syncInlineVideoPreviewState(): void {
    const nextMessageId = typeof this.message.id === 'string' ? this.message.id : '';
    if (this.inlineVideoPreviewMessageId === nextMessageId) {
      return;
    }
    this.inlineVideoPreviewMessageId = nextMessageId;
    this.inlineVideoPreviewHiddenAfterFinish = false;
  }

  /**
   * Resolves still preview path for inline video tile.
   *
   * @returns Local image path used as idle preview, if available.
   */
  private videoPreviewPath(): string {
    return resolveInlineVideoPreviewPath(this.message, false);
  }

  /**
   * Controls visibility of play overlay for inline video preview.
   *
   * @returns True when video is idle and overlay should be shown.
   */
  private shouldShowVideoPlayOverlay(): boolean {
    return !this.inlineVideoPlaying;
  }

  /**
   * Controls visibility of idle video thumbnail layer.
   *
   * @returns True when thumbnail should remain visible before playback completes.
   */
  private shouldShowVideoThumbnailPreview(): boolean {
    if (this.inlineVideoPreviewHiddenAfterFinish) {
      return false;
    }
    if (!this.shouldShowVideoPlayOverlay()) {
      return false;
    }
    return this.videoPreviewPath().length > 0;
  }

  /**
   * Controls visibility of play overlay for GIF rendered as image.
   *
   * @returns True when GIF is idle and overlay should be shown.
   */
  private shouldShowGifPlayOverlay(): boolean {
    return !this.inlineGifPlaying;
  }

  /**
   * Returns whether playback timer should be visible for current media tile.
   *
   * @returns True for inline video/gif playback preview.
   */
  private shouldShowPlaybackTimer(): boolean {
    return this.mediaVideoPath().length > 0 && this.shouldShowMediaTypeBadge();
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

  /**
   * Stops active playback timer interval.
   *
   * @param resetElapsed When true, elapsed value is reset to zero.
   * @returns Nothing.
   */
  private stopInlinePlaybackTimer(resetElapsed: boolean): void {
    if (this.inlinePlaybackTimerHandle >= 0) {
      clearInterval(this.inlinePlaybackTimerHandle);
      this.inlinePlaybackTimerHandle = -1;
    }
    if (resetElapsed) {
      this.inlinePlaybackElapsedSec = 0;
    }
  }

  /**
   * Starts playback timer ticking once per second.
   *
   * @returns Nothing.
   */
  private startInlinePlaybackTimer(): void {
    this.stopInlinePlaybackTimer(true);
    this.inlinePlaybackTimerHandle = setInterval(() => {
      this.inlinePlaybackElapsedSec = this.inlinePlaybackElapsedSec + 1;
    }, 1000);
  }

  private stopInlineVideoPlayback(): void {
    this.stopInlinePlaybackTimer(true);
    this.inlineVideoPlaying = false;
    this.inlineGifPlaying = false;
    this.inlineVideoController.stop();
  }

  private openMediaFromInlinePreview(): void {
    this.stopInlineVideoPlayback();
    this.onMediaClick(this.message);
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
    .align(Alignment.Center)
  }

  @Builder
  private buildMessageBody(): void {
    if (this.isVoiceNoteMessage()) {
      Column({ space: 6 }) {
        VoiceNoteMessageBubble({
          message: this.message,
          voiceNotePlayback: this.voiceNotePlayback,
          onVoiceNoteToggle: this.onVoiceNoteToggle
        })

        this.buildMessageMetaRow()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (this.isVideoNoteMessage()) {
      Column({ space: 6 }) {
        Row() {
          VideoNoteMessageBubble({
            message: this.message,
            onMediaClick: this.onMediaClick
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)

        if (this.shouldRenderCaption()) {
          Text(this.captionText())
            .fontSize(12)
            .width('100%')
            .fontColor($r('app.color.text_primary'))
            .maxLines(4)
        }

        this.buildMessageMetaRow()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (this.isMediaMessage()) {
      Column({ space: 6 }) {
        if (this.shouldRenderTgsLottie()) {
          Canvas(this.tgsCanvasRenderingContext)
            .width('100%')
            .height(this.mediaPreviewHeight())
            .backgroundColor($r('app.color.surface_transparent'))
            .borderRadius(11)
            .onReady(() => {
              this.ensureTgsLottieAnimation();
            })
            .onAppear(() => {
              this.ensureTgsLottieAnimation();
            })
            .onClick(() => {
              this.ensureTgsLottieAnimation();
            })
        } else if (this.mediaVideoPath().length > 0) {
          RelativeContainer() {
            Video({
              src: this.avatarSource(this.mediaVideoPath()),
              controller: this.inlineVideoController
            })
              .width('100%')
              .height(this.mediaPreviewHeight())
              .controls(false)
              .autoPlay(false)
              .objectFit(ImageFit.Contain)
              .borderRadius(11)
              .onAppear(() => {
                this.syncInlineVideoPreviewState();
                this.inlineVideoPlaying = false;
                this.stopInlinePlaybackTimer(true);
              })
              .onFinish(() => {
                if (this.shouldLoopInlineVideo()) {
                  this.inlineVideoPlaying = true;
                  this.inlineVideoController.start();
                  return;
                }
                this.inlineVideoPlaying = false;
                this.inlineVideoPreviewHiddenAfterFinish = true;
                this.stopInlinePlaybackTimer(true);
              })
              .onClick(() => {
                this.openMediaFromInlinePreview();
              })
              .alignRules({
                top: { anchor: '__container__', align: VerticalAlign.Top },
                left: { anchor: '__container__', align: HorizontalAlign.Start }
              })

            if (this.shouldShowVideoPlayOverlay()) {
              if (this.videoPreviewPath().length > 0) {
                Image(this.avatarSource(this.videoPreviewPath()))
                  .width('100%')
                  .height(this.mediaPreviewHeight())
                  .objectFit(ImageFit.Contain)
                  .visibility(this.shouldShowVideoThumbnailPreview() ? Visibility.Visible : Visibility.Hidden)
                  .onClick(() => {
                    this.openMediaFromInlinePreview();
                  })
                  .alignRules({
                    top: { anchor: '__container__', align: VerticalAlign.Top },
                    left: { anchor: '__container__', align: HorizontalAlign.Start }
                  })
              }

              Column() {
                this.buildPlayOverlay()
              }
              .width(40)
              .height(40)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                this.inlineVideoPlaying = true;
                if (this.shouldShowPlaybackTimer()) {
                  this.startInlinePlaybackTimer();
                }
                this.inlineVideoController.start();
              })
              .alignRules({
                center: { anchor: '__container__', align: VerticalAlign.Center },
                middle: { anchor: '__container__', align: HorizontalAlign.Center }
              })
            }

            if (this.shouldShowPlaybackTimer()) {
              MediaPlaybackTimerBadge({
                elapsedSec: this.timerElapsedOrDurationSec(),
                mediaDurationSec: typeof this.message.mediaDurationSec === 'number' ? this.message.mediaDurationSec : 0
              })
              .alignRules({
                top: { anchor: '__container__', align: VerticalAlign.Top },
                left: { anchor: '__container__', align: HorizontalAlign.Start }
              })
              .margin({ top: 6, left: 6 })
            }

            if (this.shouldShowMediaTypeBadge()) {
              Text(this.mediaVideoBadgeText())
                .fontSize(8)
                .fontColor($r('app.color.text_primary'))
                .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                .margin({ top: 6, right: 6 })
                .backgroundColor($r('app.color.surface_media_badge_background'))
                .borderRadius(8)
                .alignRules({
                  top: { anchor: '__container__', align: VerticalAlign.Top },
                  right: { anchor: '__container__', align: HorizontalAlign.End }
                })
            }
          }
          .width('100%')
          .height(this.mediaPreviewHeight())
        } else if (this.mediaPath().length > 0) {
          Stack({ alignContent: Alignment.TopEnd }) {
            Image(this.avatarSource(this.mediaPath()))
              .width('100%')
              .height(this.mediaPreviewHeight())
              .objectFit(ImageFit.Contain)
              .borderRadius(11)
              .onAppear(() => {
                this.inlineGifPlaying = false;
                if (this.currentTgsPath().length > 0 && this.tgsSlotBlocked) {
                  this.tgsSlotBlocked = false;
                  this.ensureTgsLottieAnimation();
                }
              })
              .onClick(() => {
                this.openMediaFromInlinePreview();
                if (this.currentTgsPath().length > 0) {
                  this.tgsSlotBlocked = false;
                  this.ensureTgsLottieAnimation();
                }
              })

            if (this.messageKind() === 'animation' && this.canRenderMainMediaAsImage()) {
              if (this.shouldShowGifPlayOverlay()) {
                Column() {
                  this.buildPlayOverlay()
                }
                .width('100%')
                .height(this.mediaPreviewHeight())
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .onClick(() => {
                  this.inlineGifPlaying = true;
                })
              }
            }

            if (this.messageKind() === 'animation' && this.canRenderMainMediaAsImage()) {
              Text(this.getString('chat_message_badge_gif'))
                .fontSize(8)
                .fontColor($r('app.color.text_primary'))
                .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                .margin({ top: 6, right: 6 })
                .backgroundColor($r('app.color.surface_media_badge_background'))
                .borderRadius(8)
            }
          }
          .width('100%')
        } else {
          Column({ space: 4 }) {
            Text(this.mediaPlaceholderText())
              .fontSize(10)
              .fontColor($r('app.color.text_media_placeholder'))
              .textAlign(TextAlign.Center)
              .maxLines(1)

            if ((this.messageKind() === 'animation' || this.messageKind() === 'video' || this.isAnimatedEmojiMessage())
              && this.shouldShowMediaTypeBadge()) {
              Text(this.mediaVideoBadgeText())
                .fontSize(9)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
            }
          }
          .width('100%')
          .height(this.mediaPreviewHeight())
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.surface_media_placeholder_background'))
          .borderRadius(11)
        }

        if (this.shouldRenderCaption()) {
          Text(this.captionText())
            .fontSize(12)
            .width('100%')
            .fontColor($r('app.color.text_primary'))
            .maxLines(4)
        }

        this.buildMessageMetaRow()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
      Column({ space: 4 }) {
        Text(this.message.text)
          .fontSize(13)
          .width('100%')
          .fontColor($r('app.color.text_primary'))
          .maxLines(6)
        this.buildMessageMetaRow()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private buildServiceEventRow(): void {
    Column({ space: 6 }) {
      if (this.hasServiceEventPreview()) {
        Image(this.avatarSource(this.mediaPath()))
          .width(84)
          .height(this.serviceEventPreviewHeight())
          .objectFit(ImageFit.Cover)
          .borderRadius(12)
      }

      Text(this.serviceEventText())
        .fontSize(8)
        .fontStyle(FontStyle.Italic)
        .fontColor($r('app.color.text_service_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor($r('app.color.surface_chat_service_event_background'))
        .borderRadius(16)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 18, right: 18, top: 10, bottom: 10 })
  }

  /**
   * Renders a `messageCall` history entry as a direction-aware bubble
   * (Task 4.7). Mirrors the regular message-bubble container styling —
   * direction-driven background / gradient / shadow — but lays out a
   * fixed 2-row content (title + arrow / time / duration) with a phone
   * icon on the inside trailing edge of the bubble.
   */
  @Builder
  private buildCallEventBubble(): void {
    Row({ space: 8 }) {
      if (!this.message.isOutgoing) {
        this.buildSenderAvatar()
      }

      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.callEventTitleResource())
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 4 }) {
            Image(this.callEventArrowResource())
              .width(12)
              .height(12)
              .objectFit(ImageFit.Contain)

            Text(this.callEventTimeDurationText())
              .fontSize(10)
              .fontColor(this.timeTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Image(this.callEventPhoneIconResource())
          .width(18)
          .height(18)
          .objectFit(ImageFit.Contain)
      }
      .width(this.bubbleWidth())
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .borderRadius(14)
      .backgroundColor(this.bubbleBackgroundColor())
      .linearGradient({
        direction: GradientDirection.LeftTop,
        colors: [[this.bubbleGradientStartColor(), 0.0], [this.bubbleGradientEndColor(), 1.0]]
      })
      .opacity(0.80)
      .shadow({
        color: $r('app.color.chat_message_shadow'),
        radius: 10,
        offsetX: 0,
        offsetY: 3
      })
      .alignItems(VerticalAlign.Center)

      if (this.message.isOutgoing) {
        this.buildSenderAvatar()
      }
    }
    .width('96%')
    .justifyContent(this.message.isOutgoing ? FlexAlign.End : FlexAlign.Start)
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  aboutToDisappear(): void {
    this.stopInlineVideoPlayback();
    this.destroyTgsLottieAnimation();
  }

  /**
   * Builds the final message row for the chat timeline.
   *
   * @returns Nothing.
   */
  build() {
    ArcListItem() {
      if (this.isServiceEventMessage()) {
        this.buildServiceEventRow()
      } else if (this.isCallEventMessage()) {
        this.buildCallEventBubble()
      } else {
        Row({ space: 8 }) {
          if (!this.message.isOutgoing) {
            this.buildSenderAvatar()
          }

          Column() {
            this.buildMessageBody()
          }
          .width(this.bubbleWidth())
          .padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .borderRadius(14)
          .backgroundColor(this.bubbleBackgroundColor())
          .linearGradient({
            direction: GradientDirection.LeftTop,
            colors: [[this.bubbleGradientStartColor(), 0.0], [this.bubbleGradientEndColor(), 1.0]]
          })
          .opacity(0.80)
          .shadow({
            color: $r('app.color.chat_message_shadow'),
            radius: 10,
            offsetX: 0,
            offsetY: 3
          })
          .alignItems(HorizontalAlign.Start)

          if (this.message.isOutgoing) {
            this.buildSenderAvatar()
          }
        }
        .width('96%')
        .justifyContent(this.message.isOutgoing ? FlexAlign.End : FlexAlign.Start)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      }
    }
  }
}
