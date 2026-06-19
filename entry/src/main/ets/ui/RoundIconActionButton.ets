/**
 * Reusable round icon button used in chat action bars.
 */
@Component
export struct RoundIconActionButton {
  /** Icon resource rendered inside the action button. */
  @Prop iconResource: Resource = $r('app.media.chat_icon_pencil_white');

  /** Base background color used when button is enabled. */
  @Prop buttonColor: ResourceColor = $r('app.color.surface_profile_chats_fill');

  /** Enables or disables click handling and visual state. */
  @Prop isEnabled: boolean = true;

  /** Outer button diameter in vp. */
  @Prop diameter: number = 44;

  /** Icon size in vp. */
  @Prop iconSize: number = 20;

  /** Click callback executed on tap. */
  onButtonClick: () => void = (): void => {};

  /**
   * Resolves effective button background color.
   *
   * @returns Disabled or enabled background color.
   */
  private resolvedButtonColor(): ResourceColor {
    if (!this.isEnabled) {
      return $r('app.color.button_disabled_secondary');
    }
    return this.buttonColor;
  }

  /**
   * Resolves effective opacity based on enabled state.
   *
   * @returns Opacity value in range 0..1.
   */
  private resolvedOpacity(): number {
    if (!this.isEnabled) {
      return 0.78;
    }
    return 0.93;
  }

  /**
   * Renders round action button with icon.
   */
  build() {
    Button() {
      Image(this.iconResource)
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
    }
    .width(this.diameter)
    .height(this.diameter)
    .borderRadius(this.diameter / 2)
    .enabled(this.isEnabled)
    .backgroundColor(this.resolvedButtonColor())
    .opacity(this.resolvedOpacity())
    .shadow({
      color: $r('app.color.surface_elevation_shadow'),
      radius: 12,
      offsetX: 0,
      offsetY: 4
    })
    .onClick((): void => {
      if (!this.isEnabled) {
        return;
      }
      this.onButtonClick();
    })
  }
}
