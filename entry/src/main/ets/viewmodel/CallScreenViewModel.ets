import { hilog } from '@kit.PerformanceAnalysisKit';
import { tdClient } from '../services/td/TdClient';
import { tdCallEventDispatcher } from '../services/td/TdCallEventDispatcher';
import type { TdCallEvent, TdParsedCallPayload, TdUserProfileItem } from '../services/td/TdPayloadTypes';
import { buildDefaultTdCallProtocolRequest } from '../services/voip/CallProtocolRequestBuilder';
import { callAcceptObserverHub } from '../services/voip/CallAcceptObserverHub';
import { callRuntimeService } from '../services/voip/CallRuntimeService';
import { parsePositiveIntegerText } from '../utils/NumericTextParser';
import { CallScreenDirection, CallScreenMockMode } from '../models/voip/CallScreenTypes';

const DOMAIN = 0x2026;
const TAG = 'CallScreenViewModel';

/** Interval used by the duration timer (1 Hz). */
const DURATION_TICK_MS = 1000;

/**
 * Semantic call-screen phase emitted by the view model.
 *
 * The view maps each phase to a localized `ResourceStr`; keeping `$r` out of
 * the view model preserves the MVVM boundary (view model never touches UI
 * resources, view never touches TDLib).
 *
 * `incomingRinging` is pre-accept for an incoming call opened with
 * `pendingAccept=true` — the VM is waiting for user `acceptIncomingCall()` /
 * `rejectIncomingCall()`.
 */
export type CallScreenPhase =
  'incomingRinging' | 'answering' | 'calling' | 'ringing' | 'connecting' | 'connected' |
  'ending' | 'ended' | 'failed' | 'invalidCall' | 'invalidUser' |
  'answerFailed' | 'createFailed';

/**
 * Peer information emitted to the view (Task 4.6 — avatar + name source of truth).
 */
export interface CallScreenPeerInfo {
  'name': string;
  'avatarPath': string;
  'avatarAnimationPath': string;
}

/**
 * Phases that reflect a failed or invalid call.
 */
const ERROR_PHASES: Set<CallScreenPhase> = new Set<CallScreenPhase>([
  'failed', 'invalidCall', 'invalidUser', 'answerFailed', 'createFailed'
]);

/**
 * Terminal phases after which the view should schedule a return navigation —
 * every error phase plus the normal `ended` discard.
 */
const TERMINAL_PHASES: Set<CallScreenPhase> = new Set<CallScreenPhase>([
  'ended', 'failed', 'invalidCall', 'invalidUser', 'answerFailed', 'createFailed'
]);

/**
 * View model for the unified call screen (ADR-0007 + Task 4.6 extensions).
 *
 * Owns all TDLib interaction for the call lifecycle — `acceptCall` /
 * `createCall` / `discardCall`, call-event subscription, peer profile load,
 * duration timer, and the call-state machine — and exposes only semantic
 * `CallScreenPhase` updates plus peer/duration/audio-level streams to the view.
 */
export class CallScreenViewModel {
  private callId: number = 0;
  private userId: string = '';
  private direction: CallScreenDirection = 'outgoing';
  private callEventSubscriptionId: number = 0;
  private acceptObserverSubscriptionId: number = 0;
  private phaseListener?: (phase: CallScreenPhase) => void;
  private audioLevelListener?: (level: number) => void;
  private peerListener?: (peer: CallScreenPeerInfo) => void;
  private durationListener?: (seconds: number) => void;
  private currentPhase: CallScreenPhase = 'calling';
  private peer: CallScreenPeerInfo = { name: '', avatarPath: '', avatarAnimationPath: '' };
  private pendingAccept: boolean = false;
  private acceptDispatched: boolean = false;
  private rejectDispatched: boolean = false;
  private endDispatched: boolean = false;
  private connectedSinceMs: number = 0;
  private lastDurationSeconds: number = 0;
  private durationIntervalId: number = -1;
  /**
   * Debug-only mock-mode flag. When non-empty, all paths that would have
   * touched TDLib (event subscription, `acceptCall`, `discardCall`) are
   * bypassed and the VM drives phase / duration purely from local input.
   *
   * TODO(task-4.6 cleanup): remove together with `startMockCall`.
   */
  private mockMode: string = '';

