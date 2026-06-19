import resourceManager from '@ohos.resourceManager';
import {
  QuickReplyPickerPageMode,
  QuickReplyPickerPageState
} from '../models/quickreply/QuickReplyPickerPageState';
import {
  QuickReplyPickerSource,
  QuickReplyTemplate
} from '../models/quickreply/QuickReplyTemplate';
import { UiTextValue, createEmptyUiTextValue, createResourceUiText } from '../models/ui/UiTextValue';
import {
  QuickReplyDispatchErrorReason,
  QuickReplyDispatchResult,
  QuickReplyResourceTextProvider,
  QuickReplyService
} from '../services/quickreply/QuickReplyService';
import {
  QuickReplyNotificationServiceCanceller,
  QuickReplyTdMessageSender
} from '../services/quickreply/QuickReplyTdAdapters';

export interface QuickReplyPickerServiceGateway {
  'getTemplates': () => Promise<QuickReplyTemplate[]>;
  'dispatchTemplate': (
    chatId: string,
    templateId: string,
    notificationId?: number
  ) => Promise<QuickReplyDispatchResult>;
}

export interface QuickReplyTemplateLoadResult {
  kind: 'ok' | 'error';
  templates: QuickReplyTemplate[];
  errorMessage: string;
}

export interface QuickReplyTemplateDispatchPlan {
  nextPageState: QuickReplyPickerPageState;
  shouldDispatch: boolean;
  chatId: string;
  templateId: string;
  notificationId?: number;
}

class DefaultQuickReplyPickerServiceGateway implements QuickReplyPickerServiceGateway {
  private readonly service: QuickReplyService;

  constructor(resourceManagerValue: resourceManager.ResourceManager) {
    this.service = new QuickReplyService(
      new QuickReplyResourceTextProvider(resourceManagerValue),
      new QuickReplyTdMessageSender(),
      new QuickReplyNotificationServiceCanceller()
    );
  }

  async getTemplates(): Promise<QuickReplyTemplate[]> {
    return this.service.getTemplates();
  }

  async dispatchTemplate(
    chatId: string,
    templateId: string,
    notificationId?: number
  ): Promise<QuickReplyDispatchResult> {
    return this.service.dispatchTemplate(chatId, templateId, notificationId);
  }
}

/**
 * Builds routed quick-reply picker states and delegates template dispatch.
 */
export class QuickReplyPickerViewModel {
  private readonly serviceGateway: QuickReplyPickerServiceGateway;

  constructor(serviceGateway: QuickReplyPickerServiceGateway) {
    this.serviceGateway = serviceGateway;
  }

  /**
   * Creates the production picker ViewModel with resource-backed quick-reply services.
   *
   * @param resourceManagerValue Host resource manager used to resolve default templates.
   * @returns Production quick-reply picker ViewModel.
   */
  static createDefault(resourceManagerValue: resourceManager.ResourceManager): QuickReplyPickerViewModel {
    return new QuickReplyPickerViewModel(new DefaultQuickReplyPickerServiceGateway(resourceManagerValue));
  }

  /**
   * Creates the placeholder state shown before route params and templates are loaded.
   *
   * @returns The initial picker-page state.
   */
  createInitialState(): QuickReplyPickerPageState {
    return {
      chatId: '',
      notificationId: undefined,
      source: 'notification',
      templates: [],
      pageMode: QuickReplyPickerPageMode.Idle,
      isLoading: false,
      isSending: false,
      selectedTemplateId: '',
      statusText: createEmptyUiTextValue(),
      errorText: createEmptyUiTextValue(),
      canPickTemplate: false,
      shouldClose: false,
      notificationCancelled: false
    };
  }

  /**
   * Applies routed quick-reply picker params.
   *
   * @param currentState Current picker-page state.
   * @param chatId Target chat id.
   * @param source Source surface that opened the picker.
   * @param notificationId Optional NotificationKit id tied to the source notification.
   * @returns Updated picker-page state.
   */
  applyRoute(
    currentState: QuickReplyPickerPageState,
    chatId: string,
    source: string,
    notificationId?: number
  ): QuickReplyPickerPageState {
    return {
      chatId: chatId.trim(),
      notificationId: this.normalizeNotificationId(notificationId),
      source: this.normalizeSource(source),
      templates: this.cloneTemplates(currentState.templates),
      pageMode: currentState.pageMode,
      isLoading: currentState.isLoading,
      isSending: currentState.isSending,
      selectedTemplateId: currentState.selectedTemplateId,
      statusText: currentState.statusText,
      errorText: currentState.errorText,
      canPickTemplate: this.canPickTemplate(currentState.isSending, chatId, currentState.templates),
      shouldClose: currentState.shouldClose,
      notificationCancelled: currentState.notificationCancelled
    };
  }

