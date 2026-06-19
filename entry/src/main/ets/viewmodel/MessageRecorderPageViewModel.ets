import { Context } from '@ohos.abilityAccessCtrl';
import { tdClient } from '../services/td/TdClient';
import {
  MessageRecorderErrorKind,
  MessageRecorderPageState,
  MessageRecorderPhase
} from '../models/chat/MessageRecorderPageState';
import { UiTextValue, createEmptyUiTextValue, createRawUiText, createResourceUiText } from '../models/ui/UiTextValue';
import {
  MicrophonePermissionResult,
  MicrophonePermissionService
} from '../services/permissions/MicrophonePermissionService';
import {
  VoiceNoteRecorderController,
  VoiceNoteRecordingResult,
  VoiceNoteRecorderSnapshot
} from '../services/media/VoiceNoteRecorderController';
import { VoiceNoteDraftPayload, VoiceNoteDraftStore } from '../services/media/VoiceNoteDraftStore';

const ERROR_MESSAGE_MAX_LENGTH: number = 56;

export interface MessageRecorderTdGateway {
  'setAuthStateListener': (listener: (state: string) => void) => void;
  'getAuthorizationStateName': () => string;
  'setMessageSendResultListener': (listener: (chatId: string, ok: boolean, errorMessage: string) => void) => void;
  'sendChatVoiceNoteMessage': (chatId: string, filePath: string, durationSec: number, waveform: ArrayBuffer) => boolean;
  'requestChatHistory': (chatId: string, limit: number) => void;
}

export interface MessageRecorderPermissionGateway {
  'requestPermission': (context: Context) => Promise<MicrophonePermissionResult>;
  'requestPermissionOnSetting': (context: Context) => Promise<MicrophonePermissionResult>;
}

export interface MessageRecorderRecorderSession {
  'setListener': (listener: ((snapshot: VoiceNoteRecorderSnapshot) => void) | undefined) => void;
  'getSnapshot': () => VoiceNoteRecorderSnapshot;
  'start': (filePath: string) => Promise<boolean>;
  'stop': () => Promise<VoiceNoteRecordingResult | undefined>;
  'cancel': () => Promise<void>;
  'release': () => Promise<void>;
}

export interface MessageRecorderDraftStore {
  'createOutputPath': (cacheDir: string) => string;
  'storePending': (result: VoiceNoteRecordingResult) => void;
  'getPendingPayload': () => VoiceNoteDraftPayload | undefined;
  'clearPending': (deleteFile: boolean) => void;
}

/**
 * Builds routed message-recorder states and delegates TDLib operations.
 */
export class MessageRecorderPageViewModel {
  private readonly tdGateway: MessageRecorderTdGateway;
  private readonly microphonePermissionGateway: MessageRecorderPermissionGateway;
  private readonly recorderSession: MessageRecorderRecorderSession;
  private readonly draftStore: MessageRecorderDraftStore;

  constructor(
    tdGateway?: MessageRecorderTdGateway,
    microphonePermissionGateway?: MessageRecorderPermissionGateway,
    recorderSession?: MessageRecorderRecorderSession,
    draftStore?: MessageRecorderDraftStore
  ) {
    this.tdGateway = tdGateway ? tdGateway : tdClient;
    this.microphonePermissionGateway = microphonePermissionGateway
      ? microphonePermissionGateway
      : new MicrophonePermissionService();
    this.recorderSession = recorderSession ? recorderSession : new VoiceNoteRecorderController();
    this.draftStore = draftStore ? draftStore : new VoiceNoteDraftStore();
  }

  setAuthStateListener(listener: (state: string) => void): void {
    this.tdGateway.setAuthStateListener(listener);
  }

  getAuthorizationStateName(): string {
    return this.tdGateway.getAuthorizationStateName();
  }

  setMessageSendResultListener(listener: (chatId: string, ok: boolean, errorMessage: string) => void): void {
    this.tdGateway.setMessageSendResultListener(listener);
  }

  clearMessageSendResultListener(): void {
    this.tdGateway.setMessageSendResultListener((_chatId: string, _ok: boolean, _errorMessage: string): void => {
      // Intentionally reset listener to avoid mutating state after page is gone.
    });
  }

  setRecorderSnapshotListener(listener: ((snapshot: VoiceNoteRecorderSnapshot) => void) | undefined): void {
    this.recorderSession.setListener(listener);
  }

  getRecorderSnapshot(): VoiceNoteRecorderSnapshot {
    return this.recorderSession.getSnapshot();
  }

  requestMicrophonePermission(context: Context): Promise<MicrophonePermissionResult> {
    return this.microphonePermissionGateway.requestPermission(context);
  }

  requestMicrophonePermissionOnSetting(context: Context): Promise<MicrophonePermissionResult> {
    return this.microphonePermissionGateway.requestPermissionOnSetting(context);
  }

