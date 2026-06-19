import { ArcListItem } from '@kit.ArkUI';
import { GradientActionButton } from './GradientActionButton';

/**
 * Reusable ArcList item with a single action button.
 */
@Component
export struct ActionButtonListItem {
  /** Button label shown to the user. */
  @Prop label: ResourceStr = '';

  /** Enables optional icon rendering inside the action button. */
  @Prop hasIcon: boolean = false;

  /** Icon resource rendered before the button label when enabled. */
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

  /** Surface background behind the action button. */
  @Prop containerBackgroundColor: ResourceColor = $r('app.color.surface_action_list_item_backdrop');

  /** Whether action can be triggered. */
  @Prop isEnabled: boolean = true;

  /** Opacity used for enabled action button. */
  @Prop buttonOpacity: number = 0.9;

  /** Opacity used for disabled action button. */
  @Prop disabledButtonOpacity: number = 0.68;

  /** Callback invoked on button tap. */
  onButtonClick: () => void = (): void => {};

  /**
   * Renders action button wrapped in ArcListItem.
   */
  build() {
    ArcListItem() {
      Column() {
        GradientActionButton({
          label: this.label,
          hasIcon: this.hasIcon,
          iconResource: this.iconResource,
          buttonColor: this.buttonColor,
          disabledButtonColor: this.disabledButtonColor,
          gradientStartColor: this.gradientStartColor,
          gradientMiddleColor: this.gradientMiddleColor,
          gradientEndColor: this.gradientEndColor,
          disabledGradientStartColor: this.disabledGradientStartColor,
          disabledGradientMiddleColor: this.disabledGradientMiddleColor,
          disabledGradientEndColor: this.disabledGradientEndColor,
          labelColor: this.labelColor,
          isEnabled: this.isEnabled,
          buttonOpacity: this.buttonOpacity,
          disabledButtonOpacity: this.disabledButtonOpacity,
          onButtonClick: (): void => {
            this.onButtonClick();
          }
        })
      }
      .width('90%')
      .padding({ left: 6, right: 6, top: 4, bottom: 4 })
      .margin({ top: 2, bottom: 2 })
      .backgroundColor(this.containerBackgroundColor)
      .borderRadius(24)
    }
  }
}
