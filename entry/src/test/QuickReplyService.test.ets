import { describe, expect, it } from '@ohos/hypium';
import { QuickReplyTemplate } from '../main/ets/models/quickreply/QuickReplyTemplate';
import {
  QuickReplyMessageSender,
  QuickReplyNotificationCanceller,
  QuickReplySendResult,
  QuickReplyService,
  QuickReplyTemplateOverrideStore,
  QuickReplyTextProvider
} from '../main/ets/services/quickreply/QuickReplyService';

class FakeQuickReplyTextProvider implements QuickReplyTextProvider {
  readonly requestedNames: string[] = [];
  missingResourceName: string = '';

  getText(resourceName: string): string {
    this.requestedNames.push(resourceName);
    if (resourceName === this.missingResourceName) {
      throw new Error('missing resource');
    }
    if (resourceName === 'quick_reply_template_ok') {
      return 'OK';
    }
    if (resourceName === 'quick_reply_template_thumbs_up') {
      return '👍';
    }
    if (resourceName === 'quick_reply_template_smile') {
      return '🙂';
    }
    if (resourceName === 'quick_reply_template_call_back') {
      return 'Call back';
    }
    if (resourceName === 'quick_reply_template_on_my_way') {
      return 'On my way';
    }
    if (resourceName === 'quick_reply_template_cant_talk') {
      return "Can't talk";
    }
    return '';
  }
}

class FakeQuickReplyTemplateOverrideStore implements QuickReplyTemplateOverrideStore {
  templates: QuickReplyTemplate[] = [];
  shouldThrow: boolean = false;

  async getTemplates(): Promise<QuickReplyTemplate[]> {
    if (this.shouldThrow) {
      throw new Error('override unavailable');
    }
    return this.templates;
  }
}

class FakeQuickReplyMessageSender implements QuickReplyMessageSender {
  readonly calls: string[] = [];
  result: QuickReplySendResult = { kind: 'ok' };
  shouldThrow: boolean = false;

  async sendTextMessage(chatId: string, text: string): Promise<QuickReplySendResult> {
    this.calls.push(`send:${chatId}:${text}`);
    if (this.shouldThrow) {
      throw new Error('network timeout');
    }
    return this.result;
  }
}

class FakeQuickReplyNotificationCanceller implements QuickReplyNotificationCanceller {
  readonly calls: string[] = [];
  shouldThrow: boolean = false;

  async cancelSentReplyNotification(chatId: string, notificationId?: number): Promise<void> {
    this.calls.push(`cancel:${chatId}:${notificationId !== undefined ? notificationId : 0}`);
    if (this.shouldThrow) {
      throw new Error('cancel failed');
    }
  }
}

function createService(
  textProvider: FakeQuickReplyTextProvider,
  sender: FakeQuickReplyMessageSender,
  canceller: FakeQuickReplyNotificationCanceller,
  overrideStore: FakeQuickReplyTemplateOverrideStore
): QuickReplyService {
  return new QuickReplyService(textProvider, sender, canceller, overrideStore);
}

