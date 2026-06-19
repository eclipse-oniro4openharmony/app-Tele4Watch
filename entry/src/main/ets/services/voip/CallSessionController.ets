import { hilog } from '@kit.PerformanceAnalysisKit';
import { tgCallSessionClient } from 'tgcall';
import type { TgCallStartRequest } from 'tgcall';
import { buildErrorMessage } from '../../utils/ErrorMessage';
import type { TdCallEvent, TdParsedCallPayload, TdParsedCallServerPayload } from '../td/TdPayloadTypes';
import {
  mapReadyCallToTgCallStartRequest,
  TgCallStartRequestMapResult
} from './TgCallStartRequestMapper';
import type { TgCallSessionBridge } from './TgCallSessionBridge';
import { voipBackgroundTask } from './VoipBackgroundTask';

const DOMAIN = 0x2026;
const TAG = 'CallSessionController';

export interface ActiveCallSessionSnapshot {
  'callId': number;
  'instanceId': number;
}

export interface CallSignalingSender {
  'sendCallSignalingData': (callId: number, data: string) => boolean;
}

class NoopCallSignalingSender implements CallSignalingSender {
  sendCallSignalingData(callId: number, data: string): boolean {
    hilog.warn(
      DOMAIN,
      TAG,
      'Dropped emitted call signaling data without sender callId=%{public}d dataLen=%{public}d',
      callId,
      data.length
    );
    return false;
  }
}

const noopCallSignalingSender: NoopCallSignalingSender = new NoopCallSignalingSender();

export class CallSessionController {
  private readonly sessionBridge: TgCallSessionBridge;
  private readonly signalingSender: CallSignalingSender;
  private activeCallId: number = 0;
  private activeInstanceId: number = 0;
  private audioLevelListener?: (level: number) => void;

  constructor(sessionBridge?: TgCallSessionBridge, signalingSender?: CallSignalingSender) {
    this.sessionBridge = sessionBridge ? sessionBridge : tgCallSessionClient;
    this.signalingSender = signalingSender ? signalingSender : noopCallSignalingSender;
  }

  /**
   * Registers the listener notified with the active call's outgoing-microphone level
   * (M2.4.2). Replaces any previous listener; pass `undefined` to clear.
   *
   * @param listener Callback invoked with a level in [0.0, 1.0].
   */
  setAudioLevelListener(listener: ((level: number) => void) | undefined): void {
    this.audioLevelListener = listener;
  }

  /**
   * Handles one parsed TDLib call event and updates the native tgcall session.
   *
   * @param event Parsed TDLib call event emitted by `TdClient`.
   */
  handleCallEvent(event: TdCallEvent): void {
    if (event.kind === 'call') {
      if (event.call === undefined) {
        return;
      }
      this.handleCallUpdate(event.call);
      return;
    }

    if (typeof event.callId !== 'number' || typeof event.data !== 'string') {
      return;
    }
    this.handleSignalingData(event.callId, event.data);
  }

  /**
   * Stops the active native session when present.
   */
  reset(): void {
    this.stopActiveSession('reset');
  }

  /**
   * Mutes or unmutes the microphone for the active native call session.
   *
   * @param muted `true` to mute the outgoing microphone, `false` to unmute.
   * @returns `true` when the request was forwarded to an active native session.
   */
  setMuteMicrophone(muted: boolean): boolean {
    if (this.activeInstanceId <= 0) {
      hilog.warn(DOMAIN, TAG, 'setMuteMicrophone ignored: no active native session');
      return false;
    }
    try {
      this.sessionBridge.setMuteMicrophone(this.activeInstanceId, muted);
      hilog.info(
        DOMAIN,
        TAG,
        'setMuteMicrophone callId=%{public}d instanceId=%{public}d muted=%{public}d',
        this.activeCallId,
        this.activeInstanceId,
        muted ? 1 : 0
      );
      return true;
    } catch (error) {
      hilog.warn(
        DOMAIN,
        TAG,
        'Failed to set microphone mute callId=%{public}d instanceId=%{public}d: %{public}s',
        this.activeCallId,
        this.activeInstanceId,
        buildErrorMessage(error)
      );
      return false;
    }
  }

