import { describe, expect, it } from '@ohos/hypium';
import {
  TgCallDiagnostics,
  TgCallNativeBridge
} from '../main/ets/services/calls/TgCallDiagnostics';
import type { TgCallSessionBridge } from '../main/ets/services/voip/TgCallSessionBridge';
import type { TgCallStartRequest } from 'tgcall';

class FakeTgCallNativeBridge implements TgCallNativeBridge {
  rawProbeCalls: number = 0;
  factoryProbeCalls: number = 0;
  webKSignalingProbeCalls: number = 0;
  rawProbeResult: boolean = true;
  factoryProbeResult: boolean = true;
  webKSignalingProbeResult: boolean = true;
  supportedVersions: string[] = ['8.0.0'];
  shouldThrowRawProbe: boolean = false;
  shouldThrowFactoryProbe: boolean = false;
  shouldThrowWebKSignalingProbe: boolean = false;

  runRawSignalingCryptoProbe(): boolean {
    this.rawProbeCalls += 1;
    if (this.shouldThrowRawProbe) {
      throw new Error('probe failed hard');
    }
    return this.rawProbeResult;
  }

  runFactoryRegistryProbe(): boolean {
    this.factoryProbeCalls += 1;
    if (this.shouldThrowFactoryProbe) {
      throw new Error('factory probe failed hard');
    }
    return this.factoryProbeResult;
  }

  runWebKSignalingProbe(): boolean {
    this.webKSignalingProbeCalls += 1;
    if (this.shouldThrowWebKSignalingProbe) {
      throw new Error('webk probe failed hard');
    }
    return this.webKSignalingProbeResult;
  }

  getSupportedVersions(): string[] {
    return this.supportedVersions;
  }
}

class FakeTgCallSessionBridge implements TgCallSessionBridge {
  startCallCalls: number = 0;
  startDiagnosticCallCalls: number = 0;
  feedSignalingDataCalls: number = 0;
  drainSignalingDataCalls: number = 0;
  stopCallCalls: number = 0;
  lastRequest: TgCallStartRequest | undefined = undefined;
  lastInstanceId: number = 0;
  lastDataBase64: string = '';
  lastOnSignalingData: ((instanceId: number) => void) | undefined = undefined;
  lastOnAudioLevel: ((level: number) => void) | undefined = undefined;
  nextInstanceId: number = 52;
  shouldThrowOnStart: boolean = false;
  shouldThrowOnFeed: boolean = false;

  getSupportedVersions(): string[] {
    return ['8.0.0'];
  }

  startCall(
    request: TgCallStartRequest,
    onSignalingData: (instanceId: number) => void,
    onAudioLevel: (level: number) => void
  ): number {
    this.startCallCalls += 1;
    this.lastRequest = request;
    this.lastOnSignalingData = onSignalingData;
    this.lastOnAudioLevel = onAudioLevel;
    return this.nextInstanceId;
  }

  startDiagnosticCall(request: TgCallStartRequest): number {
    this.startDiagnosticCallCalls += 1;
    this.lastRequest = request;
    if (this.shouldThrowOnStart) {
      throw new Error('session start failed');
    }
    return this.nextInstanceId;
  }

  feedSignalingData(instanceId: number, dataBase64: string): void {
    this.feedSignalingDataCalls += 1;
    this.lastInstanceId = instanceId;
    this.lastDataBase64 = dataBase64;
    if (this.shouldThrowOnFeed) {
      throw new Error('session feed failed');
    }
  }

