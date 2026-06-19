import { hilog } from '@kit.PerformanceAnalysisKit';
import { media } from '@kit.MediaKit';
import fs from '@ohos.file.fs';

const DOMAIN = 0x2026;
const TAG = 'VoiceNotePlayback';

export type VoiceNotePlaybackPhase = 'idle' | 'loading' | 'playing' | 'paused' | 'error';

export type VoiceNotePlayerState =
  'idle' | 'initialized' | 'prepared' | 'playing' | 'paused' | 'completed' | 'stopped' | 'released' | 'error';

export const VOICE_NOTE_ERROR_MISSING_FILE_PATH: string = 'voice_note_missing_file_path';
export const VOICE_NOTE_ERROR_PLAYBACK_FAILED: string = 'voice_note_playback_failed';

/**
 * Describes one playback target resolved for a single voice-note message.
 */
export interface VoiceNotePlaybackRequest {
  'messageId': string;
  'filePath': string;
  'mimeType': string;
  'durationMs': number;
}

/**
 * Represents UI-facing playback state for one active voice note.
 */
export interface VoiceNotePlaybackSnapshot {
  'messageId': string;
  'phase': VoiceNotePlaybackPhase;
  'positionMs': number;
  'durationMs': number;
  'errorMessage': string;
}

interface VoiceNoteValidatedFileSource {
  'file': fs.File;
  'size': number;
}

/**
 * Defines low-level player events consumed by the page-scoped controller.
 */
export interface VoiceNotePlayerEventHandler {
  'onStateChange': (state: VoiceNotePlayerState) => void;
  'onTimeUpdate': (positionMs: number) => void;
  'onDurationUpdate': (durationMs: number) => void;
  'onError': (errorMessage: string) => void;
}

/**
 * Abstracts the underlying playback engine used by the controller.
 */
export interface VoiceNotePlaybackPlayer {
  'setEventHandler': (handler: VoiceNotePlayerEventHandler) => void;
  'load': (request: VoiceNotePlaybackRequest) => Promise<number>;
  'play': () => Promise<void>;
  'pause': () => Promise<void>;
  'stop': () => Promise<void>;
  'release': () => Promise<void>;
}

/**
 * Creates the neutral playback snapshot used when no voice note is active.
 *
 * @returns Idle snapshot with empty message binding and zero progress.
 */
export function createIdleVoiceNotePlaybackSnapshot(): VoiceNotePlaybackSnapshot {
  return {
    'messageId': '',
    'phase': 'idle',
    'positionMs': 0,
    'durationMs': 0,
    'errorMessage': ''
  };
}

function formatPlaybackRequestForLog(request: VoiceNotePlaybackRequest | undefined): string {
  if (!request) {
    return 'request=<none>';
  }
  return `messageId=${request.messageId} path=${request.filePath} mime=${request.mimeType} durationMs=${request.durationMs}`;
}

function formatSnapshotForLog(snapshot: VoiceNotePlaybackSnapshot): string {
  return `messageId=${snapshot.messageId} phase=${snapshot.phase} positionMs=${snapshot.positionMs} durationMs=${snapshot.durationMs} error=${snapshot.errorMessage}`;
}

function clonePlaybackRequest(request: VoiceNotePlaybackRequest): VoiceNotePlaybackRequest {
  return {
    'messageId': request.messageId,
    'filePath': request.filePath,
    'mimeType': request.mimeType,
    'durationMs': request.durationMs
  };
}

function snapshotFromRequest(
  request: VoiceNotePlaybackRequest,
  phase: VoiceNotePlaybackPhase,
  errorMessage: string
): VoiceNotePlaybackSnapshot {
  return {
    'messageId': request.messageId,
    'phase': phase,
    'positionMs': 0,
    'durationMs': request.durationMs > 0 ? request.durationMs : 0,
    'errorMessage': errorMessage
  };
}

function normalizePlaybackRequest(request: VoiceNotePlaybackRequest): VoiceNotePlaybackRequest {
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

function isPauseCapableState(state: VoiceNotePlayerState): boolean {
  return state === 'playing';
}

function isPlayCapableState(state: VoiceNotePlayerState): boolean {
  return state === 'prepared' || state === 'paused' || state === 'completed';
}

function isStopCapableState(state: VoiceNotePlayerState): boolean {
  return state === 'prepared' || state === 'playing' || state === 'paused' || state === 'completed';
}

function canResetPlayerState(state: VoiceNotePlayerState): boolean {
  return state === 'initialized' ||
    state === 'prepared' ||
    state === 'playing' ||
    state === 'paused' ||
    state === 'completed' ||
    state === 'stopped' ||
    state === 'error';
}

function isProgressSnapshotPhase(phase: VoiceNotePlaybackPhase): boolean {
  return phase === 'playing' || phase === 'paused';
}

async function waitForPlayerState(
  player: media.AVPlayer,
  targetStates: VoiceNotePlayerState[],
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
      }, 20);
    });
  }
}