  /**
   * Returns active native session ids for tests and diagnostics.
   *
   * @returns Current session ids or `undefined` when no native session is active.
   */
  getActiveSessionSnapshot(): ActiveCallSessionSnapshot | undefined {
    if (this.activeCallId <= 0 || this.activeInstanceId <= 0) {
      return undefined;
    }
    return {
      'callId': this.activeCallId,
      'instanceId': this.activeInstanceId
    };
  }

  private handleCallUpdate(call: TdParsedCallPayload): void {
    if (call.state.kind === 'ready') {
      this.startReadyCall(call);
      return;
    }

    if (call.state.kind === 'discarded' || call.state.kind === 'error') {
      if (this.activeCallId === call.id) {
        this.stopActiveSession(call.state.kind);
        return;
      }
      hilog.debug(
        DOMAIN,
        TAG,
        'Ignored call end without active native session callId=%{public}d state=%{public}s activeCallId=%{public}d',
        call.id,
        call.state.kind,
        this.activeCallId
      );
    }
  }

  private startReadyCall(call: TdParsedCallPayload): void {
    if (this.activeCallId === call.id && this.activeInstanceId > 0) {
      hilog.debug(
        DOMAIN,
        TAG,
        'Ignored duplicate ready call update callId=%{public}d instanceId=%{public}d',
        call.id,
        this.activeInstanceId
      );
      return;
    }

    hilog.info(
      DOMAIN,
      TAG,
      'Ready call update received callId=%{public}d outgoing=%{public}d video=%{public}d servers=%{public}d keyLen=%{public}d customLen=%{public}d',
      call.id,
      call.isOutgoing ? 1 : 0,
      call.isVideo ? 1 : 0,
      call.state.servers === undefined ? 0 : call.state.servers.length,
      call.state.encryptionKey === undefined ? 0 : call.state.encryptionKey.length,
      call.state.customParameters === undefined ? 0 : call.state.customParameters.length
    );
    if (call.state.protocol !== undefined) {
      hilog.info(
        DOMAIN,
        TAG,
        'Ready call protocol callId=%{public}d minLayer=%{public}d maxLayer=%{public}d versions=%{public}s',
        call.id,
        call.state.protocol.minLayer,
        call.state.protocol.maxLayer,
        call.state.protocol.libraryVersions.join(',')
      );
    }

    const nativeSupportedVersions = this.readNativeSupportedVersions(call.id);
    const mappedRequest: TgCallStartRequestMapResult = mapReadyCallToTgCallStartRequest(call, nativeSupportedVersions);
    if (!mappedRequest.ok || mappedRequest.request === undefined) {
      hilog.warn(
        DOMAIN,
        TAG,
        'Skipped tgcall start for call %{public}d: %{public}s',
        call.id,
        mappedRequest.error === undefined ? 'invalidReadyState' : mappedRequest.error
      );
      return;
    }

    this.logMappedStartRequest(call.id, mappedRequest.request);

    if (this.activeInstanceId > 0) {
      this.stopActiveSession('replaced');
    }

    try {
      const readyCallId = call.id;
      // ADR-0008: the native session emits signaling asynchronously (the caller's
      // InitialSetup, then trickling ICE candidates). This callback fires on the JS
      // thread whenever something is queued, so emitted data reaches TDLib promptly
      // instead of sitting in the native queue until the next feed/stop.
      const instanceId = this.sessionBridge.startCall(
        mappedRequest.request,
        (notifiedInstanceId: number): void => {
          this.handleNativeSignalingAvailable(readyCallId, notifiedInstanceId);
        },
        (level: number): void => {
          this.handleAudioLevel(readyCallId, level);
        }
      );
      if (instanceId <= 0) {
        hilog.warn(DOMAIN, TAG, 'Native tgcall returned invalid instance id for call %{public}d', call.id);
        return;
      }

      this.activeCallId = call.id;
      this.activeInstanceId = instanceId;
      this.flushEmittedSignalingData(call.id, instanceId, 'start');
      // M2.4.3: keep the app alive across screen-off for the duration of the call.
      void voipBackgroundTask.start();
      hilog.info(
        DOMAIN,
        TAG,
        'Started native call session callId=%{public}d instanceId=%{public}d',
        call.id,
        instanceId
      );
    } catch (error) {
      hilog.warn(
        DOMAIN,
        TAG,
        'Failed to start native call session callId=%{public}d: %{public}s',
        call.id,
        buildErrorMessage(error)
      );
    }
  }

