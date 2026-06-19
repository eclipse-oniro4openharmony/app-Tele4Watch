import { describe, expect, it } from '@ohos/hypium';
import { TgCallSessionClient } from 'tgcall';
import type { TgCallNativeBridge, TgCallStartRequest } from 'tgcall';

class FakeTgCallNativeBridge implements TgCallNativeBridge {
  rawProbeCalls: number = 0;
  startCallCalls: number = 0;
  startDiagnosticCallCalls: number = 0;
  feedSignalingDataCalls: number = 0;
  drainSignalingDataCalls: number = 0;
  stopCallCalls: number = 0;
  lastServersJson: string = '';
  lastProtocolVersion: string = '';
  lastEncryptionKeyBase64: string = '';
  lastIsOutgoing: boolean = false;
  lastAllowP2p: boolean = false;
  lastCustomParameters: string = '';
  lastInstanceId: number = 0;
  lastDataBase64: string = '';
  lastOnSignalingData: ((instanceId: number) => void) | undefined = undefined;
  lastOnAudioLevel: ((level: number) => void) | undefined = undefined;
  emittedSignalingData: string[] = ['OUT'];
  nextInstanceId: number = 77;

  runRawSignalingCryptoProbe(): boolean {
    this.rawProbeCalls += 1;
    return true;
  }

  runFactoryRegistryProbe(): boolean {
    return true;
  }

  runWebKSignalingProbe(): boolean {
    return true;
  }

  getSupportedVersions(): string[] {
    return ['8.0.0'];
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
    this.startCallCalls += 1;
    this.lastProtocolVersion = protocolVersion;
    this.lastServersJson = serversJson;
    this.lastEncryptionKeyBase64 = encryptionKeyBase64;
    this.lastIsOutgoing = isOutgoing;
    this.lastAllowP2p = allowP2p;
    this.lastCustomParameters = customParameters;
    this.lastOnSignalingData = onSignalingData;
    this.lastOnAudioLevel = onAudioLevel;
    return this.nextInstanceId;
  }

  startDiagnosticCall(
    protocolVersion: string,
    serversJson: string,
    encryptionKeyBase64: string,
    isOutgoing: boolean,
    allowP2p: boolean,
    customParameters: string
  ): number {
    this.startDiagnosticCallCalls += 1;
    this.lastProtocolVersion = protocolVersion;
    this.lastServersJson = serversJson;
    this.lastEncryptionKeyBase64 = encryptionKeyBase64;
    this.lastIsOutgoing = isOutgoing;
    this.lastAllowP2p = allowP2p;
    this.lastCustomParameters = customParameters;
    return this.nextInstanceId;
  }

  feedSignalingData(instanceId: number, dataBase64: string): void {
    this.feedSignalingDataCalls += 1;
    this.lastInstanceId = instanceId;
    this.lastDataBase64 = dataBase64;
  }

  drainSignalingData(instanceId: number): string[] {
    this.drainSignalingDataCalls += 1;
    this.lastInstanceId = instanceId;
    return this.emittedSignalingData;
  }

  setMuteMicrophoneCalls: number = 0;
  lastMuted: boolean = false;

  setMuteMicrophone(instanceId: number, muted: boolean): void {
    this.setMuteMicrophoneCalls += 1;
    this.lastInstanceId = instanceId;
    this.lastMuted = muted;
  }

  stopCall(instanceId: number): void {
    this.stopCallCalls += 1;
    this.lastInstanceId = instanceId;
  }
}

export default function tgCallSessionClientTest() {
  describe('TgCallSessionClientTest', () => {
    it('shouldForwardSupportedVersionsRequestToNativeBridge', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      const client = new TgCallSessionClient(bridge);

      const supportedVersions = client.getSupportedVersions();

      expect(supportedVersions.length).assertEqual(1);
      expect(supportedVersions[0]).assertEqual('8.0.0');
    });

    it('shouldForwardStartCallRequestToNativeBridge', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      const client = new TgCallSessionClient(bridge);
      const request: TgCallStartRequest = {
        'protocolVersion': '8.0.0',
        'serversJson': '[{"id":"1"}]',
        'encryptionKeyBase64': 'AAECAwQ=',
        'isOutgoing': false,
        'allowP2p': true,
        'customParameters': '{"version":"s2"}'
      };

      let notifiedInstanceId: number = 0;
      let notifiedAudioLevel: number = -1;
      const instanceId = client.startCall(
        request,
        (id: number): void => {
          notifiedInstanceId = id;
        },
        (level: number): void => {
          notifiedAudioLevel = level;
        }
      );

      expect(instanceId).assertEqual(77);
      expect(bridge.startCallCalls).assertEqual(1);
      expect(bridge.lastProtocolVersion).assertEqual('8.0.0');
      expect(bridge.lastServersJson).assertEqual('[{"id":"1"}]');
      expect(bridge.lastEncryptionKeyBase64).assertEqual('AAECAwQ=');
      expect(bridge.lastIsOutgoing).assertFalse();
      expect(bridge.lastAllowP2p).assertTrue();
      expect(bridge.lastCustomParameters).assertEqual('{"version":"s2"}');
      expect(bridge.lastOnSignalingData !== undefined).assertTrue();
      if (bridge.lastOnSignalingData !== undefined) {
        bridge.lastOnSignalingData(77);
      }
      expect(notifiedInstanceId).assertEqual(77);
      expect(bridge.lastOnAudioLevel !== undefined).assertTrue();
      if (bridge.lastOnAudioLevel !== undefined) {
        bridge.lastOnAudioLevel(0.5);
      }
      expect(notifiedAudioLevel).assertEqual(0.5);
    });

    it('shouldForwardDiagnosticStartCallRequestToNativeBridge', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      const client = new TgCallSessionClient(bridge);
      const request: TgCallStartRequest = {
        'protocolVersion': '8.0.0',
        'serversJson': '[]',
        'encryptionKeyBase64': 'AAECAwQ=',
        'isOutgoing': false,
        'allowP2p': false,
        'customParameters': '{"probe":"s2"}'
      };

      const instanceId = client.startDiagnosticCall(request);

      expect(instanceId).assertEqual(77);
      expect(bridge.startCallCalls).assertEqual(0);
      expect(bridge.startDiagnosticCallCalls).assertEqual(1);
      expect(bridge.lastProtocolVersion).assertEqual('8.0.0');
      expect(bridge.lastServersJson).assertEqual('[]');
      expect(bridge.lastCustomParameters).assertEqual('{"probe":"s2"}');
    });

    it('shouldForwardSignalingDataAndStopCallToNativeBridge', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      const client = new TgCallSessionClient(bridge);

      client.feedSignalingData(77, 'AQID');
      const emittedData = client.drainSignalingData(77);
      client.stopCall(77);

      expect(bridge.feedSignalingDataCalls).assertEqual(1);
      expect(bridge.drainSignalingDataCalls).assertEqual(1);
      expect(bridge.stopCallCalls).assertEqual(1);
      expect(bridge.lastInstanceId).assertEqual(77);
      expect(bridge.lastDataBase64).assertEqual('AQID');
      expect(emittedData.length).assertEqual(1);
      expect(emittedData[0]).assertEqual('OUT');
    });
  });
}