  /**
   * Registers the listener invoked on every call-screen phase change.
   *
   * @param listener Callback invoked with the latest semantic phase.
   */
  setPhaseListener(listener: (phase: CallScreenPhase) => void): void {
    this.phaseListener = listener;
  }

  /**
   * Registers the listener invoked with the outgoing-microphone level [0.0, 1.0]
   * while a call is active (M2.4.2).
   *
   * @param listener Callback invoked with the latest audio level.
   */
  setAudioLevelListener(listener: (level: number) => void): void {
    this.audioLevelListener = listener;
  }

  /**
   * Registers the listener invoked with peer display name + avatar paths
   * (Task 4.6 A — avatar + name on the call screen).
   *
   * @param listener Callback invoked with the latest peer snapshot.
   */
  setPeerListener(listener: (peer: CallScreenPeerInfo) => void): void {
    this.peerListener = listener;
  }

  /**
   * Registers the listener invoked with elapsed call duration in seconds
   * (Task 4.6 B — 1 Hz timer that ticks while phase is `connected`).
   *
   * @param listener Callback invoked with the latest duration.
   */
  setDurationListener(listener: (seconds: number) => void): void {
    this.durationListener = listener;
  }

  /**
   * Reports whether a phase is terminal and the view should return back.
   *
   * @param phase Phase emitted by the view model.
   * @returns `true` when the call screen should schedule a return.
   */
  isTerminalPhase(phase: CallScreenPhase): boolean {
    return TERMINAL_PHASES.has(phase);
  }

  /**
   * Reports whether a phase reflects a failed or invalid call.
   *
   * @param phase Phase emitted by the view model.
   * @returns `true` when the phase is an error phase.
   */
  isErrorPhase(phase: CallScreenPhase): boolean {
    return ERROR_PHASES.has(phase);
  }

  /**
   * Accepts the incoming call identified by the route param and tracks its state.
   * When `pendingAccept` is `true`, the VM does NOT call `acceptCall` — it waits
   * for the user to tap Accept/Reject in the UI (Task 4.6 F1/F4/F5).
   *
   * @param rawCallId Route-supplied TDLib call id (number or numeric string).
   * @param rawUserId Route-supplied TDLib user id (auto-open path provides this).
   * @param pendingAccept When `true`, defer `acceptCall` to user tap.
   */
  startIncomingCall(
    rawCallId: number | string | undefined,
    rawUserId: string | undefined,
    pendingAccept: boolean
  ): void {
    this.direction = 'incoming';
    this.pendingAccept = pendingAccept;
    this.callId = this.parseCallId(rawCallId);
    if (this.callId <= 0) {
      hilog.warn(DOMAIN, TAG, 'startIncomingCall: invalid call id after parsing.');
      this.emitPhase('invalidCall');
      return;
    }

    this.captureUserId(rawUserId);
    this.subscribeCallEvents();
    this.refreshPeerFromCache();

    if (pendingAccept) {
      hilog.info(DOMAIN, TAG, 'startIncomingCall pendingAccept callId=%{public}d userId=%{public}s',
        this.callId,
        this.userId
      );
      this.emitPhase('incomingRinging');
      return;
    }

    this.emitPhase('answering');
    hilog.info(DOMAIN, TAG, 'startIncomingCall accept callId=%{public}d', this.callId);
    const started = tdClient.acceptCall(this.callId, buildDefaultTdCallProtocolRequest());
    if (!started) {
      hilog.warn(DOMAIN, TAG, 'acceptCall was not sent for call %{public}d', this.callId);
      this.emitPhase('answerFailed');
    } else {
      this.acceptDispatched = true;
    }
  }

  /**
   * Places an outgoing call to the route-supplied user and tracks its state.
   *
   * @param rawUserId Route-supplied TDLib user id string.
   */
  startOutgoingCall(rawUserId: string | undefined): void {
    this.direction = 'outgoing';
    this.emitPhase('calling');
    this.captureUserId(rawUserId);
    if (this.userId.length === 0 || this.userId === '-') {
      hilog.warn(DOMAIN, TAG, 'startOutgoingCall: invalid user id.');
      this.emitPhase('invalidUser');
      return;
    }

    this.subscribeCallEvents();
    this.refreshPeerFromCache();
    hilog.info(DOMAIN, TAG, 'startOutgoingCall userId=%{public}s', this.userId);
    const started = tdClient.createCall(
      this.userId,
      buildDefaultTdCallProtocolRequest(),
      false,
      (callId: number, errorMessage: string): void => {
        this.handleCallCreated(callId, errorMessage);
      }
    );
    if (!started) {
      hilog.warn(DOMAIN, TAG, 'createCall was not sent for user %{public}s', this.userId);
      this.emitPhase('createFailed');
    }
  }

