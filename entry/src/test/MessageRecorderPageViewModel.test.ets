import { Context } from '@ohos.abilityAccessCtrl';
import { describe, expect, it } from '@ohos/hypium';
import { MessageRecorderErrorKind, MessageRecorderPhase } from '../main/ets/models/chat/MessageRecorderPageState';
import {
  MessageRecorderDraftStore,
  MessageRecorderPageViewModel,
  MessageRecorderPermissionGateway,
  MessageRecorderRecorderSession,
  MessageRecorderTdGateway
} from '../main/ets/viewmodel/MessageRecorderPageViewModel';
import {
  MicrophonePermissionResult,
  MicrophonePermissionResultStatus
} from '../main/ets/services/permissions/MicrophonePermissionService';
import {
  VoiceNoteRecorderSnapshot,
  VoiceNoteRecordingResult,
  createIdleVoiceNoteRecorderSnapshot
} from '../main/ets/services/media/VoiceNoteRecorderController';
import { VoiceNoteDraftPayload } from '../main/ets/services/media/VoiceNoteDraftStore';

class FakeMessageRecorderTdGateway implements MessageRecorderTdGateway {
  readonly calls: string[] = [];
  sendResult: boolean = true;

  setAuthStateListener(_listener: (state: string) => void): void {
    this.calls.push('set-auth-listener');
  }

  getAuthorizationStateName(): string {
    return 'authorizationStateReady';
  }

  setMessageSendResultListener(_listener: (chatId: string, ok: boolean, errorMessage: string) => void): void {
    this.calls.push('set-send-result-listener');
  }

  sendChatVoiceNoteMessage(chatId: string, filePath: string, durationSec: number, waveform: ArrayBuffer): boolean {
    const waveformLength = new Uint8Array(waveform).length;
    this.calls.push(`send:${chatId}:${filePath}:${durationSec}:${waveformLength}`);
    return this.sendResult;
  }

  requestChatHistory(chatId: string, limit: number): void {
    this.calls.push(`history:${chatId}:${limit}`);
  }
}

class FakeMessageRecorderPermissionGateway implements MessageRecorderPermissionGateway {
  async requestPermission(_context: Context): Promise<MicrophonePermissionResult> {
    return { status: MicrophonePermissionResultStatus.Granted, errorMessage: '' };
  }

  async requestPermissionOnSetting(_context: Context): Promise<MicrophonePermissionResult> {
    return { status: MicrophonePermissionResultStatus.Granted, errorMessage: '' };
  }
}

class FakeMessageRecorderRecorderSession implements MessageRecorderRecorderSession {
  readonly calls: string[] = [];
  startResult: boolean = true;
  stopResult: VoiceNoteRecordingResult | undefined = undefined;

  setListener(listener: ((snapshot: VoiceNoteRecorderSnapshot) => void) | undefined): void {
    this.calls.push(listener ? 'set-listener' : 'clear-listener');
  }

  getSnapshot(): VoiceNoteRecorderSnapshot {
    return createIdleVoiceNoteRecorderSnapshot();
  }

  async start(filePath: string): Promise<boolean> {
    this.calls.push(`start:${filePath}`);
    return this.startResult;
  }

  async stop(): Promise<VoiceNoteRecordingResult | undefined> {
    this.calls.push('stop');
    return this.stopResult;
  }

  async cancel(): Promise<void> {
    this.calls.push('cancel');
  }

  async release(): Promise<void> {
    this.calls.push('release');
  }
}

class FakeMessageRecorderDraftStore implements MessageRecorderDraftStore {
  readonly calls: string[] = [];
  outputPath: string = '/cache/runtime/voice_notes/voice-note-fake.oga';
  pendingPayload: VoiceNoteDraftPayload | undefined = undefined;

  createOutputPath(cacheDir: string): string {
    this.calls.push(`create:${cacheDir}`);
    return this.outputPath;
  }