class MediaKitVoiceNotePlayer implements VoiceNotePlaybackPlayer {
  private avPlayer: media.AVPlayer | undefined = undefined;
  private eventHandler: VoiceNotePlayerEventHandler | undefined = undefined;
  private openedFile: fs.File | undefined = undefined;
  private playbackEventDispatchEnabled: boolean = false;
  private dataSourceErrorMessage: string = '';
  private dataSourceErrorReported: boolean = false;

  setEventHandler(handler: VoiceNotePlayerEventHandler): void {
    this.eventHandler = handler;
    hilog.debug(DOMAIN, TAG, 'Player event handler attached.');
  }

  async load(request: VoiceNotePlaybackRequest): Promise<number> {
    try {
      this.playbackEventDispatchEnabled = false;
      this.resetDataSourceErrorState();
      hilog.debug(DOMAIN, TAG, 'Player load start: %{public}s', formatPlaybackRequestForLog(request));
      const player = await this.ensurePlayer();
      await this.resetForNextSource(player);
      const fileSource = this.openValidatedFileSource(request.filePath);
      const file = fileSource.file;
      this.openedFile = file;
      hilog.debug(DOMAIN, TAG, 'Player load dataSrc start: fd=%{public}d size=%{public}d path=%{public}s',
        file.fd, fileSource.size, request.filePath);
      const source: media.AVDataSrcDescriptor = {
        'fileSize': fileSource.size,
        'callback': (buffer: ArrayBuffer, length: number, pos?: number): number => {
          return this.readFromDataSource(file, buffer, length, pos);
        }
      };
      player.dataSrc = source;
      await waitForPlayerState(player, ['initialized'], 1000);
      hilog.debug(DOMAIN, TAG, 'Player reached initialized state, preparing source. state=%{public}s', player.state);
      hilog.debug(DOMAIN, TAG, 'Player prepare() call start.');
      await player.prepare();
      if (this.dataSourceErrorMessage.length > 0) {
        throw new Error(this.dataSourceErrorMessage);
      }
      hilog.debug(DOMAIN, TAG, 'Player prepare() resolved. state=%{public}s duration=%{public}d',
        player.state, player.duration);
      await waitForPlayerState(player, ['prepared'], 1000);
      if (this.dataSourceErrorMessage.length > 0) {
        throw new Error(this.dataSourceErrorMessage);
      }
      this.playbackEventDispatchEnabled = true;
      const resolvedDurationMs = player.duration > 0 ? player.duration : request.durationMs;
      hilog.debug(DOMAIN, TAG, 'Player load prepared: %{public}s state=%{public}s duration=%{public}d',
        formatPlaybackRequestForLog(request), player.state, resolvedDurationMs);
      return resolvedDurationMs > 0 ? resolvedDurationMs : 0;
    } catch (error) {
      this.closeOpenedFile();
      hilog.debug(DOMAIN, TAG, 'Player load failed: %{public}s', buildErrorMessage(error));
      throw new Error(buildErrorMessage(error));
    }
  }

  async play(): Promise<void> {
    try {
      const player = await this.ensurePlayer();
      if (!isPlayCapableState(player.state)) {
        hilog.debug(DOMAIN, TAG, 'Player play skipped due to state=%{public}s', player.state);
        return;
      }
      this.playbackEventDispatchEnabled = true;
      hilog.debug(DOMAIN, TAG, 'Player play requested.');
      await player.play();
    } catch (error) {
      hilog.debug(DOMAIN, TAG, 'Player play failed: %{public}s', buildErrorMessage(error));
      throw new Error(buildErrorMessage(error));
    }
  }

  async pause(): Promise<void> {
    try {
      const player = await this.ensurePlayer();
      if (!isPauseCapableState(player.state)) {
        hilog.debug(DOMAIN, TAG, 'Player pause skipped due to state=%{public}s', player.state);
        return;
      }
      hilog.debug(DOMAIN, TAG, 'Player pause requested.');
      await player.pause();
    } catch (error) {
      hilog.debug(DOMAIN, TAG, 'Player pause failed: %{public}s', buildErrorMessage(error));
      throw new Error(buildErrorMessage(error));
    }
  }