  /**
   * Re-attaches to an already-active call (opened from the ongoing-call
   * notification). Unlike `startIncomingCall` / `startOutgoingCall` it does
   * NOT initiate `acceptCall` / `createCall` — the call is already in progress.
   * It only subscribes to call events and reflects the live state.
   *
   * @param rawCallId TDLib call id of the active call.
   * @param rawUserId Optional TDLib user id (when known by the caller).
   */
  resumeCall(rawCallId: number | string | undefined, rawUserId: string | undefined): void {
    this.callId = this.parseCallId(rawCallId);
    if (this.callId <= 0) {
      hilog.warn(DOMAIN, TAG, 'resumeCall: invalid call id.');
      this.emitPhase('invalidCall');
      return;
    }

    this.captureUserId(rawUserId);
    this.subscribeCallEvents();
    this.refreshPeerFromCache();
    hilog.info(DOMAIN, TAG, 'resumeCall callId=%{public}d userId=%{public}s',
      this.callId,
      this.userId
    );
    // The ongoing-call notification only exists while the call is connected;
    // subsequent updateCall events refine the phase (e.g. discarded -> ended).
    this.emitPhase('connected');
  }

  /**
   * Debug-only entry point: render the call screen in a fixed phase
   * without subscribing to TDLib events and without dispatching real
   * `acceptCall` / `discardCall`. Used by the Profile debug buttons to
   * iterate on UI layout on real hardware.
   *
   * TODO(task-4.6 cleanup): remove together with `mockMode` field and
   * the Profile debug entries before merging Task 4.6 follow-ups.
   *
   * @param rawCallId Fake TDLib call id (any positive value).
   * @param rawUserId Optional real user id — peer info still loads from
   *   the TDLib cache when available, so layout is exercised against a
   *   real avatar / name.
   * @param peerName Override for `peer.name` when no cache hit is available.
   * @param mockMode Phase to render: `incomingRinging` (pre-accept),
   *   `connected` (in-call with timer + mute + End), `outgoing` (calling
   *   pre-connect with only End).
   */
  startMockCall(
    rawCallId: number | string | undefined,
    rawUserId: string | undefined,
    peerName: string,
    mockMode: CallScreenMockMode
  ): void {
    this.mockMode = mockMode;
    this.callId = this.parseCallId(rawCallId);
    if (this.callId <= 0) {
      this.callId = 999999;
    }
    this.captureUserId(rawUserId);
    if (peerName.length > 0) {
      this.peer = {
        name: peerName,
        avatarPath: this.peer.avatarPath,
        avatarAnimationPath: this.peer.avatarAnimationPath
      };
      if (this.peerListener) {
        this.peerListener(this.peer);
      }
    }
    this.refreshPeerFromCache();

    if (mockMode === 'incomingRinging') {
      this.direction = 'incoming';
      this.emitPhase('incomingRinging');
      return;
    }
    if (mockMode === 'connected') {
      this.direction = 'incoming';
      this.emitPhase('connected');
      return;
    }
    // 'outgoing' — render the calling pre-connect screen.
    this.direction = 'outgoing';
    this.emitPhase('calling');
  }

  /**
   * Accepts a pending incoming call after the user tapped Accept in the UI
   * (Task 4.6 F4). Idempotent — a second tap during `answering`/`connecting`
   * is a no-op.
   *
   * @returns `true` when the `acceptCall` request was sent on this call.
   */
  acceptIncomingCall(): boolean {
    if (this.acceptDispatched) {
      hilog.info(DOMAIN, TAG, 'acceptIncomingCall ignored: already dispatched.');
      return false;
    }
    if (this.currentPhase !== 'incomingRinging') {
      hilog.info(DOMAIN, TAG, 'acceptIncomingCall ignored: phase=%{public}s', this.currentPhase);
      return false;
    }
    if (this.callId <= 0) {
      hilog.warn(DOMAIN, TAG, 'acceptIncomingCall ignored: invalid call id.');
      return false;
    }
    this.emitPhase('answering');
    if (this.mockMode.length > 0) {
      // TODO(task-4.6 cleanup): remove mock branch with `mockMode`.
      this.acceptDispatched = true;
      this.emitPhase('connected');
      return true;
    }
    const started = tdClient.acceptCall(this.callId, buildDefaultTdCallProtocolRequest());
    if (!started) {
      hilog.warn(DOMAIN, TAG, 'acceptCall was not sent for call %{public}d', this.callId);
      this.emitPhase('answerFailed');
      return false;
    }
    this.acceptDispatched = true;
    hilog.info(DOMAIN, TAG, 'acceptCall sent for call %{public}d', this.callId);
    return true;
  }

