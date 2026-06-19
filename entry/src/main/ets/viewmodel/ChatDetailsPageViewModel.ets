import { trimTgsLottieCache } from '../services/tgs/TgsLottieLoader';
import { tdClient } from '../services/td/TdClient';
import { TdChatMessageItem, TdUserProfileItem } from '../services/td/TdPayloadTypes';
import { ChatRouteParams, createChatRouteParams } from '../models/chat/ChatRouteParams';
import { ChatDetailsPageMode, ChatDetailsPageState } from '../models/chat/ChatDetailsPageState';
import { MediaViewerRouteParams } from '../models/chat/MediaViewerRouteParams';
import { ProfileRouteParams } from '../models/profile/ProfileRouteParams';
import { textSignature } from '../utils/TextSignature';
import {
  createIdleVoiceNotePlaybackSnapshot,
  VoiceNotePlaybackController,
  VoiceNotePlaybackRequest,
  VoiceNotePlaybackSnapshot
} from '../services/media/VoiceNotePlaybackController';
import { VoiceNotePlaybackRequestResolver } from '../services/media/VoiceNotePlaybackRequestResolver';
import { tdNotificationsService } from '../services/notifications/TdNotificationsService';
import { MediaViewerPageViewModel } from './MediaViewerPageViewModel';

// Defensive cap: when TDLib accepts an older-history pull but never emits a response (lost reply,
// timeout, parse failure), the page would otherwise wait forever in the refreshing UI. The view
// arms a setTimeout with this duration; the decision to act when it fires lives in
// `shouldProcessOlderHistoryTimeout` below so it stays testable.
export const OLDER_HISTORY_PULL_TIMEOUT_MS = 5000;

// Defensive cap for notification deeplinks. If the targeted message is deleted, unreachable, or
// not in the page TDLib returns for `getChatHistory(fromMessageId)`, the pending-deeplink flag
// would block `scheduleScrollToLatest` forever. After this window the view gives up; the
// "should-give-up" decision lives in `shouldGiveUpOnDeeplink` so it stays testable. Sized to
// outlive the avatar `refreshMessagesForUser` re-emit race (a stale-cache pre-fire arriving
// before the real response) so a re-visit with cached messages still gets a fair chance to
// locate the target.
export const DEEPLINK_GIVE_UP_TIMEOUT_MS = 3000;

export interface ChatDetailsAuthStatePlan {
  shouldNavigateToIndex: boolean;
  resetIndexNavigation: boolean;
}

export interface ChatDetailsRefreshPlan {
  nextPageState: ChatDetailsPageState;
  shouldRequestHistory: boolean;
  requestLimit: number;
}

export interface ChatDetailsOlderHistoryPlan {
  nextPageState: ChatDetailsPageState;
  chatId: string;
  shouldRequestOlderHistory: boolean;
}

export interface ChatDetailsHistoryPageResolution {
  nextPageState: ChatDetailsPageState;
  shouldShowNoOlderHistoryToast: boolean;
}

export interface ChatDetailsVisibleScrollAnchorState {
  explicitReturnAnchorMessageId: string;
  persistedScrollAnchorMessageId: string;
  topMessageId: string;
  lastVisibleStartMessageId: string;
  lastVisibleCenterMessageId: string;
  lastVisibleEndMessageId: string;
  lastVisibleWasAtLatest: boolean;
  lastVisibleWasAtTop: boolean;
  shouldPersistLoadedTopAnchor: boolean;
}

export interface ChatDetailsPersistableScrollAnchorPlan {
  shouldPersist: boolean;
  messageId: string;
  isAtLatest: boolean;
}

interface ChatDetailsScrollAnchor {
  chatId: string;
  messageId: string;
}

const CHAT_DETAILS_SCROLL_ANCHOR_CAPACITY = 64;

class ChatDetailsScrollAnchorStore {
  private anchors: ChatDetailsScrollAnchor[] = [];

  save(chatId: string, messageId: string): void {
    const safeChatId = chatId.trim();
    const safeMessageId = messageId.trim();
    if (safeChatId.length === 0 || safeMessageId.length === 0) {
      return;
    }

    const existingIndex = this.findIndexByChatId(safeChatId);
    const anchor: ChatDetailsScrollAnchor = {
      chatId: safeChatId,
      messageId: safeMessageId
    };
    if (existingIndex >= 0) {
      this.removeAt(existingIndex);
    }
    this.anchors.push(anchor);
    this.trimToCapacity();
  }

