import { describe, expect, it } from '@ohos/hypium';
import { buildDefaultTdCallProtocolRequest } from '../main/ets/services/voip/CallProtocolRequestBuilder';

export default function callProtocolRequestBuilderTest() {
  describe('CallProtocolRequestBuilderTest', () => {
    it('shouldBuildDefaultTdCallProtocolRequest', 0, () => {
      const request = buildDefaultTdCallProtocolRequest();
      const requestJson = JSON.stringify(request);

      expect(requestJson.indexOf('"@type":"callProtocol"') >= 0).assertTrue();
      expect(request.udp_p2p).assertTrue();
      expect(request.udp_reflector).assertTrue();
      expect(request.min_layer).assertEqual(92);
      expect(request.max_layer).assertEqual(92);
      // ADR-0009 / #65: legacy 4.0.0 + production 13.0.0 (tgcalls v2 signaling V3).
      expect(request.library_versions.length).assertEqual(2);
      expect(request.library_versions[0]).assertEqual('4.0.0');
      expect(request.library_versions[1]).assertEqual('13.0.0');
    });
  });
}
