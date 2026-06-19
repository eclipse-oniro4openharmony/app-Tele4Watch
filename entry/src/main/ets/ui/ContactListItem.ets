import { ArcListItem } from '@kit.ArkUI';
import { avatarFallbackGradientEndColor, avatarFallbackGradientStartColor } from './AvatarFallbackPalette';
import { UserAvatar } from './UserAvatar';

@Component
export struct ContactListItem {
  title: string = '';
  subtitle: string = '';
  subtitleColor: ResourceColor = $r('app.color.text_secondary');
  avatarPath: string = '';
  avatarPaletteIndex: number = 0;
  onItemClick: () => void = (): void => {};

  private cardGradientStartColor(): ResourceColor {
    return $r('app.color.surface_list_card_gradient_start');
  }

  private cardGradientEndColor(): ResourceColor {
    return $r('app.color.surface_list_card_gradient_end');
  }

  build() {
    ArcListItem() {
      Row({ space: 10 }) {
        UserAvatar({
          imagePath: this.avatarPath,
          fallbackText: this.title,
          avatarDiameter: 38,
          fallbackInitialFontSize: 14,
          fallbackMaxInitials: 2,
          fallbackBackgroundColor: $r('app.color.contact_avatar_fallback_background'),
          fallbackGradientStartColor: avatarFallbackGradientStartColor(this.avatarPaletteIndex),
          fallbackGradientEndColor: avatarFallbackGradientEndColor(this.avatarPaletteIndex),
          fallbackUseGradient: true
        })

        Column({ space: 2 }) {
          Text(this.title)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Start)

          if (this.subtitle.length > 0) {
            Text(this.subtitle)
              .fontSize(10)
              .fontColor(this.subtitleColor)
              .maxLines(1)
              .textAlign(TextAlign.Start)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('90%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .margin({ top: 4, bottom: 4 })
      .linearGradient({
        direction: GradientDirection.LeftTop,
        colors: [[this.cardGradientStartColor(), 0.0], [this.cardGradientEndColor(), 1.0]]
      })
      .opacity(0.85)
      .shadow({
        color: $r('app.color.surface_card_shadow'),
        radius: 10,
        offsetX: 0,
        offsetY: 3
      })
      .borderRadius(32)
    }
    .onClick((): void => {
      this.onItemClick();
    })
  }
}