  /**
   * Rejects a pending incoming call after the user tapped Decline in the UI
   * (Task 4.6 F5). Idempotent — a second tap is a no-op. Symmetric with
   * `acceptIncomingCall`: rejects when the call has already moved past the
   * pre-accept stage (Accept tap dispatched within this VM, or notification
   * Answer shortcut already drove the call beyond `incomingRinging`).
   *
   * @returns `true` when the `discardCall` request was sent on this call.
   */
  rejectIncomingCall(): boolean {
    if (this.rejectDispatched || this.endDispatched) {
      hilog.info(DOMAIN, TAG, 'rejectIncomingCall ignored: already dispatched.');
      return false;
    }
    if (this.acceptDispatched) {
      hilog.info(DOMAIN, TAG, 'rejectIncomingCall ignored: accept already dispatched.');
      return false;
    }
    if (this.currentPhase !== 'incomingRinging') {
      hilog.info(DOMAIN, TAG, 'rejectIncomingCall ignored: phase=%{public}s', this.currentPhase);
      return false;
    }
    if (this.callId <= 0) {
      hilog.warn(DOMAIN, TAG, 'rejectIncomingCall ignored: invalid call id.');
      return false;
    }
    this.emitPhase('ending');
    if (this.mockMode.length > 0) {
      // TODO(task-4.6 cleanup): remove mock branch with `mockMode`.
      this.rejectDispatched = true;
      this.emitPhase('ended');
      return true;
    }
    const dispatched = tdClient.discardCall(this.callId, false, 0, false, '0');
    if (!dispatched) {
      hilog.warn(DOMAIN, TAG, 'discardCall reject was not sent for call %{public}d', this.callId);
      return false;
    }
    this.rejectDispatched = true;
    hilog.info(DOMAIN, TAG, 'discardCall reject sent for call %{public}d', this.callId);
    return true;
  }

  /**
   * Ends an active call (Task 4.6 C2). Sends `discardCall` with the last
   * known duration. Idempotent — a second tap is a no-op.
   *
   * @returns `true` when the `discardCall` request was sent on this call.
   */
  endCall(): boolean {
    if (this.endDispatched || this.rejectDispatched) {
      hilog.info(DOMAIN, TAG, 'endCall ignored: already dispatched.');
      return false;
    }
    if (this.callId <= 0) {
      hilog.warn(DOMAIN, TAG, 'endCall ignored: invalid call id.');
      return false;
    }
    this.emitPhase('ending');
    if (this.mockMode.length > 0) {
      // TODO(task-4.6 cleanup): remove mock branch with `mockMode`.
      this.endDispatched = true;
      this.emitPhase('ended');
      return true;
    }
    const dispatched = tdClient.discardCall(
      this.callId,
      false,
      this.lastDurationSeconds,
      false,
      '0'
    );
    if (!dispatched) {
      hilog.warn(DOMAIN, TAG, 'discardCall end was not sent for call %{public}d', this.callId);
      return false;
    }
    this.endDispatched = true;
    hilog.info(DOMAIN, TAG, 'discardCall end sent for call %{public}d duration=%{public}d',
      this.callId,
      this.lastDurationSeconds
    );
    return true;
  }

  /**
   * Mutes or unmutes the outgoing microphone for the active call.
   *
   * @param muted `true` to mute, `false` to unmute.
   * @returns `true` when the request reached an active native session.
   */
  setMuted(muted: boolean): boolean {
    if (this.mockMode.length > 0) {
      // TODO(task-4.6 cleanup): remove mock branch with `mockMode`. The
      // UI toggle flips locally so the muted-button colour can be polished
      // without a live native session.
      hilog.info(DOMAIN, TAG, 'setMuted mock muted=%{public}d', muted ? 1 : 0);
      return true;
    }
    const applied = callRuntimeService.setMuteMicrophone(muted);
    hilog.info(DOMAIN, TAG, 'setMuted muted=%{public}d applied=%{public}d', muted ? 1 : 0, applied ? 1 : 0);
    return applied;
  }

