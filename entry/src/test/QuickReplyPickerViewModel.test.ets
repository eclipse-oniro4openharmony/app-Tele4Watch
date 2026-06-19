import { describe, expect, it } from '@ohos/hypium';
import {
  QuickReplyPickerPageMode,
  QuickReplyPickerPageState
} from '../main/ets/models/quickreply/QuickReplyPickerPageState';
import { QuickReplyTemplate } from '../main/ets/models/quickreply/QuickReplyTemplate';
import { QuickReplyDispatchResult } from '../main/ets/services/quickreply/QuickReplyService';
import {
  QuickReplyPickerServiceGateway,
  QuickReplyPickerViewModel
} from '../main/ets/viewmodel/QuickReplyPickerViewModel';

class FakeQuickReplyPickerServiceGateway implements QuickReplyPickerServiceGateway {
  readonly calls: string[] = [];
  templates: QuickReplyTemplate[] = [];
  dispatchResult: QuickReplyDispatchResult = {
    kind: 'ok',
    notificationCancelled: true
  };
  shouldThrowOnLoad: boolean = false;

  async getTemplates(): Promise<QuickReplyTemplate[]> {
    this.calls.push('load');
    if (this.shouldThrowOnLoad) {
      throw new Error('resource unavailable');
    }
    return this.templates;
  }

  async dispatchTemplate(
    chatId: string,
    templateId: string,
    notificationId?: number
  ): Promise<QuickReplyDispatchResult> {
    this.calls.push(`dispatch:${chatId}:${templateId}:${notificationId !== undefined ? notificationId : 0}`);
    return this.dispatchResult;
  }
}

function buildTemplates(): QuickReplyTemplate[] {
  return [
    { id: 'ok', text: 'OK', userDefined: false },
    { id: 'call_back', text: 'Call back', userDefined: false }
  ];
}

function createReadyState(viewModel: QuickReplyPickerViewModel): QuickReplyPickerPageState {
  const routedState = viewModel.applyRoute(viewModel.createInitialState(), '8529861543', 'notification', 5001);
  return viewModel.applyTemplateLoadResult(routedState, {
    kind: 'ok',
    templates: buildTemplates(),
    errorMessage: ''
  });
}

