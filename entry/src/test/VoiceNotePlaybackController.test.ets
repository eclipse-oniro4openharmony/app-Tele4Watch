import { describe, it, expect } from '@ohos/hypium';
import {
  VoiceNotePlaybackController,
  VoiceNotePlayerEventHandler,
  VoiceNotePlaybackPlayer,
  VoiceNotePlaybackRequest,
  VoiceNotePlaybackSnapshot,
  VoiceNotePlayerState,
  VOICE_NOTE_ERROR_MISSING_FILE_PATH
} from '../main/ets/services/media/VoiceNotePlaybackController';

class FakeVoiceNotePlaybackPlayer implements VoiceNotePlaybackPlayer {
  private stateChangeHandler: ((state: VoiceNotePlayerState) => void) | undefined = undefined;
  private timeUpdateHandler: ((positionMs: number) => void) | undefined = undefined;
  private durationUpdateHandler: ((durationMs: number) => void) | undefined = undefined;
  private errorHandler: ((errorMessage: string) => void) | undefined = undefined;

  readonly calls: string[] = [];
  failLoad: boolean = false;
  emitTimeUpdateDuringLoad: boolean = false;
  loadErrorMessage: string = '';

  setEventHandler(handler: VoiceNotePlayerEventHandler): void {
    this.stateChangeHandler = handler.onStateChange;
    this.timeUpdateHandler = handler.onTimeUpdate;
    this.durationUpdateHandler = handler.onDurationUpdate;
    this.errorHandler = handler.onError;
  }

  async load(request: VoiceNotePlaybackRequest): Promise<number> {
    this.calls.push(`load:${request.messageId}`);
    if (this.loadErrorMessage.length > 0 && this.errorHandler) {
      this.errorHandler(this.loadErrorMessage);
      throw new Error(this.loadErrorMessage);
    }
    if (this.failLoad) {
      throw new Error('Missing local file');
    }
    if (this.emitTimeUpdateDuringLoad && this.timeUpdateHandler) {
      this.timeUpdateHandler(321);
    }
    if (this.durationUpdateHandler) {
      this.durationUpdateHandler(request.durationMs);
    }
    if (this.stateChangeHandler) {
      this.stateChangeHandler('prepared');
    }
    return request.durationMs;
  }

  async play(): Promise<void> {
    this.calls.push('play');
    if (this.stateChangeHandler) {
      this.stateChangeHandler('playing');
    }
  }

  async pause(): Promise<void> {
    this.calls.push('pause');
    if (this.stateChangeHandler) {
      this.stateChangeHandler('paused');
    }
  }

  async stop(): Promise<void> {
    this.calls.push('stop');
    if (this.stateChangeHandler) {
      this.stateChangeHandler('stopped');
    }
  }

  async release(): Promise<void> {
    this.calls.push('release');
    if (this.stateChangeHandler) {
      this.stateChangeHandler('released');
    }
  }

  emitTimeUpdate(positionMs: number): void {
    if (this.timeUpdateHandler) {
      this.timeUpdateHandler(positionMs);
    }
  }

  emitError(errorMessage: string): void {
    if (this.errorHandler) {
      this.errorHandler(errorMessage);
    }
  }

  emitStateChange(state: VoiceNotePlayerState): void {
    if (this.stateChangeHandler) {
      this.stateChangeHandler(state);
    }
  }

  emitDurationUpdate(durationMs: number): void {
    if (this.durationUpdateHandler) {
      this.durationUpdateHandler(durationMs);
    }
  }
}

function buildPlaybackRequest(overrides?: Partial<VoiceNotePlaybackRequest>): VoiceNotePlaybackRequest {
  return {
    'messageId': overrides?.messageId ?? 'voice-1',
    'filePath': overrides?.filePath ?? '/data/storage/el2/base/files/tdlib/files/voice_notes/test.oga',
    'mimeType': overrides?.mimeType ?? 'audio/ogg',
    'durationMs': overrides?.durationMs ?? 15000
  };
}

