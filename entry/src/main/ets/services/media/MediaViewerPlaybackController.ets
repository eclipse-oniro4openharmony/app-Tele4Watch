import { hilog } from '@kit.PerformanceAnalysisKit';
import { media } from '@kit.MediaKit';
import fs from '@ohos.file.fs';

const DOMAIN = 0x2026;
const TAG = 'MediaViewerPlayback';
const SURFACE_WAIT_INTERVAL_MS: number = 20;
const SURFACE_WAIT_TIMEOUT_MS: number = 10000;

export type MediaViewerPlaybackPhase = 'idle' | 'loading' | 'playing' | 'paused' | 'error';

export type MediaViewerPlayerState =
  'idle' | 'initialized' | 'prepared' | 'playing' | 'paused' | 'completed' | 'stopped' | 'released' | 'error';

export const MEDIA_VIEWER_ERROR_MISSING_FILE_PATH: string = 'media_viewer_missing_file_path';
export const MEDIA_VIEWER_ERROR_MISSING_SURFACE: string = 'media_viewer_missing_surface';
export const MEDIA_VIEWER_ERROR_PLAYBACK_FAILED: string = 'media_viewer_playback_failed';

export interface MediaViewerPlaybackRequest {
  'messageId': string;
  'filePath': string;
  'mimeType': string;
  'durationMs': number;
}

export interface MediaViewerPlaybackSnapshot {
  'messageId': string;
  'phase': MediaViewerPlaybackPhase;
  'positionMs': number;
  'durationMs': number;
  'errorMessage': string;
}

interface MediaViewerValidatedFileSource {
  'file': fs.File;
  'size': number;
}

export interface MediaViewerPlayerEventHandler {
  'onStateChange': (state: MediaViewerPlayerState) => void;
  'onTimeUpdate': (positionMs: number) => void;
  'onDurationUpdate': (durationMs: number) => void;
  'onError': (errorMessage: string) => void;
}

export interface MediaViewerPlaybackPlayer {
  'setEventHandler': (handler: MediaViewerPlayerEventHandler) => void;
  'load': (request: MediaViewerPlaybackRequest, surfaceId: string) => Promise<number>;
  'play': () => Promise<void>;
  'pause': () => Promise<void>;
  'stop': () => Promise<void>;
  'release': () => Promise<void>;
}

export function createIdleMediaViewerPlaybackSnapshot(): MediaViewerPlaybackSnapshot {
  return {
    'messageId': '',
    'phase': 'idle',
    'positionMs': 0,
    'durationMs': 0,
    'errorMessage': ''
  };
}

function clonePlaybackRequest(request: MediaViewerPlaybackRequest): MediaViewerPlaybackRequest {
  return {
    'messageId': request.messageId,
    'filePath': request.filePath,
    'mimeType': request.mimeType,
    'durationMs': request.durationMs
  };
}

function snapshotFromRequest(
  request: MediaViewerPlaybackRequest,
  phase: MediaViewerPlaybackPhase,
  errorMessage: string
): MediaViewerPlaybackSnapshot {
  return {
    'messageId': request.messageId,
    'phase': phase,
    'positionMs': 0,
    'durationMs': request.durationMs > 0 ? request.durationMs : 0,
    'errorMessage': errorMessage
  };
}

function normalizePlaybackRequest(request: MediaViewerPlaybackRequest): MediaViewerPlaybackRequest {
  return {
    'messageId': request.messageId.trim(),
    'filePath': request.filePath.trim(),
    'mimeType': request.mimeType.trim(),
    'durationMs': request.durationMs > 0 ? request.durationMs : 0
  };
}

function buildErrorMessage(error: string | Error | Object): string {
  if (typeof error === 'string') {
    const trimmed = error.trim();
    if (trimmed.length > 0) {
      return trimmed;
    }
  }
  if (error instanceof Error && typeof error.message === 'string') {
    const trimmedMessage = error.message.trim();
    if (trimmedMessage.length > 0) {
      return trimmedMessage;
    }
  }
  return String(error);
}

