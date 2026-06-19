import { describe, expect, it } from '@ohos/hypium';
import {
  buildChatNotificationOpenRequestCode,
  buildQuickReplyNotificationRequestCode,
  shouldOfferQuickReplyForNotificationItem
} from '../main/ets/services/notifications/TdNotificationsService';
import {
  TdNotificationContentKind,
  TdNotificationItem
} from '../main/ets/services/td/TdPayloadTypes';

function buildNotificationItem(kind: TdNotificationContentKind, isSilent: boolean): TdNotificationItem {
  return {
    id: 7001,
    groupId: 9001,
    chatId: '55',
    messageId: '1001',
    senderUserId: '7',
    date: 1710000000,
    isSilent: isSilent,
    content: {
      kind: kind,
      text: 'Hello',
      showPreview: true
    }
  };
}

export default function tdNotificationsServiceTest() {
  describe('TdNotificationsServiceTest', () => {
    it('shouldOfferQuickReplyForVisibleUserMessageNotifications', 0, () => {
      const item = buildNotificationItem('text', false);

      expect(shouldOfferQuickReplyForNotificationItem(item)).assertTrue();
    });

    it('shouldNotOfferQuickReplyForSilentNotifications', 0, () => {
      const item = buildNotificationItem('text', true);

      expect(shouldOfferQuickReplyForNotificationItem(item)).assertFalse();
    });

    it('shouldNotOfferQuickReplyForServiceEventNotifications', 0, () => {
      const item = buildNotificationItem('serviceEvent', false);

      expect(shouldOfferQuickReplyForNotificationItem(item)).assertFalse();
    });

    it('shouldKeepQuickReplyRequestCodeDisjointFromChatOpenRequestCode', 0, () => {
      const openRequestCode = buildChatNotificationOpenRequestCode(7001);
      const quickReplyRequestCode = buildQuickReplyNotificationRequestCode(7001);

      expect(openRequestCode).assertEqual(7001);
      expect(quickReplyRequestCode).assertEqual(200007001);
      expect(quickReplyRequestCode !== openRequestCode).assertTrue();
      expect(quickReplyRequestCode < 400000000).assertTrue();
    });

    it('shouldNormalizeFallbackRequestCodesConsistently', 0, () => {
      const openRequestCode = buildChatNotificationOpenRequestCode(0);
      const quickReplyRequestCode = buildQuickReplyNotificationRequestCode(0);

      expect(openRequestCode).assertEqual(1);
      expect(quickReplyRequestCode).assertEqual(200000001);
      expect(quickReplyRequestCode !== openRequestCode).assertTrue();
    });
  });
}
