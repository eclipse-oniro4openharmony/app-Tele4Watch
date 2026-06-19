import { describe, it, expect } from '@ohos/hypium';
import {
  parseUpdateActiveNotifications,
  parseUpdateNotification,
  parseUpdateNotificationGroup
} from '../main/ets/services/td/TdNotificationParser';

export default function tdNotificationParserTest() {
  describe('TdNotificationParserTest', () => {
    it('shouldParseNotificationGroupWithNewMessageAndRemovedIds', 0, () => {
      const result = parseUpdateNotificationGroup(
        '{"notification_group_id":17,"chat_id":"8529861543","notification_settings_chat_id":"8529861543",'
        + '"total_count":3,"added_notifications":[{"id":5001,"date":1706192103,"is_silent":false,'
        + '"type":{"@type":"notificationTypeNewMessage","show_preview":true,'
        + '"message":{"id":"12345678","chat_id":"8529861543",'
        + '"sender_id":{"@type":"messageSenderUser","user_id":"987654321"},'
        + '"content":{"@type":"messageText","text":{"@type":"formattedText","text":"Czesc, jak tam?"}}}}}],'
        + '"removed_notification_ids":[4999,"5000"]}'
      );

      expect(result.ok).assertTrue();
      if (result.group) {
        expect(result.group.groupId).assertEqual(17);
        expect(result.group.chatId).assertEqual('8529861543');
        expect(result.group.totalCount).assertEqual(3);
        expect(result.group.removedNotificationIds.length).assertEqual(2);
        expect(result.group.items.length).assertEqual(1);
        const item = result.group.items[0];
        expect(item.id).assertEqual(5001);
        expect(item.messageId).assertEqual('12345678');
        expect(item.senderUserId).assertEqual('987654321');
        expect(item.content.kind).assertEqual('text');
        expect(item.content.text).assertEqual('Czesc, jak tam?');
        expect(item.content.showPreview).assertTrue();
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldHidePreviewWhenTdlibDisablesPreview', 0, () => {
      const result = parseUpdateNotification(
        '{"notification_group_id":18,"notification":{"id":6001,"date":1706192104,"is_silent":true,'
        + '"type":{"@type":"notificationTypeNewMessage","show_preview":false,'
        + '"message":{"id":"22345678","chat_id":"-1003559072152",'
        + '"sender_id":{"@type":"messageSenderChat","chat_id":"-1003559072152"},'
        + '"content":{"@type":"messageText","text":{"@type":"formattedText","text":"secret"}}}}}}'
      );

      expect(result.ok).assertTrue();
      if (result.item) {
        expect(result.groupId).assertEqual(18);
        expect(result.item.chatId).assertEqual('-1003559072152');
        expect(result.item.senderChatId).assertEqual('-1003559072152');
        expect(result.item.isSilent).assertTrue();
        expect(result.item.content.kind).assertEqual('text');
        expect(result.item.content.text).assertEqual('New message');
        expect(result.item.content.showPreview).assertFalse();
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseActiveNotificationsSnapshot', 0, () => {
      const result = parseUpdateActiveNotifications(
        '{"groups":[{"id":19,"chat_id":"-1003559072152","total_count":1,"notifications":[{"id":7001,'
        + '"date":1706192105,"is_silent":false,'
        + '"type":{"@type":"notificationTypeNewMessage","show_preview":true,'
        + '"message":{"id":"32345678","chat_id":"-1003559072152",'
        + '"sender_id":{"@type":"messageSenderUser","user_id":"765"},'
        + '"content":{"@type":"messagePhoto","caption":{"@type":"formattedText","text":"photo caption"}}}}}]}]}'
      );

      expect(result.ok).assertTrue();
      if (result.groups) {
        expect(result.groups.length).assertEqual(1);
        const group = result.groups[0];
        expect(group.groupId).assertEqual(19);
        expect(group.chatId).assertEqual('-1003559072152');
        expect(group.removedNotificationIds.length).assertEqual(0);
        expect(group.items.length).assertEqual(1);
        expect(group.items[0].content.kind).assertEqual('photo');
        expect(group.items[0].content.text).assertEqual('photo caption');
      } else {
        expect(false).assertTrue();
      }
    });
  });
}