  /**
   * Releases the call-event subscription. Call from the view's `aboutToDisappear`.
   */
  dispose(): void {
    this.stopDurationTimer();
    this.unsubscribeCallEvents();
    this.phaseListener = undefined;
    this.peerListener = undefined;
    this.durationListener = undefined;
  }

  /**
   * Stores the created call id, or emits a failure phase when TDLib rejected `createCall`.
   *
   * @param callId TDLib call id returned by `createCall`.
   * @param errorMessage TDLib error message, empty on success.
   */
  private handleCallCreated(callId: number, errorMessage: string): void {
    if (callId <= 0) {
      hilog.warn(DOMAIN, TAG, 'createCall failed: %{public}s', errorMessage);
      this.emitPhase('createFailed');
      return;
    }

    this.callId = callId;
    hilog.info(DOMAIN, TAG, 'createCall accepted callId=%{public}d', callId);
  }

  private captureUserId(rawUserId: string | undefined): void {
    if (this.userId.length > 0) {
      return;
    }
    if (typeof rawUserId !== 'string') {
      return;
    }
    const trimmed = rawUserId.trim();
    if (trimmed.length === 0 || trimmed === '-') {
      return;
    }
    this.userId = trimmed;
  }

  private refreshPeerFromCache(): void {
    if (this.userId.length === 0) {
      return;
    }
    const profile: TdUserProfileItem | undefined = tdClient.getUserProfile(this.userId);
    if (!profile) {
      hilog.info(DOMAIN, TAG, 'Peer profile miss for userId=%{public}s', this.userId);
      return;
    }
    const nextName = this.composePeerName(profile);
    const nextAvatarPath = typeof profile.avatarPath === 'string' ? profile.avatarPath : '';
    const nextAnimationPath = typeof profile.avatarAnimationPath === 'string'
      ? profile.avatarAnimationPath
      : '';
    if (nextName === this.peer.name
      && nextAvatarPath === this.peer.avatarPath
      && nextAnimationPath === this.peer.avatarAnimationPath) {
      return;
    }
    this.peer = {
      name: nextName,
      avatarPath: nextAvatarPath,
      avatarAnimationPath: nextAnimationPath
    };
    if (this.peerListener) {
      this.peerListener(this.peer);
    }
  }

  private composePeerName(profile: TdUserProfileItem): string {
    const first = profile.firstName.trim();
    const last = profile.lastName.trim();
    if (first.length > 0 && last.length > 0) {
      return `${first} ${last}`;
    }
    if (first.length > 0) {
      return first;
    }
    if (last.length > 0) {
      return last;
    }
    const username = profile.username.trim();
    if (username.length > 0) {
      return username;
    }
    return '';
  }

  private parseCallId(value: number | string | undefined): number {
    if (typeof value === 'number' && value > 0) {
      return Math.trunc(value);
    }
    if (typeof value === 'string' && value.length > 0) {
      return parsePositiveIntegerText(value);
    }
    return 0;
  }

  private subscribeCallEvents(): void {
    if (this.callEventSubscriptionId > 0) {
      return;
    }
    this.callEventSubscriptionId = tdCallEventDispatcher.subscribe((event: TdCallEvent): void => {
      this.handleCallEvent(event);
    });
    // Task 4.6 P1 follow-up: the notification answer shortcut dispatches
    // `acceptCall` directly from `EntryAbility`, bypassing this VM. Subscribe
    // to the accept-observer hub so we still flip `acceptDispatched` / phase
    // immediately and close the Reject-after-external-accept window.
    this.acceptObserverSubscriptionId = callAcceptObserverHub.subscribe(
      (callId: number): void => {
        this.handleExternalAccept(callId);
      }
    );
    // M2.4.2: pipe the native outgoing-microphone level through to the view's listener.
    callRuntimeService.setAudioLevelListener((level: number): void => {
      if (this.audioLevelListener) {
        this.audioLevelListener(level);
      }
    });
    hilog.info(DOMAIN, TAG, 'Subscribed call events direction=%{public}s subscription=%{public}d',
      this.direction,
      this.callEventSubscriptionId
    );
  }

