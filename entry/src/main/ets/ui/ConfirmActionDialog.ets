import { GradientActionButton } from './GradientActionButton';

/**
 * Reusable confirmation dialog overlay with two action buttons.
 */
@Component
export struct ConfirmActionDialog {
  /** Dialog title text. */
  @Prop titleText: ResourceStr = '';

  /** Dialog message text. */
  @Prop messageText: ResourceStr = '';
  /** Cancel button label. */
  @Prop cancelLabel: ResourceStr = '';

  /** Confirm button label. */
  @Prop confirmLabel: ResourceStr = '';

  /** Cancel button background color. */
  @Prop cancelButtonColor: ResourceColor = $r('app.color.bg_action_enabled');

  /** Confirm button background color. */
  @Prop confirmButtonColor: ResourceColor = $r('app.color.surface_profile_logout_fill');

  /** Cancel button gradient start color. */
  @Prop cancelGradientStartColor: ResourceColor = $r('app.color.surface_action_gradient_start');

  /** Cancel button gradient middle color. */
  @Prop cancelGradientMiddleColor: ResourceColor = $r('app.color.surface_action_gradient_middle');

  /** Cancel button gradient end color. */
  @Prop cancelGradientEndColor: ResourceColor = $r('app.color.surface_action_gradient_end');

  /** Confirm button gradient start color. */
  @Prop confirmGradientStartColor: ResourceColor = $r('app.color.surface_profile_logout_gradient_start');

  /** Confirm button gradient middle color. */
  @Prop confirmGradientMiddleColor: ResourceColor = $r('app.color.surface_profile_logout_gradient_middle');

  /** Confirm button gradient end color. */
  @Prop confirmGradientEndColor: ResourceColor = $r('app.color.surface_profile_logout_gradient_end');

  /** Cancel action callback. */
  onCancelButtonClick: () => void = (): void => {};

  /** Confirm action callback. */
  onConfirmButtonClick: () => void = (): void => {};

  /**
   * Renders confirmation dialog overlay.
   */
  build() {
    Column() {
      Column({ space: 10 }) {
        Column({ space: 6 }) {
          Text(this.titleText)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.messageText)
            .fontSize(10)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .width('100%')
        }
        .width('100%')

        Row({ space: 12 }) {
          Column() {
            GradientActionButton({
              label: this.cancelLabel,
              buttonColor: this.cancelButtonColor,
              gradientStartColor: this.cancelGradientStartColor,
              gradientMiddleColor: this.cancelGradientMiddleColor,
              gradientEndColor: this.cancelGradientEndColor,
              buttonHeight: 36,
              onButtonClick: (): void => {
                this.onCancelButtonClick();
              }
            })
          }
          .layoutWeight(1)

          Column() {
            GradientActionButton({
              label: this.confirmLabel,
              buttonColor: this.confirmButtonColor,
              gradientStartColor: this.confirmGradientStartColor,
              gradientMiddleColor: this.confirmGradientMiddleColor,
              gradientEndColor: this.confirmGradientEndColor,
              buttonHeight: 36,
              onButtonClick: (): void => {
                this.onConfirmButtonClick();
              }
            })
          }
          .layoutWeight(1)
        }
        .width('100%')
      }
      .padding({ left: 16, right: 16, top: 16, bottom: 14 })
      .linearGradient({
        direction: GradientDirection.LeftTop,
        colors: [
          [$r('app.color.surface_dialog_gradient_start'), 0.0],
          [$r('app.color.surface_dialog_gradient_end'), 1.0]
        ]
      })
      .shadow({
        color: $r('app.color.surface_card_shadow'),
        radius: 12,
        offsetX: 0,
        offsetY: 4
      })
      .borderRadius(28)
      .width('85%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.surface_dialog_scrim'))
  }
}