  storePending(result: VoiceNoteRecordingResult): void {
    const waveformLength = new Uint8Array(result.waveform).length;
    this.calls.push(`store:${result.filePath}:${result.durationSec}:${waveformLength}`);
    this.pendingPayload = {
      filePath: result.filePath,
      durationSec: result.durationSec,
      waveform: result.waveform
    };
  }

  getPendingPayload(): VoiceNoteDraftPayload | undefined {
    this.calls.push('get');
    return this.pendingPayload;
  }

  clearPending(deleteFile: boolean): void {
    this.calls.push(`clear:${deleteFile}`);
    this.pendingPayload = undefined;
  }
}

function createRecordingResult(filePath: string, durationSec: number, waveformLength: number): VoiceNoteRecordingResult {
  const waveform = new ArrayBuffer(waveformLength);
  const bytes = new Uint8Array(waveform);
  for (let index = 0; index < waveformLength; index += 1) {
    bytes[index] = (index + 1) & 0xff;
  }
  return { filePath: filePath, durationSec: durationSec, waveform: waveform };
}

export default function messageRecorderPageViewModelTest() {
  describe('MessageRecorderPageViewModelTest', () => {
    it('shouldCreateIdleInitialState', 0, () => {
      const viewModel = new MessageRecorderPageViewModel();

      const initialState = viewModel.createInitialState();

      expect(initialState.chatId).assertEqual('');
      expect(initialState.phase).assertEqual(MessageRecorderPhase.Idle);
      expect(initialState.errorKind).assertEqual(MessageRecorderErrorKind.None);
      expect(initialState.elapsedSeconds).assertEqual(0);
      expect(initialState.statusText.resourceName).assertEqual('message_recorder_status_idle');
      expect(initialState.errorText.resourceName).assertEqual('');
      expect(initialState.primaryActionText.resourceName).assertEqual('message_recorder_action_start');
      expect(initialState.secondaryActionVisible).assertFalse();
    });

    it('shouldApplyRouteWithoutDroppingExistingTitleFallback', 0, () => {
      const viewModel = new MessageRecorderPageViewModel();
      const initialState = viewModel.createInitialState();
      const titledState = viewModel.applyRoute(initialState, 'chat-15', 'OSTC Team', 'ostc_team');

      const routedState = viewModel.applyRoute(titledState, 'chat-15', '', 'new_handle');

      expect(routedState.chatId).assertEqual('chat-15');
      expect(routedState.chatTitle).assertEqual('OSTC Team');
      expect(routedState.chatUsername).assertEqual('new_handle');
      expect(routedState.phase).assertEqual(MessageRecorderPhase.Idle);
      expect(routedState.errorKind).assertEqual(MessageRecorderErrorKind.None);
    });

    it('shouldCreateRequestingPermissionState', 0, () => {
      const viewModel = new MessageRecorderPageViewModel();
      const initialState = viewModel.applyRoute(viewModel.createInitialState(), 'chat-20', 'Recorder', 'recorder');

      const requestingState = viewModel.createRequestingPermissionState(initialState);

      expect(requestingState.phase).assertEqual(MessageRecorderPhase.RequestingPermission);
      expect(requestingState.statusText.resourceName).assertEqual('message_recorder_status_requesting_permission');
      expect(requestingState.primaryActionEnabled).assertFalse();
      expect(requestingState.secondaryActionVisible).assertFalse();
    });

    it('shouldCreateRecordingStateWithStopAndCancelActions', 0, () => {
      const viewModel = new MessageRecorderPageViewModel();
      const initialState = viewModel.applyRoute(viewModel.createInitialState(), 'chat-21', 'Recorder', 'recorder');

      const recordingState = viewModel.createRecordingState(initialState, 7);

      expect(recordingState.phase).assertEqual(MessageRecorderPhase.Recording);
      expect(recordingState.errorKind).assertEqual(MessageRecorderErrorKind.None);
      expect(recordingState.elapsedSeconds).assertEqual(7);
      expect(recordingState.primaryActionText.resourceName).assertEqual('message_recorder_action_send');
      expect(recordingState.secondaryActionText.resourceName).assertEqual('message_recorder_action_cancel');
      expect(recordingState.secondaryActionVisible).assertTrue();
    });

    it('shouldCreateStoppingAndSendingStatesWithoutActions', 0, () => {
      const viewModel = new MessageRecorderPageViewModel();
      const baseState = viewModel.applyRoute(viewModel.createInitialState(), 'chat-22', 'Recorder', 'recorder');

      const stoppingState = viewModel.createStoppingState(baseState, 11);
      const sendingState = viewModel.createSendingState(baseState, 11);

      expect(stoppingState.phase).assertEqual(MessageRecorderPhase.Stopping);
      expect(stoppingState.primaryActionEnabled).assertFalse();
      expect(stoppingState.secondaryActionVisible).assertFalse();
      expect(stoppingState.elapsedSeconds).assertEqual(11);

      expect(sendingState.phase).assertEqual(MessageRecorderPhase.Sending);
      expect(sendingState.primaryActionEnabled).assertFalse();
      expect(sendingState.secondaryActionVisible).assertFalse();
      expect(sendingState.elapsedSeconds).assertEqual(11);
    });

    it('shouldCreatePermissionDeniedErrorStateWithSettingsAction', 0, () => {
      const viewModel = new MessageRecorderPageViewModel();
      const currentState = viewModel.applyRoute(viewModel.createInitialState(), 'chat-23', 'Recorder', 'recorder');

      const deniedState = viewModel.createPermissionDeniedState(currentState);

      expect(deniedState.phase).assertEqual(MessageRecorderPhase.Error);
      expect(deniedState.errorKind).assertEqual(MessageRecorderErrorKind.PermissionDenied);
      expect(deniedState.statusText.resourceName).assertEqual('message_recorder_status_permission_denied');
      expect(deniedState.errorText.resourceName).assertEqual('message_recorder_error_permission_denied');
      expect(deniedState.primaryActionText.resourceName).assertEqual('message_recorder_action_open_settings');
    });

    it('shouldTrimLongPermissionFailureMessage', 0, () => {
      const viewModel = new MessageRecorderPageViewModel();
      const currentState = viewModel.applyRoute(viewModel.createInitialState(), 'chat-24', 'Recorder', 'recorder');
      const longErrorMessage =
        'Permission request failed because the platform returned one unexpectedly long diagnostic message';

      const failedState = viewModel.createPermissionRequestFailedState(currentState, longErrorMessage);

      expect(failedState.phase).assertEqual(MessageRecorderPhase.Error);
      expect(failedState.errorKind).assertEqual(MessageRecorderErrorKind.RequestFailed);
      expect(failedState.statusText.resourceName).assertEqual('message_recorder_status_error');
      expect(failedState.errorText.resourceName).assertEqual('');
      expect(failedState.errorText.rawText).assertEqual('Permission request failed because the platform return...');
    });

    it('shouldCreateRecordingErrorStateWithResetAction', 0, () => {
      const viewModel = new MessageRecorderPageViewModel();
      const currentState = viewModel.applyRoute(viewModel.createInitialState(), 'chat-25', 'Recorder', 'recorder');

      const errorState = viewModel.createRecordingErrorState(currentState, '', 3);

      expect(errorState.phase).assertEqual(MessageRecorderPhase.Error);
      expect(errorState.errorKind).assertEqual(MessageRecorderErrorKind.RecordingFailed);
      expect(errorState.elapsedSeconds).assertEqual(3);
      expect(errorState.errorText.resourceName).assertEqual('message_recorder_error_recording_failed');
      expect(errorState.primaryActionText.resourceName).assertEqual('message_recorder_action_reset');
    });

    it('shouldCreateSendErrorStateWithRetryAction', 0, () => {
      const viewModel = new MessageRecorderPageViewModel();
      const currentState = viewModel.applyRoute(viewModel.createInitialState(), 'chat-26', 'Recorder', 'recorder');

      const errorState = viewModel.createSendErrorState(currentState, 'TDLib send failed', 12);

      expect(errorState.phase).assertEqual(MessageRecorderPhase.Error);
      expect(errorState.errorKind).assertEqual(MessageRecorderErrorKind.SendFailed);
      expect(errorState.elapsedSeconds).assertEqual(12);
      expect(errorState.errorText.rawText).assertEqual('TDLib send failed');
      expect(errorState.primaryActionText.resourceName).assertEqual('message_recorder_action_retry_send');
    });

    it('shouldCreateIdleStateAfterReset', 0, () => {
      const viewModel = new MessageRecorderPageViewModel();
      const recordingState = viewModel.createRecordingState(
        viewModel.applyRoute(viewModel.createInitialState(), 'chat-27', 'Recorder', 'recorder'),
        4
      );

      const idleState = viewModel.createIdleState(recordingState);

      expect(idleState.phase).assertEqual(MessageRecorderPhase.Idle);
      expect(idleState.elapsedSeconds).assertEqual(0);
      expect(idleState.secondaryActionVisible).assertFalse();
      expect(idleState.primaryActionText.resourceName).assertEqual('message_recorder_action_start');
    });

    it('shouldClearPendingDraftAndStartRecorderOnStartSession', 0, async (): Promise<void> => {
      const tdGateway = new FakeMessageRecorderTdGateway();
      const permissionGateway = new FakeMessageRecorderPermissionGateway();
      const recorderSession = new FakeMessageRecorderRecorderSession();
      const draftStore = new FakeMessageRecorderDraftStore();
      draftStore.outputPath = '/cache/runtime/voice_notes/voice-note-1.oga';
      const viewModel = new MessageRecorderPageViewModel(tdGateway, permissionGateway, recorderSession, draftStore);

      const started = await viewModel.startRecorderSession('/cache/runtime');

      expect(started).assertTrue();
      expect(draftStore.calls.join(',')).assertEqual('clear:true,create:/cache/runtime');
      expect(recorderSession.calls.join(',')).assertEqual('start:/cache/runtime/voice_notes/voice-note-1.oga');
    });

    it('shouldStorePendingAndReturnTrueWhenStopSessionYieldsResult', 0, async (): Promise<void> => {
      const tdGateway = new FakeMessageRecorderTdGateway();
      const permissionGateway = new FakeMessageRecorderPermissionGateway();
      const recorderSession = new FakeMessageRecorderRecorderSession();
      const draftStore = new FakeMessageRecorderDraftStore();
      recorderSession.stopResult = createRecordingResult('/cache/runtime/voice_notes/voice-note-2.oga', 9, 4);
      const viewModel = new MessageRecorderPageViewModel(tdGateway, permissionGateway, recorderSession, draftStore);

      const stored = await viewModel.stopRecorderSession();

      expect(stored).assertTrue();
      expect(recorderSession.calls.join(',')).assertEqual('stop');
      expect(draftStore.calls.join(',')).assertEqual('store:/cache/runtime/voice_notes/voice-note-2.oga:9:4');
    });

    it('shouldReturnFalseAndSkipDraftStoreWhenStopSessionYieldsNoResult', 0, async (): Promise<void> => {
      const tdGateway = new FakeMessageRecorderTdGateway();
      const permissionGateway = new FakeMessageRecorderPermissionGateway();
      const recorderSession = new FakeMessageRecorderRecorderSession();
      const draftStore = new FakeMessageRecorderDraftStore();
      recorderSession.stopResult = undefined;
      const viewModel = new MessageRecorderPageViewModel(tdGateway, permissionGateway, recorderSession, draftStore);

      const stored = await viewModel.stopRecorderSession();

      expect(stored).assertFalse();
      expect(recorderSession.calls.join(',')).assertEqual('stop');
      expect(draftStore.calls.length).assertEqual(0);
    });

    it('shouldCancelRecorderAndClearPendingDraftOnCancelSession', 0, async (): Promise<void> => {
      const tdGateway = new FakeMessageRecorderTdGateway();
      const permissionGateway = new FakeMessageRecorderPermissionGateway();
      const recorderSession = new FakeMessageRecorderRecorderSession();
      const draftStore = new FakeMessageRecorderDraftStore();
      const viewModel = new MessageRecorderPageViewModel(tdGateway, permissionGateway, recorderSession, draftStore);

      await viewModel.cancelRecorderSession();

      expect(recorderSession.calls.join(',')).assertEqual('cancel');
      expect(draftStore.calls.join(',')).assertEqual('clear:true');
    });

    it('shouldSendPendingPayloadViaTdGatewayWhenAvailable', 0, () => {
      const tdGateway = new FakeMessageRecorderTdGateway();
      const permissionGateway = new FakeMessageRecorderPermissionGateway();
      const recorderSession = new FakeMessageRecorderRecorderSession();
      const draftStore = new FakeMessageRecorderDraftStore();
      const pendingWaveform = new ArrayBuffer(3);
      draftStore.pendingPayload = {
        filePath: '/cache/runtime/voice_notes/ready.oga',
        durationSec: 11,
        waveform: pendingWaveform
      };
      tdGateway.sendResult = true;
      const viewModel = new MessageRecorderPageViewModel(tdGateway, permissionGateway, recorderSession, draftStore);

      const sent = viewModel.sendPendingVoiceNoteMessage('chat-99');

      expect(sent).assertTrue();
      expect(draftStore.calls.join(',')).assertEqual('get');
      expect(tdGateway.calls.join(',')).assertEqual('send:chat-99:/cache/runtime/voice_notes/ready.oga:11:3');
    });

    it('shouldReturnFalseAndSkipTdSendWhenNoPendingPayload', 0, () => {
      const tdGateway = new FakeMessageRecorderTdGateway();
      const permissionGateway = new FakeMessageRecorderPermissionGateway();
      const recorderSession = new FakeMessageRecorderRecorderSession();
      const draftStore = new FakeMessageRecorderDraftStore();
      draftStore.pendingPayload = undefined;
      const viewModel = new MessageRecorderPageViewModel(tdGateway, permissionGateway, recorderSession, draftStore);

      const sent = viewModel.sendPendingVoiceNoteMessage('chat-99');

      expect(sent).assertFalse();
      expect(draftStore.calls.join(',')).assertEqual('get');
      expect(tdGateway.calls.length).assertEqual(0);
    });

    it('shouldCancelRecorderAndClearPendingWhenReleasingDuringRecording', 0, async (): Promise<void> => {
      const tdGateway = new FakeMessageRecorderTdGateway();
      const permissionGateway = new FakeMessageRecorderPermissionGateway();
      const recorderSession = new FakeMessageRecorderRecorderSession();
      const draftStore = new FakeMessageRecorderDraftStore();
      const viewModel = new MessageRecorderPageViewModel(tdGateway, permissionGateway, recorderSession, draftStore);

      await viewModel.releaseRecorderSession(MessageRecorderPhase.Recording);

      expect(recorderSession.calls.join(',')).assertEqual('cancel');
      expect(draftStore.calls.join(',')).assertEqual('clear:true');
    });

    it('shouldCancelRecorderAndClearPendingWhenReleasingDuringStopping', 0, async (): Promise<void> => {
      const tdGateway = new FakeMessageRecorderTdGateway();
      const permissionGateway = new FakeMessageRecorderPermissionGateway();
      const recorderSession = new FakeMessageRecorderRecorderSession();
      const draftStore = new FakeMessageRecorderDraftStore();
      const viewModel = new MessageRecorderPageViewModel(tdGateway, permissionGateway, recorderSession, draftStore);

      await viewModel.releaseRecorderSession(MessageRecorderPhase.Stopping);

      expect(recorderSession.calls.join(',')).assertEqual('cancel');
      expect(draftStore.calls.join(',')).assertEqual('clear:true');
    });

    it('shouldReleaseRecorderButPreservePendingWhenReleasingDuringSending', 0, async (): Promise<void> => {
      const tdGateway = new FakeMessageRecorderTdGateway();
      const permissionGateway = new FakeMessageRecorderPermissionGateway();
      const recorderSession = new FakeMessageRecorderRecorderSession();
      const draftStore = new FakeMessageRecorderDraftStore();
      const viewModel = new MessageRecorderPageViewModel(tdGateway, permissionGateway, recorderSession, draftStore);

      await viewModel.releaseRecorderSession(MessageRecorderPhase.Sending);

      expect(recorderSession.calls.join(',')).assertEqual('release');
      expect(draftStore.calls.length).assertEqual(0);
    });

    it('shouldReleaseRecorderAndClearPendingWhenReleasingFromIdle', 0, async (): Promise<void> => {
      const tdGateway = new FakeMessageRecorderTdGateway();
      const permissionGateway = new FakeMessageRecorderPermissionGateway();
      const recorderSession = new FakeMessageRecorderRecorderSession();
      const draftStore = new FakeMessageRecorderDraftStore();
      const viewModel = new MessageRecorderPageViewModel(tdGateway, permissionGateway, recorderSession, draftStore);

      await viewModel.releaseRecorderSession(MessageRecorderPhase.Idle);

      expect(recorderSession.calls.join(',')).assertEqual('release');
      expect(draftStore.calls.join(',')).assertEqual('clear:true');
    });

    it('shouldRouteStopSessionResultThroughDraftStoreToTdGateway', 0, async (): Promise<void> => {
      const tdGateway = new FakeMessageRecorderTdGateway();
      const permissionGateway = new FakeMessageRecorderPermissionGateway();
      const recorderSession = new FakeMessageRecorderRecorderSession();
      const draftStore = new FakeMessageRecorderDraftStore();
      recorderSession.stopResult = createRecordingResult('/cache/runtime/voice_notes/round-trip.oga', 13, 5);
      tdGateway.sendResult = true;
      const viewModel = new MessageRecorderPageViewModel(tdGateway, permissionGateway, recorderSession, draftStore);

      const stored = await viewModel.stopRecorderSession();
      const sent = viewModel.sendPendingVoiceNoteMessage('chat-77');

      expect(stored).assertTrue();
      expect(sent).assertTrue();
      expect(recorderSession.calls.join(',')).assertEqual('stop');
      // storePending was fed the recorder result, then getPendingPayload handed the same payload to the gateway.
      expect(draftStore.calls.join(',')).assertEqual('store:/cache/runtime/voice_notes/round-trip.oga:13:5,get');
      expect(tdGateway.calls.join(',')).assertEqual('send:chat-77:/cache/runtime/voice_notes/round-trip.oga:13:5');
    });

    it('shouldDelegateClearPendingVoiceNoteToDraftStore', 0, () => {
      const tdGateway = new FakeMessageRecorderTdGateway();
      const permissionGateway = new FakeMessageRecorderPermissionGateway();
      const recorderSession = new FakeMessageRecorderRecorderSession();
      const draftStore = new FakeMessageRecorderDraftStore();
      const viewModel = new MessageRecorderPageViewModel(tdGateway, permissionGateway, recorderSession, draftStore);

      viewModel.clearPendingVoiceNote(false);

      expect(draftStore.calls.join(',')).assertEqual('clear:false');
    });
  });
}
