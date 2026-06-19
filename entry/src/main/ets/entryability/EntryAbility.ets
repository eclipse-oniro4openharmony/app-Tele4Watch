import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, window } from '@kit.ArkUI';
import { LogUtil } from '@ohos/lottie';
import { appAbilityContextStore } from '../app/AppAbilityContextStore';
import {
  CallActionDeeplink,
  ChatDeeplink,
  CALL_ANSWER_DEEPLINK_KIND,
  CALL_ANSWER_ON_PHONE_DEEPLINK_KIND,
  CALL_REJECT_DEEPLINK_KIND,
  CALL_RESUME_DEEPLINK_KIND,
  createChatDeeplinkRouteParams,
  createQuickReplyDeeplinkRouteParams,
  deeplinkInbox,
  describeCallActionWant,
  parseCallActionDeeplinkFromWant,
  parseChatDeeplinkFromWant,
  parseQuickReplyDeeplinkFromWant,
  QuickReplyDeeplink
} from '../app/DeeplinkInbox';
import { tdNotificationsService } from '../services/notifications/TdNotificationsService';
import { tdClient } from '../services/td/TdClient';
import { tdCallEventDispatcher } from '../services/td/TdCallEventDispatcher';
import { buildDefaultTdCallProtocolRequest } from '../services/voip/CallProtocolRequestBuilder';
import { callAcceptObserverHub } from '../services/voip/CallAcceptObserverHub';
import type { TdCallEvent } from '../services/td/TdPayloadTypes';

const DOMAIN = 0x0000;
const TAG = "EntryAbility";
const AUTH_STATE_READY = 'authorizationStateReady';

export default class EntryAbility extends UIAbility {
  private pendingCallAction?: CallActionDeeplink;
  /** Call id whose CallScreen we already auto-opened on this ability instance. */
  private lastOpenedIncomingCallId: number = 0;
  /** Subscription id returned by `tdCallEventDispatcher.subscribe`. */
  private autoOpenSubscriptionId: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    appAbilityContextStore.put(this.context);
    deeplinkInbox.attachContext(this.context);
    this.storeColdStartDeeplink(want);
    this.storeColdStartCallAction(want);
    this.logPendingDeeplinkOnCreate();
    LogUtil.mLogLevel = LogUtil.OFF;
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    this.unsubscribeIncomingCallAutoOpen();
    appAbilityContextStore.clear();
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onNewWant call action probe: %{public}s', describeCallActionWant(want));
    const callAction = parseCallActionDeeplinkFromWant(want);
    if (callAction) {
      hilog.info(DOMAIN, TAG, 'Parsed hot-start call action %{public}s for call %{public}d',
        callAction.kind,
        callAction.callId
      );
      this.openCallAction(callAction);
      return;
    }

    const quickReplyDeeplink = parseQuickReplyDeeplinkFromWant(want);
    if (quickReplyDeeplink) {
      this.openQuickReplyDeeplink(quickReplyDeeplink);
      return;
    }

    const deeplink = parseChatDeeplinkFromWant(want);
    if (!deeplink) {
      return;
    }