  clear(chatId: string): void {
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      return;
    }
    const nextAnchors: ChatDetailsScrollAnchor[] = [];
    for (let index = 0; index < this.anchors.length; index += 1) {
      const anchor = this.anchors[index];
      if (anchor.chatId !== safeChatId) {
        nextAnchors.push(anchor);
      }
    }
    this.anchors = nextAnchors;
  }

  getMessageId(chatId: string): string {
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      return '';
    }
    const existingIndex = this.findIndexByChatId(safeChatId);
    if (existingIndex < 0) {
      return '';
    }
    return this.anchors[existingIndex].messageId;
  }

  private findIndexByChatId(chatId: string): number {
    for (let index = 0; index < this.anchors.length; index += 1) {
      if (this.anchors[index].chatId === chatId) {
        return index;
      }
    }
    return -1;
  }

  private removeAt(indexToRemove: number): void {
    const nextAnchors: ChatDetailsScrollAnchor[] = [];
    for (let index = 0; index < this.anchors.length; index += 1) {
      if (index !== indexToRemove) {
        nextAnchors.push(this.anchors[index]);
      }
    }
    this.anchors = nextAnchors;
  }

  private trimToCapacity(): void {
    while (this.anchors.length > CHAT_DETAILS_SCROLL_ANCHOR_CAPACITY) {
      this.removeAt(0);
    }
  }
}

const chatDetailsScrollAnchorStore = new ChatDetailsScrollAnchorStore();

/**
 * Creates the typed state scaffold for the routed chat-details page.
 */
export class ChatDetailsPageViewModel {
  private readonly mediaViewerPageViewModel: MediaViewerPageViewModel = new MediaViewerPageViewModel();
  // Per-ViewModel ownership is intentional. The controller object itself is a thin JS allocation
  // and `MediaKitVoiceNotePlayer` only creates the heavyweight `media.AVPlayer` on the first
  // `load()` call — so a chat the user opens without ever playing a voice note pays no real
  // playback resource cost. The real churn (AVPlayer create/release) would only disappear if
  // the controller AND its AVPlayer lived across navigation (Telegram-like background playback),
  // which is a UX feature, not a refactor — it requires MediaSession integration, notification
  // controls, and a logout-reset story. Until that feature is scheduled (and profiling shows
  // AVPlayer churn actually causes jank), per-VM ownership stays the simpler safe default.
  private readonly voiceNotePlaybackController: VoiceNotePlaybackController = new VoiceNotePlaybackController();
  private readonly voiceNotePlaybackRequestResolver: VoiceNotePlaybackRequestResolver = new VoiceNotePlaybackRequestResolver();

  /**
   * Creates the initial idle voice-note playback snapshot used to seed `@State`.
   *
   * @returns The idle snapshot.
   */
  createInitialVoiceNotePlaybackSnapshot(): VoiceNotePlaybackSnapshot {
    return createIdleVoiceNotePlaybackSnapshot();
  }

  /**
   * Registers one voice-note playback listener.
   *
   * @param listener The listener invoked after playback-state updates.
   */
  setVoiceNotePlaybackListener(listener: (snapshot: VoiceNotePlaybackSnapshot) => void): void {
    this.voiceNotePlaybackController.setListener(listener);
  }

  /**
   * Clears the voice-note playback listener.
   */
  clearVoiceNotePlaybackListener(): void {
    this.voiceNotePlaybackController.setListener(undefined);
  }

  /**
   * Toggles voice-note playback for one timeline item, resolving the playback request first.
   * The optional `onResolvedRequest` callback hands the resolved request to the caller so the
   * view layer can attach its own diagnostic logging without owning the resolver service.
   *
   * @param message The timeline item carrying the voice-note payload.
   * @param onResolvedRequest Optional sink that receives the resolved request before playback.
   */
  async toggleVoiceNotePlayback(
    message: TdChatMessageItem,
    onResolvedRequest?: (request: VoiceNotePlaybackRequest) => void
  ): Promise<void> {
    const playbackRequest = await this.voiceNotePlaybackRequestResolver.createPlaybackRequest(message);
    if (onResolvedRequest) {
      onResolvedRequest(playbackRequest);
    }
    await this.voiceNotePlaybackController.toggle(playbackRequest);
  }

  /**
   * Releases the underlying voice-note player resources.
   */
  releaseVoiceNotePlayback(): Promise<void> {
    return this.voiceNotePlaybackController.release();
  }

