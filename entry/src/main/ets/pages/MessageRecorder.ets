import { hilog } from '@kit.PerformanceAnalysisKit';
import resourceManager from '@ohos.resourceManager';
import { Context } from '@ohos.abilityAccessCtrl';
import {
  ArcButton,
  ArcButtonOptions,
  ArcButtonPosition,
  ArcButtonStatus,
  ArcButtonStyleMode
} from '@kit.ArkUI';
import {
  MessageRecorderErrorKind,
  MessageRecorderPageState,
  MessageRecorderPhase
} from '../models/chat/MessageRecorderPageState';
import { createResourceUiText, UiTextValue } from '../models/ui/UiTextValue';
import { resolveUiTextValue } from '../utils/UiTextValueResolver';
import { MessageRecorderPageViewModel } from '../viewmodel/MessageRecorderPageViewModel';
import { MicrophonePermissionResultStatus } from '../services/permissions/MicrophonePermissionService';
import { VoiceNoteRecorderSnapshot } from '../services/media/VoiceNoteRecorderController';

interface MessageRecorderParams {
  chatId?: string;
  chatTitle?: string;
  chatUsername?: string;
}

const DOMAIN = 0x2026;
const TAG = 'MessageRecorderPage';
const CHAT_HISTORY_REFRESH_LIMIT: number = 50;

@Entry
@Component
struct MessageRecorder {
  private readonly viewModel: MessageRecorderPageViewModel = new MessageRecorderPageViewModel();
  private readonly initialPageState: MessageRecorderPageState = this.viewModel.createInitialState();
  @State chatId: string = this.initialPageState.chatId;
  @State chatTitle: string = this.initialPageState.chatTitle;
  @State chatUsername: string = this.initialPageState.chatUsername;
  @State phase: MessageRecorderPhase = this.initialPageState.phase;
  @State errorKind: MessageRecorderErrorKind = this.initialPageState.errorKind;
  @State elapsedSeconds: number = this.initialPageState.elapsedSeconds;
  @State statusText: UiTextValue = this.initialPageState.statusText;
  @State errorText: UiTextValue = this.initialPageState.errorText;
  @State primaryActionText: UiTextValue = this.initialPageState.primaryActionText;
  @State secondaryActionText: UiTextValue = this.initialPageState.secondaryActionText;
  @State primaryActionEnabled: boolean = this.initialPageState.primaryActionEnabled;
  @State secondaryActionEnabled: boolean = this.initialPageState.secondaryActionEnabled;
  @State secondaryActionVisible: boolean = this.initialPageState.secondaryActionVisible;
  @State private ledOpacity: number = 1.0;
  private hasNavigatedToIndex: boolean = false;
  private ledBlinkIntervalId: number = -1;

