import { MediaViewerPlaybackPhase } from './MediaViewerPlaybackController';

const CONTROL_PANEL_AUTO_HIDE_DELAY_MS: number = 1000;
const CONTROL_PANEL_FADE_OUT_MS: number = 260;
const CONTROL_PANEL_VISIBLE_OPACITY: number = 1;
const CONTROL_PANEL_HIDDEN_OPACITY: number = 0;

export interface MediaViewerControlsOverlaySnapshot {
  opacity: number;
  fadeDurationMs: number;
  inputEnabled: boolean;
}

export interface MediaViewerControlsOverlayScheduler {
  /**
   * Schedules a callback.
   *
   * @param callback callback executed after delay.
   * @param delayMs delay in milliseconds.
   * @returns timer identifier.
   */
  setTimeout(callback: () => void, delayMs: number): number;

  /**
   * Cancels a scheduled callback.
   *
   * @param timerId timer identifier returned by setTimeout.
   */
  clearTimeout(timerId: number): void;
}

class SystemMediaViewerControlsOverlayScheduler implements MediaViewerControlsOverlayScheduler {
  setTimeout(callback: () => void, delayMs: number): number {
    return setTimeout(callback, delayMs);
  }

  clearTimeout(timerId: number): void {
    clearTimeout(timerId);
  }
}

function createVisibleControlsOverlaySnapshot(): MediaViewerControlsOverlaySnapshot {
  return {
    opacity: CONTROL_PANEL_VISIBLE_OPACITY,
    fadeDurationMs: 0,
    inputEnabled: true
  };
}

/**
 * Owns MediaViewer video control overlay visibility, fade and auto-hide timing.
 */
export class MediaViewerControlsOverlayController {
  private readonly scheduler: MediaViewerControlsOverlayScheduler;
  private listener: ((snapshot: MediaViewerControlsOverlaySnapshot) => void) | undefined = undefined;
  private snapshot: MediaViewerControlsOverlaySnapshot = createVisibleControlsOverlaySnapshot();
  private playbackPhase: MediaViewerPlaybackPhase = 'idle';
  private hideTimerId: number = 0;
  private fadeEndTimerId: number = 0;
  private hideToken: number = 0;
  private fadeEndToken: number = 0;

  /**
   * Creates a controls overlay controller.
   *
   * @param scheduler optional scheduler used by tests for deterministic timers.
   */
  constructor(scheduler?: MediaViewerControlsOverlayScheduler) {
    this.scheduler = scheduler ? scheduler : new SystemMediaViewerControlsOverlayScheduler();
  }

  /**
   * Sets a listener for overlay snapshot changes.
   *
   * @param listener callback receiving a cloned overlay snapshot.
   */
  setListener(listener: ((snapshot: MediaViewerControlsOverlaySnapshot) => void) | undefined): void {
    this.listener = listener;
    this.notifyListener();
  }

  /**
   * Returns the current overlay snapshot.
   *
   * @returns cloned current snapshot.
   */
  getSnapshot(): MediaViewerControlsOverlaySnapshot {
    return this.cloneSnapshot(this.snapshot);
  }

  /**
   * Updates overlay behavior after playback phase changes.
   *
   * @param phase latest media playback phase.
   */
  handlePlaybackPhase(phase: MediaViewerPlaybackPhase): void {
    const previousPhase = this.playbackPhase;
    this.playbackPhase = phase;
    if (phase === 'playing' && previousPhase !== 'playing') {
      this.scheduleAutoHide();
      return;
    }
    if (phase !== 'playing' && phase !== 'loading') {
      this.showNowIfNeeded();
    }
  }

  /**
   * Reveals the overlay immediately, then schedules auto-hide while media is playing.
   */
  reveal(): void {
    this.showNow();
    if (this.playbackPhase === 'playing') {
      this.scheduleAutoHide();
    }
  }

  /**
   * Cancels all timers and restores the visible state.
   */
  dispose(): void {
    this.clearHideTimer();
    this.clearFadeEndTimer();
    this.playbackPhase = 'idle';
    this.setSnapshot(createVisibleControlsOverlaySnapshot());
  }

  private clearHideTimer(): void {
    if (this.hideTimerId > 0) {
      this.scheduler.clearTimeout(this.hideTimerId);
      this.hideTimerId = 0;
    }
    this.hideToken = this.hideToken + 1;
  }

  private clearFadeEndTimer(): void {
    if (this.fadeEndTimerId > 0) {
      this.scheduler.clearTimeout(this.fadeEndTimerId);
      this.fadeEndTimerId = 0;
    }
    this.fadeEndToken = this.fadeEndToken + 1;
  }

  private showNow(): void {
    this.clearHideTimer();
    this.clearFadeEndTimer();
    this.setSnapshot(createVisibleControlsOverlaySnapshot());
  }

  private showNowIfNeeded(): void {
    if (this.snapshot.opacity === CONTROL_PANEL_VISIBLE_OPACITY &&
      this.snapshot.inputEnabled &&
      this.snapshot.fadeDurationMs === 0 &&
      this.hideTimerId === 0 &&
      this.fadeEndTimerId === 0) {
      return;
    }
    this.showNow();
  }

  private scheduleAutoHide(): void {
    this.clearHideTimer();
    if (this.playbackPhase !== 'playing') {
      return;
    }
    const timerToken = this.hideToken;
    this.hideTimerId = this.scheduler.setTimeout((): void => {
      if (timerToken !== this.hideToken) {
        return;
      }
      this.hideTimerId = 0;
      this.fadeOut();
    }, CONTROL_PANEL_AUTO_HIDE_DELAY_MS);
  }

  private fadeOut(): void {
    if (this.playbackPhase !== 'playing') {
      this.showNow();
      return;
    }
    this.clearFadeEndTimer();
    this.setSnapshot({
      opacity: CONTROL_PANEL_HIDDEN_OPACITY,
      fadeDurationMs: CONTROL_PANEL_FADE_OUT_MS,
      inputEnabled: true
    });
    const timerToken = this.fadeEndToken;
    this.fadeEndTimerId = this.scheduler.setTimeout((): void => {
      if (timerToken !== this.fadeEndToken) {
        return;
      }
      this.fadeEndTimerId = 0;
      if (this.playbackPhase !== 'playing') {
        this.showNow();
        return;
      }
      this.setSnapshot({
        opacity: CONTROL_PANEL_HIDDEN_OPACITY,
        fadeDurationMs: 0,
        inputEnabled: false
      });
    }, CONTROL_PANEL_FADE_OUT_MS);
  }

  private setSnapshot(snapshot: MediaViewerControlsOverlaySnapshot): void {
    this.snapshot = this.cloneSnapshot(snapshot);
    this.notifyListener();
  }

  private cloneSnapshot(snapshot: MediaViewerControlsOverlaySnapshot): MediaViewerControlsOverlaySnapshot {
    return {
      opacity: snapshot.opacity,
      fadeDurationMs: snapshot.fadeDurationMs,
      inputEnabled: snapshot.inputEnabled
    };
  }

  private notifyListener(): void {
    if (!this.listener) {
      return;
    }
    this.listener(this.getSnapshot());
  }
}