  /**
   * Handles the native "signaling available" push (ADR-0008): drains and forwards
   * the data the native session queued, as soon as it queues it.
   *
   * @param callId TDLib call id captured when the session was started.
   * @param instanceId Native tgcall instance id reported by the notifier.
   */
  private handleNativeSignalingAvailable(callId: number, instanceId: number): void {
    if (callId !== this.activeCallId || instanceId !== this.activeInstanceId) {
      hilog.debug(
        DOMAIN,
        TAG,
        'Ignored native signaling notification for inactive session callId=%{public}d instanceId=%{public}d activeCallId=%{public}d activeInstanceId=%{public}d',
        callId,
        instanceId,
        this.activeCallId,
        this.activeInstanceId
      );
      return;
    }
    this.flushEmittedSignalingData(callId, instanceId, 'native-push');
  }

  /**
   * Handles the native outgoing-microphone level push (M2.4.2) and forwards it to the
   * registered listener, guarded against stale/inactive sessions.
   *
   * @param callId TDLib call id captured when the session was started.
   * @param level Outgoing-microphone level in [0.0, 1.0].
   */
  private handleAudioLevel(callId: number, level: number): void {
    if (callId !== this.activeCallId) {
      return;
    }
    if (this.audioLevelListener) {
      this.audioLevelListener(level);
    }
  }

  private handleSignalingData(callId: number, dataBase64: string): void {
    if (callId !== this.activeCallId || this.activeInstanceId <= 0) {
      hilog.debug(
        DOMAIN,
        TAG,
        'Ignored signaling data without active matching session callId=%{public}d activeCallId=%{public}d activeInstanceId=%{public}d dataLen=%{public}d',
        callId,
        this.activeCallId,
        this.activeInstanceId,
        dataBase64.length
      );
      return;
    }

    if (dataBase64.length === 0) {
      hilog.debug(DOMAIN, TAG, 'Ignored empty signaling data callId=%{public}d', callId);
      return;
    }

    try {
      this.sessionBridge.feedSignalingData(this.activeInstanceId, dataBase64);
      this.flushEmittedSignalingData(callId, this.activeInstanceId, 'feed');
      hilog.debug(
        DOMAIN,
        TAG,
        'Fed call signaling data callId=%{public}d instanceId=%{public}d dataLen=%{public}d',
        callId,
        this.activeInstanceId,
        dataBase64.length
      );
    } catch (error) {
      hilog.warn(
        DOMAIN,
        TAG,
        'Failed to feed call signaling data callId=%{public}d instanceId=%{public}d: %{public}s',
        callId,
        this.activeInstanceId,
        buildErrorMessage(error)
      );
      this.stopActiveSession('feedFailed');
    }
  }

  private flushEmittedSignalingData(callId: number, instanceId: number, source: string): void {
    let emittedData: string[] = [];
    try {
      emittedData = this.sessionBridge.drainSignalingData(instanceId);
    } catch (error) {
      hilog.warn(
        DOMAIN,
        TAG,
        'Failed to drain emitted call signaling data callId=%{public}d instanceId=%{public}d source=%{public}s: %{public}s',
        callId,
        instanceId,
        source,
        buildErrorMessage(error)
      );
      return;
    }

    for (const data of emittedData) {
      const safeData = data.trim();
      if (safeData.length === 0) {
        continue;
      }
      const sent = this.signalingSender.sendCallSignalingData(callId, safeData);
      if (!sent) {
        hilog.warn(
          DOMAIN,
          TAG,
          'Failed to send emitted call signaling data callId=%{public}d instanceId=%{public}d source=%{public}s dataLen=%{public}d',
          callId,
          instanceId,
          source,
          safeData.length
        );
      }
    }

    if (emittedData.length > 0) {
      hilog.info(
        DOMAIN,
        TAG,
        'Drained emitted call signaling data callId=%{public}d instanceId=%{public}d source=%{public}s count=%{public}d',
        callId,
        instanceId,
        source,
        emittedData.length
      );
    }
  }

