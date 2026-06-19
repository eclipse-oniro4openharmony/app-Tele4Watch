import { describe, it, expect } from '@ohos/hypium';
import {
  parseChatListMembershipPayload,
  parseChatPayload,
  parseUpdateChatLastMessagePayload,
  parseUpdateChatNotificationSettingsPayload,
  parseUpdateChatPhotoPayload,
  parseUpdateChatPositionPayload,
  parseUpdateChatReadInboxPayload,
  parseUpdateChatReadOutboxPayload,
  parseUpdateChatTitlePayload,
  parseUpdateNewChatPayload
} from '../main/ets/services/td/TdChatParser';

export default function tdChatParserTest() {
  describe('TdChatParserTest', () => {
    it('shouldParsePrivateChatKindAndPeerUserId', 0, () => {
      const result = parseChatPayload(
        '{"id":101,"title":"Ada","type":{"@type":"chatTypePrivate","user_id":42},'
        + '"last_message":{"id":900,"chat_id":101,"date":1710000000,'
        + '"content":{"@type":"messageText","text":{"text":"hello last"}}},'
        + '"last_read_inbox_message_id":"900","last_read_outbox_message_id":"901","unread_count":2}'
      );

      expect(result.ok).assertTrue();
      if (result.chat) {
        expect(result.chat.chatKind).assertEqual('private');
        expect(result.chat.peerUserId).assertEqual('42');
        expect(result.chat.lastMessageDate).assertEqual(1710000000);
        expect(result.chat.lastMessageText).assertEqual('hello last');
        expect(result.chat.lastMessageKind).assertEqual('text');
        expect(result.chat.lastReadInboxMessageId).assertEqual('900');
        expect(result.chat.lastReadOutboxMessageId).assertEqual('901');
        expect(result.chat.unreadCount).assertEqual(2);
        expect(result.chat.notificationMuteFor).assertEqual(0);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseChatNotificationMuteSettings', 0, () => {
      const result = parseChatPayload(
        '{"id":"707","title":"Muted","type":{"@type":"chatTypePrivate","user_id":"77"},'
        + '"default_disable_notification":true,"notification_settings":{"mute_for":3600}}'
      );

      expect(result.ok).assertTrue();
      if (result.chat) {
        expect(result.chat.defaultDisableNotification === true).assertTrue();
        expect(result.chat.notificationMuteFor).assertEqual(3600);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseBasicGroupChatKind', 0, () => {
      const result = parseChatPayload(
        '{"id":"202","title":"Builders","type":{"@type":"chatTypeBasicGroup","basic_group_id":"77"}}'
      );

      expect(result.ok).assertTrue();
      if (result.chat) {
        expect(result.chat.chatKind).assertEqual('basicGroup');
        expect(result.chat.peerUserId === undefined).assertTrue();
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseSupergroupChatKindWhenChannelFlagIsFalse', 0, () => {
      const result = parseChatPayload(
        '{"id":"303","title":"Supergroup","type":{"@type":"chatTypeSupergroup","supergroup_id":"88","is_channel":false}}'
      );

      expect(result.ok).assertTrue();
      if (result.chat) {
        expect(result.chat.chatKind).assertEqual('supergroup');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseChannelChatKindWhenChannelFlagIsTrue', 0, () => {
      const result = parseUpdateNewChatPayload(
        '{"chat":{"id":"404","title":"Telegram News","type":{"@type":"chatTypeSupergroup","supergroup_id":"99","is_channel":true},'
        + '"last_read_outbox_message_id":"902","unread_count":0}}'
      );

      expect(result.ok).assertTrue();
      if (result.chat) {
        expect(result.chat.chatKind).assertEqual('channel');
        expect(result.chat.lastReadOutboxMessageId).assertEqual('902');
        expect(result.chat.unreadCount).assertEqual(0);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldFallbackToUnknownForSecretChatKind', 0, () => {
      const result = parseChatPayload(
        '{"id":"505","title":"Secret","type":{"@type":"chatTypeSecret","user_id":"123","secret_chat_id":7}}'
      );

      expect(result.ok).assertTrue();
      if (result.chat) {
        expect(result.chat.chatKind).assertEqual('unknown');
        expect(result.chat.peerUserId).assertEqual('123');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseChatReadInboxUpdate', 0, () => {
      const result = parseUpdateChatReadInboxPayload(
        '{"chat_id":"303","last_read_inbox_message_id":"901","unread_count":4}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('303');
      expect(result.lastReadInboxMessageId).assertEqual('901');
      expect(result.unreadCount).assertEqual(4);
    });

    it('shouldParseNegativeChatReadInboxUpdate', 0, () => {
      const result = parseUpdateChatReadInboxPayload(
        '{"chat_id":"-1003559072152","last_read_inbox_message_id":"901","unread_count":0}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('-1003559072152');
      expect(result.lastReadInboxMessageId).assertEqual('901');
      expect(result.unreadCount).assertEqual(0);
    });

    it('shouldParseChatReadOutboxUpdate', 0, () => {
      const result = parseUpdateChatReadOutboxPayload(
        '{"chat_id":"404","last_read_outbox_message_id":"902"}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('404');
      expect(result.lastReadOutboxMessageId).assertEqual('902');
    });

    it('shouldParseChatNotificationSettingsUpdate', 0, () => {
      const result = parseUpdateChatNotificationSettingsPayload(
        '{"chat_id":"303","notification_settings":{"mute_for":7200}}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('303');
      expect(result.muteFor).assertEqual(7200);
    });

    it('shouldParseMainChatPositionUpdate', 0, () => {
      const result = parseUpdateChatPositionPayload(
        '{"chat_id":"-4995634204","position":{"list":{"@type":"chatListMain"},'
        + '"order":"7635955706255900672","is_pinned":false}}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('-4995634204');
      expect(result.isMainList === true).assertTrue();
      expect(result.order).assertEqual('7635955706255900672');
      expect(result.isPinned === false).assertTrue();
    });

    it('shouldParseMainChatPositionRemoval', 0, () => {
      const result = parseUpdateChatPositionPayload(
        '{"chat_id":-4990487809,"position":{"list":{"@type":"chatListMain"},"order":"0","is_pinned":false}}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('-4990487809');
      expect(result.isMainList === true).assertTrue();
      expect(result.order).assertEqual('0');
    });

    it('shouldParseMainChatListMembershipUpdate', 0, () => {
      const result = parseChatListMembershipPayload(
        '{"chat_id":-4995634204,"chat_list":{"@type":"chatListMain"}}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('-4995634204');
      expect(result.isMainList === true).assertTrue();
    });

    it('shouldParseChatLastMessageUpdateText', 0, () => {
      const result = parseUpdateChatLastMessagePayload(
        '{"chat_id":"303","last_message":{"id":"902","chat_id":"303","date":1710000010,'
        + '"content":{"@type":"messageText","text":{"text":"live preview"}}}}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('303');
      expect(result.lastMessageDate).assertEqual(1710000010);
      expect(result.lastMessageText).assertEqual('live preview');
      expect(result.lastMessageKind).assertEqual('text');
    });

    it('shouldParseChatLastMessageUpdateCallPreview', 0, () => {
      const result = parseUpdateChatLastMessagePayload(
        '{"chat_id":"303","last_message":{"id":"903","chat_id":"303","date":1710000011,'
        + '"content":{"@type":"messageCall","is_video":true,"duration":0,'
        + '"discard_reason":{"@type":"callDiscardReasonDeclined"}}}}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('303');
      expect(result.lastMessageDate).assertEqual(1710000011);
      expect(result.lastMessageText).assertEqual('Declined Call');
      expect(result.lastMessageKind).assertEqual('callEvent');
      expect(result.lastMessageIsOutgoing).assertFalse();
      expect(result.lastMessageCallEventStatus).assertEqual('declined');
      if (result.lastMessageTextValue) {
        expect(result.lastMessageTextValue.resourceName).assertEqual('chat_preview_call_declined');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseChatLastMessageMediaPreviewWithoutLosingCaption', 0, () => {
      const captioned = parseUpdateChatLastMessagePayload(
        '{"chat_id":"303","last_message":{"id":"904","chat_id":"303","date":1710000012,"is_outgoing":true,'
        + '"content":{"@type":"messagePhoto","caption":{"text":"holiday"}}}}'
      );
      expect(captioned.ok).assertTrue();
      expect(captioned.lastMessageText).assertEqual('holiday');
      expect(captioned.lastMessageTextValue === undefined).assertTrue();
      expect(captioned.lastMessageIsOutgoing).assertTrue();

      const voice = parseUpdateChatLastMessagePayload(
        '{"chat_id":"303","last_message":{"id":"905","chat_id":"303","date":1710000013,"is_outgoing":false,'
        + '"content":{"@type":"messageVoiceNote","voice_note":{"voice":{"@type":"file","id":8,"local":{"path":""}}}}}}'
      );
      expect(voice.ok).assertTrue();
      expect(voice.lastMessageText).assertEqual('You received a voice message');
      if (voice.lastMessageTextValue) {
        expect(voice.lastMessageTextValue.resourceName).assertEqual('chat_preview_incoming_voice_note');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseChatTitleUpdate', 0, () => {
      const result = parseUpdateChatTitlePayload(
        '{"chat_id":-5290814901,"title":" Long group title "}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('-5290814901');
      expect(result.title).assertEqual('Long group title');
    });

    it('shouldParseChatPhotoUpdateWithFileId', 0, () => {
      const result = parseUpdateChatPhotoPayload(
        '{"chat_id":-5290814901,"photo":{"@type":"chatPhotoInfo",'
        + '"small":{"@type":"file","id":1269,"local":{"path":"","is_downloading_completed":false}}}}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('-5290814901');
      expect(result.hasPhoto === true).assertTrue();
      expect(result.avatarFileId).assertEqual(1269);
      expect(result.avatarPath === undefined).assertTrue();
    });

    it('shouldParseChatPhotoRemoval', 0, () => {
      const result = parseUpdateChatPhotoPayload(
        '{"chat_id":-5290814901,"photo":null}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('-5290814901');
      expect(result.hasPhoto === false).assertTrue();
    });

    it('shouldParseNegativeChatReadOutboxUpdate', 0, () => {
      const result = parseUpdateChatReadOutboxPayload(
        '{"chat_id":"-1003559072152","last_read_outbox_message_id":"902"}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('-1003559072152');
      expect(result.lastReadOutboxMessageId).assertEqual('902');
    });
  });
}
