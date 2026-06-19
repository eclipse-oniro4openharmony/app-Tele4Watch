declare module 'libbridge.so' {
  export interface TdNativeBridge {
    createClientId(): number;
    send(clientId: number, requestJson: string): void;
    receive(timeoutSeconds?: number): string;
    execute(requestJson: string): string;
    setLogVerbosityLevel(level: number): string;
  }

  const tdNativeBridge: TdNativeBridge;
  export default tdNativeBridge;
}
