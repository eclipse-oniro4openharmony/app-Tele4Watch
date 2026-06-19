import { describe, expect, it } from '@ohos/hypium';
import {
  parseUpdateCall,
  parseUpdateNewCallSignalingData
} from '../main/ets/services/td/TdCallParser';

export default function tdCallParserTest() {
  describe('TdCallParserTest', () => {
    it('shouldParseIncomingPendingCall', 0, () => {
      const result = parseUpdateCall(
        '{"@type":"updateCall","call":{"@type":"call","id":42,"unique_id":"9876543210",'
        + '"user_id":"987654321","is_outgoing":false,"is_video":true,'
        + '"state":{"@type":"callStatePending","is_created":true,"is_received":true}}}'
      );

      expect(result.ok).assertTrue();
      if (result.call) {
        expect(result.call.id).assertEqual(42);
        expect(result.call.uniqueId).assertEqual('9876543210');
        expect(result.call.userId).assertEqual('987654321');
        expect(result.call.isOutgoing).assertFalse();
        expect(result.call.isVideo).assertTrue();
        expect(result.call.state.kind).assertEqual('pending');
        expect(result.call.state.isCreated).assertTrue();
        expect(result.call.state.isReceived).assertTrue();
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseReadyCallWithProtocolAndServers', 0, () => {
      const result = parseUpdateCall(
        '{"@type":"updateCall","call":{"id":"43","unique_id":"123","user_id":765,'
        + '"is_outgoing":false,"is_video":false,"state":{"@type":"callStateReady",'
        + '"protocol":{"@type":"callProtocol","udp_p2p":true,"udp_reflector":true,'
        + '"min_layer":65,"max_layer":"92","library_versions":["2.4.4"]},'
        + '"servers":[{"@type":"callServer","id":"6001","ip_address":"149.154.167.50",'
        + '"ipv6_address":"","port":595,"type":{"@type":"callServerTypeTelegramReflector",'
        + '"peer_tag":"abc"}},{"@type":"callServer","id":"6002","ip_address":"149.154.167.51",'
        + '"ipv6_address":"","port":443,"type":{"@type":"callServerTypeWebrtc",'
        + '"username":"turn-user","password":"turn-pass","supports_turn":true,"supports_stun":true}}],'
        + '"config":"{}","encryption_key":"base64-key",'
        + '"emojis":["a","b"],"allow_p2p":true,"is_group_call_supported":false,'
        + '"custom_parameters":"{}"}}}'
      );

      expect(result.ok).assertTrue();
      if (result.call) {
        expect(result.call.id).assertEqual(43);
        expect(result.call.userId).assertEqual('765');
        expect(result.call.state.kind).assertEqual('ready');
        if (result.call.state.protocol) {
          expect(result.call.state.protocol.udpP2p).assertTrue();
          expect(result.call.state.protocol.udpReflector).assertTrue();
          expect(result.call.state.protocol.minLayer).assertEqual(65);
          expect(result.call.state.protocol.maxLayer).assertEqual(92);
          expect(result.call.state.protocol.libraryVersions.length).assertEqual(1);
        } else {
          expect(false).assertTrue();
        }
        if (result.call.state.servers) {
          expect(result.call.state.servers.length).assertEqual(2);
          expect(result.call.state.servers[0].id).assertEqual('6001');
          expect(result.call.state.servers[0].type).assertEqual('callServerTypeTelegramReflector');
          expect(result.call.state.servers[0].peerTag).assertEqual('abc');
          expect(result.call.state.servers[1].id).assertEqual('6002');
          expect(result.call.state.servers[1].type).assertEqual('callServerTypeWebrtc');
          expect(result.call.state.servers[1].username).assertEqual('turn-user');
          expect(result.call.state.servers[1].password).assertEqual('turn-pass');
          expect(result.call.state.servers[1].supportsTurn).assertTrue();
          expect(result.call.state.servers[1].supportsStun).assertTrue();
        } else {
          expect(false).assertTrue();
        }
        expect(result.call.state.encryptionKey).assertEqual('base64-key');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseDiscardedAndErrorStates', 0, () => {
      const discarded = parseUpdateCall(
        '{"call":{"id":44,"user_id":"11","is_outgoing":false,"is_video":false,'
        + '"state":{"@type":"callStateDiscarded","reason":{"@type":"callDiscardReasonDeclined"},'
        + '"need_rating":false,"need_debug_information":true,"need_log":false}}}'
      );
      const failed = parseUpdateCall(
        '{"call":{"id":45,"user_id":"11","is_outgoing":false,"is_video":false,'
        + '"state":{"@type":"callStateError","error":{"@type":"error","code":400,"message":"CALL_FAILED"}}}}'
      );

      expect(discarded.ok).assertTrue();
      if (discarded.call) {
        expect(discarded.call.state.kind).assertEqual('discarded');
        expect(discarded.call.state.discardReason).assertEqual('callDiscardReasonDeclined');
        expect(discarded.call.state.needDebugInformation).assertTrue();
      } else {
        expect(false).assertTrue();
      }

      expect(failed.ok).assertTrue();
      if (failed.call) {
        expect(failed.call.state.kind).assertEqual('error');
        expect(failed.call.state.errorCode).assertEqual(400);
        expect(failed.call.state.errorMessage).assertEqual('CALL_FAILED');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldRejectMalformedOrIncompleteCalls', 0, () => {
      expect(parseUpdateCall('{bad json').ok).assertFalse();
      expect(parseUpdateCall('{"call":{"id":42}}').ok).assertFalse();
      expect(parseUpdateCall('{"call":{"id":42,"user_id":"77","state":{"@type":"callStateUnknown"}}}').ok)
        .assertFalse();
    });

    it('shouldParseCallSignalingData', 0, () => {
      const result = parseUpdateNewCallSignalingData(
        '{"@type":"updateNewCallSignalingData","call_id":"42","data":"AAECAwQ="}'
      );

      expect(result.ok).assertTrue();
      expect(result.callId).assertEqual(42);
      expect(result.data).assertEqual('AAECAwQ=');
      expect(parseUpdateNewCallSignalingData('{"call_id":0,"data":"x"}').ok).assertFalse();
      expect(parseUpdateNewCallSignalingData('{"call_id":42}').ok).assertFalse();
    });
  });
}
