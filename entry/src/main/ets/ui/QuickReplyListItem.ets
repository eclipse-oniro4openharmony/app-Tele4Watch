import { ArcListItem } from '@kit.ArkUI';

/**
 * Compact quick-reply action item for the wearable picker list.
 */
@Component
export struct QuickReplyListItem {
  /** Reply text rendered in the center of the button. */
  @Prop label: ResourceStr = '';

  /** Whether the reply can be selected. */
  @Prop isEnabled: boolean = true;

  /** Callback invoked after tapping the reply button. */
  onItemClick: () => void = (): void => {};

  /**
   * Renders one fixed-height quick-reply button row.
   */
  build() {
    ArcListItem() {
      Column() {
        Button() {
          Text(this.label)
            .width('100%')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(38)
        .enabled(this.isEnabled)
        .linearGradient({
          direction: GradientDirection.RightBottom,
          colors: [
            [$r('app.color.surface_list_card_gradient_start'), 0.0],
            [$r('app.color.surface_list_card_gradient_end'), 1.0]
          ]
        })
        .opacity(this.isEnabled ? 0.85 : 0.58)
        .onClick((): void => {
          this.onItemClick();
        })
      }
      .width('90%')
      .padding({ left: 6, right: 6, top: 4, bottom: 4 })
      .margin({ top: 2, bottom: 2 })
      .backgroundColor($r('app.color.surface_action_list_item_backdrop'))
      .borderRadius(24)
    }
  }
}
