import { describe, it, expect } from '@ohos/hypium';
import { extractAuthorizationStateCodeLength } from '../main/ets/services/td/TdPayloadParsers';

export default function tdPayloadParsersTest() {
  describe('TdPayloadParsersTest', () => {
    it('shouldExtractCodeLengthFromSnakeCaseWaitCodeUpdate', 0, () => {
      const payload =
        '{"@type":"updateAuthorizationState","authorization_state":{"@type":"authorizationStateWaitCode",' +
          '"code_info":{"type":{"@type":"authenticationCodeTypeSms","length":6}}}}';

      expect(extractAuthorizationStateCodeLength(payload)).assertEqual(6);
    });

    it('shouldExtractCodeLengthFromCamelCaseWaitCodeUpdate', 0, () => {
      const payload =
        '{"@type":"updateAuthorizationState","authorizationState":{"@type":"authorizationStateWaitCode",' +
          '"codeInfo":{"type":{"@type":"authenticationCodeTypeTelegramMessage","length":"4"}}}}';

      expect(extractAuthorizationStateCodeLength(payload)).assertEqual(4);
    });

    it('shouldReturnZeroWhenWaitCodeLengthIsUnavailable', 0, () => {
      const payload =
        '{"@type":"updateAuthorizationState","authorization_state":{"@type":"authorizationStateWaitCode"}}';

      expect(extractAuthorizationStateCodeLength(payload)).assertEqual(0);
      expect(extractAuthorizationStateCodeLength('{"@type":"authorizationStateWaitPhoneNumber"}')).assertEqual(0);
    });
  });
}
