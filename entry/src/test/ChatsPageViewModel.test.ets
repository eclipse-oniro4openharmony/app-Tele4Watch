import { describe, it, expect } from '@ohos/hypium';
import { createResourceUiText } from '../main/ets/models/ui/UiTextValue';
import { TdChatListItem } from '../main/ets/services/td/TdPayloadTypes';
import { ChatsPageViewModel } from '../main/ets/viewmodel/ChatsPageViewModel';

function buildChat(overrides?: Partial<TdChatListItem>): TdChatListItem {
  return {
    id: overrides?.id ?? '42',
    title: overrides?.title ?? 'Ada',
    chatKind: overrides?.chatKind ?? 'private',
    username: overrides?.username,
    peerUserId: overrides?.peerUserId,
    avatarPath: overrides?.avatarPath,
    avatarFileId: overrides?.avatarFileId,
    lastMessageDate: overrides?.lastMessageDate,
    lastMessageText: overrides?.lastMessageText,
    lastMessageTextValue: overrides?.lastMessageTextValue,
    lastMessageKind: overrides?.lastMessageKind,
    lastMessageIsOutgoing: overrides?.lastMessageIsOutgoing,
    lastMessageCallEventStatus: overrides?.lastMessageCallEventStatus,
    lastReadInboxMessageId: overrides?.lastReadInboxMessageId,
    lastReadOutboxMessageId: overrides?.lastReadOutboxMessageId,
    unreadCount: overrides?.unreadCount,
    defaultDisableNotification: overrides?.defaultDisableNotification,
    notificationMuteFor: overrides?.notificationMuteFor
  };
}

