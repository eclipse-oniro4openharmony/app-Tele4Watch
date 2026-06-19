import resourceManager from '@ohos.resourceManager';
import {
  DEFAULT_QUICK_REPLY_TEMPLATE_IDS,
  QuickReplyTemplate
} from '../../models/quickreply/QuickReplyTemplate';

const QUICK_REPLY_TEMPLATE_RESOURCE_PREFIX: string = 'quick_reply_template_';
export const QUICK_REPLY_PREFERENCES_KEY: string = 'tele4watch.quickReplies.v1';

export type QuickReplyDispatchErrorReason =
  'unknown_template' |
  'invalid_chat' |
  'send_unavailable' |
  'slowmode' |
  'paid_required' |
  'network' |
  'other';

export interface QuickReplyTextProvider {
  getText(resourceName: string): string;
}

export interface QuickReplyTemplateOverrideStore {
  getTemplates(): Promise<QuickReplyTemplate[]>;
}

export interface QuickReplyMessageSender {
  sendTextMessage(chatId: string, text: string): Promise<QuickReplySendResult>;
}

export interface QuickReplyNotificationCanceller {
  cancelSentReplyNotification(chatId: string, notificationId?: number): Promise<void>;
}

export interface QuickReplySendOkResult {
  kind: 'ok';
}

export interface QuickReplySendErrorResult {
  kind: 'error';
  errorMessage: string;
}

export type QuickReplySendResult = QuickReplySendOkResult | QuickReplySendErrorResult;

export interface QuickReplyDispatchOkResult {
  kind: 'ok';
  notificationCancelled: boolean;
}

export interface QuickReplyDispatchErrorResult {
  kind: 'error';
  reason: QuickReplyDispatchErrorReason;
  errorMessage: string;
}

export type QuickReplyDispatchResult = QuickReplyDispatchOkResult | QuickReplyDispatchErrorResult;

class EmptyQuickReplyTemplateOverrideStore implements QuickReplyTemplateOverrideStore {
  async getTemplates(): Promise<QuickReplyTemplate[]> {
    return [];
  }
}

/**
 * Resource-backed text provider used by production quick-reply surfaces.
 */
export class QuickReplyResourceTextProvider implements QuickReplyTextProvider {
  private readonly resourceManagerValue: resourceManager.ResourceManager;

  constructor(resourceManagerValue: resourceManager.ResourceManager) {
    this.resourceManagerValue = resourceManagerValue;
  }

  getText(resourceName: string): string {
    try {
      return this.resourceManagerValue.getStringByNameSync(resourceName);
    } catch (_error) {
      return '';
    }
  }
}

/**
 * Builds the resource key for one built-in quick-reply template id.
 *
 * @param templateId Built-in quick-reply template id.
 * @returns Resource key without the `app.string.` prefix.
 */
export function buildQuickReplyTemplateResourceName(templateId: string): string {
  return QUICK_REPLY_TEMPLATE_RESOURCE_PREFIX + templateId;
}

/**
 * Owns quick-reply template loading and dispatch decisions.
 */
export class QuickReplyService {
  private readonly textProvider: QuickReplyTextProvider;
  private readonly messageSender: QuickReplyMessageSender;
  private readonly notificationCanceller: QuickReplyNotificationCanceller;
  private readonly overrideStore: QuickReplyTemplateOverrideStore;

  constructor(
    textProvider: QuickReplyTextProvider,
    messageSender: QuickReplyMessageSender,
    notificationCanceller: QuickReplyNotificationCanceller,
    overrideStore?: QuickReplyTemplateOverrideStore
  ) {
    this.textProvider = textProvider;
    this.messageSender = messageSender;
    this.notificationCanceller = notificationCanceller;
    this.overrideStore = overrideStore ? overrideStore : new EmptyQuickReplyTemplateOverrideStore();
  }

  /**
   * Loads user override templates when present, otherwise built-in localized defaults.
   *
   * @returns Template list ready for picker rendering.
   */
  async getTemplates(): Promise<QuickReplyTemplate[]> {
    const overrideTemplates = await this.loadOverrideTemplates();
    if (overrideTemplates.length > 0) {
      return overrideTemplates;
    }
    return this.loadDefaultTemplates();
  }