  /**
   * Creates loading state while templates are being resolved.
   *
   * @param currentState Current picker-page state.
   * @returns Updated picker-page state.
   */
  createLoadingState(currentState: QuickReplyPickerPageState): QuickReplyPickerPageState {
    return this.copyState(currentState, {
      pageMode: currentState.templates.length > 0 ? QuickReplyPickerPageMode.Ready : QuickReplyPickerPageMode.Loading,
      isLoading: true,
      errorText: createEmptyUiTextValue(),
      shouldClose: false
    });
  }

  /**
   * Loads quick-reply templates from the injected gateway.
   *
   * @returns Load result for state mapping.
   */
  async loadTemplates(): Promise<QuickReplyTemplateLoadResult> {
    try {
      return {
        kind: 'ok',
        templates: await this.serviceGateway.getTemplates(),
        errorMessage: ''
      };
    } catch (error) {
      return {
        kind: 'error',
        templates: [],
        errorMessage: String(error)
      };
    }
  }

  /**
   * Applies template load result to picker state.
   *
   * @param currentState Current picker-page state.
   * @param result Template load result.
   * @returns Updated picker-page state.
   */
  applyTemplateLoadResult(
    currentState: QuickReplyPickerPageState,
    result: QuickReplyTemplateLoadResult
  ): QuickReplyPickerPageState {
    if (result.kind === 'error') {
      return this.copyState(currentState, {
        templates: [],
        pageMode: QuickReplyPickerPageMode.Error,
        isLoading: false,
        errorText: createResourceUiText('quick_reply_failed'),
        canPickTemplate: false
      });
    }

    const templates = this.cloneTemplates(result.templates);
    return this.copyState(currentState, {
      templates: templates,
      pageMode: templates.length > 0 ? QuickReplyPickerPageMode.Ready : QuickReplyPickerPageMode.Empty,
      isLoading: false,
      errorText: createEmptyUiTextValue(),
      canPickTemplate: this.canPickTemplate(currentState.isSending, currentState.chatId, templates)
    });
  }

  /**
   * Plans dispatch of one selected quick-reply template.
   *
   * @param currentState Current picker-page state.
   * @param templateId Selected template id.
   * @returns Dispatch decision and next state.
   */
  planTemplateDispatch(
    currentState: QuickReplyPickerPageState,
    templateId: string
  ): QuickReplyTemplateDispatchPlan {
    if (currentState.isSending) {
      return this.createNoopDispatchPlan(currentState, templateId);
    }

    const safeChatId = currentState.chatId.trim();
    const safeTemplateId = templateId.trim();
    if (safeChatId.length === 0 || !this.hasTemplate(currentState.templates, safeTemplateId)) {
      return {
        nextPageState: this.copyState(currentState, {
          pageMode: currentState.templates.length > 0 ? QuickReplyPickerPageMode.Ready : QuickReplyPickerPageMode.Error,
          errorText: createResourceUiText('quick_reply_failed'),
          canPickTemplate: this.canPickTemplate(false, currentState.chatId, currentState.templates)
        }),
        shouldDispatch: false,
        chatId: safeChatId,
        templateId: safeTemplateId,
        notificationId: currentState.notificationId
      };
    }

    return {
      nextPageState: this.copyState(currentState, {
        pageMode: QuickReplyPickerPageMode.Sending,
        isSending: true,
        selectedTemplateId: safeTemplateId,
        statusText: createResourceUiText('quick_reply_sending'),
        errorText: createEmptyUiTextValue(),
        canPickTemplate: false,
        shouldClose: false
      }),
      shouldDispatch: true,
      chatId: safeChatId,
      templateId: safeTemplateId,
      notificationId: currentState.notificationId
    };
  }

  /**
   * Dispatches selected template through the injected gateway.
   *
   * @param chatId Target chat id.
   * @param templateId Selected template id.
   * @param notificationId Optional NotificationKit id tied to the source notification.
   * @returns Dispatch result from quick-reply service.
   */
  async dispatchTemplate(
    chatId: string,
    templateId: string,
    notificationId?: number
  ): Promise<QuickReplyDispatchResult> {
    return this.serviceGateway.dispatchTemplate(chatId, templateId, notificationId);
  }