function isPauseCapableState(state: MediaViewerPlayerState): boolean {
  return state === 'playing';
}

function isPlayCapableState(state: MediaViewerPlayerState): boolean {
  return state === 'prepared' || state === 'paused' || state === 'completed';
}

function isStopCapableState(state: MediaViewerPlayerState): boolean {
  return state === 'prepared' || state === 'playing' || state === 'paused' || state === 'completed';
}

function canResetPlayerState(state: MediaViewerPlayerState): boolean {
  return state === 'initialized' ||
    state === 'prepared' ||
    state === 'playing' ||
    state === 'paused' ||
    state === 'completed' ||
    state === 'stopped' ||
    state === 'error';
}

function isProgressSnapshotPhase(phase: MediaViewerPlaybackPhase): boolean {
  return phase === 'playing' || phase === 'paused';
}

async function waitForPlayerState(
  player: media.AVPlayer,
  targetStates: MediaViewerPlayerState[],
  timeoutMs: number
): Promise<void> {
  const startedAt = Date.now();
  while (true) {
    const currentState = player.state;
    for (const targetState of targetStates) {
      if (currentState === targetState) {
        return;
      }
    }
    if (Date.now() - startedAt >= timeoutMs) {
      throw new Error(`Timed out waiting for player state: current=${currentState}`);
    }
    await new Promise<void>((resolve: () => void): void => {
      setTimeout((): void => {
        resolve();
      }, SURFACE_WAIT_INTERVAL_MS);
    });
  }
}

class MediaKitMediaViewerPlayer implements MediaViewerPlaybackPlayer {
  private avPlayer: media.AVPlayer | undefined = undefined;
  private eventHandler: MediaViewerPlayerEventHandler | undefined = undefined;
  private openedFile: fs.File | undefined = undefined;
  private playbackEventDispatchEnabled: boolean = false;
  private dataSourceErrorMessage: string = '';
  private dataSourceErrorReported: boolean = false;

  setEventHandler(handler: MediaViewerPlayerEventHandler): void {
    this.eventHandler = handler;
  }

  async load(request: MediaViewerPlaybackRequest, surfaceId: string): Promise<number> {
    try {
      this.playbackEventDispatchEnabled = false;
      this.resetDataSourceErrorState();
      const player = await this.ensurePlayer();
      await this.resetForNextSource(player);
      const fileSource = this.openValidatedFileSource(request.filePath);
      const file = fileSource.file;
      this.openedFile = file;
      const source: media.AVDataSrcDescriptor = {
        'fileSize': fileSource.size,
        'callback': (buffer: ArrayBuffer, length: number, pos?: number): number => {
          return this.readFromDataSource(file, buffer, length, pos);
        }
      };
      player.dataSrc = source;
      await waitForPlayerState(player, ['initialized'], 1000);
      player.surfaceId = surfaceId;
      await player.prepare();
      if (this.dataSourceErrorMessage.length > 0) {
        throw new Error(this.dataSourceErrorMessage);
      }
      await waitForPlayerState(player, ['prepared'], 1000);
      if (this.dataSourceErrorMessage.length > 0) {
        throw new Error(this.dataSourceErrorMessage);
      }
      this.playbackEventDispatchEnabled = true;
      const resolvedDurationMs = player.duration > 0 ? player.duration : request.durationMs;
      return resolvedDurationMs > 0 ? resolvedDurationMs : 0;
    } catch (error) {
      this.closeOpenedFile();
      throw new Error(buildErrorMessage(error));
    }
  }

  async play(): Promise<void> {
    try {
      const player = await this.ensurePlayer();
      if (!isPlayCapableState(player.state)) {
        return;
      }
      this.playbackEventDispatchEnabled = true;
      await player.play();
    } catch (error) {
      throw new Error(buildErrorMessage(error));
    }
  }

  async pause(): Promise<void> {
    try {
      const player = await this.ensurePlayer();
      if (!isPauseCapableState(player.state)) {
        return;
      }
      await player.pause();
    } catch (error) {
      throw new Error(buildErrorMessage(error));
    }
  }

