import { describe, it, expect } from '@ohos/hypium';
import {
  createIdleMediaViewerPlaybackSnapshot,
  MEDIA_VIEWER_ERROR_MISSING_FILE_PATH,
  MEDIA_VIEWER_ERROR_MISSING_SURFACE,
  MediaViewerPlaybackController,
  MediaViewerPlaybackPlayer,
  MediaViewerPlaybackRequest,
  MediaViewerPlaybackSnapshot,
  MediaViewerPlayerEventHandler,
  MediaViewerPlayerState
} from '../main/ets/services/media/MediaViewerPlaybackController';

class FakeMediaViewerPlaybackPlayer implements MediaViewerPlaybackPlayer {
  private stateChangeHandler: ((state: MediaViewerPlayerState) => void) | undefined = undefined;
  private timeUpdateHandler: ((positionMs: number) => void) | undefined = undefined;
  private durationUpdateHandler: ((durationMs: number) => void) | undefined = undefined;
  private errorHandler: ((errorMessage: string) => void) | undefined = undefined;

  readonly calls: string[] = [];
  loadErrorMessage: string = '';
  lastSurfaceId: string = '';

  setEventHandler(handler: MediaViewerPlayerEventHandler): void {
    this.stateChangeHandler = handler.onStateChange;
    this.timeUpdateHandler = handler.onTimeUpdate;
    this.durationUpdateHandler = handler.onDurationUpdate;
    this.errorHandler = handler.onError;
  }

