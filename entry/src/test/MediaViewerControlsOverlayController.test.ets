import { describe, it, expect } from '@ohos/hypium';
import {
  MediaViewerControlsOverlayController,
  MediaViewerControlsOverlayScheduler,
  MediaViewerControlsOverlaySnapshot
} from '../main/ets/services/media/MediaViewerControlsOverlayController';

class FakeScheduledTimer {
  id: number;
  delayMs: number;
  callback: () => void;
  active: boolean;

  constructor(id: number, delayMs: number, callback: () => void) {
    this.id = id;
    this.delayMs = delayMs;
    this.callback = callback;
    this.active = true;
  }
}

class FakeControlsOverlayScheduler implements MediaViewerControlsOverlayScheduler {
  private nextTimerId: number = 1;
  private timers: FakeScheduledTimer[] = [];

  setTimeout(callback: () => void, delayMs: number): number {
    const timer = new FakeScheduledTimer(this.nextTimerId, delayMs, callback);
    this.nextTimerId = this.nextTimerId + 1;
    this.timers.push(timer);
    return timer.id;
  }

  clearTimeout(timerId: number): void {
    for (const timer of this.timers) {
      if (timer.id === timerId) {
        timer.active = false;
      }
    }
  }

  activeTimerCount(): number {
    let count = 0;
    for (const timer of this.timers) {
      if (timer.active) {
        count = count + 1;
      }
    }
    return count;
  }

  latestActiveDelayMs(): number {
    let latestDelayMs = 0;
    for (const timer of this.timers) {
      if (timer.active) {
        latestDelayMs = timer.delayMs;
      }
    }
    return latestDelayMs;
  }

  runNextActiveTimer(): void {
    for (const timer of this.timers) {
      if (timer.active) {
        timer.active = false;
        timer.callback();
        return;
      }
    }
  }
}

export default function mediaViewerControlsOverlayControllerTest() {
  describe('MediaViewerControlsOverlayControllerTest', () => {
    it('shouldAutoHideAndDisableInputAfterFadeCompletes', 0, () => {
      const scheduler = new FakeControlsOverlayScheduler();
      const controller = new MediaViewerControlsOverlayController(scheduler);
      let latestSnapshot: MediaViewerControlsOverlaySnapshot = controller.getSnapshot();
      controller.setListener((snapshot: MediaViewerControlsOverlaySnapshot): void => {
        latestSnapshot = snapshot;
      });

      controller.handlePlaybackPhase('playing');

      expect(latestSnapshot.opacity).assertEqual(1);
      expect(latestSnapshot.inputEnabled).assertTrue();
      expect(scheduler.activeTimerCount()).assertEqual(1);
      expect(scheduler.latestActiveDelayMs()).assertEqual(1000);

      scheduler.runNextActiveTimer();

      expect(latestSnapshot.opacity).assertEqual(0);
      expect(latestSnapshot.fadeDurationMs).assertEqual(260);
      expect(latestSnapshot.inputEnabled).assertTrue();
      expect(scheduler.activeTimerCount()).assertEqual(1);
      expect(scheduler.latestActiveDelayMs()).assertEqual(260);

      scheduler.runNextActiveTimer();

      expect(latestSnapshot.opacity).assertEqual(0);
      expect(latestSnapshot.fadeDurationMs).assertEqual(0);
      expect(latestSnapshot.inputEnabled).assertFalse();
      expect(scheduler.activeTimerCount()).assertEqual(0);
    });

    it('shouldRevealImmediatelyAndCancelStaleFadeTimer', 0, () => {
      const scheduler = new FakeControlsOverlayScheduler();
      const controller = new MediaViewerControlsOverlayController(scheduler);
      let latestSnapshot: MediaViewerControlsOverlaySnapshot = controller.getSnapshot();
      controller.setListener((snapshot: MediaViewerControlsOverlaySnapshot): void => {
        latestSnapshot = snapshot;
      });

      controller.handlePlaybackPhase('playing');
      scheduler.runNextActiveTimer();
      controller.reveal();

      expect(latestSnapshot.opacity).assertEqual(1);
      expect(latestSnapshot.fadeDurationMs).assertEqual(0);
      expect(latestSnapshot.inputEnabled).assertTrue();
      expect(scheduler.activeTimerCount()).assertEqual(1);
      expect(scheduler.latestActiveDelayMs()).assertEqual(1000);
    });

    it('shouldRestoreControlsWhenPlaybackLeavesPlaying', 0, () => {
      const scheduler = new FakeControlsOverlayScheduler();
      const controller = new MediaViewerControlsOverlayController(scheduler);
      let latestSnapshot: MediaViewerControlsOverlaySnapshot = controller.getSnapshot();
      controller.setListener((snapshot: MediaViewerControlsOverlaySnapshot): void => {
        latestSnapshot = snapshot;
      });

      controller.handlePlaybackPhase('playing');
      scheduler.runNextActiveTimer();
      controller.handlePlaybackPhase('paused');

      expect(latestSnapshot.opacity).assertEqual(1);
      expect(latestSnapshot.fadeDurationMs).assertEqual(0);
      expect(latestSnapshot.inputEnabled).assertTrue();
      expect(scheduler.activeTimerCount()).assertEqual(0);
    });

    it('shouldCancelTimersOnDispose', 0, () => {
      const scheduler = new FakeControlsOverlayScheduler();
      const controller = new MediaViewerControlsOverlayController(scheduler);
      let latestSnapshot: MediaViewerControlsOverlaySnapshot = controller.getSnapshot();
      controller.setListener((snapshot: MediaViewerControlsOverlaySnapshot): void => {
        latestSnapshot = snapshot;
      });

      controller.handlePlaybackPhase('playing');
      scheduler.runNextActiveTimer();
      controller.dispose();

      expect(latestSnapshot.opacity).assertEqual(1);
      expect(latestSnapshot.fadeDurationMs).assertEqual(0);
      expect(latestSnapshot.inputEnabled).assertTrue();
      expect(scheduler.activeTimerCount()).assertEqual(0);
    });
  });
}
