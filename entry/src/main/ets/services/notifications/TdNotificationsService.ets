import { Want, wantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import type { WantAgent } from '@ohos.app.ability.wantAgent';
import {
  CALL_ANSWER_DEEPLINK_KIND,
  CALL_ANSWER_ON_PHONE_DEEPLINK_KIND,
  CALL_REJECT_DEEPLINK_KIND,
  CALL_RESUME_DEEPLINK_KIND,
  CHAT_DEEPLINK_KIND,
  QUICK_REPLY_DEEPLINK_KIND
} from '../../app/DeeplinkInbox';
import { appAbilityContextStore } from '../../app/AppAbilityContextStore';
import { findStaleStableIds } from './NotificationStaleIds';
import { parsePositiveIntegerText } from '../../utils/NumericTextParser';
import { resolveString } from '../../utils/ResourceTextResolver';
import { tdClient } from '../td/TdClient';
import { tdCallEventDispatcher } from '../td/TdCallEventDispatcher';
import {
  TdCallEvent,
  TdNotificationEvent,
  TdNotificationGroupPayload,
  TdNotificationItem,
  TdParsedCallPayload
} from '../td/TdPayloadTypes';

const DOMAIN = 0x2026;
const TAG = 'TdNotificationsService';
const APP_MESSAGE_PREFIX = 't4w:';
const CALL_APP_MESSAGE_PREFIX = 't4w-call:';
const GROUP_PREFIX = 'chat-';
const CALL_GROUP_PREFIX = 'call-';
const DEFAULT_TITLE = 'Telegram';
const DEFAULT_PREVIEW = 'New message';
const INCOMING_CALL_TITLE_RESOURCE_NAME = 'call_notification_incoming_title';
const ONGOING_CALL_TITLE_RESOURCE_NAME = 'call_notification_ongoing_title';
const CHAT_NOTIFICATION_OPEN_ACTION_RESOURCE_NAME = 'chat_notification_action_open';
const INCOMING_CALL_ANSWER_ACTION_RESOURCE_NAME = 'call_notification_action_answer';
const INCOMING_CALL_REJECT_ACTION_RESOURCE_NAME = 'call_notification_action_reject';
const INCOMING_CALL_ANSWER_ON_PHONE_ACTION_RESOURCE_NAME = 'call_notification_action_answer_on_phone';
const QUICK_REPLY_ACTION_RESOURCE_NAME = 'quick_reply_action_label';
const INCOMING_CALL_FALLBACK_PEER = 'Telegram';
const MAX_CACHED_ITEMS_PER_CHAT = 10;
const MAX_VISIBLE_LINES = 3;
const BUNDLE_NAME = 'com.ostc.tele4watch';
const ENTRY_ABILITY_NAME = 'EntryAbility';
const LARGE_ICON_SIZE_PX = 96;
const CALL_NOTIFICATION_ID_OFFSET = 400000000;
const CALL_NOTIFICATION_ID_MODULO = 100000000;
const CALL_NOTIFICATION_ID_MIN_SUFFIX = 1;
const QUICK_REPLY_REQUEST_CODE_OFFSET = 200000000;

/**
 * Normalizes a TDLib notification id to the stable id used by app notifications.
 *
 * @param notificationId Raw TDLib notification id.
 * @returns Positive stable notification id.
 */
export function buildChatNotificationStableId(notificationId: number): number {
  if (notificationId > 0) {
    return notificationId;
  }
  return 1;
}

/**
 * Builds the WantAgent requestCode for opening a chat notification.
 *
 * @param notificationId Raw TDLib notification id.
 * @returns Request code used by notification body and Open action.
 */
export function buildChatNotificationOpenRequestCode(notificationId: number): number {
  return buildChatNotificationStableId(notificationId);
}

/**
 * Builds the WantAgent requestCode for the quick-reply notification action.
 *
 * @param notificationId Raw TDLib notification id.
 * @returns Request code disjoint from chat-open request codes for the same notification.
 */
export function buildQuickReplyNotificationRequestCode(notificationId: number): number {
  return buildChatNotificationStableId(notificationId) + QUICK_REPLY_REQUEST_CODE_OFFSET;
}

/**
 * Decides whether a message notification may expose the quick-reply picker action.
 *
 * @param item Parsed TDLib notification item.
 * @returns `true` when the current MVP can safely offer a quick-reply action.
 */
export function shouldOfferQuickReplyForNotificationItem(item: TdNotificationItem): boolean {
  if (item.isSilent) {
    return false;
  }
  return item.content.kind !== 'serviceEvent';
}

/**
 * Own T4W notification publisher fed by TDLib notification update payloads.
 */
class TdNotificationsService {
  private initialized: boolean = false;
  private nextCallNotificationIdSuffix: number = this.seedCallNotificationIdSuffix();
  private activeStableIds: Set<number> = new Set<number>();
  private activeCallStableIdsByCallId: Map<number, number> = new Map<number, number>();
  private rawNotificationIdsByChatId: Map<string, Set<number>> = new Map<string, Set<number>>();
  private itemsByChatId: Map<string, TdNotificationItem[]> = new Map<string, TdNotificationItem[]>();
  private avatarPixelMapByPath: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private callEventSubscriptionId: number = 0;

  /**
   * Starts listening to parsed TDLib notification events.
   */
  init(): void {
    if (this.initialized) {
      return;
    }

    this.initialized = true;
    tdClient.setNotificationsListener((event: TdNotificationEvent): void => {
      void this.handleEvent(event).catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'Unhandled notification event error: %{public}s', error.message);
      });
    });
    tdClient.setChatReadListener((chatId: string): void => {
      void this.handleChatRead(chatId);
    });
    this.callEventSubscriptionId = tdCallEventDispatcher.subscribe((event: TdCallEvent): void => {
      void this.handleCallEvent(event).catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'Unhandled call notification event error: %{public}s', error.message);
      });
    });
    void this.hydrateActiveSnapshotFromSystem();
    hilog.info(DOMAIN, TAG, 'TD notification publisher initialized.');
  }

  /**
   * Stops listening to TDLib notification events without cancelling visible notifications.
   */
  release(): void {
    if (!this.initialized) {
      return;
    }

    this.initialized = false;
    tdClient.setNotificationsListener(undefined);
    tdClient.setChatReadListener(undefined);
    if (this.callEventSubscriptionId > 0) {
      tdCallEventDispatcher.unsubscribe(this.callEventSubscriptionId);
      this.callEventSubscriptionId = 0;
    }
    this.releaseAvatarPixelMaps();
    hilog.info(DOMAIN, TAG, 'TD notification publisher released.');
  }

  /**
   * Cancels all active notifications grouped for one chat.
   *
   * @param chatId TDLib chat id.
   */
  async handleChatRead(chatId: string): Promise<void> {
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      return;
    }

    try {
      await notificationManager.cancelGroup(this.buildGroupName(safeChatId));
      hilog.info(DOMAIN, TAG, 'Cancelled notification group for chat %{public}s', safeChatId);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to cancel notification group for chat %{public}s: %{public}s',
        safeChatId, String(error));
    } finally {
      this.clearChatCache(safeChatId);
    }
  }

  /**
   * Dismisses the source notification after its quick-reply action opens the picker.
   *
   * @param chatId TDLib chat id.
   * @param notificationId Optional source notification id carried by the deeplink.
   */
  async handleQuickReplyOpened(chatId: string, notificationId?: number): Promise<void> {
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      return;
    }

    if (notificationId !== undefined && notificationId > 0) {
      try {
        await notificationManager.cancel(notificationId);
        this.activeStableIds.delete(notificationId);
        this.removeRawId(safeChatId, notificationId);
        hilog.info(DOMAIN, TAG, 'Dismissed quick-reply source notification %{public}d for chat %{public}s',
          notificationId,
          safeChatId
        );
        return;
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Failed to dismiss quick-reply source notification %{public}d: %{public}s',
          notificationId,
          String(error)
        );
      }
    }

    await this.handleChatRead(safeChatId);
  }

  /**
   * Cancels notifications after a quick reply has been confirmed as sent.
   *
   * @param chatId TDLib chat id.
   * @param notificationId Optional source notification id. Group cancellation remains canonical.
   */
  async handleQuickReplySent(chatId: string, _notificationId?: number): Promise<void> {
    await this.handleChatRead(chatId);
  }

  /**
   * Cancels visible incoming-call notification without sending a TDLib call action.
   *
   * @param callId TDLib call id.
   */
  async cancelIncomingCallNotification(callId: number): Promise<void> {
    if (callId <= 0) {
      return;
    }
    await this.cancelCallNotification(callId);
  }

  private async handleEvent(event: TdNotificationEvent): Promise<void> {
    if (event.kind === 'notification') {
      await this.handleSingleNotification(event.item);
      return;
    }
    if (event.kind === 'group') {
      await this.reconcileGroup(event.group);
      return;
    }
    if (event.kind === 'active') {
      await this.reconcileAll(event.groups);
    }
  }

  private async handleCallEvent(event: TdCallEvent): Promise<void> {
    if (event.kind !== 'call' || event.call === undefined) {
      return;
    }

    const call = event.call;
    const stateKind = call.state.kind;

    // M2.4.4: a connected call gets an ongoing notification (replaces the incoming
    // one — reserveCallStableId reuses the same id) so the user can return to the
    // CallScreen from the shade.
    if (stateKind === 'ready') {
      await this.publishOngoingCall(call);
      return;
    }

    // Incoming, still ringing — the answer/reject notification.
    if (!call.isOutgoing && stateKind === 'pending') {
      await this.publishIncomingCall(call);
      return;
    }

    // Outgoing pre-ready, exchanging keys, hanging up, discarded, error — no notification.
    await this.cancelCallNotification(call.id);
  }

  private async handleSingleNotification(item: TdNotificationItem | undefined): Promise<void> {
    if (!item) {
      return;
    }

    this.upsertItem(item);
    await this.publishItem(item);
  }

  private async reconcileGroup(group: TdNotificationGroupPayload | undefined): Promise<void> {
    if (!group) {
      return;
    }

    await this.cancelRemoved(group.chatId, group.removedNotificationIds);
    if (group.items.length === 0) {
      return;
    }

    for (const item of group.items) {
      this.upsertItem(item);
    }
    for (const item of group.items) {
      await this.publishItem(item);
    }
  }

  private async reconcileAll(groups: TdNotificationGroupPayload[] | undefined): Promise<void> {
    if (!groups) {
      return;
    }

    const nextActiveStableIds: Set<number> = new Set<number>();
    for (const group of groups) {
      for (const item of group.items) {
        nextActiveStableIds.add(this.stableId(item.id));
      }
    }

    await this.cancelStaleSystemNotifications(nextActiveStableIds);

    // Call notifications have their own lifecycle (driven by call events),
    // so reconciliation against a chat-only snapshot must not cancel them.
    const callStableIds: Set<number> = new Set<number>(this.activeCallStableIdsByCallId.values());
    const staleStableIds: number[] = findStaleStableIds(
      this.activeStableIds,
      nextActiveStableIds,
      callStableIds
    );
    for (const staleStableId of staleStableIds) {
      await this.cancelStableId(staleStableId);
    }

    this.rawNotificationIdsByChatId.clear();
    this.itemsByChatId.clear();
    for (const group of groups) {
      for (const item of group.items) {
        this.upsertItem(item);
      }
    }
    for (const group of groups) {
      for (const item of group.items) {
        await this.publishItem(item);
      }
    }
  }

  private async publishItem(item: TdNotificationItem): Promise<void> {
    const chatId = item.chatId.trim();
    if (chatId.length === 0) {
      return;
    }

    const stableId = this.stableId(item.id);
    const title = this.resolveTitle(chatId, item);
    const preview = this.resolvePreview(item);
    const chatWantAgent = await this.tryBuildChatWantAgent(item, buildChatNotificationOpenRequestCode(item.id));
    const quickReplyWantAgent = shouldOfferQuickReplyForNotificationItem(item)
      ? await this.tryBuildQuickReplyWantAgent(item, buildQuickReplyNotificationRequestCode(item.id))
      : undefined;
    const largeIcon = await this.resolveLargeIcon(chatId, item);
    const actionButtons: notificationManager.NotificationActionButton[] = [];
    const request: notificationManager.NotificationRequest = {
      id: stableId,
      appMessageId: APP_MESSAGE_PREFIX + chatId + ':' + item.id,
      notificationSlotType: item.isSilent
        ? notificationManager.SlotType.SERVICE_INFORMATION
        : notificationManager.SlotType.SOCIAL_COMMUNICATION,
      groupName: this.buildGroupName(chatId),
      isOngoing: false,
      isUnremovable: false,
      tapDismissed: true,
      deliveryTime: this.resolveDeliveryTime(item),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_MULTILINE,
        multiLine: {
          title: title,
          text: preview,
          briefText: title,
          longTitle: title,
          lines: this.buildVisibleLines(chatId, preview)
        }
      }
    };
    if (chatWantAgent !== undefined) {
      // Wearable UX: body tap on the notification card is unreliable on small screens (ambiguous
      // touch target, gesture conflicts). The explicit "Open" action button guarantees a
      // discoverable, hit-test-safe tap target. Both routes use the same `wantAgent` so they
      // resolve to the same chat deeplink — duplication is intentional, not a leftover.
      request.wantAgent = chatWantAgent;
      actionButtons.push({
        title: this.getString(CHAT_NOTIFICATION_OPEN_ACTION_RESOURCE_NAME),
        wantAgent: chatWantAgent
      });
    }
    if (quickReplyWantAgent !== undefined) {
      actionButtons.push({
        title: this.getString(QUICK_REPLY_ACTION_RESOURCE_NAME),
        wantAgent: quickReplyWantAgent
      });
    }
    if (actionButtons.length > 0) {
      request.actionButtons = actionButtons;
    }
    if (largeIcon !== undefined) {
      request.largeIcon = largeIcon;
    }

    try {
      hilog.info(DOMAIN, TAG, 'Publishing notification %{public}d for chat %{public}s tapAgent=%{public}d quickReplyAgent=%{public}d actions=%{public}d',
        stableId,
        chatId,
        chatWantAgent !== undefined ? 1 : 0,
        quickReplyWantAgent !== undefined ? 1 : 0,
        actionButtons.length
      );
      await notificationManager.publish(request);
      this.activeStableIds.add(stableId);
      hilog.info(DOMAIN, TAG, 'Published notification %{public}d for chat %{public}s', stableId, chatId);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to publish notification %{public}d for chat %{public}s: %{public}s',
        stableId, chatId, String(error));
    }
  }

  private async publishIncomingCall(call: TdParsedCallPayload): Promise<void> {
    const stableId = this.reserveCallStableId(call.id);
    const peerName = this.resolveCallPeerName(call);
    const title = this.getString(INCOMING_CALL_TITLE_RESOURCE_NAME);
    const answerWantAgent = await this.tryBuildCallActionWantAgent(CALL_ANSWER_DEEPLINK_KIND, call.id, stableId + 1);
    const rejectWantAgent = await this.tryBuildCallActionWantAgent(CALL_REJECT_DEEPLINK_KIND, call.id, stableId + 2);
    const phoneWantAgent = await this.tryBuildCallActionWantAgent(CALL_ANSWER_ON_PHONE_DEEPLINK_KIND, call.id, stableId + 3);
    const actionButtons: notificationManager.NotificationActionButton[] = [];
    if (answerWantAgent !== undefined) {
      actionButtons.push({
        title: this.getString(INCOMING_CALL_ANSWER_ACTION_RESOURCE_NAME),
        wantAgent: answerWantAgent
      });
    }
    if (rejectWantAgent !== undefined) {
      actionButtons.push({
        title: this.getString(INCOMING_CALL_REJECT_ACTION_RESOURCE_NAME),
        wantAgent: rejectWantAgent
      });
    }
    if (phoneWantAgent !== undefined) {
      actionButtons.push({
        title: this.getString(INCOMING_CALL_ANSWER_ON_PHONE_ACTION_RESOURCE_NAME),
        wantAgent: phoneWantAgent
      });
    }

    const request: notificationManager.NotificationRequest = {
      id: stableId,
      appMessageId: this.buildCallAppMessageId(call.id, stableId),
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      groupName: this.buildCallGroupName(call.id, stableId),
      isOngoing: true,
      isUnremovable: true,
      tapDismissed: false,
      deliveryTime: Date.now(),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_MULTILINE,
        multiLine: {
          title: title,
          text: peerName,
          briefText: title,
          longTitle: title,
          lines: [peerName]
        }
      }
    };
    if (answerWantAgent !== undefined) {
      request.wantAgent = answerWantAgent;
    } else if (phoneWantAgent !== undefined) {
      request.wantAgent = phoneWantAgent;
    }
    if (actionButtons.length > 0) {
      request.actionButtons = actionButtons;
    }
    let defaultActionKind = 'none';
    if (answerWantAgent !== undefined) {
      defaultActionKind = CALL_ANSWER_DEEPLINK_KIND;
    } else if (phoneWantAgent !== undefined) {
      defaultActionKind = CALL_ANSWER_ON_PHONE_DEEPLINK_KIND;
    }

    try {
      hilog.info(DOMAIN, TAG, 'Publishing incoming call notification %{public}d for call %{public}d actions=%{public}d answerAgent=%{public}d rejectAgent=%{public}d phoneAgent=%{public}d defaultAgent=%{public}s',
        stableId,
        call.id,
        actionButtons.length,
        answerWantAgent !== undefined ? 1 : 0,
        rejectWantAgent !== undefined ? 1 : 0,
        phoneWantAgent !== undefined ? 1 : 0,
        defaultActionKind
      );
      await notificationManager.publish(request);
      this.activeStableIds.add(stableId);
      hilog.info(DOMAIN, TAG, 'Published incoming call notification %{public}d for call %{public}d',
        stableId,
        call.id
      );
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to publish incoming call notification %{public}d: %{public}s',
        stableId,
        String(error)
      );
    }
  }

  private async publishOngoingCall(call: TdParsedCallPayload): Promise<void> {
    const stableId = this.reserveCallStableId(call.id);
    const peerName = this.resolveCallPeerName(call);
    const title = this.getString(ONGOING_CALL_TITLE_RESOURCE_NAME);
    // requestCode + 4 stays clear of the +1/+2/+3 incoming-action codes for this call.
    const resumeWantAgent = await this.tryBuildCallResumeWantAgent(call.id, peerName, stableId + 4);

    const request: notificationManager.NotificationRequest = {
      id: stableId,
      appMessageId: this.buildCallAppMessageId(call.id, stableId),
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      groupName: this.buildCallGroupName(call.id, stableId),
      isOngoing: true,
      isUnremovable: true,
      tapDismissed: false,
      deliveryTime: Date.now(),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_MULTILINE,
        multiLine: {
          title: title,
          text: peerName,
          briefText: title,
          longTitle: title,
          lines: [peerName]
        }
      }
    };
    if (resumeWantAgent !== undefined) {
      request.wantAgent = resumeWantAgent;
    }

    try {
      hilog.info(DOMAIN, TAG, 'Publishing ongoing call notification %{public}d for call %{public}d resumeAgent=%{public}d',
        stableId,
        call.id,
        resumeWantAgent !== undefined ? 1 : 0
      );
      await notificationManager.publish(request);
      this.activeStableIds.add(stableId);
      hilog.info(DOMAIN, TAG, 'Published ongoing call notification %{public}d for call %{public}d',
        stableId,
        call.id
      );
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to publish ongoing call notification %{public}d: %{public}s',
        stableId,
        String(error)
      );
    }
  }

  private async cancelRemoved(chatId: string, rawNotificationIds: number[]): Promise<void> {
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0 || rawNotificationIds.length === 0) {
      return;
    }

    for (const rawNotificationId of rawNotificationIds) {
      const stableId = this.stableId(rawNotificationId);
      await this.cancelStableId(stableId);
      this.removeRawId(safeChatId, rawNotificationId);
    }
  }

  private async cancelStableId(stableId: number): Promise<void> {
    try {
      await notificationManager.cancel(stableId);
      hilog.info(DOMAIN, TAG, 'Cancelled notification %{public}d', stableId);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to cancel notification %{public}d: %{public}s', stableId, String(error));
    } finally {
      this.activeStableIds.delete(stableId);
    }
  }

  private async cancelCallNotification(callId: number): Promise<void> {
    const stableId = this.activeCallStableIdsByCallId.get(callId);
    if (stableId === undefined || stableId <= 0) {
      return;
    }
    await this.cancelStableId(stableId);
    this.activeCallStableIdsByCallId.delete(callId);
  }

  private upsertItem(item: TdNotificationItem): void {
    const chatId = item.chatId.trim();
    if (chatId.length === 0) {
      return;
    }

    let rawIds = this.rawNotificationIdsByChatId.get(chatId);
    if (!rawIds) {
      rawIds = new Set<number>();
      this.rawNotificationIdsByChatId.set(chatId, rawIds);
    }
    rawIds.add(item.id);

    const existingItems = this.itemsByChatId.get(chatId);
    const items = existingItems ? existingItems : [];
    let replaced = false;
    for (let i = 0; i < items.length; i++) {
      if (items[i].id === item.id) {
        items[i] = item;
        replaced = true;
      }
    }
    if (!replaced) {
      items.push(item);
    }
    items.sort((left: TdNotificationItem, right: TdNotificationItem): number => right.date - left.date);
    if (items.length > MAX_CACHED_ITEMS_PER_CHAT) {
      items.splice(MAX_CACHED_ITEMS_PER_CHAT, items.length - MAX_CACHED_ITEMS_PER_CHAT);
    }
    this.itemsByChatId.set(chatId, items);
  }

  private async hydrateActiveSnapshotFromSystem(): Promise<void> {
    let activeRequests: notificationManager.NotificationRequest[] = [];
    try {
      activeRequests = await notificationManager.getActiveNotifications();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to read active notifications during init: %{public}s', String(error));
      return;
    }

    let hydratedCount = 0;
    const hydratedChatIds: Set<string> = new Set<string>();
    for (const request of activeRequests) {
      if (!this.isOwnNotificationRequest(request)) {
        continue;
      }
      const requestId = request.id;
      if (requestId === undefined || requestId <= 0) {
        continue;
      }
      this.activeStableIds.add(requestId);
      const callId = this.resolveCallIdFromRequest(request);
      if (callId > 0) {
        this.activeCallStableIdsByCallId.set(callId, requestId);
        hydratedCount += 1;
        continue;
      }
      const chatId = this.resolveChatIdFromRequest(request);
      if (chatId.length > 0) {
        hydratedChatIds.add(chatId);
      }
      hydratedCount += 1;
    }
    if (hydratedCount > 0) {
      hilog.info(DOMAIN, TAG, 'Hydrated %{public}d notifications from system snapshot.', hydratedCount);
    }
    if (hydratedChatIds.size > 0) {
      const chatIds: string[] = [];
      for (const chatId of hydratedChatIds.values()) {
        chatIds.push(chatId);
      }
      tdClient.refreshNotificationChats(chatIds);
    }
  }

  private async cancelStaleSystemNotifications(nextActiveStableIds: Set<number>): Promise<void> {
    let activeRequests: notificationManager.NotificationRequest[] = [];
    try {
      activeRequests = await notificationManager.getActiveNotifications();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to read active system notifications: %{public}s', String(error));
      return;
    }

    for (const request of activeRequests) {
      if (!this.isOwnNotificationRequest(request)) {
        continue;
      }

      const requestId = request.id;
      if (requestId === undefined || requestId <= 0) {
        continue;
      }

      if (this.isOwnCallNotificationRequest(request)) {
        this.activeStableIds.add(requestId);
        continue;
      }

      if (nextActiveStableIds.has(requestId)) {
        this.activeStableIds.add(requestId);
        continue;
      }

      await this.cancelStableId(requestId);
    }
  }

  private isOwnNotificationRequest(request: notificationManager.NotificationRequest): boolean {
    const appMessageId = request.appMessageId;
    if (appMessageId !== undefined && appMessageId.startsWith(APP_MESSAGE_PREFIX)) {
      return true;
    }
    if (appMessageId !== undefined && appMessageId.startsWith(CALL_APP_MESSAGE_PREFIX)) {
      return true;
    }

    const groupName = request.groupName;
    if (groupName !== undefined && groupName.startsWith(GROUP_PREFIX)) {
      return true;
    }
    if (groupName !== undefined && groupName.startsWith(CALL_GROUP_PREFIX)) {
      return true;
    }

    return false;
  }

  private isOwnCallNotificationRequest(request: notificationManager.NotificationRequest): boolean {
    const appMessageId = request.appMessageId;
    if (appMessageId !== undefined && appMessageId.startsWith(CALL_APP_MESSAGE_PREFIX)) {
      return true;
    }

    const groupName = request.groupName;
    if (groupName !== undefined && groupName.startsWith(CALL_GROUP_PREFIX)) {
      return true;
    }

    return false;
  }

  private resolveChatIdFromRequest(request: notificationManager.NotificationRequest): string {
    const appMessageId = request.appMessageId;
    if (appMessageId !== undefined && appMessageId.startsWith(APP_MESSAGE_PREFIX)) {
      const delimiterIndex = appMessageId.indexOf(':', APP_MESSAGE_PREFIX.length);
      if (delimiterIndex > APP_MESSAGE_PREFIX.length) {
        return appMessageId.substring(APP_MESSAGE_PREFIX.length, delimiterIndex).trim();
      }
    }

    const groupName = request.groupName;
    if (groupName !== undefined && groupName.startsWith(GROUP_PREFIX) && groupName.length > GROUP_PREFIX.length) {
      return groupName.substring(GROUP_PREFIX.length).trim();
    }

    return '';
  }

  private resolveCallIdFromRequest(request: notificationManager.NotificationRequest): number {
    const appMessageId = request.appMessageId;
    if (appMessageId !== undefined && appMessageId.startsWith(CALL_APP_MESSAGE_PREFIX)) {
      const suffix = appMessageId.substring(CALL_APP_MESSAGE_PREFIX.length);
      const delimiterIndex = suffix.indexOf(':');
      const callIdText = delimiterIndex >= 0 ? suffix.substring(0, delimiterIndex) : suffix;
      const parsedId = parsePositiveIntegerText(callIdText);
      if (parsedId > 0) {
        return parsedId;
      }
    }

    const groupName = request.groupName;
    if (groupName !== undefined && groupName.startsWith(CALL_GROUP_PREFIX)) {
      const suffix = groupName.substring(CALL_GROUP_PREFIX.length);
      const delimiterIndex = suffix.indexOf('-');
      const callIdText = delimiterIndex >= 0 ? suffix.substring(0, delimiterIndex) : suffix;
      const parsedId = parsePositiveIntegerText(callIdText);
      if (parsedId > 0) {
        return parsedId;
      }
    }

    return 0;
  }

  private getString(resourceName: string): string {
    const context = appAbilityContextStore.peek();
    if (context === undefined) {
      return resourceName;
    }
    return resolveString(context.resourceManager, resourceName);
  }

  private removeRawId(chatId: string, rawNotificationId: number): void {
    const rawIds = this.rawNotificationIdsByChatId.get(chatId);
    if (rawIds) {
      rawIds.delete(rawNotificationId);
      if (rawIds.size === 0) {
        this.rawNotificationIdsByChatId.delete(chatId);
      }
    }

    const items = this.itemsByChatId.get(chatId);
    if (!items) {
      return;
    }
    const nextItems: TdNotificationItem[] = [];
    for (const item of items) {
      if (item.id !== rawNotificationId) {
        nextItems.push(item);
      }
    }
    if (nextItems.length === 0) {
      this.itemsByChatId.delete(chatId);
      return;
    }
    this.itemsByChatId.set(chatId, nextItems);
  }

  private clearChatCache(chatId: string): void {
    const rawIds = this.rawNotificationIdsByChatId.get(chatId);
    if (rawIds) {
      for (const rawId of rawIds.values()) {
        this.activeStableIds.delete(this.stableId(rawId));
      }
    }
    this.rawNotificationIdsByChatId.delete(chatId);
    this.itemsByChatId.delete(chatId);
  }

  private buildVisibleLines(chatId: string, fallbackPreview: string): string[] {
    const items = this.itemsByChatId.get(chatId);
    const lines: string[] = [];
    if (items) {
      const count = Math.min(items.length, MAX_VISIBLE_LINES);
      for (let i = 0; i < count; i++) {
        lines.push(this.resolvePreview(items[i]));
      }
    }
    if (lines.length === 0) {
      lines.push(fallbackPreview);
    }
    return lines;
  }

  private resolveTitle(chatId: string, item: TdNotificationItem): string {
    const cachedTitle = tdClient.getCachedChatTitle(chatId);
    if (cachedTitle.length > 0) {
      return cachedTitle;
    }

    const senderUserId = item.senderUserId;
    if (senderUserId !== undefined && senderUserId.length > 0) {
      const senderProfile = tdClient.getUserProfile(senderUserId);
      if (senderProfile !== undefined) {
        const senderName = `${senderProfile.firstName} ${senderProfile.lastName}`.trim();
        if (senderName.length > 0) {
          return senderName;
        }
        const username = senderProfile.username.trim();
        if (username.length > 0) {
          return username;
        }
      }
    }

    return DEFAULT_TITLE;
  }

  private resolveCallPeerName(call: TdParsedCallPayload): string {
    const profile = tdClient.getUserProfile(call.userId);
    if (profile !== undefined) {
      const fullName = `${profile.firstName} ${profile.lastName}`.trim();
      if (fullName.length > 0) {
        return fullName;
      }
      const username = profile.username.trim();
      if (username.length > 0) {
        return username;
      }
    }
    return INCOMING_CALL_FALLBACK_PEER;
  }

  private resolvePreview(item: TdNotificationItem): string {
    const text = item.content.text.trim();
    if (text.length > 0) {
      return text;
    }
    return DEFAULT_PREVIEW;
  }

  private async resolveLargeIcon(chatId: string, item: TdNotificationItem): Promise<image.PixelMap | undefined> {
    const path = this.pickAvatarPath(chatId, item);
    if (path.length === 0) {
      return undefined;
    }

    const cached = this.avatarPixelMapByPath.get(path);
    if (cached !== undefined) {
      return cached;
    }

    return await this.loadLargeIcon(path);
  }

  private async loadLargeIcon(path: string): Promise<image.PixelMap | undefined> {
    let source: image.ImageSource | undefined = undefined;
    try {
      source = image.createImageSource(path);
      const options: image.DecodingOptions = {
        'desiredSize': {
          'width': LARGE_ICON_SIZE_PX,
          'height': LARGE_ICON_SIZE_PX
        }
      };
      const pixelMap = await source.createPixelMap(options);
      this.avatarPixelMapByPath.set(path, pixelMap);
      hilog.info(DOMAIN, TAG, 'Loaded notification large icon from cached avatar path.');
      return pixelMap;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to load notification large icon: %{public}s', String(error));
      return undefined;
    } finally {
      if (source !== undefined) {
        try {
          await source.release();
        } catch (releaseError) {
          hilog.warn(DOMAIN, TAG, 'Failed to release large icon ImageSource: %{public}s', String(releaseError));
        }
      }
    }
  }

  private releaseAvatarPixelMaps(): void {
    for (const pixelMap of this.avatarPixelMapByPath.values()) {
      try {
        void pixelMap.release();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Failed to release avatar PixelMap: %{public}s', String(error));
      }
    }
    this.avatarPixelMapByPath.clear();
  }

  private pickAvatarPath(chatId: string, item: TdNotificationItem): string {
    const senderUserId = item.senderUserId;
    if (senderUserId !== undefined && senderUserId.length > 0) {
      const userAvatar = tdClient.getCachedUserAvatarPath(senderUserId);
      if (userAvatar.length > 0) {
        return userAvatar;
      }
    }
    return tdClient.getCachedChatAvatarPath(chatId);
  }

  private resolveDeliveryTime(item: TdNotificationItem): number {
    if (item.date > 0) {
      return item.date * 1000;
    }
    return Date.now();
  }

  private async tryBuildChatWantAgent(item: TdNotificationItem, requestCode: number): Promise<WantAgent | undefined> {
    try {
      const launchWant: Want = {
        'bundleName': BUNDLE_NAME,
        'abilityName': ENTRY_ABILITY_NAME,
        'parameters': {
          'deeplink': CHAT_DEEPLINK_KIND,
          'chatId': item.chatId,
          'messageId': this.resolveMessageId(item)
        }
      };
      const info: wantAgent.WantAgentInfo = {
        'wants': [launchWant],
        'operationType': wantAgent.OperationType.START_ABILITY,
        'requestCode': requestCode,
        'wantAgentFlags': [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      return await wantAgent.getWantAgent(info);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to create notification deeplink WantAgent: %{public}s', String(error));
      return undefined;
    }
  }

  private async tryBuildQuickReplyWantAgent(
    item: TdNotificationItem,
    requestCode: number
  ): Promise<WantAgent | undefined> {
    try {
      const launchWant: Want = {
        'bundleName': BUNDLE_NAME,
        'abilityName': ENTRY_ABILITY_NAME,
        'parameters': {
          'deeplink': QUICK_REPLY_DEEPLINK_KIND,
          'chatId': item.chatId,
          'notificationId': this.stableId(item.id),
          'source': 'notification'
        }
      };
      const info: wantAgent.WantAgentInfo = {
        'wants': [launchWant],
        'operationType': wantAgent.OperationType.START_ABILITY,
        'requestCode': requestCode,
        'wantAgentFlags': [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      return await wantAgent.getWantAgent(info);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to create quick-reply WantAgent: %{public}s', String(error));
      return undefined;
    }
  }

  private async tryBuildCallActionWantAgent(
    deeplinkKind: string,
    callId: number,
    requestCode: number
  ): Promise<WantAgent | undefined> {
    try {
      const launchWant: Want = {
        'bundleName': BUNDLE_NAME,
        'abilityName': ENTRY_ABILITY_NAME,
        'parameters': {
          'deeplink': deeplinkKind,
          'callId': callId
        }
      };
      const info: wantAgent.WantAgentInfo = {
        'wants': [launchWant],
        'operationType': wantAgent.OperationType.START_ABILITY,
        'requestCode': requestCode,
        'wantAgentFlags': [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      return await wantAgent.getWantAgent(info);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to create call action WantAgent: %{public}s', String(error));
      return undefined;
    }
  }

  /**
   * Builds the WantAgent for tapping the ongoing-call notification body — re-enters
   * the active CallScreen via the `resumeCall` deeplink, carrying the peer name.
   */
  private async tryBuildCallResumeWantAgent(
    callId: number,
    peerName: string,
    requestCode: number
  ): Promise<WantAgent | undefined> {
    try {
      const launchWant: Want = {
        'bundleName': BUNDLE_NAME,
        'abilityName': ENTRY_ABILITY_NAME,
        'parameters': {
          'deeplink': CALL_RESUME_DEEPLINK_KIND,
          'callId': callId,
          'peerName': peerName
        }
      };
      const info: wantAgent.WantAgentInfo = {
        'wants': [launchWant],
        'operationType': wantAgent.OperationType.START_ABILITY,
        'requestCode': requestCode,
        'wantAgentFlags': [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      return await wantAgent.getWantAgent(info);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to create call resume WantAgent: %{public}s', String(error));
      return undefined;
    }
  }

  private resolveMessageId(item: TdNotificationItem): string {
    if (item.messageId !== undefined && item.messageId.length > 0) {
      return item.messageId;
    }
    return '';
  }

  private buildGroupName(chatId: string): string {
    return GROUP_PREFIX + chatId;
  }

  private buildCallGroupName(callId: number, stableId: number): string {
    return CALL_GROUP_PREFIX + callId + '-' + stableId;
  }

  private buildCallAppMessageId(callId: number, stableId: number): string {
    return CALL_APP_MESSAGE_PREFIX + callId + ':' + stableId;
  }

  private stableId(notificationId: number): number {
    return buildChatNotificationStableId(notificationId);
  }

  private reserveCallStableId(callId: number): number {
    const activeStableId = this.activeCallStableIdsByCallId.get(callId);
    if (activeStableId !== undefined && activeStableId > 0) {
      return activeStableId;
    }
    const stableId = CALL_NOTIFICATION_ID_OFFSET + this.nextCallNotificationIdSuffix;
    this.nextCallNotificationIdSuffix = this.nextCallNotificationIdSuffix + 1;
    if (this.nextCallNotificationIdSuffix >= CALL_NOTIFICATION_ID_MODULO) {
      this.nextCallNotificationIdSuffix = CALL_NOTIFICATION_ID_MIN_SUFFIX;
    }
    this.activeCallStableIdsByCallId.set(callId, stableId);
    return stableId;
  }

  private seedCallNotificationIdSuffix(): number {
    const suffix = Date.now() % CALL_NOTIFICATION_ID_MODULO;
    if (suffix >= CALL_NOTIFICATION_ID_MIN_SUFFIX) {
      return suffix;
    }
    return CALL_NOTIFICATION_ID_MIN_SUFFIX;
  }

}

export const tdNotificationsService: TdNotificationsService = new TdNotificationsService();