  /**
   * Sends selected template and cancels the originating notification after confirmed send.
   *
   * @param chatId Target TDLib chat id.
   * @param templateId Selected quick-reply template id.
   * @param notificationId Optional NotificationKit id tied to the source notification.
   * @returns Dispatch result for UI feedback.
   */
  async dispatchTemplate(
    chatId: string,
    templateId: string,
    notificationId?: number
  ): Promise<QuickReplyDispatchResult> {
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      return this.createErrorResult('invalid_chat', '');
    }

    const template = await this.findTemplate(templateId);
    if (!template) {
      return this.createErrorResult('unknown_template', '');
    }

    let sendResult: QuickReplySendResult;
    try {
      sendResult = await this.messageSender.sendTextMessage(safeChatId, template.text);
    } catch (error) {
      return this.createErrorResult(this.classifySendError(String(error)), String(error));
    }

    if (sendResult.kind === 'error') {
      return this.createErrorResult(this.classifySendError(sendResult.errorMessage), sendResult.errorMessage);
    }

    let notificationCancelled = true;
    try {
      await this.notificationCanceller.cancelSentReplyNotification(safeChatId, notificationId);
    } catch (_error) {
      notificationCancelled = false;
    }

    return {
      kind: 'ok',
      notificationCancelled: notificationCancelled
    };
  }

  private async findTemplate(templateId: string): Promise<QuickReplyTemplate | undefined> {
    const safeTemplateId = templateId.trim();
    if (safeTemplateId.length === 0) {
      return undefined;
    }

    const templates = await this.getTemplates();
    for (const template of templates) {
      if (template.id === safeTemplateId) {
        return template;
      }
    }
    return undefined;
  }

  private async loadOverrideTemplates(): Promise<QuickReplyTemplate[]> {
    try {
      return this.normalizeTemplates(await this.overrideStore.getTemplates());
    } catch (_error) {
      return [];
    }
  }

  private loadDefaultTemplates(): QuickReplyTemplate[] {
    const templates: QuickReplyTemplate[] = [];
    for (const templateId of DEFAULT_QUICK_REPLY_TEMPLATE_IDS) {
      const resourceName = buildQuickReplyTemplateResourceName(templateId);
      try {
        const text = this.textProvider.getText(resourceName);
        const template = this.normalizeTemplate({
          id: templateId,
          text: text,
          userDefined: false
        });
        if (template) {
          templates.push(template);
        }
      } catch (_error) {
        continue;
      }
    }
    return templates;
  }

  private normalizeTemplates(sourceTemplates: QuickReplyTemplate[]): QuickReplyTemplate[] {
    const templates: QuickReplyTemplate[] = [];
    for (const sourceTemplate of sourceTemplates) {
      const template = this.normalizeTemplate(sourceTemplate);
      if (template) {
        templates.push(template);
      }
    }
    return templates;
  }

  private normalizeTemplate(template: QuickReplyTemplate): QuickReplyTemplate | undefined {
    const safeId = template.id.trim();
    const safeText = template.text.trim();
    if (safeId.length === 0 || safeText.length === 0) {
      return undefined;
    }
    return {
      id: safeId,
      text: safeText,
      userDefined: template.userDefined
    };
  }

  private classifySendError(message: string): QuickReplyDispatchErrorReason {
    const normalizedMessage = message.toLowerCase();
    if (normalizedMessage.length === 0) {
      return 'send_unavailable';
    }
    if (normalizedMessage.indexOf('slowmode') >= 0 || normalizedMessage.indexOf('slow mode') >= 0) {
      return 'slowmode';
    }
    if (normalizedMessage.indexOf('paid') >= 0 || normalizedMessage.indexOf('stars') >= 0) {
      return 'paid_required';
    }
    if (
      normalizedMessage.indexOf('network') >= 0 ||
      normalizedMessage.indexOf('connection') >= 0 ||
      normalizedMessage.indexOf('timeout') >= 0
    ) {
      return 'network';
    }
    return 'other';
  }

  private createErrorResult(
    reason: QuickReplyDispatchErrorReason,
    errorMessage: string
  ): QuickReplyDispatchErrorResult {
    return {
      kind: 'error',
      reason: reason,
      errorMessage: errorMessage
    };
  }
}