  async stop(): Promise<void> {
    try {
      this.playbackEventDispatchEnabled = false;
      if (!this.avPlayer) {
        this.closeOpenedFile();
        return;
      }
      if (isStopCapableState(this.avPlayer.state)) {
        await this.avPlayer.stop();
      }
      if (canResetPlayerState(this.avPlayer.state)) {
        await this.avPlayer.reset();
      }
      this.closeOpenedFile();
    } catch (error) {
      this.closeOpenedFile();
      throw new Error(buildErrorMessage(error));
    }
  }

  async release(): Promise<void> {
    try {
      this.playbackEventDispatchEnabled = false;
      if (!this.avPlayer) {
        this.closeOpenedFile();
        return;
      }
      if (isStopCapableState(this.avPlayer.state)) {
        await this.avPlayer.stop();
      }
      if (canResetPlayerState(this.avPlayer.state)) {
        await this.avPlayer.reset();
      }
      await this.avPlayer.release();
      this.avPlayer = undefined;
      this.closeOpenedFile();
    } catch (error) {
      this.closeOpenedFile();
      throw new Error(buildErrorMessage(error));
    }
  }

  private async ensurePlayer(): Promise<media.AVPlayer> {
    try {
      if (this.avPlayer) {
        return this.avPlayer;
      }
      const player = await media.createAVPlayer();
      player.on('stateChange', (state: media.AVPlayerState): void => {
        if (this.eventHandler && this.playbackEventDispatchEnabled) {
          this.eventHandler.onStateChange(state);
        }
      });
      player.on('timeUpdate', (positionMs: number): void => {
        if (this.eventHandler && this.playbackEventDispatchEnabled) {
          this.eventHandler.onTimeUpdate(positionMs);
        }
      });
      player.on('durationUpdate', (durationMs: number): void => {
        if (this.eventHandler && this.playbackEventDispatchEnabled) {
          this.eventHandler.onDurationUpdate(durationMs);
        }
      });
      player.on('error', (error): void => {
        if (!this.eventHandler || !this.playbackEventDispatchEnabled) {
          return;
        }
        this.eventHandler.onError(buildErrorMessage(error));
      });
      this.avPlayer = player;
      return player;
    } catch (error) {
      throw new Error(buildErrorMessage(error));
    }
  }

  private async resetForNextSource(player: media.AVPlayer): Promise<void> {
    try {
      this.playbackEventDispatchEnabled = false;
      const state = player.state;
      if (state === 'released') {
        this.avPlayer = undefined;
        this.closeOpenedFile();
        return;
      }
      if (isStopCapableState(state)) {
        await player.stop();
      }
      if (canResetPlayerState(player.state)) {
        await player.reset();
      }
      this.closeOpenedFile();
    } catch (error) {
      this.closeOpenedFile();
      throw new Error(buildErrorMessage(error));
    }
  }

  private closeOpenedFile(): void {
    if (!this.openedFile) {
      return;
    }
    try {
      fs.closeSync(this.openedFile);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to close media-viewer file descriptor: %{public}s', buildErrorMessage(error));
    }
    this.openedFile = undefined;
  }

  private resetDataSourceErrorState(): void {
    this.dataSourceErrorMessage = '';
    this.dataSourceErrorReported = false;
  }

  private openValidatedFileSource(filePath: string): MediaViewerValidatedFileSource {
    let probeFile: fs.File | undefined = undefined;
    let probeClosed = false;
    try {
      probeFile = fs.openSync(filePath);
      const stat = fs.statSync(filePath);
      this.validateReadableFileDescriptor(probeFile.fd, filePath);
      this.closeFileDescriptor(probeFile, 'validate media-viewer source');
      probeClosed = true;
      const file = fs.openSync(filePath);
      return {
        'file': file,
        'size': stat.size
      };
    } catch (error) {
      if (!probeClosed && probeFile) {
        this.closeFileDescriptor(probeFile, 'prepare media-viewer source');
      }
      throw new Error(buildErrorMessage(error));
    }
  }

