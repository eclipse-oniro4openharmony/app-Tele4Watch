import { describe, expect, it } from '@ohos/hypium';
import { mapReadyCallToTgCallStartRequest } from '../main/ets/services/voip/TgCallStartRequestMapper';
import type {
  TdParsedCallPayload,
  TdParsedCallStatePayload
} from '../main/ets/services/td/TdPayloadTypes';

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
      'type': 'callServerTypeTelegramReflector',
      'peerTag': 'peer-tag'
    }, {
      'id': '6002',
      'ipAddress': '149.154.167.51',
      'ipv6Address': '',
      'port': 443,
      'type': 'callServerTypeWebrtc',
      'username': 'turn-user',
      'password': 'turn-pass',
      'supportsTurn': true,
      'supportsStun': true
    }],
    'encryptionKey': 'base64-key',
    'allowP2p': true,
    'customParameters': '{"custom":"yes"}'
  };
}

function buildCall(state: TdParsedCallStatePayload): TdParsedCallPayload {
  return {
    'id': 43,
    'uniqueId': '123',
    'userId': '765',
    'isOutgoing': false,
    'isVideo': false,
    'state': state
  };
}

export default function tgCallStartRequestMapperTest() {
  describe('TgCallStartRequestMapperTest', () => {
    it('shouldMapReadyCallToNativeStartRequest', 0, () => {
      const result = mapReadyCallToTgCallStartRequest(buildCall(buildReadyState()));

      expect(result.ok).assertTrue();
      if (result.request) {
        expect(result.request.protocolVersion).assertEqual('8.0.0');
        expect(result.request.encryptionKeyBase64).assertEqual('base64-key');
        expect(result.request.isOutgoing).assertFalse();
        expect(result.request.allowP2p).assertTrue();
        expect(result.request.customParameters).assertEqual('{"custom":"yes"}');
        expect(result.request.serversJson).assertEqual(
          '[{"id":"6001","ipAddress":"149.154.167.50","ipv6Address":"","port":595,'
            + '"type":"callServerTypeTelegramReflector","peerTag":"peer-tag"},'
            + '{"id":"6002","ipAddress":"149.154.167.51","ipv6Address":"","port":443,'
            + '"type":"callServerTypeWebrtc","username":"turn-user","password":"turn-pass",'
            + '"supportsTurn":true,"supportsStun":true}]'
        );
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldRejectNonReadyCall', 0, () => {
      const state: TdParsedCallStatePayload = {
        'kind': 'pending',
        'tdType': 'callStatePending',
        'isCreated': true,
        'isReceived': true
      };

      const result = mapReadyCallToTgCallStartRequest(buildCall(state));

      expect(result.ok).assertFalse();
      expect(result.error).assertEqual('notReady');
    });

    it('shouldRejectReadyCallWithoutRequiredNativeInputs', 0, () => {
      const missingKeyState = buildReadyState();
      missingKeyState.encryptionKey = '';
      const missingServersState = buildReadyState();
      missingServersState.servers = [];
      const missingProtocolState = buildReadyState();
      missingProtocolState.protocol = undefined;

      const missingKeyResult = mapReadyCallToTgCallStartRequest(buildCall(missingKeyState));
      const missingServersResult = mapReadyCallToTgCallStartRequest(buildCall(missingServersState));
      const missingProtocolResult = mapReadyCallToTgCallStartRequest(buildCall(missingProtocolState));

      expect(missingKeyResult.ok).assertFalse();
      expect(missingKeyResult.error).assertEqual('missingEncryptionKey');
      expect(missingServersResult.ok).assertFalse();
      expect(missingServersResult.error).assertEqual('missingServers');
      expect(missingProtocolResult.ok).assertFalse();
      expect(missingProtocolResult.error).assertEqual('missingProtocolVersion');
    });

    it('shouldSelectFirstNonEmptyProtocolVersion', 0, () => {
      const state = buildReadyState();
      if (state.protocol) {
        state.protocol.libraryVersions = ['', '8.0.0'];
      }

      const result = mapReadyCallToTgCallStartRequest(buildCall(state));

      expect(result.ok).assertTrue();
      if (result.request) {
        expect(result.request.protocolVersion).assertEqual('8.0.0');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldPreferWebKProtocolVersionWhenReadyStateContainsWebKAndNativeVersions', 0, () => {
      const state = buildReadyState();
      if (state.protocol) {
        state.protocol.libraryVersions = ['4.0.0', '10.0.0'];
      }

      const result = mapReadyCallToTgCallStartRequest(buildCall(state), ['10.0.0', '11.0.0']);

      expect(result.ok).assertTrue();
      if (result.request) {
        expect(result.request.protocolVersion).assertEqual('4.0.0');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldPreferNativeSupportedProtocolVersionWhenReadyStateDoesNotContainWebKVersion', 0, () => {
      const state = buildReadyState();
      if (state.protocol) {
        state.protocol.libraryVersions = ['8.0.0', '10.0.0'];
      }

      const result = mapReadyCallToTgCallStartRequest(buildCall(state), ['10.0.0', '11.0.0']);

      expect(result.ok).assertTrue();
      if (result.request) {
        expect(result.request.protocolVersion).assertEqual('10.0.0');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldKeepFirstReadyStateVersionWhenNativeSupportedVersionsDoNotOverlap', 0, () => {
      const state = buildReadyState();
      if (state.protocol) {
        state.protocol.libraryVersions = ['4.0.0'];
      }

      const result = mapReadyCallToTgCallStartRequest(buildCall(state), ['10.0.0', '11.0.0']);

      expect(result.ok).assertTrue();
      if (result.request) {
        expect(result.request.protocolVersion).assertEqual('4.0.0');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldRejectReadyCallWithEmptyProtocolVersions', 0, () => {
      const state = buildReadyState();
      if (state.protocol) {
        state.protocol.libraryVersions = [];
      }

      const result = mapReadyCallToTgCallStartRequest(buildCall(state));

      expect(result.ok).assertFalse();
      expect(result.error).assertEqual('missingProtocolVersion');
    });

    it('shouldKeepWebKProtocolVersionFromReadyState', 0, () => {
      const state = buildReadyState();
      if (state.protocol) {
        state.protocol.libraryVersions = ['4.0.0'];
      }

      const result = mapReadyCallToTgCallStartRequest(buildCall(state));

      expect(result.ok).assertTrue();
      if (result.request) {
        expect(result.request.protocolVersion).assertEqual('4.0.0');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldSelectV3ProtocolVersionWhenPeerOffersThirteenOnly', 0, () => {
      // Web-K production after 2026-05-24 (#65): TDLib intersection contains only 13.0.0.
      const state = buildReadyState();
      if (state.protocol) {
        state.protocol.libraryVersions = ['13.0.0'];
      }

      const result = mapReadyCallToTgCallStartRequest(buildCall(state), ['10.0.0', '11.0.0', '13.0.0', '4.0.0']);

      expect(result.ok).assertTrue();
      if (result.request) {
        expect(result.request.protocolVersion).assertEqual('13.0.0');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldPreferV3OverLegacyWhenBothCommonVersionsPresent', 0, () => {
      // ADR-0009 preference order: 13.0.0 wins over legacy 4.0.0 when the
      // intersection carries both (hypothetical peer declaring both versions).
      const state = buildReadyState();
      if (state.protocol) {
        state.protocol.libraryVersions = ['4.0.0', '13.0.0'];
      }

      const result = mapReadyCallToTgCallStartRequest(buildCall(state), ['10.0.0', '11.0.0', '13.0.0', '4.0.0']);

      expect(result.ok).assertTrue();
      if (result.request) {
        expect(result.request.protocolVersion).assertEqual('13.0.0');
      } else {
        expect(false).assertTrue();
      }
    });
  });
}