    this.openChatDeeplink(deeplink);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
      this.subscribeIncomingCallAutoOpen();
      this.openPendingCallAction();
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }

  private storeColdStartDeeplink(want: Want): void {
    const deeplink = parseChatDeeplinkFromWant(want);
    if (deeplink) {
      deeplinkInbox.put(deeplink);
      hilog.info(DOMAIN, TAG, 'Stored cold-start chat deeplink for chat %{public}s', deeplink.chatId);
      return;
    }

    const quickReplyDeeplink = parseQuickReplyDeeplinkFromWant(want);
    if (!quickReplyDeeplink) {
      return;
    }

    void tdNotificationsService.handleQuickReplyOpened(
      quickReplyDeeplink.chatId,
      quickReplyDeeplink.notificationId
    );
    deeplinkInbox.put(quickReplyDeeplink);
    hilog.info(DOMAIN, TAG, 'Stored cold-start quick-reply deeplink for chat %{public}s',
      quickReplyDeeplink.chatId);
  }

  private storeColdStartCallAction(want: Want): void {
    hilog.info(DOMAIN, TAG, 'Cold-start call action probe: %{public}s', describeCallActionWant(want));
    const callAction = parseCallActionDeeplinkFromWant(want);
    if (!callAction) {
      hilog.info(DOMAIN, TAG, 'No cold-start call action parsed.');
      return;
    }

    this.pendingCallAction = callAction;
    hilog.info(DOMAIN, TAG, 'Stored cold-start call action %{public}s for call %{public}d',
      callAction.kind,
      callAction.callId
    );
  }

  private openPendingCallAction(): void {
    const callAction = this.pendingCallAction;
    if (!callAction) {
      hilog.info(DOMAIN, TAG, 'No pending call action to open after content load.');
      return;
    }
    this.pendingCallAction = undefined;
    hilog.info(DOMAIN, TAG, 'Opening pending call action %{public}s for call %{public}d',
      callAction.kind,
      callAction.callId
    );
    this.openCallAction(callAction);
  }

  private logPendingDeeplinkOnCreate(): void {
    const deeplink = deeplinkInbox.peek();
    if (!deeplink) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'Pending %{public}s deeplink available on create for chat %{public}s',
      deeplink.kind,
      deeplink.chatId);
  }

  private openChatDeeplink(deeplink: ChatDeeplink): void {
    if (tdClient.getAuthorizationStateName() !== AUTH_STATE_READY) {
      deeplinkInbox.put(deeplink);
      try {
        router.pushUrl({
          url: 'pages/Index'
        });
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'Failed to route unauthorized deeplink to Index: %{public}s', String(error));
      }
      hilog.info(DOMAIN, TAG, 'Stored unauthorized hot-start chat deeplink for chat %{public}s', deeplink.chatId);
      return;
    }

    try {
      router.pushUrl({
        url: 'pages/ChatDetails',
        params: createChatDeeplinkRouteParams(deeplink)
      });
      hilog.info(DOMAIN, TAG, 'Opened hot-start chat deeplink for chat %{public}s', deeplink.chatId);
    } catch (error) {
      deeplinkInbox.put(deeplink);
      hilog.error(DOMAIN, TAG, 'Failed to open hot-start chat deeplink: %{public}s', String(error));
    }
  }

  private openQuickReplyDeeplink(deeplink: QuickReplyDeeplink): void {
    void tdNotificationsService.handleQuickReplyOpened(deeplink.chatId, deeplink.notificationId);
    if (tdClient.getAuthorizationStateName() !== AUTH_STATE_READY) {
      deeplinkInbox.put(deeplink);
      try {
        router.pushUrl({
          url: 'pages/Index'
        });
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'Failed to route unauthorized quick-reply deeplink to Index: %{public}s',
          String(error));
      }
      hilog.info(DOMAIN, TAG, 'Stored unauthorized hot-start quick-reply deeplink for chat %{public}s',
        deeplink.chatId);
      return;
    }

    try {
      router.pushUrl({
        url: 'pages/QuickReplyPicker',
        params: createQuickReplyDeeplinkRouteParams(deeplink)
      });
      hilog.info(DOMAIN, TAG, 'Opened hot-start quick-reply deeplink for chat %{public}s', deeplink.chatId);
    } catch (error) {
      deeplinkInbox.put(deeplink);
      hilog.error(DOMAIN, TAG, 'Failed to open hot-start quick-reply deeplink: %{public}s', String(error));
    }
  }

  private openCallAction(callAction: CallActionDeeplink): void {
    hilog.info(DOMAIN, TAG, 'Handling call action %{public}s for call %{public}d',
      callAction.kind,
      callAction.callId
    );
    if (callAction.kind === CALL_ANSWER_DEEPLINK_KIND) {
      void tdNotificationsService.cancelIncomingCallNotification(callAction.callId);
      // Task 4.6 F3: when the auto-open already opened CallScreen for this
      // incoming call, the notification answer action must NOT push a second
      // CallScreen — accept the call directly so the VM observes the state
      // transition through its existing call-event subscription.
      if (this.lastOpenedIncomingCallId === callAction.callId) {
        const accepted = tdClient.acceptCall(callAction.callId, buildDefaultTdCallProtocolRequest());
        if (accepted) {
          // Task 4.6 P1 follow-up: notify the live VM that accept was
          // dispatched externally so the in-screen Decline button stops
          // being a viable hangup target while TDLib is still rolling
          // from `pending` to `exchangingKeys`.
          callAcceptObserverHub.notifyAccepted(callAction.callId);
          hilog.info(DOMAIN, TAG, 'Notification answer routed to acceptCall (auto-open active) for %{public}d',
            callAction.callId
          );
        } else {
          hilog.warn(DOMAIN, TAG, 'acceptCall was not sent from notification answer for %{public}d',
            callAction.callId
          );
        }
        return;
      }
      try {
        router.pushUrl({
          url: 'pages/CallScreen',
          params: {
            direction: 'incoming',
            callId: callAction.callId
          }
        });
        hilog.info(DOMAIN, TAG, 'Opened call answer action for call %{public}d', callAction.callId);
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'Failed to open call answer action: %{public}s', String(error));
      }
      return;
    }

    if (callAction.kind === CALL_ANSWER_ON_PHONE_DEEPLINK_KIND) {
      void tdNotificationsService.cancelIncomingCallNotification(callAction.callId);
      hilog.info(DOMAIN, TAG, 'Cancelled incoming call notification for answer-on-phone action: %{public}d',
        callAction.callId
      );
      return;
    }

    if (callAction.kind === CALL_RESUME_DEEPLINK_KIND) {
      // M2.4.4: ongoing-call notification tapped — re-attach to the active call.
      // The call is already running, so CallScreen enters resume mode (no accept/create).
      try {
        router.pushUrl({
          url: 'pages/CallScreen',
          params: {
            resume: true,
            callId: callAction.callId,
            peerName: callAction.peerName !== undefined ? callAction.peerName : ''
          }
        });
        hilog.info(DOMAIN, TAG, 'Opened call resume action for call %{public}d', callAction.callId);
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'Failed to open call resume action: %{public}s', String(error));
      }
      return;
    }

    if (callAction.kind !== CALL_REJECT_DEEPLINK_KIND) {
      return;
    }

    // ADR-0007: reject never needed a screen — discard the call directly from
    // the notification action instead of routing to a transient page.
    const rejected = tdClient.discardCall(callAction.callId, false, 0, false, '0');
    if (rejected) {
      hilog.info(DOMAIN, TAG, 'Discarded call %{public}d from reject action', callAction.callId);
    } else {
      hilog.warn(DOMAIN, TAG, 'discardCall was not sent for reject action %{public}d', callAction.callId);
    }
  }

  /**
   * Subscribes to `tdCallEventDispatcher` so an incoming call (`updateCall`
   * pending + `isOutgoing=false`) auto-opens `pages/CallScreen` in
   * `pendingAccept` mode, regardless of whether the user reaches the
   * notification shade in time (Task 4.6 F2).
   */
  private subscribeIncomingCallAutoOpen(): void {
    if (this.autoOpenSubscriptionId > 0) {
      return;
    }
    this.autoOpenSubscriptionId = tdCallEventDispatcher.subscribe((event: TdCallEvent): void => {
      this.handleAutoOpenCallEvent(event);
    });
    hilog.info(DOMAIN, TAG, 'Incoming-call auto-open subscribed (sub=%{public}d).',
      this.autoOpenSubscriptionId
    );
  }

  private unsubscribeIncomingCallAutoOpen(): void {
    if (this.autoOpenSubscriptionId <= 0) {
      return;
    }
    tdCallEventDispatcher.unsubscribe(this.autoOpenSubscriptionId);
    this.autoOpenSubscriptionId = 0;
  }

  private handleAutoOpenCallEvent(event: TdCallEvent): void {
    if (event.kind !== 'call' || event.call === undefined) {
      return;
    }
    const call = event.call;
    if (call.isOutgoing) {
      return;
    }
    if (call.state.kind === 'discarded' || call.state.kind === 'error') {
      if (this.lastOpenedIncomingCallId === call.id) {
        this.lastOpenedIncomingCallId = 0;
      }
      return;
    }
    if (call.state.kind !== 'pending') {
      return;
    }
    if (this.lastOpenedIncomingCallId === call.id) {
      return;
    }
    this.lastOpenedIncomingCallId = call.id;
    try {
      router.pushUrl({
        url: 'pages/CallScreen',
        params: {
          direction: 'incoming',
          callId: call.id,
          userId: call.userId,
          pendingAccept: true
        }
      });
      hilog.info(DOMAIN, TAG, 'Auto-opened CallScreen for incoming call %{public}d userId=%{public}s',
        call.id,
        call.userId
      );
    } catch (error) {
      this.lastOpenedIncomingCallId = 0;
      hilog.error(DOMAIN, TAG, 'Failed to auto-open CallScreen for call %{public}d: %{public}s',
        call.id,
        String(error)
      );
    }
  }
}
