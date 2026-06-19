import { describe, expect, it } from '@ohos/hypium';
import {
  buildTdSendVoiceNoteMessageRequest,
  encodeTdVoiceNoteWaveform,
  TdAcceptCallRequest,
  TdDiscardCallRequest,
  TdSendCallSignalingDataRequest
} from '../main/ets/services/td/TdRequestTypes';

function createWaveformBytes(): Uint8Array {
  return new Uint8Array([1, 7, 31, 63, 127, 255]);
}

function createShortWaveformBytes(): Uint8Array {
  return new Uint8Array([1, 7]);
}

function createFullWaveformBytes(): Uint8Array {
  return new Uint8Array([
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
    10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
    20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
    30, 31, 32, 33, 34, 35, 36, 37, 38, 39,
    40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
    50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
    60, 61, 62
  ]);
}

export default function tdRequestTypesTest() {
  describe('TdRequestTypesTest', () => {
    it('shouldEncodeVoiceNoteWaveformToBase64', 0, () => {
      const sourceBytes = createWaveformBytes();

      const encoded = encodeTdVoiceNoteWaveform(sourceBytes);

      expect(encoded).assertEqual('AQcfP3//');
    });

    it('shouldEncode63ByteVoiceNoteWaveformToBase64WithoutPadding', 0, () => {
      const sourceBytes = createFullWaveformBytes();

      const encoded = encodeTdVoiceNoteWaveform(sourceBytes);

      expect(encoded).assertEqual('AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+');
    });

    it('shouldEncodeShortVoiceNoteWaveformToBase64WithPadding', 0, () => {
      const sourceBytes = createShortWaveformBytes();

      const encoded = encodeTdVoiceNoteWaveform(sourceBytes);

      expect(encoded).assertEqual('AQc=');
    });

    it('shouldBuildSendVoiceNoteMessageRequestShape', 0, () => {
      const request = buildTdSendVoiceNoteMessageRequest(
        'message:send:voice:321:123456',
        '321',
        '/data/storage/el2/base/cache/voice_notes/test.oga',
        17,
        'AQc='
      );
      const requestJson = JSON.stringify(request);

      expect(request.chat_id).assertEqual('321');
      expect(requestJson.indexOf('"@type":"sendMessage"') >= 0).assertTrue();
      expect(requestJson.indexOf('"@extra":"message:send:voice:321:123456"') >= 0).assertTrue();
      expect(requestJson.indexOf('"@type":"inputMessageVoiceNote"') >= 0).assertTrue();
      expect(requestJson.indexOf('"@type":"inputFileLocal"') >= 0).assertTrue();
      expect(requestJson.indexOf('"@type":"formattedText"') >= 0).assertTrue();

      expect(requestJson.indexOf('"path":"/data/storage/el2/base/cache/voice_notes/test.oga"') >= 0).assertTrue();
      expect(requestJson.indexOf('"duration":17') >= 0).assertTrue();
      expect(requestJson.indexOf('"waveform":"AQc="') >= 0).assertTrue();
      expect(requestJson.indexOf('"text":""') >= 0).assertTrue();
    });

    it('shouldSupportCallRequestShapes', 0, () => {
      const acceptRequest: TdAcceptCallRequest = {
        '@type': 'acceptCall',
        '@extra': 'call:accept:42',
        'call_id': 42,
        'protocol': {
          '@type': 'callProtocol',
          'udp_p2p': true,
          'udp_reflector': true,
          'min_layer': 65,
          'max_layer': 92,
          'library_versions': ['2.4.4']
        }
      };
      const discardRequest: TdDiscardCallRequest = {
        '@type': 'discardCall',
        '@extra': 'call:discard:42',
        'call_id': 42,
        'is_disconnected': false,
        'invite_link': '',
        'duration': 0,
        'is_video': false,
        'connection_id': '0'
      };
      const signalingRequest: TdSendCallSignalingDataRequest = {
        '@type': 'sendCallSignalingData',
        '@extra': 'call:signal:42',
        'call_id': 42,
        'data': 'AAECAwQ='
      };

      expect(JSON.stringify(acceptRequest).indexOf('"@type":"acceptCall"') >= 0).assertTrue();
      expect(JSON.stringify(acceptRequest).indexOf('"@type":"callProtocol"') >= 0).assertTrue();
      expect(JSON.stringify(discardRequest).indexOf('"@type":"discardCall"') >= 0).assertTrue();
      expect(JSON.stringify(discardRequest).indexOf('"connection_id":"0"') >= 0).assertTrue();
      expect(JSON.stringify(signalingRequest).indexOf('"@type":"sendCallSignalingData"') >= 0).assertTrue();
      expect(JSON.stringify(signalingRequest).indexOf('"data":"AAECAwQ="') >= 0).assertTrue();
    });
  });
}
