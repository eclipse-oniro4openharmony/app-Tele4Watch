import { describe, it, expect } from '@ohos/hypium';
import { buildFallbackNotificationId } from '../main/ets/services/td/TdNotificationId';

export default function tdNotificationIdTest() {
  describe('TdNotificationIdTest', () => {
    it('shouldIncludeChatIdForFallbackMessageId', 0, () => {
      const firstId = buildFallbackNotificationId('1001', '2147483647');
      const secondId = buildFallbackNotificationId('1002', '2147483647');

      expect(firstId > 0).assertTrue();
      expect(secondId > 0).assertTrue();
      expect(firstId === secondId).assertFalse();
      expect(firstId === 2147483647).assertFalse();
      expect(secondId === 2147483647).assertFalse();
    });

    it('shouldBeStableForSameFallbackMessageIdentity', 0, () => {
      const firstId = buildFallbackNotificationId('-1003559072152', '123456789');
      const secondId = buildFallbackNotificationId('-1003559072152', '123456789');

      expect(firstId).assertEqual(secondId);
      expect(firstId > 0).assertTrue();
    });
  });
}