  private validateReadableFileDescriptor(fd: number, filePath: string): void {
    const probeBuffer = new ArrayBuffer(1);
    try {
      fs.readSync(fd, probeBuffer, {
        'offset': 0,
        'length': 1
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Player source validation failed for %{public}s: %{public}s',
        filePath, buildErrorMessage(error));
      throw new Error(buildErrorMessage(error));
    }
  }

  private readFromDataSource(file: fs.File, buffer: ArrayBuffer, length: number, pos?: number): number {
    if (length <= 0) {
      return 0;
    }
    try {
      if (typeof pos === 'number' && pos >= 0) {
        return fs.readSync(file.fd, buffer, {
          'offset': pos,
          'length': length
        });
      }
      return fs.readSync(file.fd, buffer, {
        'length': length
      });
    } catch (error) {
      const errorMessage = buildErrorMessage(error);
      this.reportDataSourceReadFailure(errorMessage);
      return 0;
    }
  }

  private reportDataSourceReadFailure(errorMessage: string): void {
    this.dataSourceErrorMessage = errorMessage;
    if (this.dataSourceErrorReported) {
      return;
    }
    this.dataSourceErrorReported = true;
    this.playbackEventDispatchEnabled = false;
    if (!this.eventHandler) {
      return;
    }
    setTimeout((): void => {
      if (!this.eventHandler) {
        return;
      }
      try {
        this.eventHandler.onError(errorMessage);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Player error callback dispatch failed: %{public}s', buildErrorMessage(error));
      }
    }, 0);
  }

  private closeFileDescriptor(file: fs.File, reason: string): void {
    try {
      fs.closeSync(file);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to close file descriptor after %{public}s: %{public}s',
        reason, buildErrorMessage(error));
    }
  }
}

export class MediaViewerPlaybackController {
  private readonly player: MediaViewerPlaybackPlayer;
  private currentRequest: MediaViewerPlaybackRequest | undefined = undefined;
  private listener: ((snapshot: MediaViewerPlaybackSnapshot) => void) | undefined = undefined;
  private snapshot: MediaViewerPlaybackSnapshot = createIdleMediaViewerPlaybackSnapshot();
  private operationChain: Promise<void> = Promise.resolve();
  private surfaceId: string = '';
  private releaseRequested: boolean = false;

  constructor(player?: MediaViewerPlaybackPlayer) {
    this.player = player ? player : new MediaKitMediaViewerPlayer();
    this.player.setEventHandler({
      'onStateChange': (state: MediaViewerPlayerState): void => {
        this.handlePlayerStateChange(state);
      },
      'onTimeUpdate': (positionMs: number): void => {
        this.handleTimeUpdate(positionMs);
      },
      'onDurationUpdate': (durationMs: number): void => {
        this.handleDurationUpdate(durationMs);
      },
      'onError': (errorMessage: string): void => {
        this.applyErrorState(errorMessage);
      }
    });
  }

  setListener(listener: ((snapshot: MediaViewerPlaybackSnapshot) => void) | undefined): void {
    this.listener = listener;
    this.notifyListener();
  }

  getSnapshot(): MediaViewerPlaybackSnapshot {
    return {
      'messageId': this.snapshot.messageId,
      'phase': this.snapshot.phase,
      'positionMs': this.snapshot.positionMs,
      'durationMs': this.snapshot.durationMs,
      'errorMessage': this.snapshot.errorMessage
    };
  }

  attachSurface(surfaceId: string): void {
    this.surfaceId = surfaceId.trim();
    this.releaseRequested = false;
  }

  detachSurface(): void {
    this.surfaceId = '';
  }

