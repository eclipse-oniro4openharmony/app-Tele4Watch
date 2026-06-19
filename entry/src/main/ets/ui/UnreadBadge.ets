import { formatUnreadBadgeCount } from '../models/chat/UnreadBadgeFormatter';

@Component
export struct UnreadBadge {
  count: number = 0;
  isMuted: boolean = false;

  private badgeBackgroundColor(): ResourceColor {
    if (this.isMuted) {
      return $r('app.color.surface_unread_badge_background_muted');
    }
    return $r('app.color.surface_unread_badge_background');
  }

  private badgeTextColor(): ResourceColor {
    if (this.isMuted) {
      return $r('app.color.text_unread_badge_muted');
    }
    return $r('app.color.text_unread_badge');
  }

  build() {
    Text(formatUnreadBadgeCount(this.count))
      .fontSize(9)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.badgeTextColor())
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .backgroundColor(this.badgeBackgroundColor())
      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
      .borderRadius(8)
      .constraintSize({ minWidth: 18, minHeight: 16 })
  }
}