  private logMappedStartRequest(callId: number, request: TgCallStartRequest): void {
    hilog.info(
      DOMAIN,
      TAG,
      'Mapped ready call to tgcall start request callId=%{public}d serversJsonLen=%{public}d keyLen=%{public}d allowP2p=%{public}d customLen=%{public}d',
      callId,
      request.serversJson.length,
      request.encryptionKeyBase64.length,
      request.allowP2p ? 1 : 0,
      request.customParameters.length
    );
    hilog.info(
      DOMAIN,
      TAG,
      'Mapped ready call protocol version callId=%{public}d version=%{public}s',
      callId,
      request.protocolVersion
    );
    this.logMappedServersDiagnostics(callId, request.serversJson);
  }

  // #65 E4 diagnostics: relay-only smoke 2026-06-11 reached the native layer with the
  // Telegram WebRTC TURN servers carrying turn=0/empty credentials, so ICE had no usable
  // relay pairs. Logs per-server field PRESENCE (lengths/flags only — never credential
  // values) on the ArkTS side of the bridge to pin down where the fields get lost.
  // Remove with the M2.x diagnostic cleanup (task 4.4 C1) once #65 E4 is green.
  private logMappedServersDiagnostics(callId: number, serversJson: string): void {
    try {
      const servers = JSON.parse(serversJson) as TdParsedCallServerPayload[];
      for (const server of servers) {
        hilog.info(
          DOMAIN,
          TAG,
          'Mapped server diag callId=%{public}d id=%{public}s type=%{public}s port=%{public}d userLen=%{public}d passLen=%{public}d turn=%{public}s stun=%{public}s peerTagLen=%{public}d',
          callId,
          server.id,
          server.type,
          server.port,
          server.username === undefined ? -1 : server.username.length,
          server.password === undefined ? -1 : server.password.length,
          server.supportsTurn === undefined ? 'undef' : String(server.supportsTurn),
          server.supportsStun === undefined ? 'undef' : String(server.supportsStun),
          server.peerTag === undefined ? -1 : server.peerTag.length
        );
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Mapped server diag failed callId=%{public}d', callId);
    }
  }

  private readNativeSupportedVersions(callId: number): string[] {
    try {
      const versions = this.sessionBridge.getSupportedVersions();
      hilog.info(
        DOMAIN,
        TAG,
        'Native tgcall supported versions callId=%{public}d versions=%{public}s',
        callId,
        versions.join(',')
      );
      return versions;
    } catch (error) {
      hilog.warn(
        DOMAIN,
        TAG,
        'Failed to read native tgcall supported versions callId=%{public}d: %{public}s',
        callId,
        buildErrorMessage(error)
      );
      return [];
    }
  }

  private stopActiveSession(reason: string): void {
    // M2.4.3: release the voip continuous task on every stop path (idempotent).
    void voipBackgroundTask.stop();
    if (this.activeInstanceId <= 0) {
      this.activeCallId = 0;
      return;
    }

    const callId = this.activeCallId;
    const instanceId = this.activeInstanceId;
    this.flushEmittedSignalingData(callId, instanceId, 'stop');
    this.activeCallId = 0;
    this.activeInstanceId = 0;
    try {
      this.sessionBridge.stopCall(instanceId);
      hilog.info(
        DOMAIN,
        TAG,
        'Stopped native call session callId=%{public}d instanceId=%{public}d reason=%{public}s',
        callId,
        instanceId,
        reason
      );
    } catch (error) {
      hilog.warn(
        DOMAIN,
        TAG,
        'Failed to stop native call session callId=%{public}d instanceId=%{public}d: %{public}s',
        callId,
        instanceId,
        buildErrorMessage(error)
      );
    }
  }
}
