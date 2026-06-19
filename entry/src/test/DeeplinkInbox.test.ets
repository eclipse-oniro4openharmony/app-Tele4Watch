import { Want } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import {
  CALL_ANSWER_DEEPLINK_KIND,
  CALL_ANSWER_ON_PHONE_DEEPLINK_KIND,
  CALL_REJECT_DEEPLINK_KIND,
  QUICK_REPLY_DEEPLINK_KIND,
  createChatDeeplinkRouteParams,
  createQuickReplyDeeplinkRouteParams,
  deeplinkInbox,
  parseCallActionDeeplinkFromWant,
  parseChatDeeplinkFromWant,
  parseQuickReplyDeeplinkFromWant
} from '../main/ets/app/DeeplinkInbox';

export default function deeplinkInboxTest() {
  describe('DeeplinkInboxTest', () => {
    it('shouldParseChatDeeplinkFromWantParameters', 0, () => {
      const want: Want = new Want();
      want.parameters = {
        deeplink: 'chat',
        chatId: '-1003559072152',
        messageId: '32345678'
      };

      const deeplink = parseChatDeeplinkFromWant(want);

      if (deeplink) {
        expect(deeplink.kind).assertEqual('chat');
        expect(deeplink.chatId).assertEqual('-1003559072152');
        expect(deeplink.messageId).assertEqual('32345678');
        const routeParams = createChatDeeplinkRouteParams(deeplink);
        expect(routeParams.chatId).assertEqual('-1003559072152');
        expect(routeParams.initialMessageId).assertEqual('32345678');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldRejectNonChatWantParameters', 0, () => {
      const want: Want = new Want();
      want.parameters = {
        deeplink: 'profile',
        chatId: '-1003559072152'
      };

      const deeplink = parseChatDeeplinkFromWant(want);

      expect(deeplink === undefined).assertTrue();
    });

    it('shouldParseQuickReplyDeeplinkFromWantParameters', 0, () => {
      const want: Want = new Want();
      want.parameters = {
        deeplink: QUICK_REPLY_DEEPLINK_KIND,
        chatId: '-1003559072152',
        notificationId: 7001,
        source: 'notification'
      };

      const deeplink = parseQuickReplyDeeplinkFromWant(want);

      if (deeplink) {
        expect(deeplink.kind).assertEqual(QUICK_REPLY_DEEPLINK_KIND);
        expect(deeplink.chatId).assertEqual('-1003559072152');
        expect(deeplink.notificationId).assertEqual(7001);
        expect(deeplink.source).assertEqual('notification');
        const routeParams = createQuickReplyDeeplinkRouteParams(deeplink);
        expect(routeParams.chatId).assertEqual('-1003559072152');
        expect(routeParams.notificationId).assertEqual(7001);
        expect(routeParams.source).assertEqual('notification');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldDefaultQuickReplySourceAndParseNumericNotificationIdText', 0, () => {
      const want: Want = new Want();
      want.parameters = {
        deeplink: QUICK_REPLY_DEEPLINK_KIND,
        chatId: '99887766',
        notificationId: '7002',
        source: 'unsupported'
      };

      const deeplink = parseQuickReplyDeeplinkFromWant(want);

      if (deeplink) {
        expect(deeplink.notificationId).assertEqual(7002);
        expect(deeplink.source).assertEqual('notification');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseCallActionDeeplinkFromWantParameters', 0, () => {
      const rejectWant: Want = new Want();
      rejectWant.parameters = {
        deeplink: CALL_REJECT_DEEPLINK_KIND,
        callId: 42
      };
      const phoneWant: Want = new Want();
      phoneWant.parameters = {
        deeplink: CALL_ANSWER_ON_PHONE_DEEPLINK_KIND,
        callId: '43'
      };
      const answerWant: Want = new Want();
      answerWant.parameters = {
        deeplink: CALL_ANSWER_DEEPLINK_KIND,
        callId: '44'
      };

      const rejectDeeplink = parseCallActionDeeplinkFromWant(rejectWant);
      const phoneDeeplink = parseCallActionDeeplinkFromWant(phoneWant);
      const answerDeeplink = parseCallActionDeeplinkFromWant(answerWant);

      if (rejectDeeplink && phoneDeeplink && answerDeeplink) {
        expect(rejectDeeplink.kind).assertEqual(CALL_REJECT_DEEPLINK_KIND);
        expect(rejectDeeplink.callId).assertEqual(42);
        expect(phoneDeeplink.kind).assertEqual(CALL_ANSWER_ON_PHONE_DEEPLINK_KIND);
        expect(phoneDeeplink.callId).assertEqual(43);
        expect(answerDeeplink.kind).assertEqual(CALL_ANSWER_DEEPLINK_KIND);
        expect(answerDeeplink.callId).assertEqual(44);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldRejectInvalidCallActionDeeplink', 0, () => {
      const want: Want = new Want();
      want.parameters = {
        deeplink: CALL_REJECT_DEEPLINK_KIND,
        callId: 0
      };

      const deeplink = parseCallActionDeeplinkFromWant(want);

      expect(deeplink === undefined).assertTrue();
    });

    it('shouldStoreCloneAndConsumeOnce', 0, () => {
      deeplinkInbox.put({
        kind: 'chat',
        chatId: '12345',
        messageId: '67890'
      });

      const firstPeek = deeplinkInbox.peek();
      const consumed = deeplinkInbox.consume();
      const secondPeek = deeplinkInbox.peek();

      if (firstPeek && consumed && consumed.kind === 'chat') {
        expect(firstPeek.chatId).assertEqual('12345');
        expect(consumed.chatId).assertEqual('12345');
        expect(consumed.messageId).assertEqual('67890');
        expect(secondPeek === undefined).assertTrue();
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldStoreAndConsumeQuickReplyDeeplinkOnce', 0, () => {
      deeplinkInbox.put({
        kind: QUICK_REPLY_DEEPLINK_KIND,
        chatId: '12345',
        notificationId: 5001,
        source: 'notification'
      });

      const consumed = deeplinkInbox.consume();
      const secondPeek = deeplinkInbox.peek();

      if (consumed && consumed.kind === QUICK_REPLY_DEEPLINK_KIND) {
        expect(consumed.chatId).assertEqual('12345');
        expect(consumed.notificationId).assertEqual(5001);
        expect(consumed.source).assertEqual('notification');
        expect(secondPeek === undefined).assertTrue();
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseNumericMessageIdFromWantParameters', 0, () => {
      const want: Want = new Want();
      want.parameters = {
        deeplink: 'chat',
        chatId: '-1003559072152',
        messageId: 32345678
      };

      const deeplink = parseChatDeeplinkFromWant(want);

      if (deeplink) {
        expect(deeplink.kind).assertEqual('chat');
        expect(deeplink.chatId).assertEqual('-1003559072152');
        expect(deeplink.messageId).assertEqual('32345678');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldRejectWantWithEmptyChatId', 0, () => {
      const want: Want = new Want();
      want.parameters = {
        deeplink: 'chat',
        chatId: '',
        messageId: '32345678'
      };

      const deeplink = parseChatDeeplinkFromWant(want);

      expect(deeplink === undefined).assertTrue();
    });

    it('shouldRejectWantWithoutParameters', 0, () => {
      const want: Want = new Want();

      const deeplink = parseChatDeeplinkFromWant(want);

      expect(deeplink === undefined).assertTrue();
    });

    it('shouldParseChatIdEvenWhenAlienKeyContainsRegexMetacharacters', 0, () => {
      const want: Want = new Want();
      want.parameters = {
        '.*deeplink.*': 'fake',
        deeplink: 'chat',
        chatId: '99887766',
        messageId: '11223344'
      };

      const deeplink = parseChatDeeplinkFromWant(want);

      if (deeplink) {
        expect(deeplink.kind).assertEqual('chat');
        expect(deeplink.chatId).assertEqual('99887766');
        expect(deeplink.messageId).assertEqual('11223344');
      } else {
        expect(false).assertTrue();
      }
    });
  });
}