  drainSignalingData(instanceId: number): string[] {
    this.drainSignalingDataCalls += 1;
    this.lastInstanceId = instanceId;
    return [];
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

export default function tgCallDiagnosticsTest() {
  describe('TgCallDiagnosticsTest', () => {
    it('shouldReturnPassedWhenNativeProbePasses', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      const diagnostics = new TgCallDiagnostics(bridge);

      const result = diagnostics.runRawSignalingCryptoProbe();

      expect(bridge.rawProbeCalls).assertEqual(1);
      expect(result.status).assertEqual('passed');
      expect(result.message).assertEqual('Raw signaling crypto probe passed.');
    });

    it('shouldReturnFailedWhenNativeProbeReturnsFalse', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      bridge.rawProbeResult = false;
      const diagnostics = new TgCallDiagnostics(bridge);

      const result = diagnostics.runRawSignalingCryptoProbe();

      expect(bridge.rawProbeCalls).assertEqual(1);
      expect(result.status).assertEqual('failed');
      expect(result.message).assertEqual('Raw signaling crypto probe failed.');
    });

    it('shouldReturnFailedWhenNativeProbeThrows', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      bridge.shouldThrowRawProbe = true;
      const diagnostics = new TgCallDiagnostics(bridge);

      const result = diagnostics.runRawSignalingCryptoProbe();

      expect(bridge.rawProbeCalls).assertEqual(1);
      expect(result.status).assertEqual('failed');
      expect(result.message).assertEqual('probe failed hard');
    });

    it('shouldReturnPassedWhenFactoryRegistryProbePasses', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      const diagnostics = new TgCallDiagnostics(bridge);

      const result = diagnostics.runFactoryRegistryProbe();

      expect(bridge.factoryProbeCalls).assertEqual(1);
      expect(result.status).assertEqual('passed');
      expect(result.message).assertEqual('Real factory registry probe passed.');
    });

