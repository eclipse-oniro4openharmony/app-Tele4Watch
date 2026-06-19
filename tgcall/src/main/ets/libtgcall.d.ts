declare module 'libtgcall.so' {
  export interface TgCallNativeBridge {
    runRawSignalingCryptoProbe(): boolean;
    runFactoryRegistryProbe(): boolean;
    runWebKSignalingProbe(): boolean;
    getSupportedVersions(): string[];
    startCall(
      protocolVersion: string,
      serversJson: string,
      encryptionKeyBase64: string,
      isOutgoing: boolean,
      allowP2p: boolean,
      customParameters: string,
      onSignalingData: (instanceId: number) => void,
      onAudioLevel: (level: number) => void
    ): number;
    startDiagnosticCall(
      protocolVersion: string,
      serversJson: string,
      encryptionKeyBase64: string,
      isOutgoing: boolean,
      allowP2p: boolean,
      customParameters: string
    ): number;
    feedSignalingData(instanceId: number, dataBase64: string): void;
    drainSignalingData(instanceId: number): string[];
    setMuteMicrophone(instanceId: number, muted: boolean): void;
    stopCall(instanceId: number): void;
  }

  const tgCallNativeBridge: TgCallNativeBridge;
  export default tgCallNativeBridge;
}
