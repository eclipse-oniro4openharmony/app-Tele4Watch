import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CallScreenPeerInfo,
  CallScreenPhase,
  CallScreenViewModel
} from '../viewmodel/CallScreenViewModel';
import { CallScreenDirection } from '../models/voip/CallScreenTypes';
import { CallScreenRouteParams } from '../models/voip/CallScreenRouteParams';
import { UserAvatar } from '../ui/UserAvatar';
import { RoundIconActionButton } from '../ui/RoundIconActionButton';
import {
  avatarFallbackGradientEndColor,
  avatarFallbackGradientStartColor
} from '../ui/AvatarFallbackPalette';
import { formatCallDurationMMSS } from '../utils/CallDurationFormatter';
import { textSignature } from '../utils/TextSignature';

const DOMAIN = 0x2026;
const TAG = 'CallScreenPage';
const FINISH_DELAY_MS = 500;

/**
 * Unified call screen (ADR-0007 + Task 4.6). Renders the full call lifecycle
 * for both directions; all TDLib interaction lives in `CallScreenViewModel`,
 * the view only maps the semantic `CallScreenPhase` to UI resources and owns
 * navigation. The `connected` phase is the anchor for in-call controls
 * (mute / hangup / audio level / duration); `incomingRinging` is the anchor
 * for the pre-accept Answer / Decline pair.
 */
@Entry
@Component
struct CallScreen {
  private readonly viewModel: CallScreenViewModel = new CallScreenViewModel();
  @State phase: CallScreenPhase = 'calling';
  @State peerName: string = '';
  @State peerAvatarPath: string = '';
  @State peerAvatarAnimationPath: string = '';
  @State isMuted: boolean = false;
  @State audioLevel: number = 0;
  @State durationSeconds: number = 0;
  private peerUserId: string = '';
  private finishTimerId: number = -1;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as CallScreenRouteParams;
    const direction: CallScreenDirection = params.direction === 'incoming' ? 'incoming' : 'outgoing';
    if (typeof params.peerName === 'string') {
      this.peerName = params.peerName;
    }
    if (typeof params.userId === 'string') {
      this.peerUserId = params.userId;
    }
    hilog.info(DOMAIN, TAG, 'CallScreen aboutToAppear direction=%{public}s pendingAccept=%{public}d',
      direction,
      params.pendingAccept === true ? 1 : 0
    );

    this.viewModel.setPhaseListener((phase: CallScreenPhase): void => {
      this.phase = phase;
      if (this.viewModel.isTerminalPhase(phase)) {
        this.scheduleReturn();
      }
    });
    this.viewModel.setAudioLevelListener((level: number): void => {
      this.audioLevel = level;
    });
    this.viewModel.setPeerListener((peer: CallScreenPeerInfo): void => {
      this.peerName = peer.name;
      this.peerAvatarPath = peer.avatarPath;
      this.peerAvatarAnimationPath = peer.avatarAnimationPath;
    });
    this.viewModel.setDurationListener((seconds: number): void => {
      this.durationSeconds = seconds;
    });