  async stop(): Promise<void> {
    try {
      this.playbackEventDispatchEnabled = false;
      if (!this.avPlayer) {
        hilog.debug(DOMAIN, TAG, 'Player stop skipped: player not initialized.');
        this.closeOpenedFile();
        return;
      }
      hilog.debug(DOMAIN, TAG, 'Player stop requested in state=%{public}s', this.avPlayer.state);
      if (isStopCapableState(this.avPlayer.state)) {
        await this.avPlayer.stop();
      }
      if (canResetPlayerState(this.avPlayer.state)) {
        await this.avPlayer.reset();
      }
      this.closeOpenedFile();
    } catch (error) {
      this.closeOpenedFile();
      hilog.debug(DOMAIN, TAG, 'Player stop failed: %{public}s', buildErrorMessage(error));
      throw new Error(buildErrorMessage(error));
    }
  }

  async release(): Promise<void> {
    try {
      this.playbackEventDispatchEnabled = false;
      if (!this.avPlayer) {
        hilog.debug(DOMAIN, TAG, 'Player release skipped: player not initialized.');
        this.closeOpenedFile();
        return;
      }
      hilog.debug(DOMAIN, TAG, 'Player release requested in state=%{public}s', this.avPlayer.state);
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
      hilog.debug(DOMAIN, TAG, 'Player release failed: %{public}s', buildErrorMessage(error));
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
        hilog.debug(DOMAIN, TAG, 'Player event stateChange=%{public}s', state);
        if (this.eventHandler && this.playbackEventDispatchEnabled) {
          this.eventHandler.onStateChange(state);
        }
      });
      player.on('timeUpdate', (positionMs: number): void => {
        hilog.debug(DOMAIN, TAG, 'Player event timeUpdate=%{public}d', positionMs);
        if (this.eventHandler && this.playbackEventDispatchEnabled) {
          this.eventHandler.onTimeUpdate(positionMs);
        }
      });
      player.on('durationUpdate', (durationMs: number): void => {
        hilog.debug(DOMAIN, TAG, 'Player event durationUpdate=%{public}d', durationMs);
        if (this.eventHandler && this.playbackEventDispatchEnabled) {
          this.eventHandler.onDurationUpdate(durationMs);
        }
      });
      player.on('error', (error): void => {
        hilog.debug(DOMAIN, TAG, 'Player event error raw=%{public}s', String(error));
        hilog.debug(DOMAIN, TAG, 'Player event error normalized=%{public}s', buildErrorMessage(error));
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
      hilog.debug(DOMAIN, TAG, 'Player resetForNextSource state=%{public}s', state);
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
      hilog.warn(DOMAIN, TAG, 'Failed to close voice-note file descriptor: %{public}s', buildErrorMessage(error));
    }
    this.openedFile = undefined;
  }

  private resetDataSourceErrorState(): void {
    this.dataSourceErrorMessage = '';
    this.dataSourceErrorReported = false;
  }

