import { describe, expect, it } from '@ohos/hypium';
import {
  QuickReplyNotificationGateway,
  QuickReplyNotificationServiceCanceller,
  QuickReplyTdMessageSender,
  QuickReplyTdSendGateway
} from '../main/ets/services/quickreply/QuickReplyTdAdapters';

class FakeQuickReplyTdSendGateway implements QuickReplyTdSendGateway {
  readonly calls: string[] = [];
  started: boolean = true;
  listener?: (ok: boolean, errorMessage: string) => void;

  sendChatTextMessageWithConfirm(
    chatId: string,
    text: string,
    listener: (ok: boolean, errorMessage: string) => void
  ): boolean {
    this.calls.push(`send:${chatId}:${text}`);
    this.listener = listener;
    return this.started;
  }

  complete(ok: boolean, errorMessage: string): void {
    if (this.listener) {
      this.listener(ok, errorMessage);
    }
  }
}

class FakeQuickReplyNotificationGateway implements QuickReplyNotificationGateway {
  readonly calls: string[] = [];

  async handleQuickReplySent(chatId: string, notificationId?: number): Promise<void> {
    this.calls.push(`cancel:${chatId}:${notificationId !== undefined ? notificationId : 0}`);
  }
}

export default function quickReplyTdAdaptersTest() {
  describe('QuickReplyTdAdaptersTest', () => {
    it('shouldResolveOkAfterTdSendConfirmation', 0, async (): Promise<void> => {
      const gateway = new FakeQuickReplyTdSendGateway();
      const sender = new QuickReplyTdMessageSender(gateway);

      const resultPromise = sender.sendTextMessage('8529861543', 'OK');
      gateway.complete(true, '');
      const result = await resultPromise;

      expect(result.kind).assertEqual('ok');
      expect(gateway.calls.join(',')).assertEqual('send:8529861543:OK');
    });

    it('shouldResolveErrorAfterTdSendRejection', 0, async (): Promise<void> => {
      const gateway = new FakeQuickReplyTdSendGateway();
      const sender = new QuickReplyTdMessageSender(gateway);

      const resultPromise = sender.sendTextMessage('8529861543', 'OK');
      gateway.complete(false, '420 SLOWMODE_WAIT_12');
      const result = await resultPromise;

      expect(result.kind).assertEqual('error');
      if (result.kind === 'error') {
        expect(result.errorMessage).assertEqual('420 SLOWMODE_WAIT_12');
      }
    });

    it('shouldReturnUnavailableWhenTdRequestCannotStart', 0, async (): Promise<void> => {
      const gateway = new FakeQuickReplyTdSendGateway();
      gateway.started = false;
      const sender = new QuickReplyTdMessageSender(gateway);

      const result = await sender.sendTextMessage('8529861543', 'OK');

      expect(result.kind).assertEqual('error');
      if (result.kind === 'error') {
        expect(result.errorMessage).assertEqual('send unavailable');
      }
    });

    it('shouldReturnTimeoutErrorFromTdGateway', 0, async (): Promise<void> => {
      const gateway = new FakeQuickReplyTdSendGateway();
      const sender = new QuickReplyTdMessageSender(gateway);

      const resultPromise = sender.sendTextMessage('8529861543', 'OK');
      gateway.complete(false, 'send confirmation timeout');
      const result = await resultPromise;

      expect(result.kind).assertEqual('error');
      if (result.kind === 'error') {
        expect(result.errorMessage).assertEqual('send confirmation timeout');
      }
    });

    it('shouldDelegateQuickReplyNotificationCancelToNotificationGateway', 0, async (): Promise<void> => {
      const gateway = new FakeQuickReplyNotificationGateway();
      const canceller = new QuickReplyNotificationServiceCanceller(gateway);

      await canceller.cancelSentReplyNotification('8529861543', 5001);

      expect(gateway.calls.join(',')).assertEqual('cancel:8529861543:5001');
    });
  });
}