  /**
   * Starts or resumes playback for a media-viewer source.
   *
   * @param request Media source to play.
   * @returns Promise resolved after the queued playback action completes.
   */
  play(request: MediaViewerPlaybackRequest): Promise<void> {
    this.releaseRequested = false;
    return this.enqueue(async (): Promise<void> => {
      const normalizedRequest = normalizePlaybackRequest(request);
      if (normalizedRequest.messageId.length === 0) {
        hilog.warn(DOMAIN, TAG, 'play() ignored: empty messageId');
        return;
      }
      if (normalizedRequest.filePath.length === 0) {
        hilog.warn(DOMAIN, TAG, 'play() rejected: missing file path messageId=%{public}s', normalizedRequest.messageId);
        this.currentRequest = clonePlaybackRequest(normalizedRequest);
        this.setSnapshot(snapshotFromRequest(normalizedRequest, 'error', MEDIA_VIEWER_ERROR_MISSING_FILE_PATH));
        return;
      }
      if (this.isSameMessage(normalizedRequest) && this.snapshot.phase === 'playing') {
        return;
      }
      if (this.isSameMessage(normalizedRequest) && this.snapshot.phase === 'paused') {
        await this.player.play();
        this.setSnapshot({
          'messageId': normalizedRequest.messageId,
          'phase': 'playing',
          'positionMs': this.snapshot.positionMs,
          'durationMs': this.snapshot.durationMs,
          'errorMessage': ''
        });
        return;
      }

      await this.player.stop();
      this.currentRequest = clonePlaybackRequest(normalizedRequest);
      this.setSnapshot(snapshotFromRequest(normalizedRequest, 'loading', ''));
      const surfaceId = await this.waitForSurface();
      const resolvedDurationMs = await this.player.load(normalizedRequest, surfaceId);
      this.setSnapshot({
        'messageId': normalizedRequest.messageId,
        'phase': 'loading',
        'positionMs': 0,
        'durationMs': resolvedDurationMs > 0 ? resolvedDurationMs : this.snapshot.durationMs,
        'errorMessage': ''
      });
      await this.player.play();
      this.setSnapshot({
        'messageId': normalizedRequest.messageId,
        'phase': 'playing',
        'positionMs': this.snapshot.positionMs,
        'durationMs': this.snapshot.durationMs,
        'errorMessage': ''
      });
    });
  }