export default function voiceNotePlaybackControllerTest() {
  describe('VoiceNotePlaybackControllerTest', () => {
    it('shouldStartPlayingNewVoiceNoteAndTrackProgress', 0, async (): Promise<void> => {
      const player = new FakeVoiceNotePlaybackPlayer();
      const controller = new VoiceNotePlaybackController(player);
      let snapshot: VoiceNotePlaybackSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNotePlaybackSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.toggle(buildPlaybackRequest({ messageId: 'voice-10', durationMs: 17000 }));
      player.emitTimeUpdate(2300);

      expect(snapshot.messageId).assertEqual('voice-10');
      expect(snapshot.phase).assertEqual('playing');
      expect(snapshot.durationMs).assertEqual(17000);
      expect(snapshot.positionMs).assertEqual(2300);
      expect(player.calls.join(',')).assertEqual('stop,load:voice-10,play');
    });

    it('shouldPauseWhenTogglingSameVoiceNoteWhilePlaying', 0, async (): Promise<void> => {
      const player = new FakeVoiceNotePlaybackPlayer();
      const controller = new VoiceNotePlaybackController(player);
      let snapshot: VoiceNotePlaybackSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNotePlaybackSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.toggle(buildPlaybackRequest({ messageId: 'voice-11' }));
      await controller.toggle(buildPlaybackRequest({ messageId: 'voice-11' }));

      expect(snapshot.messageId).assertEqual('voice-11');
      expect(snapshot.phase).assertEqual('paused');
      expect(player.calls.join(',')).assertEqual('stop,load:voice-11,play,pause');
    });

    it('shouldExposeErrorForMissingVoiceNotePath', 0, async (): Promise<void> => {
      const player = new FakeVoiceNotePlaybackPlayer();
      const controller = new VoiceNotePlaybackController(player);
      let snapshot: VoiceNotePlaybackSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNotePlaybackSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.toggle(buildPlaybackRequest({ messageId: 'voice-12', filePath: '   ' }));

      expect(snapshot.messageId).assertEqual('voice-12');
      expect(snapshot.phase).assertEqual('error');
      expect(snapshot.errorMessage).assertEqual(VOICE_NOTE_ERROR_MISSING_FILE_PATH);
      expect(player.calls.length).assertEqual(0);
    });

    it('shouldSwitchToErrorWhenRuntimePlayerFailsToLoad', 0, async (): Promise<void> => {
      const player = new FakeVoiceNotePlaybackPlayer();
      player.failLoad = true;
      const controller = new VoiceNotePlaybackController(player);
      let snapshot: VoiceNotePlaybackSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNotePlaybackSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.toggle(buildPlaybackRequest({ messageId: 'voice-13' }));

      expect(snapshot.messageId).assertEqual('voice-13');
      expect(snapshot.phase).assertEqual('error');
      expect(snapshot.errorMessage).assertEqual('Missing local file');
      expect(player.calls.join(',')).assertEqual('stop,load:voice-13');
    });

    it('shouldIgnoreProgressUpdatesWhileLoadingBeforePlaybackStarts', 0, async (): Promise<void> => {
      const player = new FakeVoiceNotePlaybackPlayer();
      player.emitTimeUpdateDuringLoad = true;
      const controller = new VoiceNotePlaybackController(player);
      let snapshot: VoiceNotePlaybackSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNotePlaybackSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.toggle(buildPlaybackRequest({ messageId: 'voice-15', durationMs: 2600 }));

      expect(snapshot.messageId).assertEqual('voice-15');
      expect(snapshot.phase).assertEqual('playing');
      expect(snapshot.durationMs).assertEqual(2600);
      expect(snapshot.positionMs).assertEqual(0);
    });

    it('shouldIgnoreLatePreparedAndProgressEventsAfterErrorSnapshot', 0, async (): Promise<void> => {
      const player = new FakeVoiceNotePlaybackPlayer();
      player.failLoad = true;
      const controller = new VoiceNotePlaybackController(player);
      let snapshot: VoiceNotePlaybackSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNotePlaybackSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.toggle(buildPlaybackRequest({ messageId: 'voice-16', durationMs: 3100 }));
      player.emitStateChange('prepared');
      player.emitDurationUpdate(9999);
      player.emitTimeUpdate(777);

      expect(snapshot.messageId).assertEqual('voice-16');
      expect(snapshot.phase).assertEqual('error');
      expect(snapshot.durationMs).assertEqual(3100);
      expect(snapshot.positionMs).assertEqual(0);
      expect(snapshot.errorMessage).assertEqual('Missing local file');
    });

    it('shouldExposeExplicitErrorWhenPlayerReportsReadFailureDuringLoad', 0, async (): Promise<void> => {
      const player = new FakeVoiceNotePlaybackPlayer();
      player.loadErrorMessage = 'Is a directory';
      const controller = new VoiceNotePlaybackController(player);
      let snapshot: VoiceNotePlaybackSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNotePlaybackSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.toggle(buildPlaybackRequest({ messageId: 'voice-17', durationMs: 2000 }));

      expect(snapshot.messageId).assertEqual('voice-17');
      expect(snapshot.phase).assertEqual('error');
      expect(snapshot.positionMs).assertEqual(0);
      expect(snapshot.durationMs).assertEqual(2000);
      expect(snapshot.errorMessage).assertEqual('Is a directory');
      expect(player.calls.join(',')).assertEqual('stop,load:voice-17');
    });

    it('shouldReleasePlaybackAndReturnToIdleSnapshot', 0, async (): Promise<void> => {
      const player = new FakeVoiceNotePlaybackPlayer();
      const controller = new VoiceNotePlaybackController(player);
      let snapshot: VoiceNotePlaybackSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNotePlaybackSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.toggle(buildPlaybackRequest({ messageId: 'voice-14' }));
      player.emitError('temporary');
      await controller.release();

      expect(snapshot.messageId).assertEqual('');
      expect(snapshot.phase).assertEqual('idle');
      expect(snapshot.positionMs).assertEqual(0);
      expect(snapshot.durationMs).assertEqual(0);
      expect(snapshot.errorMessage).assertEqual('');
      expect(player.calls.join(',')).assertEqual('stop,load:voice-14,play,release');
    });
  });
}
