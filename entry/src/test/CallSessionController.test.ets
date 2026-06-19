import { describe, expect, it } from '@ohos/hypium';
import { CallSessionController } from '../main/ets/services/voip/CallSessionController';
import type { CallSignalingSender } from '../main/ets/services/voip/CallSessionController';
import type { TgCallSessionBridge } from '../main/ets/services/voip/TgCallSessionBridge';
import type { TgCallStartRequest } from 'tgcall';
import type {
  TdCallEvent,
  TdParsedCallPayload,
  TdParsedCallStatePayload
} from '../main/ets/services/td/TdPayloadTypes';

class FakeTgCallSessionBridge implements TgCallSessionBridge {
  startCallCalls: number = 0;
  feedSignalingDataCalls: number = 0;
  stopCallCalls: number = 0;
  drainSignalingDataCalls: number = 0;
  nextInstanceId: number = 88;
  lastRequest: TgCallStartRequest | undefined = undefined;
  lastInstanceId: number = 0;
  lastDataBase64: string = '';
  emittedSignalingData: string[] = [];
  supportedVersions: string[] = ['8.0.0'];
  shouldThrowOnStart: boolean = false;
  shouldThrowOnFeed: boolean = false;
  shouldThrowOnDrain: boolean = false;
  shouldThrowOnStop: boolean = false;

  getSupportedVersions(): string[] {
    return this.supportedVersions;
  }

  lastOnSignalingData: ((instanceId: number) => void) | undefined = undefined;
  lastOnAudioLevel: ((level: number) => void) | undefined = undefined;

  startCall(
    request: TgCallStartRequest,
    onSignalingData: (instanceId: number) => void,
    onAudioLevel: (level: number) => void
  ): number {
    this.startCallCalls += 1;
    this.lastRequest = request;
    this.lastOnSignalingData = onSignalingData;
    this.lastOnAudioLevel = onAudioLevel;
    if (this.shouldThrowOnStart) {
      throw new Error('start failed');
    }
    return this.nextInstanceId;
  }

  startDiagnosticCall(request: TgCallStartRequest): number {
    this.lastRequest = request;
    return this.nextInstanceId;
  }

  feedSignalingData(instanceId: number, dataBase64: string): void {
    this.feedSignalingDataCalls += 1;
    this.lastInstanceId = instanceId;
    this.lastDataBase64 = dataBase64;
    if (this.shouldThrowOnFeed) {
      throw new Error('feed failed');
    }
  }

  drainSignalingData(instanceId: number): string[] {
    this.drainSignalingDataCalls += 1;
    this.lastInstanceId = instanceId;
    if (this.shouldThrowOnDrain) {
      throw new Error('drain failed');
    }
    const result: string[] = this.emittedSignalingData;
    this.emittedSignalingData = [];
    return result;
  }

  setMuteMicrophoneCalls: number = 0;
  lastMuted: boolean = false;
  shouldThrowOnSetMute: boolean = false;

  setMuteMicrophone(instanceId: number, muted: boolean): void {
    this.setMuteMicrophoneCalls += 1;
    this.lastInstanceId = instanceId;
    this.lastMuted = muted;
    if (this.shouldThrowOnSetMute) {
      throw new Error('setMute failed');
    }
  }

  stopCall(instanceId: number): void {
    this.stopCallCalls += 1;
    this.lastInstanceId = instanceId;
    if (this.shouldThrowOnStop) {
      throw new Error('stop failed');
    }
  }
}

class FakeCallSignalingSender implements CallSignalingSender {
  sendCallSignalingDataCalls: number = 0;
  lastCallId: number = 0;
  lastData: string = '';
  shouldReject: boolean = false;

  sendCallSignalingData(callId: number, data: string): boolean {
    this.sendCallSignalingDataCalls += 1;
    this.lastCallId = callId;
    this.lastData = data;
    return !this.shouldReject;
  }
}

function buildReadyState(): TdParsedCallStatePayload {
  return {
    'kind': 'ready',
    'tdType': 'callStateReady',
    'protocol': {
      'udpP2p': true,
      'udpReflector': true,
      'minLayer': 65,
      'maxLayer': 92,
      'libraryVersions': ['8.0.0']
    },
    'servers': [{
      'id': '6001',
      'ipAddress': '149.154.167.50',
      'ipv6Address': '',
      'port': 595,
      'type': 'callServerTypeTelegramReflector'
    }],
    'encryptionKey': 'base64-key',
    'allowP2p': true,
    'customParameters': '{"custom":"yes"}'
  };
}

function buildReadyStateWithoutEncryptionKey(): TdParsedCallStatePayload {
  return {
    'kind': 'ready',
    'tdType': 'callStateReady',
    'protocol': {
      'udpP2p': true,
      'udpReflector': true,
      'minLayer': 65,
      'maxLayer': 92,
      'libraryVersions': ['8.0.0']
    },
    'servers': [{
      'id': '6001',
      'ipAddress': '149.154.167.50',
      'ipv6Address': '',
      'port': 595,
      'type': 'callServerTypeTelegramReflector'
    }],
    'encryptionKey': '',
    'allowP2p': true,
    'customParameters': '{"custom":"yes"}'
  };
}