  private getResourceManager(): resourceManager.ResourceManager {
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      throw new Error('Host context unavailable.');
    }
    return hostContext.resourceManager;
  }

  private resolveUiText(textValue: UiTextValue): string {
    return resolveUiTextValue(this.getResourceManager(), textValue);
  }

  private getAbilityContext(): Context {
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      throw new Error('Host context unavailable.');
    }
    return hostContext;
  }

  private redirectToIndexIfUnauthorized(state: string): void {
    if (state === 'authorizationStateReady') {
      return;
    }
    if (this.hasNavigatedToIndex) {
      return;
    }

    hilog.info(DOMAIN, TAG, 'Session is no longer authorized (state=%{public}s). Redirecting to Index.', state);
    try {
      this.hasNavigatedToIndex = true;
      this.getUIContext().getRouter().replaceUrl({
        url: 'pages/Index'
      });
    } catch (error) {
      this.hasNavigatedToIndex = false;
      hilog.error(DOMAIN, TAG, 'Failed to redirect MessageRecorder to Index: %{public}s', String(error));
    }
  }

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle enter: MessageRecorder');
    this.hasNavigatedToIndex = false;
    const params = this.getUIContext().getRouter().getParams() as MessageRecorderParams;
    this.applyPageState(this.viewModel.applyRoute(
      this.currentPageState(),
      typeof params.chatId === 'string' ? params.chatId : '',
      typeof params.chatTitle === 'string' ? params.chatTitle : '',
      typeof params.chatUsername === 'string' ? params.chatUsername : ''
    ));

    this.viewModel.setMessageSendResultListener((chatId: string, ok: boolean, errorMessage: string): void => {
      if (chatId !== this.chatId) {
        return;
      }
      if (ok) {
        this.viewModel.clearPendingVoiceNote(false);
        this.returnToChatDetails(true);
        return;
      }
      this.applyPageState(this.viewModel.createSendErrorState(
        this.currentPageState(),
        errorMessage,
        this.elapsedSeconds
      ));
    });

    this.viewModel.setAuthStateListener((state: string): void => {
      this.redirectToIndexIfUnauthorized(state);
    });
    this.viewModel.setRecorderSnapshotListener((snapshot: VoiceNoteRecorderSnapshot): void => {
      this.handleRecorderSnapshot(snapshot);
    });
    this.redirectToIndexIfUnauthorized(this.viewModel.getAuthorizationStateName());
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle leave: MessageRecorder');
    this.stopRecordingLedBlink();
    this.viewModel.clearMessageSendResultListener();
    this.viewModel.setRecorderSnapshotListener(undefined);
    void this.viewModel.releaseRecorderSession(this.phase);
  }

  private startRecordingLedBlink(): void {
    if (this.ledBlinkIntervalId >= 0) {
      return;
    }
    this.ledOpacity = 1.0;
    this.ledBlinkIntervalId = setInterval((): void => {
      this.ledOpacity = this.ledOpacity > 0.5 ? 0.25 : 1.0;
    }, 500);
  }

  private stopRecordingLedBlink(): void {
    if (this.ledBlinkIntervalId >= 0) {
      clearInterval(this.ledBlinkIntervalId);
      this.ledBlinkIntervalId = -1;
    }
    this.ledOpacity = 1.0;
  }

  private currentPageState(): MessageRecorderPageState {
    return {
      chatId: this.chatId,
      chatTitle: this.chatTitle,
      chatUsername: this.chatUsername,
      phase: this.phase,
      errorKind: this.errorKind,
      elapsedSeconds: this.elapsedSeconds,
      statusText: this.statusText,
      errorText: this.errorText,
      primaryActionText: this.primaryActionText,
      secondaryActionText: this.secondaryActionText,
      primaryActionEnabled: this.primaryActionEnabled,
      secondaryActionEnabled: this.secondaryActionEnabled,
      secondaryActionVisible: this.secondaryActionVisible
    };
  }

  private applyPageState(nextPageState: MessageRecorderPageState): void {
    this.chatId = nextPageState.chatId;
    this.chatTitle = nextPageState.chatTitle;
    this.chatUsername = nextPageState.chatUsername;
    this.phase = nextPageState.phase;
    this.errorKind = nextPageState.errorKind;
    this.elapsedSeconds = nextPageState.elapsedSeconds;
    this.statusText = nextPageState.statusText;
    this.errorText = nextPageState.errorText;
    this.primaryActionText = nextPageState.primaryActionText;
    this.secondaryActionText = nextPageState.secondaryActionText;
    this.primaryActionEnabled = nextPageState.primaryActionEnabled;
    this.secondaryActionEnabled = nextPageState.secondaryActionEnabled;
    this.secondaryActionVisible = nextPageState.secondaryActionVisible;
    if (nextPageState.phase === MessageRecorderPhase.Recording) {
      this.startRecordingLedBlink();
    } else {
      this.stopRecordingLedBlink();
    }
  }

  private async handlePrimaryAction(): Promise<void> {
    const currentState = this.currentPageState();
    if (currentState.phase === MessageRecorderPhase.Idle) {
      await this.requestMicrophonePermission();
      return;
    }

    if (currentState.phase === MessageRecorderPhase.Recording) {
      await this.stopAndSendRecording();
      return;
    }

    if (currentState.phase !== MessageRecorderPhase.Error) {
      return;
    }

    if (currentState.errorKind === MessageRecorderErrorKind.PermissionDenied) {
      await this.requestMicrophonePermissionOnSetting();
      return;
    }

    if (currentState.errorKind === MessageRecorderErrorKind.SendFailed) {
      this.sendPendingVoiceNote();
      return;
    }

    this.viewModel.clearPendingVoiceNote(true);
    this.applyPageState(this.viewModel.createIdleState(currentState));
  }

  private handleSecondaryAction(): void {
    if (this.phase !== MessageRecorderPhase.Recording) {
      return;
    }
    void this.cancelRecordingAndReturn();
  }

  private formattedElapsedTime(): string {
    const safeSeconds = this.elapsedSeconds > 0 ? this.elapsedSeconds : 0;
    const minutes = Math.floor(safeSeconds / 60);
    const seconds = safeSeconds % 60;
    const minutesText = minutes < 10 ? `0${minutes}` : `${minutes}`;
    const secondsText = seconds < 10 ? `0${seconds}` : `${seconds}`;
    return `${minutesText}:${secondsText}`;
  }

  private phaseBadgeText(): ResourceStr {
    if (this.phase === MessageRecorderPhase.RequestingPermission) {
      return $r('app.string.message_recorder_phase_requesting_permission');
    }
    if (this.phase === MessageRecorderPhase.Recording) {
      return $r('app.string.message_recorder_phase_recording');
    }
    if (this.phase === MessageRecorderPhase.Stopping) {
      return $r('app.string.message_recorder_phase_stopping');
    }
    if (this.phase === MessageRecorderPhase.Sending) {
      return $r('app.string.message_recorder_phase_sending');
    }
    if (this.phase === MessageRecorderPhase.Error) {
      return $r('app.string.message_recorder_phase_error');
    }
    return $r('app.string.message_recorder_phase_idle');
  }

  private phaseBadgeColor(): ResourceColor {
    if (this.phase === MessageRecorderPhase.Recording) {
      return $r('app.color.message_recorder_phase_recording');
    }
    if (this.phase === MessageRecorderPhase.RequestingPermission) {
      return $r('app.color.message_recorder_phase_requesting_permission');
    }
    if (this.phase === MessageRecorderPhase.Stopping || this.phase === MessageRecorderPhase.Sending) {
      return $r('app.color.message_recorder_phase_busy');
    }
    if (this.phase === MessageRecorderPhase.Error) {
      return $r('app.color.message_recorder_phase_error');
    }
    return $r('app.color.message_recorder_phase_idle');
  }

  private resolveResourceText(resourceName: string): string {
    return this.resolveUiText(createResourceUiText(resourceName));
  }

  @Builder
  private buildRecordingLed(): void {
    Row()
      .width(8)
      .height(8)
      .backgroundColor($r('app.color.message_recorder_led_recording'))
      .borderRadius(4)
      .opacity(this.ledOpacity)
      .animation({ duration: 450, curve: Curve.EaseInOut })
      .shadow({
        color: $r('app.color.message_recorder_led_recording_glow'),
        radius: 12,
        offsetX: 0,
        offsetY: 0
      })
  }

  @Builder
  private buildPhaseBadge(): void {
    Row({ space: 5 }) {
      if (this.phase === MessageRecorderPhase.Recording) {
        this.buildRecordingLed()
      }
      Text(this.phaseBadgeText())
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
    }
    .alignItems(VerticalAlign.Center)
    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    .backgroundColor(this.phaseBadgeColor())
    .borderRadius(12)
  }

  @Builder
  private buildTimerPanel(): void {
    Column() {

      Stack() {
        Column({ space: 6 }) {
          Text(this.formattedElapsedTime())
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)

          Text($r('app.string.message_recorder_timer_caption'))
            .fontSize(14)
            .fontColor($r('app.color.message_recorder_timer_caption'))
            .textAlign(TextAlign.Center)

          this.buildPhaseBadge()

          Text(this.resolveUiText(this.statusText))
            .width('70%')
            .fontSize(8)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .padding({ left: 14, right: 14 })
        }
        .alignItems(HorizontalAlign.Center)
      }
      .width(180)
      .height(180)
      .linearGradient({
        direction: GradientDirection.LeftTop,
        colors: [
          [$r('app.color.surface_list_card_gradient_start'), 0.0],
          [$r('app.color.surface_list_card_gradient_end'), 1.0]
        ]
      })
      .opacity(0.85)
      .shadow({
        color: $r('app.color.surface_card_shadow'),
        radius: 10,
        offsetX: 0,
        offsetY: 3
      })
      .border({
        width: 2,
        color: this.phaseBadgeColor()
      })
      .borderRadius(90)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildBottomArcButton(buttonId: string, labelText: string, enabled: boolean): void {
    ArcButton({
      options: new ArcButtonOptions({
        label: labelText,
        status: enabled ? ArcButtonStatus.NORMAL : ArcButtonStatus.DISABLED,
        position: ArcButtonPosition.BOTTOM_EDGE,
        styleMode: ArcButtonStyleMode.EMPHASIZED_LIGHT,
        onClick: (): void => {
          void this.handlePrimaryAction();
        }
      })
    })
      .id(buttonId)
      .width('100%')
      .align(Alignment.Center)
      .alignRules({
        left: { anchor: '__container__', align: HorizontalAlign.Start },
        right: { anchor: '__container__', align: HorizontalAlign.End },
        bottom: { anchor: '__container__', align: VerticalAlign.Bottom }
      })
  }

  @Builder
  private buildPrimaryActionButton(): void {
    if (this.phase === MessageRecorderPhase.Idle) {
      this.buildBottomArcButton(
        'message-recorder-primary-action-idle',
        this.resolveUiText(this.primaryActionText),
        this.primaryActionEnabled
      )
    } else if (this.phase === MessageRecorderPhase.Recording) {
      this.buildBottomArcButton(
        'message-recorder-primary-action-recording',
        this.resolveUiText(this.primaryActionText),
        this.primaryActionEnabled
      )
    } else if (this.phase === MessageRecorderPhase.RequestingPermission ||
      this.phase === MessageRecorderPhase.Stopping ||
      this.phase === MessageRecorderPhase.Sending) {
      this.buildBottomArcButton(
        'message-recorder-primary-action-busy',
        this.resolveUiText(this.primaryActionText),
        this.primaryActionEnabled
      )
    } else if (this.phase === MessageRecorderPhase.Error &&
      this.errorKind === MessageRecorderErrorKind.PermissionDenied) {
      this.buildBottomArcButton(
        'message-recorder-primary-action-open-settings',
        this.resolveUiText(this.primaryActionText),
        this.primaryActionEnabled
      )
    } else if (this.phase === MessageRecorderPhase.Error &&
      this.errorKind === MessageRecorderErrorKind.SendFailed) {
      this.buildBottomArcButton(
        'message-recorder-primary-action-retry-send',
        this.resolveUiText(this.primaryActionText),
        this.primaryActionEnabled
      )
    } else {
      this.buildBottomArcButton(
        'message-recorder-primary-action-reset',
        this.resolveUiText(this.primaryActionText),
        this.primaryActionEnabled
      )
    }
  }

  @Builder
  private buildSecondaryActionButton(): void {
    if (this.secondaryActionVisible) {
      ArcButton({
        options: new ArcButtonOptions({
          label: this.resolveUiText(this.secondaryActionText),
          status: this.secondaryActionEnabled ? ArcButtonStatus.NORMAL : ArcButtonStatus.DISABLED,
          position: ArcButtonPosition.TOP_EDGE,
          styleMode: ArcButtonStyleMode.NORMAL_DARK,
          onClick: (): void => {
            this.handleSecondaryAction();
          }
        })
      })
        .id('message-recorder-secondary-action')
        .width('100%')
        .align(Alignment.Center)
        .alignRules({
          left: { anchor: '__container__', align: HorizontalAlign.Start },
          right: { anchor: '__container__', align: HorizontalAlign.End },
          top: { anchor: '__container__', align: VerticalAlign.Top }
        })
    }
  }

  build() {
    Stack() {
      Image($r('app.media.watch_wallpaper_466'))
        .width('100%')
        .align(Alignment.Center)

      RelativeContainer() {
        Column() {
          this.buildTimerPanel()
        }
        .width('100%')
        .height('100%')
        .padding({
          left: 18,
          right: 18
        })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .alignRules({
          top: { anchor: '__container__', align: VerticalAlign.Top },
          left: { anchor: '__container__', align: HorizontalAlign.Start },
          right: { anchor: '__container__', align: HorizontalAlign.End },
          bottom: { anchor: '__container__', align: VerticalAlign.Bottom }
        })
        this.buildSecondaryActionButton()
        this.buildPrimaryActionButton()
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  private handleRecorderSnapshot(snapshot: VoiceNoteRecorderSnapshot): void {
    if (snapshot.phase === 'recording') {
      this.applyPageState(this.viewModel.createRecordingState(this.currentPageState(), snapshot.elapsedSeconds));
      return;
    }
    if (snapshot.phase === 'stopping') {
      this.applyPageState(this.viewModel.createStoppingState(this.currentPageState(), snapshot.elapsedSeconds));
      return;
    }
    if (snapshot.phase === 'error') {
      this.applyPageState(this.viewModel.createRecordingErrorState(
        this.currentPageState(),
        snapshot.errorMessage,
        snapshot.elapsedSeconds
      ));
    }
  }

  private async requestMicrophonePermission(): Promise<void> {
    this.applyPageState(this.viewModel.createRequestingPermissionState(this.currentPageState()));

    const permissionResult = await this.viewModel.requestMicrophonePermission(this.getAbilityContext());
    if (permissionResult.status === MicrophonePermissionResultStatus.Granted) {
      await this.startRecorderSession();
      return;
    }

    if (permissionResult.status === MicrophonePermissionResultStatus.Denied) {
      this.applyPageState(this.viewModel.createPermissionDeniedState(this.currentPageState()));
      return;
    }

    this.applyPageState(this.viewModel.createPermissionRequestFailedState(
      this.currentPageState(),
      permissionResult.errorMessage
    ));
  }

  private async requestMicrophonePermissionOnSetting(): Promise<void> {
    this.applyPageState(this.viewModel.createRequestingPermissionState(this.currentPageState()));

    const permissionResult = await this.viewModel.requestMicrophonePermissionOnSetting(this.getAbilityContext());
    if (permissionResult.status === MicrophonePermissionResultStatus.Granted) {
      this.applyPageState(this.viewModel.createIdleState(this.currentPageState()));
      return;
    }

    if (permissionResult.status === MicrophonePermissionResultStatus.Denied) {
      this.applyPageState(this.viewModel.createPermissionDeniedState(this.currentPageState()));
      return;
    }

    this.applyPageState(this.viewModel.createPermissionRequestFailedState(
      this.currentPageState(),
      permissionResult.errorMessage
    ));
  }

  private async startRecorderSession(): Promise<void> {
    try {
      const started = await this.viewModel.startRecorderSession(this.getCacheDir());
      if (started) {
        const recorderSnapshot = this.viewModel.getRecorderSnapshot();
        if (recorderSnapshot.phase === 'recording') {
          this.handleRecorderSnapshot(recorderSnapshot);
        } else {
          this.applyPageState(this.viewModel.createRecordingState(this.currentPageState(), 0));
        }
        return;
      }

      if (this.phase === MessageRecorderPhase.RequestingPermission) {
        this.applyPageState(this.viewModel.createRecordingErrorState(
          this.currentPageState(),
          this.resolveResourceText('message_recorder_error_start_failed'),
          0
        ));
      }
    } catch (error) {
      this.applyPageState(this.viewModel.createRecordingErrorState(
        this.currentPageState(),
        String(error),
        0
      ));
    }
  }

  private async stopAndSendRecording(): Promise<void> {
    this.applyPageState(this.viewModel.createStoppingState(this.currentPageState(), this.elapsedSeconds));
    const stopped = await this.viewModel.stopRecorderSession();
    if (!stopped) {
      return;
    }
    this.sendPendingVoiceNote();
  }

  private sendPendingVoiceNote(): void {
    const started = this.viewModel.sendPendingVoiceNoteMessage(this.chatId);
    if (!started) {
      this.applyPageState(this.viewModel.createSendErrorState(
        this.currentPageState(),
        this.resolveResourceText('message_recorder_error_send_unavailable'),
        this.elapsedSeconds
      ));
      return;
    }
    this.applyPageState(this.viewModel.createSendingState(this.currentPageState(), this.elapsedSeconds));
  }

  private async cancelRecordingAndReturn(): Promise<void> {
    await this.viewModel.cancelRecorderSession();
    this.returnToChatDetails(false);
  }

  private returnToChatDetails(requestRefresh: boolean): void {
    const safeChatId = this.chatId.trim();
    if (requestRefresh && safeChatId.length > 0) {
      this.viewModel.requestChatHistory(safeChatId, CHAT_HISTORY_REFRESH_LIMIT);
    }

    try {
      this.getUIContext().getRouter().back();
      return;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'router.back failed, fallback push: %{public}s', String(error));
    }

    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/ChatDetails',
        params: {
          chatId: this.chatId,
          chatTitle: this.chatTitle,
          chatUsername: this.chatUsername
        }
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'returnToChatDetails failed: %{public}s', String(error));
    }
  }

  private getCacheDir(): string {
    return this.getAbilityContext().cacheDir.trim();
  }
}