export default function chatsPageViewModelTest() {
  describe('ChatsPageViewModelTest', () => {
    it('shouldFormatUnreadBadgeText', 0, () => {
      const viewModel = new ChatsPageViewModel();

      expect(viewModel.formatUnreadBadge(0)).assertEqual('');
      expect(viewModel.formatUnreadBadge(-1)).assertEqual('');
      expect(viewModel.formatUnreadBadge(1)).assertEqual('1');
      expect(viewModel.formatUnreadBadge(99)).assertEqual('99');
      expect(viewModel.formatUnreadBadge(100)).assertEqual('99+');
      expect(viewModel.formatUnreadBadge(9999)).assertEqual('99+');
    });

    it('shouldNormalizeUnreadCount', 0, () => {
      const viewModel = new ChatsPageViewModel();

      expect(viewModel.chatUnreadCount(buildChat({ unreadCount: undefined }))).assertEqual(0);
      expect(viewModel.chatUnreadCount(buildChat({ unreadCount: -3 }))).assertEqual(0);
      expect(viewModel.chatUnreadCount(buildChat({ unreadCount: 0 }))).assertEqual(0);
      expect(viewModel.chatUnreadCount(buildChat({ unreadCount: 7 }))).assertEqual(7);
    });

    it('shouldResolveMutedState', 0, () => {
      const viewModel = new ChatsPageViewModel();

      expect(viewModel.chatIsMuted(buildChat({
        notificationMuteFor: 3600,
        defaultDisableNotification: false
      }))).assertTrue();
      expect(viewModel.chatIsMuted(buildChat({
        notificationMuteFor: 0,
        defaultDisableNotification: true
      }))).assertTrue();
      expect(viewModel.chatIsMuted(buildChat({
        notificationMuteFor: 0,
        defaultDisableNotification: false
      }))).assertFalse();
      expect(viewModel.chatIsMuted(buildChat())).assertFalse();
    });

    it('shouldIncludeUnreadCountAndMutedStateInRenderKey', 0, () => {
      const viewModel = new ChatsPageViewModel();
      const baseChat = buildChat({
        id: '42',
        lastMessageDate: 1710000000,
        lastMessageText: 'hello',
        avatarPath: '/tmp/avatar.jpg',
        unreadCount: 0,
        notificationMuteFor: 0,
        defaultDisableNotification: false
      });
      const unreadChat = buildChat({
        id: '42',
        lastMessageDate: 1710000000,
        lastMessageText: 'hello',
        avatarPath: '/tmp/avatar.jpg',
        unreadCount: 5,
        notificationMuteFor: 0,
        defaultDisableNotification: false
      });
      const mutedChat = buildChat({
        id: '42',
        lastMessageDate: 1710000000,
        lastMessageText: 'hello',
        avatarPath: '/tmp/avatar.jpg',
        unreadCount: 0,
        notificationMuteFor: 3600,
        defaultDisableNotification: false
      });

      expect(viewModel.chatRenderKey(baseChat)).assertEqual('42:Ada:1710000000:hello:::in::/tmp/avatar.jpg:0:a');
      expect(viewModel.chatRenderKey(unreadChat)).assertEqual('42:Ada:1710000000:hello:::in::/tmp/avatar.jpg:5:a');
      expect(viewModel.chatRenderKey(mutedChat)).assertEqual('42:Ada:1710000000:hello:::in::/tmp/avatar.jpg:0:m');
      expect(viewModel.chatRenderKey(baseChat) !== viewModel.chatRenderKey(unreadChat)).assertTrue();
      expect(viewModel.chatRenderKey(baseChat) !== viewModel.chatRenderKey(mutedChat)).assertTrue();
    });

    it('shouldUseTitleAndLastMessageTextInRenderKey', 0, () => {
      const viewModel = new ChatsPageViewModel();
      const firstChat = buildChat({
        id: '42',
        title: 'First title',
        lastMessageDate: 1710000000,
        lastMessageText: 'first message'
      });
      const secondChat = buildChat({
        id: '42',
        title: 'First title',
        lastMessageDate: 1710000000,
        lastMessageText: 'second message'
      });
      const renamedChat = buildChat({
        id: '42',
        title: 'Second title',
        lastMessageDate: 1710000000,
        lastMessageText: 'first message'
      });

      expect(viewModel.chatLastMessageText(buildChat({ lastMessageText: '  hello  ' }))).assertEqual('hello');
      expect(viewModel.chatLastMessageText(buildChat({ lastMessageText: '' }))).assertEqual('');
      expect(viewModel.chatLastMessageText(buildChat({ lastMessageText: undefined }))).assertEqual('');
      expect(viewModel.chatRenderKey(firstChat) !== viewModel.chatRenderKey(secondChat)).assertTrue();
      expect(viewModel.chatRenderKey(firstChat) !== viewModel.chatRenderKey(renamedChat)).assertTrue();
    });

    it('shouldPreserveUnreadAndMutedFieldsWhenApplyingChats', 0, () => {
      const viewModel = new ChatsPageViewModel();
      const chats: TdChatListItem[] = [buildChat({
        unreadCount: 12,
        defaultDisableNotification: true,
        notificationMuteFor: 0,
        lastMessageText: 'latest preview',
        lastReadInboxMessageId: '100',
        lastReadOutboxMessageId: '101'
      })];

      const nextState = viewModel.applyChats(chats);
      chats[0].unreadCount = 0;
      chats[0].defaultDisableNotification = false;

      expect(nextState.chats.length).assertEqual(1);
      expect(nextState.chats[0].unreadCount).assertEqual(12);
      expect(nextState.chats[0].defaultDisableNotification).assertTrue();
      expect(nextState.chats[0].notificationMuteFor).assertEqual(0);
      expect(nextState.chats[0].lastMessageText).assertEqual('latest preview');
      expect(nextState.chats[0].lastReadInboxMessageId).assertEqual('100');
      expect(nextState.chats[0].lastReadOutboxMessageId).assertEqual('101');
      expect(viewModel.chatIsMuted(nextState.chats[0])).assertTrue();
      expect(viewModel.chatUnreadCount(nextState.chats[0])).assertEqual(12);
    });

    it('shouldPreservePreviewMetadataWhenApplyingChats', 0, () => {
      const viewModel = new ChatsPageViewModel();
      const chats: TdChatListItem[] = [buildChat({
        lastMessageText: 'Outgoing Call (49 s)',
        lastMessageTextValue: createResourceUiText('chat_preview_call_outgoing_seconds_format', 49),
        lastMessageKind: 'callEvent',
        lastMessageIsOutgoing: true,
        lastMessageCallEventStatus: 'answered'
      })];

      const nextState = viewModel.applyChats(chats);
      chats[0].lastMessageIsOutgoing = false;
      chats[0].lastMessageCallEventStatus = 'missed';

      expect(nextState.chats.length).assertEqual(1);
      expect(nextState.chats[0].lastMessageKind).assertEqual('callEvent');
      expect(nextState.chats[0].lastMessageIsOutgoing).assertTrue();
      expect(nextState.chats[0].lastMessageCallEventStatus).assertEqual('answered');
      if (nextState.chats[0].lastMessageTextValue) {
        expect(nextState.chats[0].lastMessageTextValue.resourceName).assertEqual('chat_preview_call_outgoing_seconds_format');
        expect(nextState.chats[0].lastMessageTextValue.args[0]).assertEqual(49);
      } else {
        expect(false).assertTrue();
      }
      expect(viewModel.chatRenderKey(nextState.chats[0]).indexOf(':out:answered:') > 0).assertTrue();
    });
  });
}