function buildDiscardedState(): TdParsedCallStatePayload {
  return {
    'kind': 'discarded',
    'tdType': 'callStateDiscarded',
    'discardReason': 'callDiscardReasonDeclined'
  };
}

function buildErrorState(): TdParsedCallStatePayload {
  return {
    'kind': 'error',
    'tdType': 'callStateError',
    'errorCode': 400,
    'errorMessage': 'CALL_FAILED'
  };
}

function buildCall(id: number, state: TdParsedCallStatePayload): TdParsedCallPayload {
  return {
    'id': id,
    'uniqueId': 'unique',
    'userId': '765',
    'isOutgoing': false,
    'isVideo': false,
    'state': state
  };
}

function buildCallEvent(call: TdParsedCallPayload): TdCallEvent {
  return {
    'kind': 'call',
    'call': call
  };
}

export default function callSessionControllerTest() {
  describe('CallSessionControllerTest', () => {
    it('shouldStartNativeSessionWhenCallBecomesReady', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const controller = new CallSessionController(bridge);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));

      expect(bridge.startCallCalls).assertEqual(1);
      if (bridge.lastRequest) {
        expect(bridge.lastRequest.protocolVersion).assertEqual('8.0.0');
        expect(bridge.lastRequest.encryptionKeyBase64).assertEqual('base64-key');
        expect(bridge.lastRequest.allowP2p).assertTrue();
      } else {
        expect(false).assertTrue();
      }
      const snapshot = controller.getActiveSessionSnapshot();
      if (snapshot) {
        expect(snapshot.callId).assertEqual(43);
        expect(snapshot.instanceId).assertEqual(88);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldPreferWebKProtocolVersionWhenReadyCallOffersWebKAndNativeVersions', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      bridge.supportedVersions = ['10.0.0', '11.0.0'];
      const state = buildReadyState();
      if (state.protocol) {
        state.protocol.libraryVersions = ['4.0.0', '10.0.0'];
      }
      const controller = new CallSessionController(bridge);

      controller.handleCallEvent(buildCallEvent(buildCall(43, state)));

      expect(bridge.startCallCalls).assertEqual(1);
      if (bridge.lastRequest) {
        expect(bridge.lastRequest.protocolVersion).assertEqual('4.0.0');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldFeedSignalingDataOnlyForActiveCall', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const controller = new CallSessionController(bridge);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));
      controller.handleCallEvent({
        'kind': 'signalingData',
        'callId': 44,
        'data': 'IGNORED'
      });
      controller.handleCallEvent({
        'kind': 'signalingData',
        'callId': 43,
        'data': 'AQID'
      });

      expect(bridge.feedSignalingDataCalls).assertEqual(1);
      expect(bridge.lastInstanceId).assertEqual(88);
      expect(bridge.lastDataBase64).assertEqual('AQID');
    });

    it('shouldSendEmittedSignalingDataAfterNativeFeed', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const sender = new FakeCallSignalingSender();
      const controller = new CallSessionController(bridge, sender);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));
      bridge.emittedSignalingData = [' OUTBOUND '];
      controller.handleCallEvent({
        'kind': 'signalingData',
        'callId': 43,
        'data': 'AQID'
      });

      expect(bridge.feedSignalingDataCalls).assertEqual(1);
      expect(bridge.drainSignalingDataCalls).assertEqual(2);
      expect(sender.sendCallSignalingDataCalls).assertEqual(1);
      expect(sender.lastCallId).assertEqual(43);
      expect(sender.lastData).assertEqual('OUTBOUND');
    });

    it('shouldKeepSessionActiveWhenDrainThrows', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const sender = new FakeCallSignalingSender();
      const controller = new CallSessionController(bridge, sender);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));
      bridge.shouldThrowOnDrain = true;
      controller.handleCallEvent({
        'kind': 'signalingData',
        'callId': 43,
        'data': 'AQID'
      });

      expect(bridge.feedSignalingDataCalls).assertEqual(1);
      expect(bridge.drainSignalingDataCalls).assertEqual(2);
      expect(sender.sendCallSignalingDataCalls).assertEqual(0);
      const snapshot = controller.getActiveSessionSnapshot();
      if (snapshot) {
        expect(snapshot.callId).assertEqual(43);
        expect(snapshot.instanceId).assertEqual(88);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldKeepSessionActiveWhenSendingEmittedSignalingFails', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const sender = new FakeCallSignalingSender();
      const controller = new CallSessionController(bridge, sender);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));
      bridge.emittedSignalingData = ['OUTBOUND'];
      sender.shouldReject = true;
      controller.handleCallEvent({
        'kind': 'signalingData',
        'callId': 43,
        'data': 'AQID'
      });

      expect(bridge.feedSignalingDataCalls).assertEqual(1);
      expect(sender.sendCallSignalingDataCalls).assertEqual(1);
      expect(sender.lastCallId).assertEqual(43);
      expect(sender.lastData).assertEqual('OUTBOUND');
      const snapshot = controller.getActiveSessionSnapshot();
      if (snapshot) {
        expect(snapshot.callId).assertEqual(43);
        expect(snapshot.instanceId).assertEqual(88);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldStopNativeSessionWhenActiveCallEnds', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const controller = new CallSessionController(bridge);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));
      controller.handleCallEvent(buildCallEvent(buildCall(43, buildDiscardedState())));

      expect(bridge.stopCallCalls).assertEqual(1);
      expect(bridge.lastInstanceId).assertEqual(88);
      expect(controller.getActiveSessionSnapshot()).assertUndefined();
    });

    it('shouldDrainEmittedSignalingDataBeforeStop', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const sender = new FakeCallSignalingSender();
      const controller = new CallSessionController(bridge, sender);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));
      bridge.emittedSignalingData = ['FINAL'];
      controller.handleCallEvent(buildCallEvent(buildCall(43, buildDiscardedState())));

      expect(bridge.stopCallCalls).assertEqual(1);
      expect(bridge.drainSignalingDataCalls).assertEqual(2);
      expect(sender.sendCallSignalingDataCalls).assertEqual(1);
      expect(sender.lastData).assertEqual('FINAL');
      expect(controller.getActiveSessionSnapshot()).assertUndefined();
    });

    it('shouldReplaceActiveSessionWhenDifferentCallBecomesReady', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const controller = new CallSessionController(bridge);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));
      bridge.nextInstanceId = 99;
      controller.handleCallEvent(buildCallEvent(buildCall(44, buildReadyState())));

      expect(bridge.startCallCalls).assertEqual(2);
      expect(bridge.stopCallCalls).assertEqual(1);
      const snapshot = controller.getActiveSessionSnapshot();
      if (snapshot) {
        expect(snapshot.callId).assertEqual(44);
        expect(snapshot.instanceId).assertEqual(99);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldIgnoreDuplicateReadyForActiveCall', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const controller = new CallSessionController(bridge);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));
      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));

      expect(bridge.startCallCalls).assertEqual(1);
      expect(bridge.stopCallCalls).assertEqual(0);
    });

    it('shouldSkipStartWhenReadyMappingFails', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const controller = new CallSessionController(bridge);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyStateWithoutEncryptionKey())));

      expect(bridge.startCallCalls).assertEqual(0);
      expect(controller.getActiveSessionSnapshot()).assertUndefined();
    });

    it('shouldKeepStateEmptyWhenNativeStartReturnsInvalidInstanceId', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      bridge.nextInstanceId = 0;
      const controller = new CallSessionController(bridge);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));

      expect(bridge.startCallCalls).assertEqual(1);
      expect(controller.getActiveSessionSnapshot()).assertUndefined();
    });

    it('shouldKeepStateEmptyWhenNativeStartThrows', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      bridge.shouldThrowOnStart = true;
      const controller = new CallSessionController(bridge);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));

      expect(bridge.startCallCalls).assertEqual(1);
      expect(controller.getActiveSessionSnapshot()).assertUndefined();
    });

    it('shouldCleanupActiveSessionWhenFeedThrows', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const controller = new CallSessionController(bridge);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));
      bridge.shouldThrowOnFeed = true;
      controller.handleCallEvent({
        'kind': 'signalingData',
        'callId': 43,
        'data': 'AQID'
      });

      expect(bridge.feedSignalingDataCalls).assertEqual(1);
      expect(bridge.stopCallCalls).assertEqual(1);
      expect(controller.getActiveSessionSnapshot()).assertUndefined();
    });

    it('shouldClearStateEvenWhenNativeStopThrows', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const controller = new CallSessionController(bridge);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));
      bridge.shouldThrowOnStop = true;
      controller.handleCallEvent(buildCallEvent(buildCall(43, buildDiscardedState())));

      expect(bridge.stopCallCalls).assertEqual(1);
      expect(controller.getActiveSessionSnapshot()).assertUndefined();
    });

    it('shouldStopNativeSessionWhenActiveCallFails', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const controller = new CallSessionController(bridge);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));
      controller.handleCallEvent(buildCallEvent(buildCall(43, buildErrorState())));

      expect(bridge.stopCallCalls).assertEqual(1);
      expect(controller.getActiveSessionSnapshot()).assertUndefined();
    });

    it('shouldStopNativeSessionOnReset', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const controller = new CallSessionController(bridge);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));
      controller.reset();

      expect(bridge.stopCallCalls).assertEqual(1);
      expect(controller.getActiveSessionSnapshot()).assertUndefined();
    });

    it('shouldIgnoreEmptySignalingData', 0, () => {
      const bridge = new FakeTgCallSessionBridge();
      const controller = new CallSessionController(bridge);

      controller.handleCallEvent(buildCallEvent(buildCall(43, buildReadyState())));
      controller.handleCallEvent({
        'kind': 'signalingData',
        'callId': 43,
        'data': ''
      });

      expect(bridge.feedSignalingDataCalls).assertEqual(0);
      const snapshot = controller.getActiveSessionSnapshot();
      if (snapshot) {
        expect(snapshot.callId).assertEqual(43);
      } else {
        expect(false).assertTrue();
      }
    });
  });
}