export default function quickReplyServiceTest() {
  describe('QuickReplyServiceTest', () => {
    it('shouldLoadDefaultTemplatesFromResourceProvider', 0, async (): Promise<void> => {
      const textProvider = new FakeQuickReplyTextProvider();
      const service = createService(
        textProvider,
        new FakeQuickReplyMessageSender(),
        new FakeQuickReplyNotificationCanceller(),
        new FakeQuickReplyTemplateOverrideStore()
      );

      const templates = await service.getTemplates();

      expect(templates.length).assertEqual(6);
      expect(templates[0].id).assertEqual('ok');
      expect(templates[0].text).assertEqual('OK');
      expect(templates[0].userDefined).assertFalse();
      expect(templates[1].text).assertEqual('👍');
      expect(textProvider.requestedNames[0]).assertEqual('quick_reply_template_ok');
    });

    it('shouldUseOverrideTemplatesWhenAvailable', 0, async (): Promise<void> => {
      const overrideStore = new FakeQuickReplyTemplateOverrideStore();
      overrideStore.templates = [
        { id: ' custom ', text: ' Later ', userDefined: true },
        { id: '', text: 'ignored', userDefined: true }
      ];
      const service = createService(
        new FakeQuickReplyTextProvider(),
        new FakeQuickReplyMessageSender(),
        new FakeQuickReplyNotificationCanceller(),
        overrideStore
      );

      const templates = await service.getTemplates();

      expect(templates.length).assertEqual(1);
      expect(templates[0].id).assertEqual('custom');
      expect(templates[0].text).assertEqual('Later');
      expect(templates[0].userDefined).assertTrue();
    });

    it('shouldFallbackToDefaultsWhenOverrideStoreFails', 0, async (): Promise<void> => {
      const overrideStore = new FakeQuickReplyTemplateOverrideStore();
      overrideStore.shouldThrow = true;
      const service = createService(
        new FakeQuickReplyTextProvider(),
        new FakeQuickReplyMessageSender(),
        new FakeQuickReplyNotificationCanceller(),
        overrideStore
      );

      const templates = await service.getTemplates();

      expect(templates.length).assertEqual(6);
      expect(templates[0].id).assertEqual('ok');
    });

    it('shouldSkipOneMissingDefaultResourceWithoutFailingAllTemplates', 0, async (): Promise<void> => {
      const textProvider = new FakeQuickReplyTextProvider();
      textProvider.missingResourceName = 'quick_reply_template_smile';
      const service = createService(
        textProvider,
        new FakeQuickReplyMessageSender(),
        new FakeQuickReplyNotificationCanceller(),
        new FakeQuickReplyTemplateOverrideStore()
      );

      const templates = await service.getTemplates();

      expect(templates.length).assertEqual(5);
      expect(templates[2].id).assertEqual('call_back');
    });

    it('shouldSendSelectedTemplateAndCancelNotificationAfterSuccess', 0, async (): Promise<void> => {
      const sender = new FakeQuickReplyMessageSender();
      const canceller = new FakeQuickReplyNotificationCanceller();
      const service = createService(
        new FakeQuickReplyTextProvider(),
        sender,
        canceller,
        new FakeQuickReplyTemplateOverrideStore()
      );

      const result = await service.dispatchTemplate(' 8529861543 ', 'thumbs_up', 5001);

      expect(result.kind).assertEqual('ok');
      if (result.kind === 'ok') {
        expect(result.notificationCancelled).assertTrue();
      }
      expect(sender.calls.length).assertEqual(1);
      expect(sender.calls[0]).assertEqual('send:8529861543:👍');
      expect(canceller.calls.length).assertEqual(1);
      expect(canceller.calls[0]).assertEqual('cancel:8529861543:5001');
    });

    it('shouldNotCancelNotificationWhenSendFails', 0, async (): Promise<void> => {
      const sender = new FakeQuickReplyMessageSender();
      sender.result = {
        kind: 'error',
        errorMessage: '420 SLOWMODE_WAIT_12'
      };
      const canceller = new FakeQuickReplyNotificationCanceller();
      const service = createService(
        new FakeQuickReplyTextProvider(),
        sender,
        canceller,
        new FakeQuickReplyTemplateOverrideStore()
      );

      const result = await service.dispatchTemplate('8529861543', 'ok', 5001);

      expect(result.kind).assertEqual('error');
      if (result.kind === 'error') {
        expect(result.reason).assertEqual('slowmode');
      }
      expect(canceller.calls.length).assertEqual(0);
    });

    it('shouldClassifyNetworkSendFailureWithoutCancellingNotification', 0, async (): Promise<void> => {
      const sender = new FakeQuickReplyMessageSender();
      sender.result = {
        kind: 'error',
        errorMessage: 'network connection timeout'
      };
      const canceller = new FakeQuickReplyNotificationCanceller();
      const service = createService(
        new FakeQuickReplyTextProvider(),
        sender,
        canceller,
        new FakeQuickReplyTemplateOverrideStore()
      );

      const result = await service.dispatchTemplate('8529861543', 'ok', 5001);

      expect(result.kind).assertEqual('error');
      if (result.kind === 'error') {
        expect(result.reason).assertEqual('network');
      }
      expect(canceller.calls.length).assertEqual(0);
    });

    it('shouldClassifyPaidSendFailureWithoutCancellingNotification', 0, async (): Promise<void> => {
      const sender = new FakeQuickReplyMessageSender();
      sender.result = {
        kind: 'error',
        errorMessage: 'paid messages require stars'
      };
      const canceller = new FakeQuickReplyNotificationCanceller();
      const service = createService(
        new FakeQuickReplyTextProvider(),
        sender,
        canceller,
        new FakeQuickReplyTemplateOverrideStore()
      );

      const result = await service.dispatchTemplate('8529861543', 'ok', 5001);

      expect(result.kind).assertEqual('error');
      if (result.kind === 'error') {
        expect(result.reason).assertEqual('paid_required');
      }
      expect(canceller.calls.length).assertEqual(0);
    });

    it('shouldClassifyBlankSendErrorAsUnavailableWithoutCancellingNotification', 0, async (): Promise<void> => {
      const sender = new FakeQuickReplyMessageSender();
      sender.result = {
        kind: 'error',
        errorMessage: ''
      };
      const canceller = new FakeQuickReplyNotificationCanceller();
      const service = createService(
        new FakeQuickReplyTextProvider(),
        sender,
        canceller,
        new FakeQuickReplyTemplateOverrideStore()
      );

      const result = await service.dispatchTemplate('8529861543', 'ok', 5001);

      expect(result.kind).assertEqual('error');
      if (result.kind === 'error') {
        expect(result.reason).assertEqual('send_unavailable');
      }
      expect(canceller.calls.length).assertEqual(0);
    });

    it('shouldClassifyOtherSendFailureWithoutCancellingNotification', 0, async (): Promise<void> => {
      const sender = new FakeQuickReplyMessageSender();
      sender.result = {
        kind: 'error',
        errorMessage: 'unexpected tdlib rejection'
      };
      const canceller = new FakeQuickReplyNotificationCanceller();
      const service = createService(
        new FakeQuickReplyTextProvider(),
        sender,
        canceller,
        new FakeQuickReplyTemplateOverrideStore()
      );

      const result = await service.dispatchTemplate('8529861543', 'ok', 5001);

      expect(result.kind).assertEqual('error');
      if (result.kind === 'error') {
        expect(result.reason).assertEqual('other');
      }
      expect(canceller.calls.length).assertEqual(0);
    });

    it('shouldClassifyThrownSenderErrorWithoutCancellingNotification', 0, async (): Promise<void> => {
      const sender = new FakeQuickReplyMessageSender();
      sender.shouldThrow = true;
      const canceller = new FakeQuickReplyNotificationCanceller();
      const service = createService(
        new FakeQuickReplyTextProvider(),
        sender,
        canceller,
        new FakeQuickReplyTemplateOverrideStore()
      );

      const result = await service.dispatchTemplate('8529861543', 'ok', 5001);

      expect(result.kind).assertEqual('error');
      if (result.kind === 'error') {
        expect(result.reason).assertEqual('network');
      }
      expect(canceller.calls.length).assertEqual(0);
    });

    it('shouldReturnUnknownTemplateWithoutSending', 0, async (): Promise<void> => {
      const sender = new FakeQuickReplyMessageSender();
      const service = createService(
        new FakeQuickReplyTextProvider(),
        sender,
        new FakeQuickReplyNotificationCanceller(),
        new FakeQuickReplyTemplateOverrideStore()
      );

      const result = await service.dispatchTemplate('8529861543', 'missing', 5001);

      expect(result.kind).assertEqual('error');
      if (result.kind === 'error') {
        expect(result.reason).assertEqual('unknown_template');
      }
      expect(sender.calls.length).assertEqual(0);
    });

    it('shouldReturnInvalidChatWithoutLoadingTemplates', 0, async (): Promise<void> => {
      const textProvider = new FakeQuickReplyTextProvider();
      const sender = new FakeQuickReplyMessageSender();
      const service = createService(
        textProvider,
        sender,
        new FakeQuickReplyNotificationCanceller(),
        new FakeQuickReplyTemplateOverrideStore()
      );

      const result = await service.dispatchTemplate('   ', 'ok', 5001);

      expect(result.kind).assertEqual('error');
      if (result.kind === 'error') {
        expect(result.reason).assertEqual('invalid_chat');
      }
      expect(textProvider.requestedNames.length).assertEqual(0);
      expect(sender.calls.length).assertEqual(0);
    });

    it('shouldKeepOkResultWhenNotificationCancelFailsAfterSend', 0, async (): Promise<void> => {
      const canceller = new FakeQuickReplyNotificationCanceller();
      canceller.shouldThrow = true;
      const service = createService(
        new FakeQuickReplyTextProvider(),
        new FakeQuickReplyMessageSender(),
        canceller,
        new FakeQuickReplyTemplateOverrideStore()
      );

      const result = await service.dispatchTemplate('8529861543', 'ok', 5001);

      expect(result.kind).assertEqual('ok');
      if (result.kind === 'ok') {
        expect(result.notificationCancelled).assertFalse();
      }
    });
  });
}
