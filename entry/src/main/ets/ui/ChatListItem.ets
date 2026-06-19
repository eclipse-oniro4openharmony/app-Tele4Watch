import resourceManager from '@ohos.resourceManager';
import { ArcListItem } from '@kit.ArkUI';
import { avatarFallbackGradientEndColor, avatarFallbackGradientStartColor } from './AvatarFallbackPalette';
import { UnreadBadge } from './UnreadBadge';
import { UserAvatar } from './UserAvatar';
import { resolveString } from '../utils/ResourceTextResolver';
import { normalizeUnreadBadgeCount } from '../models/chat/UnreadBadgeFormatter';
import { TdCallEventStatus, TdChatKind, TdChatMessageKind } from '../services/td/TdPayloadTypes';
import { UiTextValue } from '../models/ui/UiTextValue';

@Component
export struct ChatListItem {
  title: string = '';
  lastMessageText: string = '';
  lastMessageTextValue?: UiTextValue;
  lastMessageKind?: TdChatMessageKind;
  lastMessageIsOutgoing: boolean = false;
  lastMessageCallEventStatus?: TdCallEventStatus;
  avatarPath: string = '';
  avatarPaletteIndex: number = 0;
  chatKind: TdChatKind = 'unknown';
  timeLabel: string = '';
  unreadCount: number = 0;
  isMuted: boolean = false;
  onAvatarClick: () => void = (): void => {};
  onItemClick: () => void = (): void => {};

  private cardGradientStartColor(): ResourceColor {
    if (this.chatKind === 'basicGroup' || this.chatKind === 'supergroup') {
      return $r('app.color.surface_group_list_card_gradient_start');
    }
    if (this.chatKind === 'channel') {
      return $r('app.color.surface_channel_list_card_gradient_start');
    }
    return $r('app.color.surface_list_card_gradient_start');
  }

  private cardGradientEndColor(): ResourceColor {
    if (this.chatKind === 'basicGroup' || this.chatKind === 'supergroup') {
      return $r('app.color.surface_group_list_card_gradient_end');
    }
    if (this.chatKind === 'channel') {
      return $r('app.color.surface_channel_list_card_gradient_end');
    }
    return $r('app.color.surface_list_card_gradient_end');
  }

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

  private resolvedTitle(): string {
    if (this.title.length > 0) {
      return this.title;
    }
    return this.getString('chat_list_item_title_missing');
  }

  private resolvedTimeLabel(): string {
    if (this.timeLabel.length > 0) {
      return this.timeLabel;
    }
    return this.getString('common_time_placeholder');
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

  private resolvedLastMessageText(): string {
    const resolvedText = this.resolveUiText(this.lastMessageTextValue);
    if (resolvedText.length > 0) {
      return resolvedText;
    }
    return this.lastMessageText;
  }

  private isMediaPlaceholderPreview(): boolean {
    const textValue = this.lastMessageTextValue;
    if (!textValue) {
      return false;
    }
    const resourceName = textValue.resourceName;
    return resourceName === 'chat_preview_outgoing_photo'
      || resourceName === 'chat_preview_incoming_photo'
      || resourceName === 'chat_preview_outgoing_animation'
      || resourceName === 'chat_preview_incoming_animation'
      || resourceName === 'chat_preview_outgoing_video'
      || resourceName === 'chat_preview_incoming_video'
      || resourceName === 'chat_preview_outgoing_video_note'
      || resourceName === 'chat_preview_incoming_video_note'
      || resourceName === 'chat_preview_outgoing_voice_note'
      || resourceName === 'chat_preview_incoming_voice_note'
      || resourceName === 'chat_preview_outgoing_sticker'
      || resourceName === 'chat_preview_incoming_sticker'
      || resourceName === 'chat_preview_outgoing_animated_emoji'
      || resourceName === 'chat_preview_incoming_animated_emoji';
  }

  private lastMessageColor(): ResourceColor {
    if (this.lastMessageKind === 'serviceEvent'
      || this.lastMessageKind === 'callEvent'
      || this.isMediaPlaceholderPreview()) {
      return $r('app.color.text_chat_list_service_preview');
    }
    return $r('app.color.text_secondary');
  }

  /**
   * Picks the chat-list call-event preview icon matching direction × status.
   * Reuses the Telegram-Android convention: phone glyph with a small arrow
   * in the top-right corner, tinted green for answered calls and red for
   * missed / declined / cancelled.
   */
  private callEventPreviewIconResource(): Resource {
    const isAnswered = this.lastMessageCallEventStatus === undefined
      || this.lastMessageCallEventStatus === 'answered';
    if (this.lastMessageIsOutgoing) {
      if (isAnswered) {
        return $r('app.media.chat_calls_outgoing_answered');
      }
      return $r('app.media.chat_calls_outgoing_cancelled');
    }
    if (isAnswered) {
      return $r('app.media.chat_calls_incoming_answered');
    }
    return $r('app.media.chat_calls_incoming_missed');
  }

  build() {
    ArcListItem() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Row({ space: 10 }) {
          Column() {
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
          }
          .onClick((): void => {
            this.onAvatarClick();
          })

          Column({ space: 2 }) {
            Text(this.resolvedTitle())
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Start)

            if (this.resolvedLastMessageText().length > 0) {
              Row({ space: 4 }) {
                if (this.lastMessageKind === 'callEvent') {
                  Image(this.callEventPreviewIconResource())
                    .width(12)
                    .height(12)
                    .objectFit(ImageFit.Contain)
                }
                Text(this.resolvedLastMessageText())
                  .fontSize(9)
                  .fontColor(this.lastMessageColor())
                  .layoutWeight(1)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Start)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('90%')
        .padding({ left: 10, right: 32, top: 8, bottom: 8 })
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

        Text(this.resolvedTimeLabel())
          .fontSize(7)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .padding({ left: 2, right: 2 })
          .margin({ top: 16, right: 16 })

        if (normalizeUnreadBadgeCount(this.unreadCount) > 0) {
          UnreadBadge({
            count: this.unreadCount,
            isMuted: this.isMuted
          })
            .margin({ right: 16, top: 32 })
            .align(Alignment.BottomEnd)
        }
      }
    }
    .onClick((): void => {
      this.onItemClick();
    })
  }
}