  /**
   * Applies quick-reply dispatch result.
   *
   * @param currentState Current picker-page state.
   * @param result Dispatch result.
   * @returns Updated picker-page state.
   */
  applyDispatchResult(
    currentState: QuickReplyPickerPageState,
    result: QuickReplyDispatchResult
  ): QuickReplyPickerPageState {
    if (result.kind === 'ok') {
      return this.copyState(currentState, {
        pageMode: QuickReplyPickerPageMode.Sent,
        isSending: false,
        selectedTemplateId: '',
        statusText: createResourceUiText('quick_reply_sent'),
        errorText: createEmptyUiTextValue(),
        canPickTemplate: false,
        shouldClose: true,
        notificationCancelled: result.notificationCancelled
      });
    }

    return this.copyState(currentState, {
      pageMode: currentState.templates.length > 0 ? QuickReplyPickerPageMode.Ready : QuickReplyPickerPageMode.Error,
      isSending: false,
      statusText: createEmptyUiTextValue(),
      errorText: this.mapDispatchErrorText(result.reason),
      canPickTemplate: this.canPickTemplate(false, currentState.chatId, currentState.templates),
      shouldClose: false,
      notificationCancelled: false
    });
  }

  private createNoopDispatchPlan(
    currentState: QuickReplyPickerPageState,
    templateId: string
  ): QuickReplyTemplateDispatchPlan {
    return {
      nextPageState: currentState,
      shouldDispatch: false,
      chatId: currentState.chatId,
      templateId: templateId,
      notificationId: currentState.notificationId
    };
  }

  private hasTemplate(templates: QuickReplyTemplate[], templateId: string): boolean {
    for (const template of templates) {
      if (template.id === templateId) {
        return true;
      }
    }
    return false;
  }

  private cloneTemplates(sourceTemplates: QuickReplyTemplate[]): QuickReplyTemplate[] {
    const templates: QuickReplyTemplate[] = [];
    for (const sourceTemplate of sourceTemplates) {
      const id = sourceTemplate.id.trim();
      const text = sourceTemplate.text.trim();
      if (id.length > 0 && text.length > 0) {
        templates.push({
          id: id,
          text: text,
          userDefined: sourceTemplate.userDefined
        });
      }
    }
    return templates;
  }

  private normalizeSource(source: string): QuickReplyPickerSource {
    return source === 'chatDetails' ? 'chatDetails' : 'notification';
  }

  private normalizeNotificationId(notificationId: number | undefined): number | undefined {
    if (notificationId === undefined || notificationId < 0) {
      return undefined;
    }
    return Math.trunc(notificationId);
  }

  private mapDispatchErrorText(reason: QuickReplyDispatchErrorReason): UiTextValue {
    if (reason === 'network') {
      return createResourceUiText('quick_reply_network_queued');
    }
    return createResourceUiText('quick_reply_failed');
  }

  private canPickTemplate(sending: boolean, chatId: string, templates: QuickReplyTemplate[]): boolean {
    if (sending) {
      return false;
    }
    return chatId.trim().length > 0 && templates.length > 0;
  }

  private copyState(
    currentState: QuickReplyPickerPageState,
    patch: QuickReplyPickerPageStatePatch
  ): QuickReplyPickerPageState {
    return {
      chatId: patch.chatId !== undefined ? patch.chatId : currentState.chatId,
      notificationId: patch.notificationId !== undefined ? patch.notificationId : currentState.notificationId,
      source: patch.source !== undefined ? patch.source : currentState.source,
      templates: patch.templates !== undefined ? this.cloneTemplates(patch.templates) : this.cloneTemplates(currentState.templates),
      pageMode: patch.pageMode !== undefined ? patch.pageMode : currentState.pageMode,
      isLoading: patch.isLoading !== undefined ? patch.isLoading : currentState.isLoading,
      isSending: patch.isSending !== undefined ? patch.isSending : currentState.isSending,
      selectedTemplateId: patch.selectedTemplateId !== undefined ? patch.selectedTemplateId : currentState.selectedTemplateId,
      statusText: patch.statusText !== undefined ? patch.statusText : currentState.statusText,
      errorText: patch.errorText !== undefined ? patch.errorText : currentState.errorText,
      canPickTemplate: patch.canPickTemplate !== undefined ? patch.canPickTemplate : currentState.canPickTemplate,
      shouldClose: patch.shouldClose !== undefined ? patch.shouldClose : currentState.shouldClose,
      notificationCancelled: patch.notificationCancelled !== undefined
        ? patch.notificationCancelled
        : currentState.notificationCancelled
    };
  }
}

interface QuickReplyPickerPageStatePatch {
  chatId?: string;
  notificationId?: number;
  source?: QuickReplyPickerSource;
  templates?: QuickReplyTemplate[];
  pageMode?: QuickReplyPickerPageMode;
  isLoading?: boolean;
  isSending?: boolean;
  selectedTemplateId?: string;
  statusText?: UiTextValue;
  errorText?: UiTextValue;
  canPickTemplate?: boolean;
  shouldClose?: boolean;
  notificationCancelled?: boolean;
}
