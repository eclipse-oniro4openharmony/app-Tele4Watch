/**
 * Reusable gradient action button shared by action list items and dialogs.
 */
@Component
export struct GradientActionButton {
  /** Button label shown to the user. */
  @Prop label: ResourceStr = '';

  /** Enables optional icon rendering before the label. */
  @Prop hasIcon: boolean = false;

  /** Icon resource rendered before the label when enabled. */
  @Prop iconResource: Resource = $r('app.media.chat_icon_pencil_white');

  /** Base button background color used when button is enabled. */
  @Prop buttonColor: ResourceColor = $r('app.color.bg_action_enabled');

  /** Base button background color used when button is disabled. */
  @Prop disabledButtonColor: ResourceColor = $r('app.color.bg_action_disabled');

  /** Gradient start color used when action is enabled. */
  @Prop gradientStartColor: ResourceColor = $r('app.color.surface_action_gradient_start');

  /** Gradient middle color used when action is enabled. */
  @Prop gradientMiddleColor: ResourceColor = $r('app.color.surface_action_gradient_middle');

  /** Gradient end color used when action is enabled. */
  @Prop gradientEndColor: ResourceColor = $r('app.color.surface_action_gradient_end');

  /** Gradient start color used when action is disabled. */
  @Prop disabledGradientStartColor: ResourceColor = $r('app.color.surface_action_disabled_gradient_start');

  /** Gradient middle color used when action is disabled. */
  @Prop disabledGradientMiddleColor: ResourceColor = $r('app.color.surface_action_disabled_gradient_middle');

  /** Gradient end color used when action is disabled. */
  @Prop disabledGradientEndColor: ResourceColor = $r('app.color.surface_action_disabled_gradient_end');

  /** Text color rendered inside the action button. */
  @Prop labelColor: ResourceColor = $r('app.color.text_primary');

  /** Whether action can be triggered. */
  @Prop isEnabled: boolean = true;

  /** Opacity used for enabled action button. */
  @Prop buttonOpacity: number = 0.9;

  /** Opacity used for disabled action button. */
  @Prop disabledButtonOpacity: number = 0.68;

  /** Button height in vp. */
  @Prop buttonHeight: number = 36;

  /** Label font size in fp. */
  @Prop labelFontSize: number = 11;

  /** Icon size in vp. */
  @Prop iconSize: number = 16;

  /** Callback invoked on button tap. */
  onButtonClick: () => void = (): void => {};

  /**
   * Resolves effective button color based on enabled state.
   *
   * @returns Background color for action button.
   */
  private resolvedButtonColor(): ResourceColor {
    if (!this.isEnabled) {
      return this.disabledButtonColor;
    }
    return this.buttonColor;
  }

  /**
   * Resolves gradient start color for current enabled state.
   *
   * @returns Color used at gradient start.
   */
  private resolvedGradientStartColor(): ResourceColor {
    if (!this.isEnabled) {
      return this.disabledGradientStartColor;
    }
    return this.gradientStartColor;
  }

  /**
   * Resolves gradient middle color for current enabled state.
   *
   * @returns Color used at gradient midpoint.
   */
  private resolvedGradientMiddleColor(): ResourceColor {
    if (!this.isEnabled) {
      return this.disabledGradientMiddleColor;
    }
    return this.gradientMiddleColor;
  }

  /**
   * Resolves gradient end color for current enabled state.
   *
   * @returns Color used at gradient end.
   */
  private resolvedGradientEndColor(): ResourceColor {
    if (!this.isEnabled) {
      return this.disabledGradientEndColor;
    }
    return this.gradientEndColor;
  }

  /**
   * Resolves button opacity for enabled and disabled states.
   *
   * @returns Opacity value in range 0..1.
   */
  private resolvedOpacity(): number {
    if (!this.isEnabled) {
      return this.disabledButtonOpacity;
    }
    return this.buttonOpacity;
  }

  /**
   * Renders the gradient action button.
   */
  build() {
    Button() {
      Row({ space: 8 }) {
        if (this.hasIcon) {
          Image(this.iconResource)
            .width(this.iconSize)
            .height(this.iconSize)
            .objectFit(ImageFit.Contain)
        }

        Text(this.label)
          .fontSize(this.labelFontSize)
          .fontColor(this.labelColor)
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(this.buttonHeight)
    .enabled(this.isEnabled)
    .backgroundColor(this.resolvedButtonColor())
    .linearGradient({
      direction: GradientDirection.RightBottom,
      colors: [
        [this.resolvedGradientStartColor(), 0.0],
        [this.resolvedGradientMiddleColor(), 0.58],
        [this.resolvedGradientEndColor(), 1.0]
      ]
    })
    .opacity(this.resolvedOpacity())
    .onClick((): void => {
      this.onButtonClick();
    })
  }
}