    // TODO(task-4.6 cleanup): remove the `mockMode` branch together with
    // the Profile debug entries once the UI polish iteration is done.
    if (typeof params.mockMode === 'string' && params.mockMode.length > 0) {
      this.viewModel.startMockCall(
        params.callId,
        params.userId,
        this.peerName,
        params.mockMode
      );
    } else if (params.resume === true) {
      // Re-entered from the ongoing-call notification — the call is already active.
      this.viewModel.resumeCall(params.callId, params.userId);
    } else if (direction === 'incoming') {
      this.viewModel.startIncomingCall(params.callId, params.userId, params.pendingAccept === true);
    } else {
      this.viewModel.startOutgoingCall(params.userId);
    }
  }

  aboutToDisappear(): void {
    if (this.finishTimerId >= 0) {
      clearTimeout(this.finishTimerId);
      this.finishTimerId = -1;
    }
    this.viewModel.dispose();
  }

  /**
   * System back gesture is wired to "end the call" so the user always has a
   * way to terminate the conversation — without this, an active call screen
   * would only be exited via the on-screen End / Decline button. In terminal
   * phases the call is already finished, so we let ArkUI pop the page
   * normally and the user returns immediately.
   *
   * @returns true when the back event is consumed (active call), false to
   *   delegate to default router pop (terminal phase).
   */
  onBackPress(): boolean {
    if (this.viewModel.isTerminalPhase(this.phase)) {
      return false;
    }
    hilog.info(DOMAIN, TAG, 'System back routed to endCall in phase=%{public}s', this.phase);
    this.viewModel.endCall();
    return true;
  }

  /**
   * Maps the current semantic phase to a localized status string.
   *
   * @returns Status text shown under the peer name.
   */
  private statusResource(): ResourceStr {
    switch (this.phase) {
      case 'incomingRinging':
        return $r('app.string.call_screen_status_incoming_ringing');
      case 'answering':
        return $r('app.string.call_screen_status_answering');
      case 'calling':
        return $r('app.string.call_screen_status_calling');
      case 'ringing':
        return $r('app.string.call_screen_status_ringing');
      case 'connecting':
        return $r('app.string.call_screen_status_connecting');
      case 'connected':
        return $r('app.string.call_screen_status_connected');
      case 'ending':
        return $r('app.string.call_screen_status_ending');
      case 'ended':
        return $r('app.string.call_screen_status_ended');
      case 'failed':
        return $r('app.string.call_screen_status_failed');
      case 'invalidCall':
        return $r('app.string.call_screen_status_invalid_call');
      case 'invalidUser':
        return $r('app.string.call_screen_status_invalid_user');
      case 'answerFailed':
        return $r('app.string.call_screen_status_answer_failed');
      case 'createFailed':
        return $r('app.string.call_screen_status_create_failed');
      default:
        return $r('app.string.call_screen_status_calling');
    }
  }

  private statusColor(): ResourceColor {
    if (this.viewModel.isErrorPhase(this.phase)) {
      return $r('app.color.call_screen_status_error');
    }
    return $r('app.color.call_screen_status');
  }

  private scheduleReturn(): void {
    if (this.finishTimerId >= 0) {
      return;
    }
    this.finishTimerId = setTimeout((): void => {
      this.returnBack();
    }, FINISH_DELAY_MS);
  }

  private returnBack(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to return after call: %{public}s', String(error));
      try {
        this.getUIContext().getRouter().replaceUrl({
          url: 'pages/Index'
        });
      } catch (replaceError) {
        hilog.error(DOMAIN, TAG, 'Failed to route to Index after call: %{public}s', String(replaceError));
      }
    }
  }

  /**
   * Toggles the outgoing microphone mute state. The UI flips only when the view
   * model confirms the request reached an active native session.
   */
  private toggleMute(): void {
    const next = !this.isMuted;
    if (this.viewModel.setMuted(next)) {
      this.isMuted = next;
    }
  }

  /**
   * Resolves the avatar gradient palette index from the peer user id or name —
   * keeps the call screen colour consistent with the contact's profile card.
   */
  private avatarPaletteIndex(): number {
    if (this.peerUserId.length > 0) {
      return textSignature(this.peerUserId) % 8;
    }
    if (this.peerName.length > 0) {
      return textSignature(this.peerName) % 8;
    }
    return 0;
  }

  build() {
    Stack() {
      Image($r('app.media.watch_wallpaper_466'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)

      Column({ space: 8 }) {

        this.buildAvatar()

        if (this.peerName.length > 0) {
          Text(this.peerName)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('80%')
        }

        if (this.phase === 'connected') {
          Text(formatCallDurationMMSS(this.durationSeconds))
            .fontSize(12)
            .fontWeight(FontWeight.Regular)
            .fontColor($r('app.color.call_screen_status'))
            .textAlign(TextAlign.Center)
            .width('80%')
        } else {
          Text(this.statusResource())
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.statusColor())
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .width('80%')
        }

        this.buildActionRow()
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.call_screen_overlay_background'))
    }
    .width('100%')
    .height('100%')
  }

  /**
   * Reuses `UserAvatar` with the gradient-initials fallback shared by
   * `ProfileCard` — the call screen displays the same visual identity that
   * the contact already has elsewhere in the app.
   */
  @Builder
  private buildAvatar(): void {
    UserAvatar({
      imagePath: this.peerAvatarPath,
      animationPath: this.peerAvatarAnimationPath,
      animateAvatar: true,
      fallbackText: this.peerName.length > 0 ? this.peerName : '?',
      avatarDiameter: 80,
      fallbackInitialFontSize: 28,
      fallbackMaxInitials: 2,
      fallbackBackgroundColor: $r('app.color.contact_avatar_fallback_background'),
      fallbackGradientStartColor: avatarFallbackGradientStartColor(this.avatarPaletteIndex()),
      fallbackGradientEndColor: avatarFallbackGradientEndColor(this.avatarPaletteIndex()),
      fallbackUseGradient: true
    })
  }

  /**
   * Outgoing-microphone amplitude bars (M2.4.2) — five bars lit proportionally to
   * `audioLevel` [0.0, 1.0], so the user sees their voice is going out. Muting the
   * mic drops the level to zero, so the bars also reflect the mute state.
   */
  @Builder
  private buildAudioLevelBars(): void {
    Row({ space: 4 }) {
      ForEach([0, 1, 2, 3, 4], (barIndex: number): void => {
        Column()
          .width(4)
          .height(8 + barIndex * 5)
          .borderRadius(2)
          .backgroundColor(this.audioLevel >= (barIndex + 1) / 5
            ? Color.White
            : $r('app.color.call_screen_control_fill'))
      }, (barIndex: number): string => barIndex.toString())
    }
    .height(28)
    .alignItems(VerticalAlign.Bottom)
  }

  /**
   * Renders the bottom action row whose contents depend on the current phase:
   * - `incomingRinging`: Decline (red) + Accept (green) — pre-accept choice,
   * - `connected`: Mute toggle + End (red),
   * - other non-terminal phases: a single End (red) to cancel/hang up,
   * - terminal phases: nothing.
   */
  @Builder
  private buildActionRow(): void {
    if (this.phase === 'incomingRinging') {
      Row({ space: 32 }) {
        this.buildDeclineButton()
        this.buildAcceptButton()
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
    } else if (this.phase === 'connected') {
      Row({ space: 8 }) {
        this.buildMuteButton()
        this.buildAudioLevelBars()
        this.buildEndButton()
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
    } else if (!this.viewModel.isTerminalPhase(this.phase)) {
      Row() {
        this.buildEndButton()
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  private buildAcceptButton(): void {
    RoundIconActionButton({
      iconResource: $r('app.media.chat_icon_call_accept_white'),
      buttonColor: $r('app.color.call_screen_button_accept'),
      isEnabled: true,
      diameter: 56,
      iconSize: 24,
      onButtonClick: (): void => {
        this.viewModel.acceptIncomingCall();
      }
    })
  }

  @Builder
  private buildDeclineButton(): void {
    RoundIconActionButton({
      iconResource: $r('app.media.chat_icon_call_decline_white'),
      buttonColor: $r('app.color.call_screen_button_decline'),
      isEnabled: true,
      diameter: 56,
      iconSize: 24,
      onButtonClick: (): void => {
        this.viewModel.rejectIncomingCall();
      }
    })
  }

  @Builder
  private buildEndButton(): void {
    RoundIconActionButton({
      iconResource: $r('app.media.chat_icon_call_decline_white'),
      buttonColor: $r('app.color.call_screen_button_end'),
      isEnabled: true,
      diameter: 56,
      iconSize: 24,
      onButtonClick: (): void => {
        this.viewModel.endCall();
      }
    })
  }

  @Builder
  private buildMuteButton(): void {
    RoundIconActionButton({
      iconResource: this.isMuted
        ? $r('app.media.chat_icon_microphone_off_white')
        : $r('app.media.chat_icon_microphone_white'),
      buttonColor: this.isMuted
        ? $r('app.color.call_screen_button_mute_active')
        : $r('app.color.call_screen_control_fill'),
      isEnabled: true,
      diameter: 56,
      iconSize: 24,
      onButtonClick: (): void => {
        this.toggleMute();
      }
    })
  }
}