  private unsubscribeCallEvents(): void {
    callRuntimeService.setAudioLevelListener(undefined);
    if (this.acceptObserverSubscriptionId > 0) {
      callAcceptObserverHub.unsubscribe(this.acceptObserverSubscriptionId);
      this.acceptObserverSubscriptionId = 0;
    }
    if (this.callEventSubscriptionId <= 0) {
      return;
    }
    tdCallEventDispatcher.unsubscribe(this.callEventSubscriptionId);
    this.callEventSubscriptionId = 0;
  }

  /**
   * Reacts to an external `acceptCall` dispatch for this VM's call id by
   * promoting the VM state — `acceptDispatched` becomes the same source of
   * truth as for the in-screen Accept tap, so a subsequent Decline tap in
   * the still-rendered `incomingRinging` phase becomes a no-op even before
   * TDLib emits `exchangingKeys`.
   *
   * @param callId TDLib call id reported by the accept-observer hub.
   */
  private handleExternalAccept(callId: number): void {
    if (this.callId <= 0 || callId !== this.callId) {
      return;
    }
    if (this.acceptDispatched) {
      return;
    }
    this.acceptDispatched = true;
    hilog.info(DOMAIN, TAG, 'External accept observed for callId=%{public}d phase=%{public}s',
      this.callId,
      this.currentPhase
    );
    if (this.currentPhase === 'incomingRinging') {
      this.emitPhase('answering');
    }
  }

  private handleCallEvent(event: TdCallEvent): void {
    if (event.kind !== 'call' || event.call === undefined) {
      return;
    }

    const call = event.call;
    if (this.callId <= 0 || call.id !== this.callId) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'Observed call event callId=%{public}d state=%{public}s',
      call.id,
      call.state.kind
    );
    // Late peer discovery: the call payload always carries `userId`; use it
    // to fill in name/avatar when the route did not provide one (legacy
    // notification answer path, resume-from-notification with stale cache).
    if (this.userId.length === 0 && call.userId.length > 0) {
      this.userId = call.userId;
    }
    this.refreshPeerFromCache();
    this.applyCallState(call);
  }

  private applyCallState(call: TdParsedCallPayload): void {
    if (call.state.kind === 'pending') {
      // Incoming pendingAccept path stays in `incomingRinging` until the user
      // taps Accept; outgoing surfaces `ringing` once TDLib reports pending.
      if (this.direction === 'outgoing') {
        this.emitPhase('ringing');
      }
      return;
    }
    if (call.state.kind === 'exchangingKeys') {
      this.emitPhase('connecting');
      return;
    }
    if (call.state.kind === 'ready') {
      // ADR-0007: `ready`/connected is the anchor for M2.4 in-call controls
      // (mute / hangup / audio level / duration).
      this.emitPhase('connected');
      return;
    }
    if (call.state.kind === 'hangingUp') {
      this.emitPhase('ending');
      return;
    }
    if (call.state.kind === 'error') {
      this.emitPhase('failed');
      return;
    }
    if (call.state.kind === 'discarded') {
      this.emitPhase('ended');
    }
  }

  private emitPhase(phase: CallScreenPhase): void {
    if (this.currentPhase === phase) {
      return;
    }
    const previous = this.currentPhase;
    this.currentPhase = phase;
    if (phase === 'connected') {
      this.startDurationTimer();
    } else if (previous === 'connected') {
      this.stopDurationTimer();
    }
    if (this.phaseListener) {
      this.phaseListener(phase);
    }
  }

  private startDurationTimer(): void {
    if (this.durationIntervalId >= 0) {
      return;
    }
    this.connectedSinceMs = Date.now();
    this.lastDurationSeconds = 0;
    if (this.durationListener) {
      this.durationListener(0);
    }
    this.durationIntervalId = setInterval((): void => {
      this.tickDuration();
    }, DURATION_TICK_MS);
  }

  private tickDuration(): void {
    if (this.connectedSinceMs <= 0) {
      return;
    }
    const elapsed = Math.max(0, Math.floor((Date.now() - this.connectedSinceMs) / 1000));
    if (elapsed === this.lastDurationSeconds) {
      return;
    }
    this.lastDurationSeconds = elapsed;
    if (this.durationListener) {
      this.durationListener(elapsed);
    }
  }

  private stopDurationTimer(): void {
    if (this.durationIntervalId < 0) {
      return;
    }
    clearInterval(this.durationIntervalId);
    this.durationIntervalId = -1;
  }
}