  /**
   * Dismisses chat-level notifications for the chat currently visible on the page.
   *
   * @param chatId The chat identifier currently in view.
   */
  dismissChatNotifications(chatId: string): void {
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      return;
    }
    void tdNotificationsService.handleChatRead(safeChatId);
  }
  /**
   * Subscribes a chat-messages listener via the TdClient fan-out hub. Returns a token used to
   * unsubscribe in `aboutToDisappear`; multiple pages can subscribe concurrently without
   * stealing each other's slot.
   *
   * @param listener The listener invoked after timeline updates.
   * @returns Subscription token used to unsubscribe.
   */
  subscribeChatMessages(listener: (chatId: string, items: TdChatMessageItem[]) => void): number {
    return tdClient.subscribeChatMessages(listener);
  }

  /**
   * Unsubscribes a previously-registered chat-messages listener. Idempotent on the `0` sentinel
   * or any unknown token.
   *
   * @param token Subscription token returned by `subscribeChatMessages`.
   */
  unsubscribeChatMessages(token: number): void {
    tdClient.unsubscribeChatMessages(token);
  }

  /**
   * Registers one authorization-state listener.
   *
   * @param listener The listener invoked after auth-state updates.
   */
  setAuthStateListener(listener: (state: string) => void): void {
    tdClient.setAuthStateListener(listener);
  }

  /**
   * Returns the latest TDLib authorization state name.
   *
   * @returns The current authorization state name.
   */
  getAuthorizationStateName(): string {
    return tdClient.getAuthorizationStateName();
  }

  /**
   * Requests one chat-history page.
   *
   * @param chatId The chat identifier.
   * @param limit The requested history limit.
   */
  requestChatHistory(chatId: string, limit: number): void {
    tdClient.requestChatHistory(chatId, limit);
  }

  /**
   * Requests one chat-history page centered around a known message id.
   *
   * @param chatId The chat identifier.
   * @param limit The requested history limit.
   * @param messageId The message id that should be included in the first page.
   */
  requestChatHistoryFromMessage(chatId: string, limit: number, messageId: string): void {
    tdClient.requestChatHistoryFromMessage(chatId, limit, messageId);
  }

  /**
   * Requests one older-history page.
   *
   * @param chatId The chat identifier.
   * @returns `'started'` when TDLib accepted the request, `'no-more-pages'` when the chat has
   * already been fully fetched (so the view can surface a "no earlier messages" hint instead of
   * silently dropping the spinner), or `'rejected'` for unauthorized / malformed requests.
   */
  requestOlderChatHistory(chatId: string): 'started' | 'no-more-pages' | 'rejected' {
    return tdClient.requestOlderChatHistory(chatId);
  }

  /**
   * Subscribes to "older-history pull just resolved" events on the TdClient hub. Fires only for
   * responses to user-initiated pulls (`requestOlderChatHistory` returning `'started'`); live
   * updates and probe retries do not trigger it. Returns a token used to unsubscribe.
   *
   * @param listener Callback invoked once per resolved pull cycle.
   * @returns Subscription token used to unsubscribe.
   */
  subscribeHistoryPageResolved(
    listener: (chatId: string, outcome: 'page-loaded' | 'no-more' | 'rejected') => void
  ): number {
    return tdClient.subscribeHistoryPageResolved(listener);
  }

  /**
   * Unsubscribes a previously-registered history-page-resolved listener. Idempotent on the `0`
   * sentinel and on unknown tokens.
   *
   * @param token Subscription token returned by `subscribeHistoryPageResolved`.
   */
  unsubscribeHistoryPageResolved(token: number): void {
    tdClient.unsubscribeHistoryPageResolved(token);
  }

  /**
   * Drops the in-flight pull-token registration for `chatId` on the TdClient hub. Call from the
   * view's defensive-timeout path and from `aboutToDisappear` so a late TDLib response cannot
   * match a stale token and fire `historyPageResolved` after the view has already given up on
   * the pull cycle (or the user has left the page).
   *
   * @param chatId Chat identifier whose pending pull should be abandoned.
   */
  abandonPendingPull(chatId: string): void {
    tdClient.abandonPendingPull(chatId);
  }

  /**
   * Closes the in-flight older-history pull cycle on the routed page state and decides whether
   * the "no earlier messages" toast should fire. Pure function so the contract can be unit-tested
   * without touching the TdClient singleton.
   *
   * @param currentState Current routed chat-details page state.
   * @param outcome Resolution outcome reported by the TdClient hub.
   * @returns Page state with `isLoadingOlder=false` plus a flag whether the view should show the
   * "no earlier messages" toast.
   */
  applyHistoryPageResolved(
    currentState: ChatDetailsPageState,
    outcome: 'page-loaded' | 'no-more' | 'rejected'
  ): ChatDetailsHistoryPageResolution {
    return {
      nextPageState: {
        chatId: currentState.chatId,
        chatTitle: currentState.chatTitle,
        chatUsername: currentState.chatUsername,
        messages: currentState.messages,
        pageMode: currentState.pageMode,
        isLoadingMessages: currentState.isLoadingMessages,
        isLoadingOlder: false
      },
      shouldShowNoOlderHistoryToast: outcome === 'no-more'
    };
  }

  /**
   * Marks currently rendered timeline messages as viewed/read.
   *
   * @param chatId The chat identifier.
   * @param messages Messages currently rendered in the timeline.
   */
  viewMessages(chatId: string, messages: TdChatMessageItem[]): void {
    tdClient.viewMessages(chatId, messages);
  }

  /**
   * Trims the shared TGS cache.
   *
   * @param maxEntries The maximum hot-entry count.
   * @param maxBytes The maximum cache size in bytes.
   */
  trimTgsCache(maxEntries: number, maxBytes: number): void {
    trimTgsLottieCache(maxEntries, maxBytes);
  }

  /**
   * Stores the last non-latest visible timeline message for one chat. A latest-position leave
   * clears the saved anchor so the next visit can keep the normal "open at latest" behavior.
   *
   * @param chatId The routed chat identifier.
   * @param messageId The visible message id to restore on the next visit.
   * @param isAtLatest Whether the viewport was parked at the latest message.
   */
  saveScrollAnchor(chatId: string, messageId: string, isAtLatest: boolean): void {
    const safeMessageId = messageId.trim();
    if (safeMessageId.length === 0) {
      return;
    }
    if (isAtLatest) {
      chatDetailsScrollAnchorStore.clear(chatId);
      return;
    }
    chatDetailsScrollAnchorStore.save(chatId, safeMessageId);
  }

  /**
   * Clears the stored scroll anchor for one chat.
   *
   * @param chatId The routed chat identifier.
   */
  clearScrollAnchor(chatId: string): void {
    chatDetailsScrollAnchorStore.clear(chatId);
  }

  /**
   * Returns the saved scroll-anchor message id that can be restored for this route visit.
   * Deeplinks own the scroll target, so a pending deeplink suppresses stored-anchor restore.
   *
   * @param chatId The routed chat identifier.
   * @param pendingInitialMessageId Pending notification/deeplink target, if any.
   * @returns The restorable message id, or an empty string when no restore should run.
   */
  getRestorableScrollAnchorMessageId(chatId: string, pendingInitialMessageId: string): string {
    if (pendingInitialMessageId.trim().length > 0) {
      return '';
    }
    return chatDetailsScrollAnchorStore.getMessageId(chatId);
  }

  /**
   * Selects the message id that should be persisted as the next re-entry scroll anchor.
   *
   * @param anchorState Latest visible-anchor snapshot from the view.
   * @returns Persist plan. `shouldPersist=false` means the view does not know enough to update
   * the stored anchor, so the previous value should be left untouched.
   */
  selectPersistableScrollAnchor(
    anchorState: ChatDetailsVisibleScrollAnchorState
  ): ChatDetailsPersistableScrollAnchorPlan {
    const explicitReturnAnchorMessageId = anchorState.explicitReturnAnchorMessageId.trim();
    if (explicitReturnAnchorMessageId.length > 0) {
      return {
        shouldPersist: true,
        messageId: explicitReturnAnchorMessageId,
        isAtLatest: false
      };
    }

    if (anchorState.shouldPersistLoadedTopAnchor || anchorState.lastVisibleWasAtTop) {
      const topMessageId = anchorState.topMessageId.trim();
      if (topMessageId.length > 0) {
        return {
          shouldPersist: true,
          messageId: topMessageId,
          isAtLatest: false
        };
      }
    }

    const centerMessageId = anchorState.lastVisibleCenterMessageId.trim();
    if (centerMessageId.length > 0) {
      return {
        shouldPersist: true,
        messageId: centerMessageId,
        isAtLatest: anchorState.lastVisibleWasAtLatest
      };
    }

    const startMessageId = anchorState.lastVisibleStartMessageId.trim();
    if (startMessageId.length > 0) {
      return {
        shouldPersist: true,
        messageId: startMessageId,
        isAtLatest: anchorState.lastVisibleWasAtLatest
      };
    }

    const endMessageId = anchorState.lastVisibleEndMessageId.trim();
    if (endMessageId.length > 0) {
      return {
        shouldPersist: true,
        messageId: endMessageId,
        isAtLatest: anchorState.lastVisibleWasAtLatest
      };
    }

    const persistedScrollAnchorMessageId = anchorState.persistedScrollAnchorMessageId.trim();
    if (persistedScrollAnchorMessageId.length > 0) {
      return {
        shouldPersist: true,
        messageId: persistedScrollAnchorMessageId,
        isAtLatest: false
      };
    }

    return {
      shouldPersist: false,
      messageId: '',
      isAtLatest: false
    };
  }

  /**
   * Creates typed route params for the compose-message screen.
   *
   * @param currentState The current chat-details page state.
   * @returns The routed compose-message params.
   */
  createComposeRouteParams(currentState: ChatDetailsPageState): ChatRouteParams {
    return createChatRouteParams(currentState.chatId, currentState.chatTitle, currentState.chatUsername);
  }

  /**
   * Creates typed route params for the message-recorder screen.
   *
   * @param currentState The current chat-details page state.
   * @returns The routed message-recorder params.
   */
  createMessageRecorderRouteParams(currentState: ChatDetailsPageState): ChatRouteParams {
    return createChatRouteParams(currentState.chatId, currentState.chatTitle, currentState.chatUsername);
  }

  /**
   * Creates typed route params for the media-viewer screen from one timeline item.
   *
   * @param currentState The current chat-details page state.
   * @param message The selected timeline item.
   * @returns Routed media-viewer params or `undefined` when media kind is unsupported.
   */
  createMediaViewerRouteParams(
    currentState: ChatDetailsPageState,
    message: TdChatMessageItem
  ): MediaViewerRouteParams | undefined {
    return this.mediaViewerPageViewModel.createMediaViewerRouteParams(
      currentState.chatId,
      currentState.chatTitle,
      currentState.chatUsername,
      message
    );
  }

  /**
   * Creates typed route params for the read-only user-profile screen from one timeline item.
   *
   * @param message The selected timeline item.
   * @returns Routed user-profile params or `undefined` when sender profile is unavailable.
   */
  createUserProfileRouteParams(message: TdChatMessageItem): ProfileRouteParams | undefined {
    const senderUserId = this.normalizeSenderUserId(message.senderUserId);
    if (senderUserId.length === 0) {
      return undefined;
    }

    return this.mapUserProfileRouteParams(
      senderUserId,
      tdClient.getUserProfile(senderUserId),
      message.senderAvatarPath
    );
  }

  /**
   * Maps one cached sender profile to router params used by the read-only user-profile screen.
   *
   * @param senderUserId The normalized sender identifier.
   * @param cachedProfile The cached sender profile snapshot.
   * @param messageAvatarPath The message-level avatar path fallback.
   * @returns Routed user-profile params or `undefined` when profile data is unavailable.
   */
  mapUserProfileRouteParams(
    senderUserId: string,
    cachedProfile: TdUserProfileItem | undefined,
    messageAvatarPath: string | undefined
  ): ProfileRouteParams | undefined {
    const safeUserId = senderUserId.trim();
    if (safeUserId.length === 0 || !cachedProfile) {
      return undefined;
    }

    const avatarPath = this.resolveProfileAvatarPath(cachedProfile, messageAvatarPath);
    return {
      id: safeUserId,
      firstName: cachedProfile.firstName,
      lastName: cachedProfile.lastName,
      username: this.normalizeRouteUsername(cachedProfile.username),
      phoneNumber: cachedProfile.phoneNumber,
      avatarPath: avatarPath,
      avatarAnimationPath: this.optionalPath(cachedProfile.avatarAnimationPath)
    };
  }

  /**
   * Creates the placeholder state shown before the routed page binds live timeline data.
   *
   * @returns The initial chat-details page state.
   */
  createInitialState(): ChatDetailsPageState {
    return {
      chatId: '',
      chatTitle: '',
      chatUsername: '',
      messages: [],
      pageMode: ChatDetailsPageMode.Idle,
      isLoadingMessages: false,
      isLoadingOlder: false
    };
  }

  /**
   * Applies routed chat-details parameters to presentation-safe state. Loading flags are reset
   * because any in-flight request from a previous page session targets a different chat (or a
   * resolution that already missed its UI window) — keeping them would block the next pull cycle.
   *
   * @param currentState The current chat-details page state.
   * @param chatId The routed chat identifier.
   * @param chatTitle The routed chat title.
   * @param chatUsername The routed chat username.
   * @returns The updated chat-details page state.
   */
  applyRoute(
    currentState: ChatDetailsPageState,
    chatId: string,
    chatTitle: string,
    chatUsername: string
  ): ChatDetailsPageState {
    return {
      chatId: chatId.length > 0 ? chatId : currentState.chatId,
      chatTitle: chatTitle.length > 0 ? chatTitle : currentState.chatTitle,
      chatUsername: chatUsername.length > 0 ? chatUsername : currentState.chatUsername,
      messages: currentState.messages,
      pageMode: currentState.pageMode,
      isLoadingMessages: false,
      isLoadingOlder: false
    };
  }

  /**
   * Creates the transient loading state used while the page refreshes timeline data.
   *
   * @param currentState The current chat-details page state.
   * @returns The updated chat-details page state.
   */
  createLoadingMessagesState(currentState: ChatDetailsPageState): ChatDetailsPageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      messages: currentState.messages,
      pageMode: currentState.messages.length > 0 ? ChatDetailsPageMode.Ready : ChatDetailsPageMode.Loading,
      isLoadingMessages: true,
      isLoadingOlder: currentState.isLoadingOlder
    };
  }

  /**
   * Creates the transient loading state used while the page loads older messages.
   *
   * @param currentState The current chat-details page state.
   * @returns The updated chat-details page state.
   */
  createLoadingOlderState(currentState: ChatDetailsPageState): ChatDetailsPageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      messages: currentState.messages,
      pageMode: currentState.pageMode,
      isLoadingMessages: currentState.isLoadingMessages,
      isLoadingOlder: true
    };
  }

  /**
   * Plans one full timeline refresh request.
   *
   * @param currentState The current chat-details page state.
   * @param limit The requested history limit.
   * @returns The next state and request decision.
   */
  planRefresh(currentState: ChatDetailsPageState, limit: number): ChatDetailsRefreshPlan {
    if (currentState.chatId.length === 0) {
      return {
        nextPageState: this.applyMessages(currentState, []),
        shouldRequestHistory: false,
        requestLimit: limit
      };
    }

    return {
      nextPageState: this.createLoadingMessagesState(currentState),
      shouldRequestHistory: true,
      requestLimit: limit
    };
  }

  /**
   * Plans one older-history request. When the chat id is missing the plan refuses the request and
   * keeps the page state untouched (no spurious `isLoadingOlder=true` and no clone-of-clone).
   *
   * @param currentState The current chat-details page state.
   * @returns The next state and request decision.
   */
  planOlderHistoryLoad(currentState: ChatDetailsPageState): ChatDetailsOlderHistoryPlan {
    if (currentState.chatId.length === 0) {
      return {
        nextPageState: currentState,
        chatId: '',
        shouldRequestOlderHistory: false
      };
    }

    return {
      nextPageState: this.createLoadingOlderState(currentState),
      chatId: currentState.chatId,
      shouldRequestOlderHistory: true
    };
  }

  /**
   * Resets the older-history loading flag without touching `messages`. Used when the requested
   * older-history page was rejected upstream or when the page-side timeout fires before TDLib
   * answers.
   *
   * @param currentState The current chat-details page state.
   * @returns The state with `isLoadingOlder=false` and the same `messages` reference.
   */
  clearOlderHistoryLoading(currentState: ChatDetailsPageState): ChatDetailsPageState {
    if (!currentState.isLoadingOlder) {
      return currentState;
    }
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      messages: currentState.messages,
      pageMode: currentState.pageMode,
      isLoadingMessages: currentState.isLoadingMessages,
      isLoadingOlder: false
    };
  }

  /**
   * Applies one timeline snapshot to presentation-safe chat-details state. PRESERVES
   * `isLoadingOlder` so a live update (or any non-pull `chatMessages` emit) that arrives
   * mid-pull cannot close the pull spinner ahead of the actual page response — the pull cycle
   * is closed by `applyHistoryPageResolved` after the correlated TdClient hub event.
   * Closes the initial-load spinner (`isLoadingMessages=false`) unconditionally: TdClient
   * populates `messagesByChatId` before emitting (see `handleChatHistory`), so the first
   * `applyMessages` always represents a real response — an empty snapshot here means the
   * chat is genuinely empty, not "still loading". Avatar `refreshMessagesForUser` cannot
   * race the initial load to empty either, because it only emits for chats that already
   * have a cache entry.
   *
   * @param currentState The current chat-details page state.
   * @param items The latest timeline payload.
   * @returns The updated chat-details page state.
   */
  applyMessages(currentState: ChatDetailsPageState, items: TdChatMessageItem[]): ChatDetailsPageState {
    const clonedMessages = this.cloneMessages(items);
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      messages: clonedMessages,
      pageMode: clonedMessages.length > 0 ? ChatDetailsPageMode.Ready : ChatDetailsPageMode.Empty,
      isLoadingMessages: false,
      isLoadingOlder: currentState.isLoadingOlder
    };
  }

  /**
   * Decides whether the older-history pull timeout that just fired should still act on the page
   * state. Returns `true` only when the chat the user was on when the timer was armed is still
   * the routed chat AND a pull cycle is still in flight (`isLoadingOlder=true`). Used by the view
   * to skip the timeout body when the user has navigated away or the pull already resolved.
   *
   * @param currentChatId The chat currently displayed by the view.
   * @param scheduledChatId The chat the timeout was armed for.
   * @param isLoadingOlder Whether a pull cycle is still in flight.
   * @returns `true` when the timeout body should run.
   */
  shouldProcessOlderHistoryTimeout(currentChatId: string, scheduledChatId: string, isLoadingOlder: boolean): boolean {
    return currentChatId === scheduledChatId && isLoadingOlder;
  }

  /**
   * Decides whether the deeplink give-up timer that just fired should clear the pending target.
   * Returns `true` only when the routed chat still matches the scheduled chat AND the pending
   * target id still matches the one the timer was armed for — guards against navigation away
   * and against a fresh deeplink request superseding the original target.
   *
   * @param currentChatId The chat currently displayed by the view.
   * @param scheduledChatId The chat the timeout was armed for.
   * @param currentPendingTargetMessageId The currently pending deeplink target id.
   * @param scheduledTargetMessageId The deeplink target id the timer was armed for.
   * @returns `true` when the give-up body should run.
   */
  shouldGiveUpOnDeeplink(
    currentChatId: string,
    scheduledChatId: string,
    currentPendingTargetMessageId: string,
    scheduledTargetMessageId: string
  ): boolean {
    return currentChatId === scheduledChatId && currentPendingTargetMessageId === scheduledTargetMessageId;
  }

  /**
   * Decides whether the one-shot initial auto-scroll latch should fire for the current snapshot.
   * The latch exists to land the timeline at the latest message exactly once per page visit, on
   * the first real `Ready` snapshot with data. After that, list position is owned by the user
   * (or by follow-latest when the user is parked at the bottom — see `shouldFollowLatestOnSnapshot`).
   *
   * Why: the previous implementation re-fired `scrollToIndex(last)` on every `chatMessages` emit
   * AND on every `onPageShow`, which jumped the list to the end whenever a live update, delivery
   * refresh, avatar emit or return from a child route (MediaViewer, ComposeMessage, etc.) arrived
   * while the user was reading older messages. Reviewer #2389 flagged this as a UX regression.
   */
  shouldRunInitialAutoScrollLatch(
    hasPerformedInitialAutoScroll: boolean,
    pageMode: ChatDetailsPageMode,
    messageCount: number,
    pendingInitialMessageId: string,
    pullInFlight: boolean
  ): boolean {
    if (hasPerformedInitialAutoScroll) {
      return false;
    }
    if (pageMode !== ChatDetailsPageMode.Ready) {
      return false;
    }
    if (messageCount === 0) {
      return false;
    }
    if (pendingInitialMessageId.length > 0) {
      return false;
    }
    if (pullInFlight) {
      return false;
    }
    return true;
  }

  /**
   * Decides whether a `chatMessages` snapshot should trigger a follow-latest scroll. Follow-latest
   * is intent-driven: the user must already be parked at the bottom of the timeline, signaled by
   * `isAtLatest` (the view derives this from `ArcList.onScrollIndex`). Live updates, send-success
   * refreshes, and avatar re-emits arriving while the user is reading older messages must NOT
   * jump the list to the end.
   */
  shouldFollowLatestOnSnapshot(
    isAtLatest: boolean,
    pageMode: ChatDetailsPageMode,
    messageCount: number,
    pendingInitialMessageId: string,
    pullInFlight: boolean
  ): boolean {
    if (!isAtLatest) {
      return false;
    }
    if (pageMode !== ChatDetailsPageMode.Ready) {
      return false;
    }
    if (messageCount === 0) {
      return false;
    }
    if (pendingInitialMessageId.length > 0) {
      return false;
    }
    if (pullInFlight) {
      return false;
    }
    return true;
  }

  /**
   * Plans one auth-state reaction for the chat-details page.
   *
   * @param authState The latest TDLib authorization state.
   * @returns The redirect decision for the routed page.
   */
  planAuthStateChange(authState: string): ChatDetailsAuthStatePlan {
    return {
      shouldNavigateToIndex: authState !== 'authorizationStateReady',
      resetIndexNavigation: authState === 'authorizationStateReady'
    };
  }

  /**
   * Returns the stable render key for one message row.
   *
   * @param message The timeline item.
   * @returns The row render key.
   */
  messageRenderKey(message: TdChatMessageItem): string {
    const outgoingFlag = message.isOutgoing ? '1' : '0';
    const senderAvatarPath = message.senderAvatarPath ? message.senderAvatarPath : '';
    const kind = message.kind ? message.kind : '';
    const mediaLocalPath = message.mediaLocalPath ? message.mediaLocalPath : '';
    const mediaThumbPath = message.mediaThumbPath ? message.mediaThumbPath : '';
    const sendingState = message.sendingState ? message.sendingState : '';
    const deliveryState = message.deliveryState ? message.deliveryState : '';
    return `${message.id}:${message.date}:${outgoingFlag}:${senderAvatarPath}:${kind}:${mediaLocalPath}:${mediaThumbPath}:${sendingState}:${deliveryState}`;
  }

  /**
   * Finds one message index in the current timeline.
   *
   * @param items Timeline items.
   * @param messageId Message id to locate.
   * @returns Zero-based message index or `-1` when not found.
   */
  findMessageIndexById(items: TdChatMessageItem[], messageId: string): number {
    const safeMessageId = messageId.trim();
    if (safeMessageId.length === 0) {
      return -1;
    }

    for (let index = 0; index < items.length; index++) {
      if (items[index].id === safeMessageId) {
        return index;
      }
    }
    return -1;
  }

  /**
   * Returns whether a resolved deeplink target can stop blocking latest-message auto-scroll.
   *
   * A single-message timeline may be TDLib's sparse anchor response. Keep the target pending
   * until the follow-up latest-page refresh merges a fuller timeline, then scroll to the target
   * again and clear it.
   *
   * @param messageCount Current timeline size.
   * @returns `true` when the deeplink target can be considered fully resolved.
   */
  shouldClearInitialMessageScroll(messageCount: number): boolean {
    return messageCount > 1;
  }

  /**
   * Returns the sender label rendered in the message bubble avatar fallback.
   *
   * @param chatTitle The current chat title.
   * @param message The timeline item.
   * @returns The sender label.
   */
  senderLabel(chatTitle: string, message: TdChatMessageItem, cachedProfile?: TdUserProfileItem): string {
    if (message.isOutgoing) {
      return 'Me';
    }

    const senderUserId = this.normalizeSenderUserId(message.senderUserId);
    if (senderUserId.length > 0) {
      const resolvedProfile = cachedProfile ? cachedProfile : tdClient.getUserProfile(senderUserId);
      const profileLabel = this.profileDisplayLabel(resolvedProfile);
      if (profileLabel.length > 0) {
        return profileLabel;
      }
    }

    const trimmedTitle = chatTitle.trim();
    if (trimmedTitle.length > 0) {
      return trimmedTitle;
    }

    return '?';
  }

  /**
   * Returns deterministic palette index for one message-bubble avatar fallback.
   *
   * @param chatTitle The current chat title.
   * @param message The timeline item.
   * @returns Palette index in range `0..7`.
   */
  senderAvatarPaletteIndex(chatTitle: string, message: TdChatMessageItem): number {
    if (typeof message.senderUserId === 'string' && message.senderUserId.length > 0) {
      return textSignature(message.senderUserId) % 8;
    }

    const senderLabel = this.senderLabel(chatTitle, message).trim();
    if (senderLabel.length > 0) {
      return textSignature(senderLabel) % 8;
    }
    return 0;
  }

  /**
   * Formats one message timestamp for the bubble footer.
   *
   * @param unixSeconds The unix timestamp in seconds.
   * @returns The formatted time label.
   */
  formatMessageTime(unixSeconds: number): string {
    if (unixSeconds <= 0) {
      return '--:--';
    }
    const date = new Date(unixSeconds * 1000);
    const hours = date.getHours();
    const minutes = date.getMinutes();
    const hoursText = hours < 10 ? `0${hours}` : `${hours}`;
    const minutesText = minutes < 10 ? `0${minutes}` : `${minutes}`;
    return `${hoursText}:${minutesText}`;
  }

  private normalizeSenderUserId(senderUserId: string | undefined): string {
    if (typeof senderUserId !== 'string') {
      return '';
    }
    return senderUserId.trim();
  }

  private profileDisplayLabel(cachedProfile: TdUserProfileItem | undefined): string {
    if (!cachedProfile) {
      return '';
    }

    const fullName = `${cachedProfile.firstName} ${cachedProfile.lastName}`.trim();
    if (fullName.length > 0) {
      return fullName;
    }

    return this.normalizeRouteUsername(cachedProfile.username).trim();
  }

  private normalizeRouteUsername(username: string): string {
    const trimmedUsername = username.trim();
    if (trimmedUsername.startsWith('@')) {
      return trimmedUsername.substring(1);
    }
    return trimmedUsername;
  }

  private resolveProfileAvatarPath(cachedProfile: TdUserProfileItem, messageAvatarPath: string | undefined): string {
    if (typeof cachedProfile.avatarPath === 'string' && cachedProfile.avatarPath.length > 0) {
      return cachedProfile.avatarPath;
    }
    return this.optionalPath(messageAvatarPath);
  }

  private optionalPath(path: string | undefined): string {
    if (typeof path !== 'string') {
      return '';
    }
    return path;
  }

  /**
   * Creates a deep-enough clone of one TDLib message list for ArkUI state ownership.
   *
   * @param items The TDLib message payload.
   * @returns The cloned timeline payload.
   */
  private cloneMessages(items: TdChatMessageItem[]): TdChatMessageItem[] {
    const clonedMessages: TdChatMessageItem[] = [];
    for (let index = 0; index < items.length; index += 1) {
      const item = items[index];
      clonedMessages.push({
        id: item.id,
        chatId: item.chatId,
        senderUserId: item.senderUserId,
        senderChatId: item.senderChatId,
        senderAvatarPath: item.senderAvatarPath,
        sendingState: item.sendingState,
        deliveryState: item.deliveryState,
        kind: item.kind,
        text: item.text,
        textValue: item.textValue ? {
          resourceName: item.textValue.resourceName,
          rawText: item.textValue.rawText,
          args: [...item.textValue.args]
        } : undefined,
        caption: item.caption,
        mediaFileId: item.mediaFileId,
        mediaThumbFileId: item.mediaThumbFileId,
        mediaMinithumbnailData: item.mediaMinithumbnailData,
        mediaLocalPath: item.mediaLocalPath,
        mediaThumbPath: item.mediaThumbPath,
        mediaWidth: item.mediaWidth,
        mediaHeight: item.mediaHeight,
        mediaMimeType: item.mediaMimeType,
        mediaIsAnimated: item.mediaIsAnimated,
        mediaDurationSec: item.mediaDurationSec,
        voiceNoteWaveform: item.voiceNoteWaveform ? [...item.voiceNoteWaveform] : undefined,
        voiceNoteIsListened: item.voiceNoteIsListened,
        callEventStatus: item.callEventStatus,
        callEventDurationSec: item.callEventDurationSec,
        callEventIsVideo: item.callEventIsVideo,
        isOutgoing: item.isOutgoing,
        date: item.date
      });
    }

    return clonedMessages;
  }

}
