import resourceManager from '@ohos.resourceManager';
import { ArcListItem } from '@kit.ArkUI';
import { avatarFallbackGradientEndColor, avatarFallbackGradientStartColor } from './AvatarFallbackPalette';
import { UserAvatar } from './UserAvatar';
import { textSignature } from '../utils/TextSignature';
import { resolveString } from '../utils/ResourceTextResolver';

/**
 * Reusable profile summary card used on wearable profile page.
 */
@Component
export struct ProfileCard {
  @Prop userId: string = '';
  @Prop fullName: string = '';
  @Prop username: string = '';
  @Prop phoneNumber: string = '';
  @Prop avatarPath: string = '';
  @Prop avatarAnimationPath: string = '';
  private cachedAvatarPaletteKey: string = '';
  private cachedAvatarPaletteIndex: number = 0;

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

  private placeholderValue(): string {
    return this.getString('common_value_placeholder');
  }

  private hasDisplayValue(value: string): boolean {
    const trimmed = value.trim();
    if (trimmed.length === 0) {
      return false;
    }
    return trimmed !== this.placeholderValue();
  }

  private resolvedFieldValue(value: string): string {
    if (this.hasDisplayValue(value)) {
      return value;
    }
    return this.placeholderValue();
  }

  /**
   * Resolves fallback text used when avatar image is unavailable.
   *
   * @returns Full name, username without prefix, or `?`.
   */
  private avatarFallbackText(): string {
    const name = this.fullName.trim();
    if (name.length > 0 && name !== this.placeholderValue()) {
      return name;
    }
    const handle = this.username.replace('@', '').trim();
    if (handle.length > 0 && handle !== this.placeholderValue()) {
      return handle;
    }
    return this.getString('common_unknown_label');
  }

  /**
   * Formats phone label for UI field.
   *
   * @returns `-` when phone is unavailable, otherwise prefixed with `+`.
   */
  private phoneLabel(): string {
    if (!this.hasDisplayValue(this.phoneNumber)) {
      return this.placeholderValue();
    }
    return `+${this.phoneNumber}`;
  }

  /**
   * Returns gradient start color aligned with chat-list card style.
   *
   * @returns RGBA color used for left-top gradient stop.
   */
  private cardGradientStartColor(): ResourceColor {
    return $r('app.color.surface_list_card_gradient_start');
  }

  /**
   * Returns gradient end color aligned with chat-list card style.
   *
   * @returns RGBA color used for right-bottom gradient stop.
   */
  private cardGradientEndColor(): ResourceColor {
    return $r('app.color.surface_list_card_gradient_end');
  }

  /**
   * Resolves deterministic palette index for profile fallback avatar.
   *
   * @returns Palette index in range `0..7`.
   */
  private avatarPaletteIndex(): number {
    const cacheKey = `${this.userId}|${this.fullName}|${this.username}`;
    if (this.cachedAvatarPaletteKey === cacheKey) {
      return this.cachedAvatarPaletteIndex;
    }

    let resolvedPaletteIndex = 0;
    const normalizedUserId = this.userId.trim();
    if (normalizedUserId.length > 0 && normalizedUserId !== this.placeholderValue()) {
      resolvedPaletteIndex = textSignature(normalizedUserId) % 8;
    } else {
      const normalizedName = this.fullName.trim();
      if (normalizedName.length > 0 && normalizedName !== this.placeholderValue()) {
        resolvedPaletteIndex = textSignature(normalizedName) % 8;
      } else {
        const normalizedUsername = this.username.trim();
        if (normalizedUsername.length > 0 && normalizedUsername !== this.placeholderValue()) {
          resolvedPaletteIndex = textSignature(normalizedUsername) % 8;
        }
      }
    }

    this.cachedAvatarPaletteKey = cacheKey;
    this.cachedAvatarPaletteIndex = resolvedPaletteIndex;
    return resolvedPaletteIndex;
  }

  /**
   * Renders profile card visual content.
   */
  build() {
    ArcListItem() {
      Row({ space: 0 }) {
        Column() {
          UserAvatar({
            imagePath: this.avatarPath,
            animationPath: this.avatarAnimationPath,
            animateAvatar: true,
            fallbackText: this.avatarFallbackText(),
            avatarDiameter: 64,
            fallbackInitialFontSize: 18,
            fallbackMaxInitials: 2,
            fallbackBackgroundColor: $r('app.color.contact_avatar_fallback_background'),
            fallbackGradientStartColor: avatarFallbackGradientStartColor(this.avatarPaletteIndex()),
            fallbackGradientEndColor: avatarFallbackGradientEndColor(this.avatarPaletteIndex()),
            fallbackUseGradient: true
          })
        }
        .padding({ left: 10, right: 14 })
        .alignItems(HorizontalAlign.Start)

        Column({ space: 5 }) {
          Column({ space: 2 }) {
            Text($r('app.string.profile_field_name'))
              .fontSize(7)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Start)
              .width('100%')
            Text(this.resolvedFieldValue(this.fullName))
              .fontSize(9)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Start)
              .width('100%')
              .maxLines(3)
          }
          .alignItems(HorizontalAlign.Start)

          Column({ space: 2 }) {
            Text($r('app.string.profile_field_username'))
              .fontSize(7)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Start)
              .width('100%')
            Text(this.resolvedFieldValue(this.username))
              .fontSize(9)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Start)
              .width('100%')
              .maxLines(2)
          }
          .alignItems(HorizontalAlign.Start)

          Column({ space: 2 }) {
            Text($r('app.string.profile_field_phone'))
              .fontSize(7)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Start)
              .width('100%')
            Text(this.phoneLabel())
              .fontSize(9)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Start)
              .width('100%')
              .maxLines(2)
          }
          .alignItems(HorizontalAlign.Start)

          Column({ space: 2 }) {
            Text($r('app.string.profile_field_id'))
              .fontSize(7)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Start)
              .width('100%')
            Text(this.resolvedFieldValue(this.userId))
              .fontSize(8)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Start)
              .width('100%')
              .maxLines(2)
          }
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .alignItems(VerticalAlign.Center)
      .width('85%')
      .padding({
        left: 10,
        right: 10,
        top: 10,
        bottom: 10
      })
      .opacity(0.85)
      .linearGradient({
        direction: GradientDirection.LeftTop,
        colors: [[this.cardGradientStartColor(), 0.0], [this.cardGradientEndColor(), 1.0]]
      })
      .shadow({
        color: $r('app.color.surface_card_shadow'),
        radius: 10,
        offsetX: 0,
        offsetY: 3
      })
      .borderRadius(32)
    }
  }
}