  async startRecorderSession(cacheDir: string): Promise<boolean> {
    this.draftStore.clearPending(true);
    const outputPath = this.draftStore.createOutputPath(cacheDir);
    return this.recorderSession.start(outputPath);
  }

  async stopRecorderSession(): Promise<boolean> {
    const result = await this.recorderSession.stop();
    if (!result) {
      return false;
    }
    this.draftStore.storePending(result);
    return true;
  }

  clearPendingVoiceNote(deleteFile: boolean): void {
    this.draftStore.clearPending(deleteFile);
  }

  async cancelRecorderSession(): Promise<void> {
    await this.recorderSession.cancel();
    this.draftStore.clearPending(true);
  }

  async releaseRecorderSession(currentPhase: MessageRecorderPhase): Promise<void> {
    if (currentPhase === MessageRecorderPhase.Recording || currentPhase === MessageRecorderPhase.Stopping) {
      await this.recorderSession.cancel();
    } else {
      await this.recorderSession.release();
    }

    if (currentPhase !== MessageRecorderPhase.Sending) {
      this.draftStore.clearPending(true);
    }
  }

  sendPendingVoiceNoteMessage(chatId: string): boolean {
    const payload = this.draftStore.getPendingPayload();
    if (!payload) {
      return false;
    }
    return this.tdGateway.sendChatVoiceNoteMessage(
      chatId,
      payload.filePath,
      payload.durationSec,
      payload.waveform
    );
  }

  requestChatHistory(chatId: string, limit: number): void {
    this.tdGateway.requestChatHistory(chatId, limit);
  }

  createInitialState(): MessageRecorderPageState {
    return {
      chatId: '',
      chatTitle: '',
      chatUsername: '',
      phase: MessageRecorderPhase.Idle,
      errorKind: MessageRecorderErrorKind.None,
      elapsedSeconds: 0,
      statusText: createResourceUiText('message_recorder_status_idle'),
      errorText: createEmptyUiTextValue(),
      primaryActionText: createResourceUiText('message_recorder_action_start'),
      secondaryActionText: createEmptyUiTextValue(),
      primaryActionEnabled: true,
      secondaryActionEnabled: false,
      secondaryActionVisible: false
    };
  }

  applyRoute(
    currentState: MessageRecorderPageState,
    chatId: string,
    chatTitle: string,
    chatUsername: string
  ): MessageRecorderPageState {
    return {
      chatId: chatId,
      chatTitle: chatTitle.length > 0 ? chatTitle : currentState.chatTitle,
      chatUsername: chatUsername,
      phase: currentState.phase,
      errorKind: currentState.errorKind,
      elapsedSeconds: currentState.elapsedSeconds,
      statusText: currentState.statusText,
      errorText: currentState.errorText,
      primaryActionText: currentState.primaryActionText,
      secondaryActionText: currentState.secondaryActionText,
      primaryActionEnabled: currentState.primaryActionEnabled,
      secondaryActionEnabled: currentState.secondaryActionEnabled,
      secondaryActionVisible: currentState.secondaryActionVisible
    };
  }