    it('shouldReturnFailedWhenFactoryRegistryProbeFindsNoVersions', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      bridge.factoryProbeResult = false;
      const diagnostics = new TgCallDiagnostics(bridge);

      const result = diagnostics.runFactoryRegistryProbe();

      expect(bridge.factoryProbeCalls).assertEqual(1);
      expect(result.status).assertEqual('failed');
      expect(result.message).assertEqual('Real factory registry probe found no registered versions.');
    });

    it('shouldReturnPassedWhenWebKSignalingProbePasses', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      const diagnostics = new TgCallDiagnostics(bridge);

      const result = diagnostics.runWebKSignalingProbe();

      expect(bridge.webKSignalingProbeCalls).assertEqual(1);
      expect(result.status).assertEqual('passed');
      expect(result.message).assertEqual('Web-K signaling 4.0.0 probe passed.');
    });

    it('shouldReturnFailedWhenWebKSignalingProbeReturnsFalse', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      bridge.webKSignalingProbeResult = false;
      const diagnostics = new TgCallDiagnostics(bridge);

      const result = diagnostics.runWebKSignalingProbe();

      expect(bridge.webKSignalingProbeCalls).assertEqual(1);
      expect(result.status).assertEqual('failed');
      expect(result.message).assertEqual('Web-K signaling 4.0.0 probe failed.');
    });

    it('shouldReturnFailedWhenWebKSignalingProbeThrows', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      bridge.shouldThrowWebKSignalingProbe = true;
      const diagnostics = new TgCallDiagnostics(bridge);

      const result = diagnostics.runWebKSignalingProbe();

      expect(bridge.webKSignalingProbeCalls).assertEqual(1);
      expect(result.status).assertEqual('failed');
      expect(result.message).assertEqual('webk probe failed hard');
    });

    it('shouldReturnPassedWhenWebKMediaPathProbeFindsFactoryVersion', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      bridge.supportedVersions = ['4.0.0', '10.0.0'];
      const diagnostics = new TgCallDiagnostics(bridge);

      const result = diagnostics.runWebKMediaPathProbe();

      expect(bridge.webKSignalingProbeCalls).assertEqual(1);
      expect(result.status).assertEqual('passed');
      expect(result.message).assertEqual('Web-K media path 4.0.0 probe passed.');
    });

    it('shouldReturnFailedWhenWebKMediaPathProbeDoesNotFindFactoryVersion', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      bridge.supportedVersions = ['10.0.0', '11.0.0'];
      const diagnostics = new TgCallDiagnostics(bridge);

      const result = diagnostics.runWebKMediaPathProbe();

      expect(bridge.webKSignalingProbeCalls).assertEqual(1);
      expect(result.status).assertEqual('failed');
      expect(result.message).assertEqual(
        'Web-K media path 4.0.0 probe failed: media factory does not advertise 4.0.0. supported=10.0.0,11.0.0'
      );
    });

    it('shouldReturnFailedWhenWebKMediaPathProbeFindsNoFactoryVersions', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      bridge.supportedVersions = [];
      const diagnostics = new TgCallDiagnostics(bridge);

      const result = diagnostics.runWebKMediaPathProbe();

      expect(bridge.webKSignalingProbeCalls).assertEqual(1);
      expect(result.status).assertEqual('failed');
      expect(result.message).assertEqual(
        'Web-K media path 4.0.0 probe failed: media factory does not advertise 4.0.0. supported=<empty>'
      );
    });

    it('shouldReturnFailedWhenWebKMediaPathProbeSignalingFails', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      bridge.webKSignalingProbeResult = false;
      const diagnostics = new TgCallDiagnostics(bridge);

      const result = diagnostics.runWebKMediaPathProbe();

      expect(bridge.webKSignalingProbeCalls).assertEqual(1);
      expect(result.status).assertEqual('failed');
      expect(result.message).assertEqual('Web-K media path 4.0.0 probe failed: signaling unavailable.');
    });

    it('shouldReturnPassedWhenSessionLifecycleProbePasses', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      const sessionBridge = new FakeTgCallSessionBridge();
      const diagnostics = new TgCallDiagnostics(bridge, sessionBridge);

      const result = diagnostics.runSessionLifecycleProbe();

      expect(result.status).assertEqual('passed');
      expect(result.message).assertEqual('Session lifecycle probe passed.');
      expect(sessionBridge.startCallCalls).assertEqual(0);
      expect(sessionBridge.startDiagnosticCallCalls).assertEqual(1);
      expect(sessionBridge.feedSignalingDataCalls).assertEqual(1);
      expect(sessionBridge.stopCallCalls).assertEqual(1);
      expect(sessionBridge.lastInstanceId).assertEqual(52);
      expect(sessionBridge.lastDataBase64).assertEqual('AQID');
      if (sessionBridge.lastRequest) {
        expect(sessionBridge.lastRequest.protocolVersion).assertEqual('8.0.0');
        expect(sessionBridge.lastRequest.serversJson).assertEqual('[]');
        expect(sessionBridge.lastRequest.isOutgoing).assertFalse();
        expect(sessionBridge.lastRequest.allowP2p).assertFalse();
      }
    });

    it('shouldReturnFailedWhenSessionLifecycleProbeStartFails', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      const sessionBridge = new FakeTgCallSessionBridge();
      sessionBridge.shouldThrowOnStart = true;
      const diagnostics = new TgCallDiagnostics(bridge, sessionBridge);

      const result = diagnostics.runSessionLifecycleProbe();

      expect(result.status).assertEqual('failed');
      expect(result.message).assertEqual('session start failed');
      expect(sessionBridge.startCallCalls).assertEqual(0);
      expect(sessionBridge.startDiagnosticCallCalls).assertEqual(1);
      expect(sessionBridge.stopCallCalls).assertEqual(0);
    });

    it('shouldReturnFailedWhenSessionLifecycleProbeReturnsInvalidInstanceId', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      const sessionBridge = new FakeTgCallSessionBridge();
      sessionBridge.nextInstanceId = 0;
      const diagnostics = new TgCallDiagnostics(bridge, sessionBridge);

      const result = diagnostics.runSessionLifecycleProbe();

      expect(result.status).assertEqual('failed');
      expect(result.message).assertEqual('Session lifecycle probe returned invalid instance id.');
      expect(sessionBridge.feedSignalingDataCalls).assertEqual(0);
      expect(sessionBridge.stopCallCalls).assertEqual(0);
      expect(sessionBridge.startCallCalls).assertEqual(0);
      expect(sessionBridge.startDiagnosticCallCalls).assertEqual(1);
    });

    it('shouldStopSessionWhenSessionLifecycleProbeFeedFails', 0, () => {
      const bridge = new FakeTgCallNativeBridge();
      const sessionBridge = new FakeTgCallSessionBridge();
      sessionBridge.shouldThrowOnFeed = true;
      const diagnostics = new TgCallDiagnostics(bridge, sessionBridge);

      const result = diagnostics.runSessionLifecycleProbe();

      expect(result.status).assertEqual('failed');
      expect(result.message).assertEqual('session feed failed');
      expect(sessionBridge.startCallCalls).assertEqual(0);
      expect(sessionBridge.startDiagnosticCallCalls).assertEqual(1);
      expect(sessionBridge.feedSignalingDataCalls).assertEqual(1);
      expect(sessionBridge.stopCallCalls).assertEqual(1);
      expect(sessionBridge.lastInstanceId).assertEqual(52);
    });
  });
}