export default function quickReplyPickerViewModelTest() {
  describe('QuickReplyPickerViewModelTest', () => {
    it('shouldCreateInitialState', 0, () => {
      const viewModel = new QuickReplyPickerViewModel(new FakeQuickReplyPickerServiceGateway());

      const state = viewModel.createInitialState();

      expect(state.chatId).assertEqual('');
      expect(state.source).assertEqual('notification');
      expect(state.pageMode).assertEqual(QuickReplyPickerPageMode.Idle);
      expect(state.templates.length).assertEqual(0);
      expect(state.canPickTemplate).assertFalse();
      expect(state.shouldClose).assertFalse();
    });

    it('shouldApplyRoute', 0, () => {
      const viewModel = new QuickReplyPickerViewModel(new FakeQuickReplyPickerServiceGateway());

      const routedState = viewModel.applyRoute(viewModel.createInitialState(), ' 8529861543 ', 'chatDetails', 5001.8);

      expect(routedState.chatId).assertEqual('8529861543');
      expect(routedState.source).assertEqual('chatDetails');
      expect(routedState.notificationId).assertEqual(5001);
    });

    it('shouldFallbackInvalidSourceToNotification', 0, () => {
      const viewModel = new QuickReplyPickerViewModel(new FakeQuickReplyPickerServiceGateway());

      const routedState = viewModel.applyRoute(viewModel.createInitialState(), '55', 'other', -1);

      expect(routedState.source).assertEqual('notification');
      expect(routedState.notificationId).assertEqual(undefined);
    });

    it('shouldLoadTemplatesThroughGateway', 0, async (): Promise<void> => {
      const gateway = new FakeQuickReplyPickerServiceGateway();
      gateway.templates = buildTemplates();
      const viewModel = new QuickReplyPickerViewModel(gateway);

      const result = await viewModel.loadTemplates();

      expect(result.kind).assertEqual('ok');
      expect(result.templates.length).assertEqual(2);
      expect(gateway.calls.join(',')).assertEqual('load');
    });

    it('shouldApplyLoadedTemplatesAsReadyStateAndCloneThem', 0, () => {
      const viewModel = new QuickReplyPickerViewModel(new FakeQuickReplyPickerServiceGateway());
      const sourceTemplates = buildTemplates();
      const routedState = viewModel.applyRoute(viewModel.createInitialState(), '55', 'notification', 12);

      const readyState = viewModel.applyTemplateLoadResult(routedState, {
        kind: 'ok',
        templates: sourceTemplates,
        errorMessage: ''
      });
      sourceTemplates[0].text = 'changed';

      expect(readyState.pageMode).assertEqual(QuickReplyPickerPageMode.Ready);
      expect(readyState.templates.length).assertEqual(2);
      expect(readyState.templates[0].text).assertEqual('OK');
      expect(readyState.canPickTemplate).assertTrue();
    });

    it('shouldApplyEmptyTemplatesAsEmptyState', 0, () => {
      const viewModel = new QuickReplyPickerViewModel(new FakeQuickReplyPickerServiceGateway());
      const routedState = viewModel.applyRoute(viewModel.createInitialState(), '55', 'notification', 12);

      const emptyState = viewModel.applyTemplateLoadResult(routedState, {
        kind: 'ok',
        templates: [],
        errorMessage: ''
      });

      expect(emptyState.pageMode).assertEqual(QuickReplyPickerPageMode.Empty);
      expect(emptyState.canPickTemplate).assertFalse();
    });

    it('shouldMapTemplateLoadFailureToErrorState', 0, async (): Promise<void> => {
      const gateway = new FakeQuickReplyPickerServiceGateway();
      gateway.shouldThrowOnLoad = true;
      const viewModel = new QuickReplyPickerViewModel(gateway);
      const routedState = viewModel.applyRoute(viewModel.createInitialState(), '55', 'notification', 12);

      const result = await viewModel.loadTemplates();
      const errorState = viewModel.applyTemplateLoadResult(routedState, result);

      expect(result.kind).assertEqual('error');
      expect(errorState.pageMode).assertEqual(QuickReplyPickerPageMode.Error);
      expect(errorState.errorText.resourceName).assertEqual('quick_reply_failed');
      expect(errorState.canPickTemplate).assertFalse();
    });

    it('shouldPlanTemplateDispatchForKnownTemplate', 0, () => {
      const viewModel = new QuickReplyPickerViewModel(new FakeQuickReplyPickerServiceGateway());
      const readyState = createReadyState(viewModel);

      const plan = viewModel.planTemplateDispatch(readyState, ' ok ');

      expect(plan.shouldDispatch).assertTrue();
      expect(plan.chatId).assertEqual('8529861543');
      expect(plan.templateId).assertEqual('ok');
      expect(plan.notificationId).assertEqual(5001);
      expect(plan.nextPageState.pageMode).assertEqual(QuickReplyPickerPageMode.Sending);
      expect(plan.nextPageState.statusText.resourceName).assertEqual('quick_reply_sending');
      expect(plan.nextPageState.canPickTemplate).assertFalse();
    });

    it('shouldRejectUnknownTemplateWithoutDispatch', 0, () => {
      const viewModel = new QuickReplyPickerViewModel(new FakeQuickReplyPickerServiceGateway());
      const readyState = createReadyState(viewModel);

      const plan = viewModel.planTemplateDispatch(readyState, 'missing');

      expect(plan.shouldDispatch).assertFalse();
      expect(plan.nextPageState.pageMode).assertEqual(QuickReplyPickerPageMode.Ready);
      expect(plan.nextPageState.errorText.resourceName).assertEqual('quick_reply_failed');
      expect(plan.nextPageState.canPickTemplate).assertTrue();
    });

    it('shouldIgnoreDispatchWhileAlreadySending', 0, () => {
      const viewModel = new QuickReplyPickerViewModel(new FakeQuickReplyPickerServiceGateway());
      const readyState = createReadyState(viewModel);
      const sendingPlan = viewModel.planTemplateDispatch(readyState, 'ok');

      const duplicatePlan = viewModel.planTemplateDispatch(sendingPlan.nextPageState, 'call_back');

      expect(duplicatePlan.shouldDispatch).assertFalse();
      expect(duplicatePlan.nextPageState.selectedTemplateId).assertEqual('ok');
      expect(duplicatePlan.nextPageState.pageMode).assertEqual(QuickReplyPickerPageMode.Sending);
    });

    it('shouldDispatchTemplateThroughGateway', 0, async (): Promise<void> => {
      const gateway = new FakeQuickReplyPickerServiceGateway();
      const viewModel = new QuickReplyPickerViewModel(gateway);

      const result = await viewModel.dispatchTemplate('55', 'ok', 5001);

      expect(result.kind).assertEqual('ok');
      expect(gateway.calls.join(',')).assertEqual('dispatch:55:ok:5001');
    });

    it('shouldApplyDispatchSuccessAsCloseSignal', 0, () => {
      const viewModel = new QuickReplyPickerViewModel(new FakeQuickReplyPickerServiceGateway());
      const readyState = createReadyState(viewModel);
      const sendingPlan = viewModel.planTemplateDispatch(readyState, 'ok');

      const sentState = viewModel.applyDispatchResult(sendingPlan.nextPageState, {
        kind: 'ok',
        notificationCancelled: true
      });

      expect(sentState.pageMode).assertEqual(QuickReplyPickerPageMode.Sent);
      expect(sentState.statusText.resourceName).assertEqual('quick_reply_sent');
      expect(sentState.shouldClose).assertTrue();
      expect(sentState.notificationCancelled).assertTrue();
      expect(sentState.canPickTemplate).assertFalse();
    });

    it('shouldApplyDispatchFailureAsRetryableReadyState', 0, () => {
      const viewModel = new QuickReplyPickerViewModel(new FakeQuickReplyPickerServiceGateway());
      const readyState = createReadyState(viewModel);
      const sendingPlan = viewModel.planTemplateDispatch(readyState, 'ok');

      const errorState = viewModel.applyDispatchResult(sendingPlan.nextPageState, {
        kind: 'error',
        reason: 'slowmode',
        errorMessage: '420 SLOWMODE_WAIT_12'
      });

      expect(errorState.pageMode).assertEqual(QuickReplyPickerPageMode.Ready);
      expect(errorState.errorText.resourceName).assertEqual('quick_reply_failed');
      expect(errorState.shouldClose).assertFalse();
      expect(errorState.canPickTemplate).assertTrue();
    });

    it('shouldMapNetworkDispatchFailureToQueuedMessage', 0, () => {
      const viewModel = new QuickReplyPickerViewModel(new FakeQuickReplyPickerServiceGateway());
      const readyState = createReadyState(viewModel);
      const sendingPlan = viewModel.planTemplateDispatch(readyState, 'ok');

      const errorState = viewModel.applyDispatchResult(sendingPlan.nextPageState, {
        kind: 'error',
        reason: 'network',
        errorMessage: 'send confirmation timeout'
      });

      expect(errorState.pageMode).assertEqual(QuickReplyPickerPageMode.Ready);
      expect(errorState.errorText.resourceName).assertEqual('quick_reply_network_queued');
      expect(errorState.shouldClose).assertFalse();
      expect(errorState.canPickTemplate).assertTrue();
    });
  });
}