  createIdleState(currentState: MessageRecorderPageState): MessageRecorderPageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      phase: MessageRecorderPhase.Idle,
      errorKind: MessageRecorderErrorKind.None,
      elapsedSeconds: 0,
      statusText: createResourceUiText('message_recorder_status_idle'),
      errorText: createEmptyUiTextValue(),
      primaryActionText: createResourceUiText('message_recorder_action_start'),
      secondaryActionText: createEmptyUiTextValue(),
      primaryActionEnabled: true,
      secondaryActionEnabled: false,
      secondaryActionVisible: false
    };
  }

  createRequestingPermissionState(currentState: MessageRecorderPageState): MessageRecorderPageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      phase: MessageRecorderPhase.RequestingPermission,
      errorKind: MessageRecorderErrorKind.None,
      elapsedSeconds: 0,
      statusText: createResourceUiText('message_recorder_status_requesting_permission'),
      errorText: createEmptyUiTextValue(),
      primaryActionText: createResourceUiText('message_recorder_action_waiting'),
      secondaryActionText: createEmptyUiTextValue(),
      primaryActionEnabled: false,
      secondaryActionEnabled: false,
      secondaryActionVisible: false
    };
  }

  createRecordingState(currentState: MessageRecorderPageState, elapsedSeconds: number): MessageRecorderPageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      phase: MessageRecorderPhase.Recording,
      errorKind: MessageRecorderErrorKind.None,
      elapsedSeconds: elapsedSeconds >= 0 ? elapsedSeconds : 0,
      statusText: createResourceUiText('message_recorder_status_recording'),
      errorText: createEmptyUiTextValue(),
      primaryActionText: createResourceUiText('message_recorder_action_send'),
      secondaryActionText: createResourceUiText('message_recorder_action_cancel'),
      primaryActionEnabled: true,
      secondaryActionEnabled: true,
      secondaryActionVisible: true
    };
  }

  createStoppingState(currentState: MessageRecorderPageState, elapsedSeconds: number): MessageRecorderPageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      phase: MessageRecorderPhase.Stopping,
      errorKind: MessageRecorderErrorKind.None,
      elapsedSeconds: elapsedSeconds >= 0 ? elapsedSeconds : 0,
      statusText: createResourceUiText('message_recorder_status_stopping'),
      errorText: createEmptyUiTextValue(),
      primaryActionText: createResourceUiText('message_recorder_action_waiting'),
      secondaryActionText: createEmptyUiTextValue(),
      primaryActionEnabled: false,
      secondaryActionEnabled: false,
      secondaryActionVisible: false
    };
  }

  createSendingState(currentState: MessageRecorderPageState, elapsedSeconds: number): MessageRecorderPageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      phase: MessageRecorderPhase.Sending,
      errorKind: MessageRecorderErrorKind.None,
      elapsedSeconds: elapsedSeconds >= 0 ? elapsedSeconds : 0,
      statusText: createResourceUiText('message_recorder_status_sending'),
      errorText: createEmptyUiTextValue(),
      primaryActionText: createResourceUiText('message_recorder_action_waiting'),
      secondaryActionText: createEmptyUiTextValue(),
      primaryActionEnabled: false,
      secondaryActionEnabled: false,
      secondaryActionVisible: false
    };
  }

  createPermissionDeniedState(currentState: MessageRecorderPageState): MessageRecorderPageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      phase: MessageRecorderPhase.Error,
      errorKind: MessageRecorderErrorKind.PermissionDenied,
      elapsedSeconds: 0,
      statusText: createResourceUiText('message_recorder_status_permission_denied'),
      errorText: createResourceUiText('message_recorder_error_permission_denied'),
      primaryActionText: createResourceUiText('message_recorder_action_open_settings'),
      secondaryActionText: createEmptyUiTextValue(),
      primaryActionEnabled: true,
      secondaryActionEnabled: false,
      secondaryActionVisible: false
    };
  }

  createPermissionRequestFailedState(currentState: MessageRecorderPageState, errorMessage: string): MessageRecorderPageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      phase: MessageRecorderPhase.Error,
      errorKind: MessageRecorderErrorKind.RequestFailed,
      elapsedSeconds: 0,
      statusText: createResourceUiText('message_recorder_status_error'),
      errorText: this.mapErrorText(errorMessage, 'message_recorder_error_request_failed'),
      primaryActionText: createResourceUiText('message_recorder_action_reset'),
      secondaryActionText: createEmptyUiTextValue(),
      primaryActionEnabled: true,
      secondaryActionEnabled: false,
      secondaryActionVisible: false
    };
  }

  createRecordingErrorState(
    currentState: MessageRecorderPageState,
    errorMessage: string,
    elapsedSeconds: number
  ): MessageRecorderPageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      phase: MessageRecorderPhase.Error,
      errorKind: MessageRecorderErrorKind.RecordingFailed,
      elapsedSeconds: elapsedSeconds >= 0 ? elapsedSeconds : 0,
      statusText: createResourceUiText('message_recorder_status_error'),
      errorText: this.mapErrorText(errorMessage, 'message_recorder_error_recording_failed'),
      primaryActionText: createResourceUiText('message_recorder_action_reset'),
      secondaryActionText: createEmptyUiTextValue(),
      primaryActionEnabled: true,
      secondaryActionEnabled: false,
      secondaryActionVisible: false
    };
  }

  createSendErrorState(
    currentState: MessageRecorderPageState,
    errorMessage: string,
    elapsedSeconds: number
  ): MessageRecorderPageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      phase: MessageRecorderPhase.Error,
      errorKind: MessageRecorderErrorKind.SendFailed,
      elapsedSeconds: elapsedSeconds >= 0 ? elapsedSeconds : 0,
      statusText: createResourceUiText('message_recorder_status_error'),
      errorText: this.mapErrorText(errorMessage, 'message_recorder_error_send_failed'),
      primaryActionText: createResourceUiText('message_recorder_action_retry_send'),
      secondaryActionText: createEmptyUiTextValue(),
      primaryActionEnabled: true,
      secondaryActionEnabled: false,
      secondaryActionVisible: false
    };
  }

  private mapErrorText(errorMessage: string, fallbackResourceName: string): UiTextValue {
    const trimmedMessage = errorMessage.trim();
    if (trimmedMessage.length === 0) {
      return createResourceUiText(fallbackResourceName);
    }

    if (trimmedMessage.length <= ERROR_MESSAGE_MAX_LENGTH) {
      return createRawUiText(trimmedMessage);
    }

    return createRawUiText(`${trimmedMessage.substring(0, ERROR_MESSAGE_MAX_LENGTH - 3)}...`);
  }
}
