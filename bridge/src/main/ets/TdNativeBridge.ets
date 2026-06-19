import bridgeModule, { TdNativeBridge as NativeBridgeModule } from 'libbridge.so';

class TdNativeBridgeClient {
  private readonly nativeModule: NativeBridgeModule = bridgeModule;

  createClientId(): number {
    return this.nativeModule.createClientId();
  }

  send(clientId: number, requestJson: string): void {
    this.nativeModule.send(clientId, requestJson);
  }

  receive(timeoutSeconds?: number): string {
    return this.nativeModule.receive(timeoutSeconds);
  }

  execute(requestJson: string): string {
    return this.nativeModule.execute(requestJson);
  }

  setLogVerbosityLevel(level: number): string {
    return this.nativeModule.setLogVerbosityLevel(level);
  }
}

export const tdNativeBridge: TdNativeBridgeClient = new TdNativeBridgeClient();