  async load(request: MediaViewerPlaybackRequest, surfaceId: string): Promise<number> {
    this.calls.push(`load:${request.messageId}`);
    this.lastSurfaceId = surfaceId;
    if (this.loadErrorMessage.length > 0) {
      if (this.errorHandler) {
        this.errorHandler(this.loadErrorMessage);
      }
      throw new Error(this.loadErrorMessage);
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
}

function buildPlaybackRequest(overrides?: Partial<MediaViewerPlaybackRequest>): MediaViewerPlaybackRequest {
  return {
    'messageId': overrides?.messageId ?? 'media-1',
    'filePath': overrides?.filePath ?? '/data/storage/el2/base/files/tdlib/files/videos/test.mp4',
    'mimeType': overrides?.mimeType ?? 'video/mp4',
    'durationMs': overrides?.durationMs ?? 9000
  };
}

export default function mediaViewerPlaybackControllerTest() {
  describe('MediaViewerPlaybackControllerTest', () => {
    it('shouldStartPlayingWhenSurfaceBecomesAvailable', 0, async (): Promise<void> => {
      const player = new FakeMediaViewerPlaybackPlayer();
      const controller = new MediaViewerPlaybackController(player);
      let snapshot: MediaViewerPlaybackSnapshot = createIdleMediaViewerPlaybackSnapshot();
      controller.setListener((nextSnapshot: MediaViewerPlaybackSnapshot): void => {
        snapshot = nextSnapshot;
      });

      const playPromise = controller.play(buildPlaybackRequest({ messageId: 'media-10', durationMs: 17000 }));
      controller.attachSurface('surface-10');
      await playPromise;
      player.emitTimeUpdate(2400);

      expect(player.lastSurfaceId).assertEqual('surface-10');
      expect(snapshot.messageId).assertEqual('media-10');
      expect(snapshot.phase).assertEqual('playing');
      expect(snapshot.durationMs).assertEqual(17000);
      expect(snapshot.positionMs).assertEqual(2400);
      expect(player.calls.join(',')).assertEqual('stop,load:media-10,play');
    });

    it('shouldPlayPauseAndStopWithExplicitControls', 0, async (): Promise<void> => {
      const player = new FakeMediaViewerPlaybackPlayer();
      const controller = new MediaViewerPlaybackController(player);
      let snapshot: MediaViewerPlaybackSnapshot = createIdleMediaViewerPlaybackSnapshot();
      controller.setListener((nextSnapshot: MediaViewerPlaybackSnapshot): void => {
        snapshot = nextSnapshot;
      });

      controller.attachSurface('surface-controls');
      await controller.play(buildPlaybackRequest({ messageId: 'media-controls', durationMs: 12000 }));
      player.emitTimeUpdate(3200);
      await controller.pause();
      await controller.stop();

      expect(player.lastSurfaceId).assertEqual('surface-controls');
      expect(snapshot.phase).assertEqual('idle');
      expect(snapshot.positionMs).assertEqual(0);
      expect(player.calls.join(',')).assertEqual('stop,load:media-controls,play,pause,stop');
    });

    it('shouldResumePausedMediaWithoutReloading', 0, async (): Promise<void> => {
      const player = new FakeMediaViewerPlaybackPlayer();
      const controller = new MediaViewerPlaybackController(player);
      let snapshot: MediaViewerPlaybackSnapshot = createIdleMediaViewerPlaybackSnapshot();
      controller.setListener((nextSnapshot: MediaViewerPlaybackSnapshot): void => {
        snapshot = nextSnapshot;
      });
      const request = buildPlaybackRequest({ messageId: 'media-resume' });

      controller.attachSurface('surface-resume');
      await controller.play(request);
      await controller.pause();
      await controller.play(request);

      expect(snapshot.phase).assertEqual('playing');
      expect(player.calls.join(',')).assertEqual('stop,load:media-resume,play,pause,play');
    });

    it('shouldExposeErrorForMissingFilePath', 0, async (): Promise<void> => {
      const player = new FakeMediaViewerPlaybackPlayer();
      const controller = new MediaViewerPlaybackController(player);
      let snapshot: MediaViewerPlaybackSnapshot = createIdleMediaViewerPlaybackSnapshot();
      controller.setListener((nextSnapshot: MediaViewerPlaybackSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.play(buildPlaybackRequest({ messageId: 'media-12', filePath: '   ' }));

      expect(snapshot.messageId).assertEqual('media-12');
      expect(snapshot.phase).assertEqual('error');
      expect(snapshot.errorMessage).assertEqual(MEDIA_VIEWER_ERROR_MISSING_FILE_PATH);
      expect(player.calls.length).assertEqual(0);
    });

    it('shouldAbortWaitingForSurfaceWhenReleased', 0, async (): Promise<void> => {
      const player = new FakeMediaViewerPlaybackPlayer();
      const controller = new MediaViewerPlaybackController(player);
      let snapshot: MediaViewerPlaybackSnapshot = createIdleMediaViewerPlaybackSnapshot();
      controller.setListener((nextSnapshot: MediaViewerPlaybackSnapshot): void => {
        snapshot = nextSnapshot;
      });

      const playPromise = controller.play(buildPlaybackRequest({ messageId: 'media-13' }));
      await controller.release();
      await playPromise;

      expect(snapshot.phase).assertEqual('idle');
      expect(snapshot.errorMessage).assertEqual('');
      expect(player.calls.join(',')).assertEqual('stop,release');
    });

    it('shouldExposeRuntimeLoadError', 0, async (): Promise<void> => {
      const player = new FakeMediaViewerPlaybackPlayer();
      player.loadErrorMessage = 'broken video file';
      const controller = new MediaViewerPlaybackController(player);
      let snapshot: MediaViewerPlaybackSnapshot = createIdleMediaViewerPlaybackSnapshot();
      controller.setListener((nextSnapshot: MediaViewerPlaybackSnapshot): void => {
        snapshot = nextSnapshot;
      });

      controller.attachSurface('surface-14');
      await controller.play(buildPlaybackRequest({ messageId: 'media-14', durationMs: 3000 }));

      expect(snapshot.phase).assertEqual('error');
      expect(snapshot.durationMs).assertEqual(3000);
      expect(snapshot.errorMessage).assertEqual('broken video file');
      expect(player.calls.join(',')).assertEqual('stop,load:media-14');
    });
  });
}