  private openValidatedFileSource(filePath: string): VoiceNoteValidatedFileSource {
    let probeFile: fs.File | undefined = undefined;
    let probeClosed = false;
    try {
      probeFile = fs.openSync(filePath);
      const stat = fs.statSync(filePath);
      this.validateReadableFileDescriptor(probeFile.fd, filePath);
      this.closeFileDescriptor(probeFile, 'validate voice-note source');
      probeClosed = true;
      const file = fs.openSync(filePath);
      return {
        'file': file,
        'size': stat.size
      };
    } catch (error) {
      if (!probeClosed && probeFile) {
        this.closeFileDescriptor(probeFile, 'prepare voice-note source');
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
    hilog.warn(DOMAIN, TAG, 'Player data source read failed: %{public}s', errorMessage);
    if (!this.eventHandler) {
      return;
    }

    // Defer error dispatch outside the AVPlayer data source callback so load()
    // can reject first and the controller sees one consistent failure path.
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

/**
 * Owns page-scoped voice-note playback and exposes a single reactive snapshot for UI.
 */
export class VoiceNotePlaybackController {
  private readonly player: VoiceNotePlaybackPlayer;
  private currentRequest: VoiceNotePlaybackRequest | undefined = undefined;
  private listener: ((snapshot: VoiceNotePlaybackSnapshot) => void) | undefined = undefined;
  private snapshot: VoiceNotePlaybackSnapshot = createIdleVoiceNotePlaybackSnapshot();
  private operationChain: Promise<void> = Promise.resolve();

  /**
   * Creates controller instance and wires low-level player events to snapshot updates.
   *
   * @param player Optional test double or alternate player implementation.
   */
  constructor(player?: VoiceNotePlaybackPlayer) {
    this.player = player ? player : new MediaKitVoiceNotePlayer();
    hilog.debug(DOMAIN, TAG, 'Playback controller created.');
    this.player.setEventHandler({
      'onStateChange': (state: VoiceNotePlayerState): void => {
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

  /**
   * Registers snapshot listener used by the page/view-model layer.
   *
   * @param listener Callback invoked after every snapshot update, or `undefined` to detach.
   * @returns Nothing.
   */
  setListener(listener: ((snapshot: VoiceNotePlaybackSnapshot) => void) | undefined): void {
    this.listener = listener;
    hilog.debug(DOMAIN, TAG, 'Controller listener updated: attached=%{public}d', listener ? 1 : 0);
    this.notifyListener();
  }

  /**
   * Returns a defensive copy of current playback snapshot.
   *
   * @returns Current UI-facing playback state.
   */
  getSnapshot(): VoiceNotePlaybackSnapshot {
    return {
      'messageId': this.snapshot.messageId,
      'phase': this.snapshot.phase,
      'positionMs': this.snapshot.positionMs,
      'durationMs': this.snapshot.durationMs,
      'errorMessage': this.snapshot.errorMessage
    };
  }

  /**
   * Toggles playback for a message: pause/resume current item or switch to a new source.
   *
   * @param request Fully resolved playback target for one voice note.
   * @returns Promise resolved after queued playback operation finishes.
   */
  toggle(request: VoiceNotePlaybackRequest): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      const normalizedRequest = normalizePlaybackRequest(request);
      hilog.debug(DOMAIN, TAG, 'Controller toggle requested: %{public}s', formatPlaybackRequestForLog(normalizedRequest));
      if (normalizedRequest.messageId.length === 0) {
        hilog.debug(DOMAIN, TAG, 'Controller toggle ignored: empty messageId.');
        return;
      }

      if (normalizedRequest.filePath.length === 0) {
        hilog.debug(DOMAIN, TAG, 'Controller toggle -> error: missing file path for %{public}s', normalizedRequest.messageId);
        this.currentRequest = clonePlaybackRequest(normalizedRequest);
        this.setSnapshot(snapshotFromRequest(normalizedRequest, 'error', VOICE_NOTE_ERROR_MISSING_FILE_PATH));
        return;
      }

      if (this.isSameMessage(normalizedRequest) && this.snapshot.phase === 'playing') {
        hilog.debug(DOMAIN, TAG, 'Controller toggle -> pause current messageId=%{public}s', normalizedRequest.messageId);
        await this.player.pause();
        return;
      }

      if (this.isSameMessage(normalizedRequest) && this.snapshot.phase === 'paused') {
        hilog.debug(DOMAIN, TAG, 'Controller toggle -> resume current messageId=%{public}s', normalizedRequest.messageId);
        await this.player.play();
        return;
      }

      hilog.debug(DOMAIN, TAG, 'Controller toggle -> switch source to %{public}s', normalizedRequest.messageId);
      await this.player.stop();
      this.currentRequest = clonePlaybackRequest(normalizedRequest);
      this.setSnapshot(snapshotFromRequest(normalizedRequest, 'loading', ''));
      const resolvedDurationMs = await this.player.load(normalizedRequest);
      this.setSnapshot({
        'messageId': normalizedRequest.messageId,
        'phase': 'loading',
        'positionMs': 0,
        'durationMs': resolvedDurationMs > 0 ? resolvedDurationMs : this.snapshot.durationMs,
        'errorMessage': ''
      });
      await this.player.play();
    });
  }

  /**
   * Stops current playback and resets controller snapshot to idle.
   *
   * @returns Promise resolved after queued stop operation finishes.
   */
  stop(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      hilog.debug(DOMAIN, TAG, 'Controller stop requested. current=%{public}s', formatPlaybackRequestForLog(this.currentRequest));
      await this.player.stop();
      this.currentRequest = undefined;
      this.setSnapshot(createIdleVoiceNotePlaybackSnapshot());
    });
  }

  /**
   * Releases player resources and resets controller snapshot to idle.
   *
   * @returns Promise resolved after queued release operation finishes.
   */
  release(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      hilog.debug(DOMAIN, TAG, 'Controller release requested. current=%{public}s', formatPlaybackRequestForLog(this.currentRequest));
      await this.player.release();
      this.currentRequest = undefined;
      this.setSnapshot(createIdleVoiceNotePlaybackSnapshot());
    });
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const nextOperation = this.operationChain.then(async (): Promise<void> => {
      try {
        await operation();
      } catch (error) {
        hilog.debug(DOMAIN, TAG, 'Controller queued operation failed: %{public}s', buildErrorMessage(error));
        this.applyErrorState(buildErrorMessage(error));
      }
    });
    this.operationChain = nextOperation.then((): void => {
      // Keep queue alive even after previous failures.
    });
    return nextOperation;
  }

  private handlePlayerStateChange(state: VoiceNotePlayerState): void {
    hilog.debug(
      DOMAIN,
      TAG,
      'Controller handlePlayerStateChange state=%{public}s current=%{public}s snapshot=%{public}s',
      state,
      formatPlaybackRequestForLog(this.currentRequest),
      formatSnapshotForLog(this.snapshot)
    );
    if (!this.currentRequest) {
      if (state === 'released' || state === 'stopped' || state === 'completed') {
        this.setSnapshot(createIdleVoiceNotePlaybackSnapshot());
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

    if (state === 'paused') {
      this.setSnapshot({
        'messageId': this.currentRequest.messageId,
        'phase': 'paused',
        'positionMs': this.snapshot.positionMs,
        'durationMs': this.snapshot.durationMs,
        'errorMessage': ''
      });
      return;
    }

    if (state === 'completed' || state === 'stopped' || state === 'released') {
      this.currentRequest = undefined;
      this.setSnapshot(createIdleVoiceNotePlaybackSnapshot());
      return;
    }

    if (state === 'error') {
      this.applyErrorState(VOICE_NOTE_ERROR_PLAYBACK_FAILED);
    }
  }

  private handleTimeUpdate(positionMs: number): void {
    hilog.debug(DOMAIN, TAG, 'Controller handleTimeUpdate positionMs=%{public}d', positionMs);
    if (!this.currentRequest) {
      return;
    }
    if (!isProgressSnapshotPhase(this.snapshot.phase)) {
      return;
    }

    this.setSnapshot({
      'messageId': this.currentRequest.messageId,
      'phase': this.snapshot.phase,
      'positionMs': positionMs >= 0 ? positionMs : 0,
      'durationMs': this.snapshot.durationMs,
      'errorMessage': this.snapshot.errorMessage
    });
  }

  private handleDurationUpdate(durationMs: number): void {
    hilog.debug(DOMAIN, TAG, 'Controller handleDurationUpdate durationMs=%{public}d', durationMs);
    if (!this.currentRequest) {
      return;
    }
    if (!isProgressSnapshotPhase(this.snapshot.phase)) {
      return;
    }

    const nextDuration = durationMs > 0 ? durationMs : this.snapshot.durationMs;
    this.setSnapshot({
      'messageId': this.currentRequest.messageId,
      'phase': this.snapshot.phase,
      'positionMs': this.snapshot.positionMs,
      'durationMs': nextDuration,
      'errorMessage': this.snapshot.errorMessage
    });
  }

  private applyErrorState(errorMessage: string): void {
    hilog.debug(
      DOMAIN,
      TAG,
      'Controller applyErrorState error=%{public}s current=%{public}s snapshot=%{public}s',
      errorMessage,
      formatPlaybackRequestForLog(this.currentRequest),
      formatSnapshotForLog(this.snapshot)
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

  private isSameMessage(request: VoiceNotePlaybackRequest): boolean {
    return this.currentRequest !== undefined && this.currentRequest.messageId === request.messageId;
  }

  private setSnapshot(snapshot: VoiceNotePlaybackSnapshot): void {
    this.snapshot = {
      'messageId': snapshot.messageId,
      'phase': snapshot.phase,
      'positionMs': snapshot.positionMs,
      'durationMs': snapshot.durationMs,
      'errorMessage': snapshot.errorMessage
    };
    hilog.debug(DOMAIN, TAG, 'Controller snapshot updated: %{public}s', formatSnapshotForLog(this.snapshot));
    this.notifyListener();
  }

  private notifyListener(): void {
    if (!this.listener) {
      hilog.debug(DOMAIN, TAG, 'Controller notifyListener skipped: no listener.');
      return;
    }
    hilog.debug(DOMAIN, TAG, 'Controller notifyListener dispatch: %{public}s', formatSnapshotForLog(this.snapshot));
    this.listener(this.getSnapshot());
  }
}
