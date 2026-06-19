import { tgCallNativeBridge } from './TgCallNativeBridge';
import type { TgCallNativeBridge } from './TgCallNativeBridge';

export interface TgCallStartRequest {
  'protocolVersion': string;
  'serversJson': string;
  'encryptionKeyBase64': string;
  'isOutgoing': boolean;
  'allowP2p': boolean;
  'customParameters': string;
}

export class TgCallSessionClient {
  private readonly bridge: TgCallNativeBridge;

  constructor(bridge?: TgCallNativeBridge) {
    this.bridge = bridge ? bridge : tgCallNativeBridge;
  }

  /**
   * Returns tgcall protocol versions supported by the native implementation.
   *
   * @returns Local native tgcall library versions.
   */
  getSupportedVersions(): string[] {
    return this.bridge.getSupportedVersions();
  }

  /**
   * Starts a native tgcall session.
   *
   * @param request TDLib call parameters serialized for the native side.
   * @param onSignalingData Invoked on the JS thread when the native session emits
   *   signaling data; the receiver should drain it via `drainSignalingData`.
   * @param onAudioLevel Invoked on the JS thread with the outgoing-microphone level
   *   in [0.0, 1.0] for the in-call UI.
   * @returns Native tgcall instance id.
   */
  startCall(
    request: TgCallStartRequest,
    onSignalingData: (instanceId: number) => void,
    onAudioLevel: (level: number) => void
  ): number {
    return this.bridge.startCall(
      request.protocolVersion,
      request.serversJson,
      request.encryptionKeyBase64,
      request.isOutgoing,
      request.allowP2p,
      request.customParameters,
      onSignalingData,
      onAudioLevel
    );
  }

  /**
   * Starts a diagnostic-only tgcall session.
   *
   * @param request TDLib call parameters serialized for the native side.
   * @returns Native tgcall instance id.
   */
  startDiagnosticCall(request: TgCallStartRequest): number {
    return this.bridge.startDiagnosticCall(
      request.protocolVersion,
      request.serversJson,
      request.encryptionKeyBase64,
      request.isOutgoing,
      request.allowP2p,
      request.customParameters
    );
  }

  /**
   * Forwards raw signaling data to the native tgcall session.
   *
   * @param instanceId Native tgcall instance id.
   * @param dataBase64 Raw signaling payload encoded by TDLib.
   */
  feedSignalingData(instanceId: number, dataBase64: string): void {
    this.bridge.feedSignalingData(instanceId, dataBase64);
  }

  /**
   * Drains signaling data emitted by the native tgcall session.
   *
   * @param instanceId Native tgcall instance id.
   * @returns Base64-encoded signaling payloads for TDLib.
   */
  drainSignalingData(instanceId: number): string[] {
    return this.bridge.drainSignalingData(instanceId);
  }

  /**
   * Mutes or unmutes the microphone for an active native tgcall session.
   *
   * @param instanceId Native tgcall instance id.
   * @param muted `true` to mute the outgoing microphone, `false` to unmute.
   */
  setMuteMicrophone(instanceId: number, muted: boolean): void {
    this.bridge.setMuteMicrophone(instanceId, muted);
  }

  /**
   * Stops a native tgcall session.
   *
   * @param instanceId Native tgcall instance id.
   */
  stopCall(instanceId: number): void {
    this.bridge.stopCall(instanceId);
  }
}

export const tgCallSessionClient: TgCallSessionClient = new TgCallSessionClient();