  /**
   * Pauses the current media-viewer playback without resetting position.
   *
   * @returns Promise resolved after the queued pause action completes.
   */
  pause(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      if (this.snapshot.phase !== 'playing') {
        hilog.warn(DOMAIN, TAG, 'pause() ignored: snapshotPhase=%{public}s', this.snapshot.phase);
        return;
      }
      this.setSnapshot({
        'messageId': this.snapshot.messageId,
        'phase': 'paused',
        'positionMs': this.snapshot.positionMs,
        'durationMs': this.snapshot.durationMs,
        'errorMessage': ''
      });
      await this.player.pause();
    });
  }

  stop(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      await this.player.stop();
      this.currentRequest = undefined;
      this.setSnapshot(createIdleMediaViewerPlaybackSnapshot());
    });
  }

  release(): Promise<void> {
    this.releaseRequested = true;
    return this.enqueue(async (): Promise<void> => {
      await this.player.release();
      this.surfaceId = '';
      this.currentRequest = undefined;
      this.setSnapshot(createIdleMediaViewerPlaybackSnapshot());
    });
  }

  private async waitForSurface(): Promise<string> {
    const startedAt = Date.now();
    while (true) {
      if (this.releaseRequested) {
        throw new Error(MEDIA_VIEWER_ERROR_MISSING_SURFACE);
      }
      if (this.surfaceId.length > 0) {
        return this.surfaceId;
      }
      if (Date.now() - startedAt >= SURFACE_WAIT_TIMEOUT_MS) {
        throw new Error(MEDIA_VIEWER_ERROR_MISSING_SURFACE);
      }
      await new Promise<void>((resolve: () => void): void => {
        setTimeout((): void => {
          resolve();
        }, SURFACE_WAIT_INTERVAL_MS);
      });
    }
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const nextOperation = this.operationChain.then(async (): Promise<void> => {
      try {
        await operation();
      } catch (error) {
        this.applyErrorState(buildErrorMessage(error));
      }
    });
    this.operationChain = nextOperation.then((): void => {
      // Keep queue alive even after failures.
    });
    return nextOperation;
  }

  private handlePlayerStateChange(state: MediaViewerPlayerState): void {
    if (!this.currentRequest) {
      if (state === 'released' || state === 'stopped') {
        this.setSnapshot(createIdleMediaViewerPlaybackSnapshot());
      }
      return;
    }
    if (state === 'playing') {
      this.setSnapshot({
        'messageId': this.currentRequest.messageId,
        'phase': 'playing',
        'positionMs': this.snapshot.positionMs,
        'durationMs': this.snapshot.durationMs,
        'errorMessage': ''
      });
      return;
    }
    if (state === 'paused' || state === 'completed') {
      this.setSnapshot({
        'messageId': this.currentRequest.messageId,
        'phase': 'paused',
        'positionMs': this.snapshot.positionMs,
        'durationMs': this.snapshot.durationMs,
        'errorMessage': ''
      });
      return;
    }
    if (state === 'stopped' || state === 'released') {
      this.currentRequest = undefined;
      this.setSnapshot(createIdleMediaViewerPlaybackSnapshot());
      return;
    }
    if (state === 'error') {
      this.applyErrorState(MEDIA_VIEWER_ERROR_PLAYBACK_FAILED);
    }
  }

  private handleTimeUpdate(positionMs: number): void {
    if (!this.currentRequest) {
      return;
    }
    if (!isProgressSnapshotPhase(this.snapshot.phase)) {
      return;
    }
    const nextPositionMs = positionMs >= 0 ? positionMs : 0;
    this.setSnapshot({
      'messageId': this.currentRequest.messageId,
      'phase': this.snapshot.phase,
      'positionMs': nextPositionMs,
      'durationMs': this.snapshot.durationMs,
      'errorMessage': this.snapshot.errorMessage
    });
  }

  private handleDurationUpdate(durationMs: number): void {
    if (!this.currentRequest) {
      return;
    }
    const nextDuration = durationMs > 0 ? durationMs : this.snapshot.durationMs;
    if (!isProgressSnapshotPhase(this.snapshot.phase) && this.snapshot.phase !== 'loading') {
      return;
    }
    this.setSnapshot({
      'messageId': this.currentRequest.messageId,
      'phase': this.snapshot.phase,
      'positionMs': this.snapshot.positionMs,
      'durationMs': nextDuration,
      'errorMessage': this.snapshot.errorMessage
    });
  }

  private applyErrorState(errorMessage: string): void {
    hilog.error(DOMAIN, TAG,
      'Controller error state: message=%{public}s currentRequest=%{public}s snapshotPhase=%{public}s',
      errorMessage,
      this.currentRequest ? this.currentRequest.messageId : '<none>',
      this.snapshot.phase
    );
    if (!this.currentRequest) {
      this.setSnapshot({
        'messageId': '',
        'phase': 'error',
        'positionMs': 0,
        'durationMs': 0,
        'errorMessage': errorMessage
      });
      return;
    }
    this.setSnapshot({
      'messageId': this.currentRequest.messageId,
      'phase': 'error',
      'positionMs': this.snapshot.positionMs,
      'durationMs': this.snapshot.durationMs,
      'errorMessage': errorMessage
    });
  }

  private isSameMessage(request: MediaViewerPlaybackRequest): boolean {
    return this.currentRequest !== undefined && this.currentRequest.messageId === request.messageId;
  }

  private setSnapshot(snapshot: MediaViewerPlaybackSnapshot): void {
    this.snapshot = {
      'messageId': snapshot.messageId,
      'phase': snapshot.phase,
      'positionMs': snapshot.positionMs,
      'durationMs': snapshot.durationMs,
      'errorMessage': snapshot.errorMessage
    };
    this.notifyListener();
  }

  private notifyListener(): void {
    if (!this.listener) {
      return;
    }
    this.listener(this.getSnapshot());
  }
}
