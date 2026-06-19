import { RoundIconActionButton } from './RoundIconActionButton';

/**
 * Renders compact watch action buttons for fullscreen media playback.
 */
@Component
export struct MediaViewerPlaybackControlPanel {
  /** Enables the play action button. */
  @Prop canPlay: boolean = false;

  /** Enables the pause action button. */
  @Prop canPause: boolean = false;

  /** Enables the stop action button. */
  @Prop canStop: boolean = false;

  /** Callback executed when the user taps play. */
  onPlay: () => void = (): void => {};

  /** Callback executed when the user taps pause. */
  onPause: () => void = (): void => {};

  /** Callback executed when the user taps stop. */
  onStop: () => void = (): void => {};

  /**
   * Renders the full control panel.
   */
  build() {
    Row({ space: 16 }) {
      RoundIconActionButton({
        iconResource: $r('app.media.media_viewer_player_play_white'),
        buttonColor: $r('app.color.media_viewer_control_play_background'),
        isEnabled: this.canPlay,
        diameter: 38,
        iconSize: 18,
        onButtonClick: (): void => {
          this.onPlay();
        }
      })
      RoundIconActionButton({
        iconResource: $r('app.media.media_viewer_player_pause_white'),
        buttonColor: $r('app.color.media_viewer_control_pause_background'),
        isEnabled: this.canPause,
        diameter: 38,
        iconSize: 18,
        onButtonClick: (): void => {
          this.onPause();
        }
      })
      RoundIconActionButton({
        iconResource: $r('app.media.media_viewer_player_stop_white'),
        buttonColor: $r('app.color.media_viewer_control_stop_background'),
        isEnabled: this.canStop,
        diameter: 38,
        iconSize: 18,
        onButtonClick: (): void => {
          this.onStop();
        }
      })
    }
    .justifyContent(FlexAlign.Center)
  }
}
