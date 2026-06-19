import {
  ArcButton,
  ArcButtonOptions,
  ArcButtonPosition,
  ArcButtonStatus,
  ArcButtonStyleMode
} from '@kit.ArkUI';

/**
 * Reusable bottom-edge Arc submit button.
 *
 * The enabled and disabled branches intentionally render different node ids.
 * This forces ArkUI to recreate `ArcButton`, which is required for
 * `ArcButtonOptions.status` to be applied after state changes.
 */
@Component
export struct ArcSubmitButton {
  /** Button label shown to the user. */
  @Prop label: ResourceStr = '';

  /** Whether submit action can be triggered. */
  @Prop isEnabled: boolean = false;

  /** Node id used for the enabled branch. */
  @Prop enabledId: string = 'submitButtonEnabled';

  /** Node id used for the disabled branch. */
  @Prop disabledId: string = 'submitButtonDisabled';

  /** Callback invoked when enabled button is tapped. */
  onSubmitButtonClick: () => void = (): void => {};

  /**
   * Renders one ArcButton instance with fixed bottom-edge placement.
   *
   * @param buttonId Node id used to force branch-specific recreation.
   * @param status ArcButton status applied at construction time.
   */
  @Builder
  private buildArcButton(buttonId: string, status: ArcButtonStatus): void {
    ArcButton({
      options: new ArcButtonOptions({
        label: this.label,
        status: status,
        position: ArcButtonPosition.BOTTOM_EDGE,
        styleMode: ArcButtonStyleMode.EMPHASIZED_LIGHT,
        onClick: (): void => {
          if (!this.isEnabled) {
            return;
          }
          this.onSubmitButtonClick();
        }
      })
    })
      .id(buttonId)
      .width('100%')
      .align(Alignment.Center)
      .alignRules({
        bottom: { anchor: '__container__', align: VerticalAlign.Bottom }
      })
  }

  /**
   * Renders enabled or disabled ArcButton branch.
   */
  build() {
    if (this.isEnabled) {
      this.buildArcButton(this.enabledId, ArcButtonStatus.NORMAL)
    } else {
      this.buildArcButton(this.disabledId, ArcButtonStatus.DISABLED)
    }
  }
}
