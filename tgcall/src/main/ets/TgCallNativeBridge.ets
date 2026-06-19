import tgCallModule, { TgCallNativeBridge as NativeTgCallBridgeModule } from 'libtgcall.so';

export interface TgCallDiagnosticBridge {
  'runRawSignalingCryptoProbe': () => boolean;
  'runFactoryRegistryProbe': () => boolean;
  'runWebKSignalingProbe': () => boolean;
  'getSupportedVersions': () => string[];
}

export interface TgCallNativeBridge extends TgCallDiagnosticBridge {
  'startCall': (
    protocolVersion: string,
    serversJson: string,
    encryptionKeyBase64: string,
    isOutgoing: boolean,
    allowP2p: boolean,
    customParameters: string,
    onSignalingData: (instanceId: number) => void,
    onAudioLevel: (level: number) => void
  ) => number;
  'startDiagnosticCall': (
    protocolVersion: string,
    serversJson: string,
    encryptionKeyBase64: string,
    isOutgoing: boolean,
    allowP2p: boolean,
    customParameters: string
  ) => number;
  'feedSignalingData': (instanceId: number, dataBase64: string) => void;
  'drainSignalingData': (instanceId: number) => string[];
  'setMuteMicrophone': (instanceId: number, muted: boolean) => void;
  'stopCall': (instanceId: number) => void;
}

class TgCallNativeBridgeClient implements TgCallNativeBridge {
  private readonly nativeModule: NativeTgCallBridgeModule = tgCallModule;

  runRawSignalingCryptoProbe(): boolean {
    return this.nativeModule.runRawSignalingCryptoProbe();
  }

  runFactoryRegistryProbe(): boolean {
    return this.nativeModule.runFactoryRegistryProbe();
  }

  runWebKSignalingProbe(): boolean {
    return this.nativeModule.runWebKSignalingProbe();
  }

  getSupportedVersions(): string[] {
    return this.nativeModule.getSupportedVersions();
  }

  startCall(
    protocolVersion: string,
    serversJson: string,
    encryptionKeyBase64: string,
    isOutgoing: boolean,
    allowP2p: boolean,
    customParameters: string,
    onSignalingData: (instanceId: number) => void,
    onAudioLevel: (level: number) => void
  ): number {
    return this.nativeModule.startCall(
      protocolVersion,
      serversJson,
      encryptionKeyBase64,
      isOutgoing,
      allowP2p,
      customParameters,
      onSignalingData,
      onAudioLevel
    );
  }

  startDiagnosticCall(
    protocolVersion: string,
    serversJson: string,
    encryptionKeyBase64: string,
    isOutgoing: boolean,
    allowP2p: boolean,
    customParameters: string
  ): number {
    return this.nativeModule.startDiagnosticCall(
      protocolVersion,
      serversJson,
      encryptionKeyBase64,
      isOutgoing,
      allowP2p,
      customParameters
    );
  }

  feedSignalingData(instanceId: number, dataBase64: string): void {
    this.nativeModule.feedSignalingData(instanceId, dataBase64);
  }

  drainSignalingData(instanceId: number): string[] {
    return this.nativeModule.drainSignalingData(instanceId);
  }

  setMuteMicrophone(instanceId: number, muted: boolean): void {
    this.nativeModule.setMuteMicrophone(instanceId, muted);
  }

  stopCall(instanceId: number): void {
    this.nativeModule.stopCall(instanceId);
  }
}

export const tgCallNativeBridge: TgCallNativeBridgeClient = new TgCallNativeBridgeClient();
