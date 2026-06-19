import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { TdChatMessageItem } from '../models/td/TdViewTypes';
import { ChatMessageListItem } from '../ui/ChatMessageListItem';
import { RoundIconActionButton } from '../ui/RoundIconActionButton';
import { VoiceNotePlaybackRequest, VoiceNotePlaybackSnapshot } from '../services/media/VoiceNotePlaybackController';
import {
  ArcList,
  ArcScrollBar
} from '@kit.ArkUI';
import { ChatDetailsPageMode, ChatDetailsPageState } from '../models/chat/ChatDetailsPageState';
import {
  ChatDetailsPageViewModel,
  DEEPLINK_GIVE_UP_TIMEOUT_MS,
  OLDER_HISTORY_PULL_TIMEOUT_MS
} from '../viewmodel/ChatDetailsPageViewModel';

const DOMAIN = 0x2026;
const TAG = 'ChatDetailsPage';
const CHAT_HISTORY_INITIAL_LIMIT = 50;
const CHAT_DETAILS_ARC_LIST_CACHED_COUNT = CHAT_HISTORY_INITIAL_LIMIT;
const TGS_CACHE_MAX_FILES = 8;
const TGS_CACHE_MAX_BYTES = 2 * 1024 * 1024;
// Timeout constants and their "should-act" predicates live in the ViewModel module
// (`OLDER_HISTORY_PULL_TIMEOUT_MS`, `DEEPLINK_GIVE_UP_TIMEOUT_MS`,
// `shouldProcessOlderHistoryTimeout`, `shouldGiveUpOnDeeplink`) so the decisions stay testable
// as pure functions. The view only owns the scheduling mechanism (setTimeout/clearTimeout).

interface ChatDetailsParams {
  chatId?: string;
  chatTitle?: string;
  chatUsername?: string;
  initialMessageId?: string;
}

@Entry
@Component
struct ChatDetails {
  private readonly viewModel: ChatDetailsPageViewModel = new ChatDetailsPageViewModel();
  private readonly initialPageState: ChatDetailsPageState = this.viewModel.createInitialState();
  @State chatId: string = this.initialPageState.chatId;
  @State chatTitle: string = this.initialPageState.chatTitle;
  @State chatUsername: string = this.initialPageState.chatUsername;
  @State messages: TdChatMessageItem[] = this.initialPageState.messages;
  @State pageMode: ChatDetailsPageMode = this.initialPageState.pageMode;
  @State isLoadingMessages: boolean = this.initialPageState.isLoadingMessages;
  @State isLoadingOlder: boolean = this.initialPageState.isLoadingOlder;
  @State voiceNotePlayback: VoiceNotePlaybackSnapshot = this.viewModel.createInitialVoiceNotePlaybackSnapshot();
  // Reactive gate for ArcScrollBar visibility. Flipped `true` the moment the user starts a
  // scroll gesture (touch/crown) on the ArcList — bound to `.onScrollStart(...)` below.
  // Programmatic scrolls (`scrollToIndex(_, false, _)` without animation) don't fire
  // `onScrollStart`, so the bar stays unmounted during initial-latch / deeplink /
  // return-anchor flows. Reset on each `aboutToAppear` so a fresh page visit starts hidden.
  @State hasUserInitiatedScroll: boolean = false;
  // Initial auto-scroll latch — fires `scrollToIndex(last)` exactly once per `aboutToAppear`,
  // on the first real `Ready` snapshot with data. Subsequent snapshots only follow-latest if
  // the user is parked at the bottom (`isAtLatest`). Decision lives in
  // `shouldRunInitialAutoScrollLatch` in the ViewModel. Reset on every `aboutToAppear`.
  private hasPerformedInitialAutoScroll: boolean = false;
  private messageScroller: Scroller = new Scroller();
  private hasNavigatedToIndex: boolean = false;
  private isPageVisible: boolean = false;
  private pendingInitialMessageId: string = '';
  // ----- Timer handles ------------------------------------------------------------------------
  // Convention for every `*TimeoutId` field below: `-1` means "no scheduled timer". Each timer
  // captures `this` via its setTimeout callback, but tear-down is centralized in
  // `aboutToDisappear` (one `cancel*` call per handle), so the closures never outlive the
  // component except in a process-kill scenario where heap unwinding is irrelevant. The
  // "should-act-when-fires" decision for each timer is delegated to a pure ViewModel predicate
  // (e.g. `shouldProcessOlderHistoryTimeout`, `shouldGiveUpOnDeeplink`) so the callback body
  // stays free of business rules. Add new timers by following the same field + cancel method
  // + aboutToDisappear cancel triplet, and put the predicate in the ViewModel.
  private pendingOlderHistoryTimeoutId: number = -1;
  // Re-entry guard for the pull lifecycle. View-owned, never written by the Refresh component,
  // so a duplicate `onRefreshing` cannot start a second cycle while the first is still in flight.
  private pullInFlight: boolean = false;
  // Token for the chat-messages subscription on the TdClient fan-out hub. `0` means not subscribed.
  private chatMessagesSubscription: number = 0;
  // Token for the history-page-resolved subscription. Fires only when a pull cycle this view
  // initiated has been resolved by TDLib (page-loaded / no-more / rejected). `0` means detached.
  private historyPageResolvedSubscription: number = 0;
  // Pending timeout id for the latest-message auto-scroll.
  private initialScrollTimeoutId: number = -1;
  // Pending timeout id for notification deeplink scroll-to-message.
  private initialMessageScrollTimeoutId: number = -1;
  // Pending timeout id for the deeplink give-up safety net (see `DEEPLINK_GIVE_UP_TIMEOUT_MS`
  // and `shouldGiveUpOnDeeplink` in the ViewModel).
  private initialMessageGiveUpTimeoutId: number = -1;
  // Pending timeout id for the return-from-child-route anchor scroll (see `openMediaViewerPage`).
  private returnAnchorScrollTimeoutId: number = -1;
  // Follow-latest signal derived from `ArcList.onScrollIndex`. `true` means the last rendered
  // index is the final message; updates flip it when the user scrolls up. Default `true` so the
  // very first snapshot (empty list, `end=-1` interpreted as "at bottom") still latches.
  private isAtLatest: boolean = true;
  // Anchor message id captured when the user opens a child route that should preserve list
  // position on return (currently `MediaViewer`). `onPageShow` consumes it once, scrolling the
  // list to `findMessageIndexById(...)` with `ScrollAlign.CENTER` instead of jumping to latest.
  private returnAnchorMessageId: string = '';
  // Anchor restored across full ChatDetails re-entry. Unlike `returnAnchorMessageId`, this
  // survives component teardown through the ViewModel module-level store.
  private persistedScrollAnchorMessageId: string = '';
  private lastVisibleStartMessageId: string = '';
  private lastVisibleCenterMessageId: string = '';
  private lastVisibleEndMessageId: string = '';
  private lastVisibleWasAtLatest: boolean = true;
  private lastVisibleWasAtTop: boolean = false;
  private olderPullStartedAtTop: boolean = false;
  private shouldPersistLoadedTopAnchor: boolean = false;

  /**
   * Redirects to Index when current session is no longer authorized.
   *
   * @param state Current authorization state.
   */
  private redirectToIndexIfUnauthorized(state: string): void {
    const authStatePlan = this.viewModel.planAuthStateChange(state);
    if (authStatePlan.resetIndexNavigation) {
      this.hasNavigatedToIndex = false;
    }
    if (!authStatePlan.shouldNavigateToIndex) {
      return;
    }
    if (this.hasNavigatedToIndex) {
      return;
    }

    hilog.info(DOMAIN, TAG, 'Session is no longer authorized (state=%{public}s). Redirecting to Index.', state);
    try {
      this.hasNavigatedToIndex = true;
      this.getUIContext().getRouter().replaceUrl({
        url: 'pages/Index'
      });
    } catch (error) {
      this.hasNavigatedToIndex = false;
      hilog.error(DOMAIN, TAG, 'Failed to redirect ChatDetails to Index: %{public}s', String(error));
    }
  }

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle enter: ChatDetails');
    this.hasNavigatedToIndex = false;
    this.pullInFlight = false;
    // Fresh entry — initial latch must fire once on the next Ready snapshot, follow-latest
    // starts permissive, return anchor from a previous session is dropped, scrollbar hides until
    // any of the three scheduled scrolls (latest / deeplink / return-anchor) resolves.
    this.hasPerformedInitialAutoScroll = false;
    this.hasUserInitiatedScroll = false;
    this.isAtLatest = true;
    this.returnAnchorMessageId = '';
    this.persistedScrollAnchorMessageId = '';
    this.lastVisibleStartMessageId = '';
    this.lastVisibleCenterMessageId = '';
    this.lastVisibleEndMessageId = '';
    this.lastVisibleWasAtLatest = true;
    this.lastVisibleWasAtTop = false;
    this.olderPullStartedAtTop = false;
    this.shouldPersistLoadedTopAnchor = false;
    this.cancelPendingScrollToLatest();
    this.cancelPendingScrollToInitialMessage();
    this.cancelPendingScrollToReturnAnchor();
    const params = this.getUIContext().getRouter().getParams() as ChatDetailsParams;
    this.applyPageState(this.viewModel.applyRoute(
      this.currentPageState(),
      typeof params.chatId === 'string' ? params.chatId : '',
      typeof params.chatTitle === 'string' ? params.chatTitle : '',
      typeof params.chatUsername === 'string' ? params.chatUsername : ''
    ));
    if (typeof params.initialMessageId === 'string' && params.initialMessageId.length > 0) {
      this.pendingInitialMessageId = params.initialMessageId;
      hilog.info(DOMAIN, TAG, 'Initial deeplink message requested: %{public}s', params.initialMessageId);
    } else {
      this.pendingInitialMessageId = '';
    }
    this.persistedScrollAnchorMessageId =
      this.viewModel.getRestorableScrollAnchorMessageId(this.chatId, this.pendingInitialMessageId);
    if (this.persistedScrollAnchorMessageId.length > 0) {
      this.hasPerformedInitialAutoScroll = true;
      this.isAtLatest = false;
      this.lastVisibleWasAtLatest = false;
      hilog.info(
        DOMAIN,
        TAG,
        'Restoring persisted scroll anchor scheduled (chatId=%{public}s, messageId=%{public}s)',
        this.chatId,
        this.persistedScrollAnchorMessageId
      );
    }
    this.viewModel.dismissChatNotifications(this.chatId);

    this.chatMessagesSubscription = this.viewModel.subscribeChatMessages((chatId: string, items: TdChatMessageItem[]): void => {
      if (chatId !== this.chatId) {
        return;
      }
      // Snapshot-only path: applyMessages preserves `isLoadingOlder`. The pull lifecycle
      // (spinner close, defensive timeout cancel, toast trigger) is owned by the
      // historyPageResolved subscriber below so a live update mid-pull cannot close the cycle
      // before the actual page response arrives.
      const nextPageState = this.viewModel.applyMessages(this.currentPageState(), items);
      this.applyPageState(nextPageState);
      if (!this.scheduleScrollToInitialMessageIfNeeded() && !this.scheduleScrollToPersistedAnchorIfNeeded()) {
        // Two distinct scroll intents, both gated by pure VM predicates:
        //  - initial auto-scroll latch: fires once per page visit, on the first Ready snapshot
        //    with data, to land the user at the latest message;
        //  - follow-latest: keeps the user pinned to the bottom when they were already there
        //    and a live update / delivery / avatar emit arrives.
        // The previous unconditional `scheduleScrollToLatest()` was the regression flagged in
        // review #2389 (live updates / send-success refreshes jumping the list to the end while
        // the user was reading older messages).
        const messageCount = this.messages.length;
        if (this.viewModel.shouldRunInitialAutoScrollLatch(
          this.hasPerformedInitialAutoScroll,
          this.pageMode,
          messageCount,
          this.pendingInitialMessageId,
          this.pullInFlight
        )) {
          this.scheduleScrollToLatest();
        } else if (this.viewModel.shouldFollowLatestOnSnapshot(
          this.isAtLatest,
          this.pageMode,
          messageCount,
          this.pendingInitialMessageId,
          this.pullInFlight
        )) {
          this.scheduleScrollToLatest();
        }
      }
      this.markVisibleMessagesAsViewed('messages-update');
    });

    this.viewModel.setAuthStateListener((state: string): void => {
      this.redirectToIndexIfUnauthorized(state);
    });
    this.redirectToIndexIfUnauthorized(this.viewModel.getAuthorizationStateName());
    this.viewModel.setVoiceNotePlaybackListener((snapshot: VoiceNotePlaybackSnapshot): void => {
      this.voiceNotePlayback = snapshot;
    });
    this.historyPageResolvedSubscription = this.viewModel.subscribeHistoryPageResolved(
      (chatId: string, outcome: 'page-loaded' | 'no-more' | 'rejected'): void => {
        // TdClient only fires this event for chats that had a user-initiated pull in flight, so
        // no extra `pullInFlight` guard is needed — but we still gate on the routed chatId to
        // ignore events for chats this view isn't displaying.
        if (chatId !== this.chatId) {
          return;
        }
        this.cancelPendingOlderHistoryTimeout();
        const resolution = this.viewModel.applyHistoryPageResolved(this.currentPageState(), outcome);
        this.applyPageState(resolution.nextPageState);
        this.pullInFlight = false;
        this.captureTopAnchorAfterOlderPullIfNeeded(outcome);
        if (resolution.shouldShowNoOlderHistoryToast) {
          this.showNoOlderHistoryToast();
        }
      }
    );

    this.refreshMessages();
  }

  onPageShow(): void {
    this.isPageVisible = true;
    hilog.info(DOMAIN, TAG, 'Lifecycle show: ChatDetails');
    // Return from a child route (MediaViewer, ComposeMessage, MessageRecorder, UserProfile) is
    // NOT an "initial load" — the Scroller already holds the position the user left. The only
    // automatic scroll on page-show is either a pending deeplink (`pendingInitialMessageId`) or a
    // return anchor captured when opening MediaViewer. Anything else respects the preserved
    // Scroller position. Initial auto-scroll latch lives on `aboutToAppear` lifecycle and fires
    // from the `chatMessages` snapshot path (see `shouldRunInitialAutoScrollLatch`).
    if (!this.scheduleScrollToInitialMessageIfNeeded() && this.returnAnchorMessageId.length > 0) {
      this.scheduleScrollToReturnAnchor();
    } else if (this.persistedScrollAnchorMessageId.length > 0) {
      this.scheduleScrollToPersistedAnchorIfNeeded();
    }
    this.markVisibleMessagesAsViewed('page-show');
  }

  onPageHide(): void {
    this.isPageVisible = false;
    hilog.info(DOMAIN, TAG, 'Lifecycle hide: ChatDetails');
  }

  /**
   * Emits lifecycle log when leaving ChatDetails screen.
   */
  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle leave: ChatDetails');
    this.persistCurrentScrollAnchor();
    this.isPageVisible = false;
    this.cancelPendingOlderHistoryTimeout();
    this.cancelPendingScrollToLatest();
    this.cancelPendingScrollToInitialMessage();
    this.cancelPendingScrollToReturnAnchor();
    this.cancelDeeplinkGiveUpTimeout();
    // Re-entry safety lives in `applyRoute`, which drops both loading flags on the next
    // navigation (see `shouldResetIsLoadingOlderWhenApplyingRoute`). No state writes during
    // tear-down — only local non-@State teardown below.
    this.pullInFlight = false;
    // Keep cache bounded on wearable; preserve a small hot set for quick return to chat.
    this.viewModel.trimTgsCache(TGS_CACHE_MAX_FILES, TGS_CACHE_MAX_BYTES);
    // Drain any pending pull-token registration on the way out: the historyPageResolved
    // subscriber is about to be unsubscribed anyway, but cleaning up `pullTokenByChatId` keeps
    // the next visit's correlation from racing with a late response from the previous visit.
    this.viewModel.abandonPendingPull(this.chatId);
    this.viewModel.unsubscribeChatMessages(this.chatMessagesSubscription);
    this.chatMessagesSubscription = 0;
    this.viewModel.unsubscribeHistoryPageResolved(this.historyPageResolvedSubscription);
    this.historyPageResolvedSubscription = 0;
    this.viewModel.clearVoiceNotePlaybackListener();
    void this.viewModel.releaseVoiceNotePlayback();
  }

  private showNoOlderHistoryToast(): void {
    try {
      promptAction.showToast({
        message: $r('app.string.chat_details_no_older_history'),
        duration: 1500
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'showNoOlderHistoryToast failed: %{public}s', String(error));
    }
  }

  private cancelPendingOlderHistoryTimeout(): void {
    if (this.pendingOlderHistoryTimeoutId !== -1) {
      clearTimeout(this.pendingOlderHistoryTimeoutId);
      this.pendingOlderHistoryTimeoutId = -1;
    }
  }

  private persistCurrentScrollAnchor(): void {
    const anchorPlan = this.viewModel.selectPersistableScrollAnchor({
      explicitReturnAnchorMessageId: this.returnAnchorMessageId,
      persistedScrollAnchorMessageId: this.persistedScrollAnchorMessageId,
      topMessageId: this.messageIdAt(this.messages, 0),
      lastVisibleStartMessageId: this.lastVisibleStartMessageId,
      lastVisibleCenterMessageId: this.lastVisibleCenterMessageId,
      lastVisibleEndMessageId: this.lastVisibleEndMessageId,
      lastVisibleWasAtLatest: this.lastVisibleWasAtLatest,
      lastVisibleWasAtTop: this.lastVisibleWasAtTop,
      shouldPersistLoadedTopAnchor: this.shouldPersistLoadedTopAnchor
    });
    if (!anchorPlan.shouldPersist) {
      return;
    }

    this.viewModel.saveScrollAnchor(this.chatId, anchorPlan.messageId, anchorPlan.isAtLatest);
    hilog.info(
      DOMAIN,
      TAG,
      'Persisted scroll anchor candidate (chatId=%{public}s, messageId=%{public}s, isAtLatest=%{public}d)',
      this.chatId,
      anchorPlan.messageId,
      anchorPlan.isAtLatest ? 1 : 0
    );
  }

  private captureTopAnchorAfterOlderPullIfNeeded(outcome: 'page-loaded' | 'no-more' | 'rejected'): void {
    if (!this.olderPullStartedAtTop) {
      return;
    }
    this.olderPullStartedAtTop = false;
    if (outcome !== 'page-loaded' || this.messages.length === 0) {
      return;
    }

    const topMessageId = this.messageIdAt(this.messages, 0);
    this.lastVisibleStartMessageId = topMessageId;
    this.lastVisibleCenterMessageId = topMessageId;
    this.lastVisibleEndMessageId = topMessageId;
    this.lastVisibleWasAtLatest = false;
    this.lastVisibleWasAtTop = true;
    this.shouldPersistLoadedTopAnchor = true;
    hilog.info(
      DOMAIN,
      TAG,
      'Older pull top anchor refreshed (chatId=%{public}s, messageId=%{public}s, count=%{public}d)',
      this.chatId,
      topMessageId,
      this.messages.length
    );
  }

  private scheduleScrollToLatest(): void {
    if (this.pullInFlight) {
      return;
    }
    if (this.pendingInitialMessageId.length > 0) {
      return;
    }
    if (this.initialScrollTimeoutId !== -1) {
      clearTimeout(this.initialScrollTimeoutId);
      this.initialScrollTimeoutId = -1;
    }
    const scheduledChatId = this.chatId;
    this.initialScrollTimeoutId = setTimeout((): void => {
      this.initialScrollTimeoutId = -1;
      if (!this.isPageVisible || this.pullInFlight) {
        return;
      }
      if (this.chatId !== scheduledChatId) {
        return;
      }
      if (this.pendingInitialMessageId.length > 0) {
        return;
      }
      if (this.messages.length === 0 || this.pageMode !== ChatDetailsPageMode.Ready) {
        return;
      }
      const lastIndex = this.messages.length - 1;
      try {
        this.messageScroller.scrollToIndex(lastIndex, false, ScrollAlign.END);
        // Latch the initial auto-scroll exactly here: a successful programmatic scroll-to-latest
        // is what the latch was guarding. Follow-latest takes over from this point — driven by
        // `isAtLatest` (the user can break it by scrolling up) instead of "every snapshot wins".
        this.hasPerformedInitialAutoScroll = true;
        hilog.info(DOMAIN, TAG, 'Scrolled to latest (chatId=%{public}s, index=%{public}d)', scheduledChatId, lastIndex);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Scroll to latest failed: %{public}s', String(error));
      }
    }, 0);
  }

  private scheduleScrollToPersistedAnchorIfNeeded(): boolean {
    const targetMessageId = this.persistedScrollAnchorMessageId.trim();
    if (targetMessageId.length === 0) {
      return false;
    }
    if (this.messages.length === 0 || this.pageMode !== ChatDetailsPageMode.Ready) {
      return true;
    }

    const targetIndex = this.viewModel.findMessageIndexById(this.messages, targetMessageId);
    if (targetIndex < 0) {
      hilog.info(
        DOMAIN,
        TAG,
        'Persisted scroll anchor missing from snapshot; falling back to initial latest (chatId=%{public}s, messageId=%{public}s, count=%{public}d)',
        this.chatId,
        targetMessageId,
        this.messages.length
      );
      this.viewModel.clearScrollAnchor(this.chatId);
      this.persistedScrollAnchorMessageId = '';
      this.hasPerformedInitialAutoScroll = false;
      this.isAtLatest = true;
      return false;
    }

    this.cancelPendingScrollToLatest();
    this.cancelPendingScrollToReturnAnchor();
    const scheduledChatId = this.chatId;
    this.returnAnchorScrollTimeoutId = setTimeout((): void => {
      this.returnAnchorScrollTimeoutId = -1;
      if (!this.isPageVisible || this.chatId !== scheduledChatId) {
        return;
      }
      if (this.persistedScrollAnchorMessageId !== targetMessageId) {
        return;
      }
      if (this.pageMode !== ChatDetailsPageMode.Ready) {
        return;
      }

      const currentIndex = this.viewModel.findMessageIndexById(this.messages, targetMessageId);
      if (currentIndex < 0) {
        return;
      }

      try {
        this.messageScroller.scrollToIndex(currentIndex, false, ScrollAlign.CENTER);
        this.hasPerformedInitialAutoScroll = true;
        this.isAtLatest = false;
        this.persistedScrollAnchorMessageId = '';
        hilog.info(
          DOMAIN,
          TAG,
          'Scrolled to persisted anchor (chatId=%{public}s, messageId=%{public}s, index=%{public}d)',
          scheduledChatId,
          targetMessageId,
          currentIndex
        );
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Scroll to persisted anchor failed: %{public}s', String(error));
      }
    }, 0);
    return true;
  }

  private cancelPendingScrollToReturnAnchor(): void {
    if (this.returnAnchorScrollTimeoutId !== -1) {
      clearTimeout(this.returnAnchorScrollTimeoutId);
      this.returnAnchorScrollTimeoutId = -1;
    }
  }

  private scheduleScrollToReturnAnchor(): void {
    const targetMessageId = this.returnAnchorMessageId;
    if (targetMessageId.length === 0) {
      return;
    }
    this.cancelPendingScrollToReturnAnchor();
    const scheduledChatId = this.chatId;
    this.returnAnchorScrollTimeoutId = setTimeout((): void => {
      this.returnAnchorScrollTimeoutId = -1;
      if (!this.isPageVisible || this.chatId !== scheduledChatId) {
        return;
      }
      if (this.returnAnchorMessageId !== targetMessageId) {
        return;
      }
      if (this.messages.length === 0 || this.pageMode !== ChatDetailsPageMode.Ready) {
        return;
      }
      const targetIndex = this.viewModel.findMessageIndexById(this.messages, targetMessageId);
      if (targetIndex < 0) {
        // Anchor message is no longer in the cached timeline (cache eviction, force-kill, etc.).
        // Preferred fallback is "keep the Scroller's current position" — the regression was
        // jumping to latest on every `onPageShow`, which is exactly what we must avoid.
        this.returnAnchorMessageId = '';
        return;
      }
      try {
        this.messageScroller.scrollToIndex(targetIndex, false, ScrollAlign.CENTER);
        hilog.info(
          DOMAIN,
          TAG,
          'Scrolled to return anchor (chatId=%{public}s, messageId=%{public}s, index=%{public}d)',
          scheduledChatId,
          targetMessageId,
          targetIndex
        );
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Scroll to return anchor failed: %{public}s', String(error));
      }
      this.returnAnchorMessageId = '';
    }, 0);
  }

  private scheduleScrollToInitialMessageIfNeeded(): boolean {
    const targetMessageId = this.pendingInitialMessageId.trim();
    if (targetMessageId.length === 0) {
      return false;
    }
    if (this.messages.length === 0 || this.pageMode !== ChatDetailsPageMode.Ready) {
      return true;
    }

    const targetIndex = this.viewModel.findMessageIndexById(this.messages, targetMessageId);
    if (targetIndex < 0) {
      return true;
    }

    this.cancelPendingScrollToLatest();
    this.cancelPendingScrollToInitialMessage();
    const scheduledChatId = this.chatId;
    this.initialMessageScrollTimeoutId = setTimeout((): void => {
      this.initialMessageScrollTimeoutId = -1;
      if (!this.isPageVisible || this.chatId !== scheduledChatId) {
        return;
      }
      if (this.pendingInitialMessageId.trim() !== targetMessageId) {
        return;
      }
      if (this.pageMode !== ChatDetailsPageMode.Ready) {
        return;
      }

      const currentIndex = this.viewModel.findMessageIndexById(this.messages, targetMessageId);
      if (currentIndex < 0) {
        return;
      }

      try {
        this.messageScroller.scrollToIndex(currentIndex, false, ScrollAlign.CENTER);
        if (this.viewModel.shouldClearInitialMessageScroll(this.messages.length)) {
          this.pendingInitialMessageId = '';
          this.cancelDeeplinkGiveUpTimeout();
        }
        hilog.info(
          DOMAIN,
          TAG,
          'Scrolled to deeplink message (chatId=%{public}s, messageId=%{public}s, index=%{public}d)',
          scheduledChatId,
          targetMessageId,
          currentIndex
        );
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Scroll to deeplink message failed: %{public}s', String(error));
      }
    }, 0);
    return true;
  }

  private cancelPendingScrollToLatest(): void {
    if (this.initialScrollTimeoutId !== -1) {
      clearTimeout(this.initialScrollTimeoutId);
      this.initialScrollTimeoutId = -1;
    }
  }

  private cancelPendingScrollToInitialMessage(): void {
    if (this.initialMessageScrollTimeoutId !== -1) {
      clearTimeout(this.initialMessageScrollTimeoutId);
      this.initialMessageScrollTimeoutId = -1;
    }
  }

  private refreshMessages(): void {
    const refreshPlan = this.viewModel.planRefresh(this.currentPageState(), CHAT_HISTORY_INITIAL_LIMIT);
    this.applyPageState(refreshPlan.nextPageState);
    if (refreshPlan.shouldRequestHistory) {
      if (this.pendingInitialMessageId.length > 0) {
        this.armDeeplinkGiveUpTimeout(this.pendingInitialMessageId);
        this.viewModel.requestChatHistoryFromMessage(this.chatId, refreshPlan.requestLimit, this.pendingInitialMessageId);
        return;
      }
      this.viewModel.requestChatHistory(this.chatId, refreshPlan.requestLimit);
    }
  }

  /**
   * Arms the deeplink safety net: if the target message hasn't been located inside
   * DEEPLINK_GIVE_UP_TIMEOUT_MS, clear `pendingInitialMessageId` so subsequent emits are no
   * longer blocked from running `scheduleScrollToLatest`. The "should-give-up" decision lives
   * in `viewModel.shouldGiveUpOnDeeplink` to keep this body free of business rules.
   */
  private armDeeplinkGiveUpTimeout(targetMessageId: string): void {
    this.cancelDeeplinkGiveUpTimeout();
    const scheduledChatId = this.chatId;
    this.initialMessageGiveUpTimeoutId = setTimeout((): void => {
      this.initialMessageGiveUpTimeoutId = -1;
      if (!this.viewModel.shouldGiveUpOnDeeplink(
        this.chatId,
        scheduledChatId,
        this.pendingInitialMessageId,
        targetMessageId
      )) {
        return;
      }
      hilog.info(DOMAIN, TAG,
        'Deeplink target not located within %{public}d ms — giving up (chatId=%{public}s, messageId=%{public}s)',
        DEEPLINK_GIVE_UP_TIMEOUT_MS,
        scheduledChatId,
        targetMessageId
      );
      this.pendingInitialMessageId = '';
      this.scheduleScrollToLatest();
    }, DEEPLINK_GIVE_UP_TIMEOUT_MS);
  }

  private cancelDeeplinkGiveUpTimeout(): void {
    if (this.initialMessageGiveUpTimeoutId !== -1) {
      clearTimeout(this.initialMessageGiveUpTimeoutId);
      this.initialMessageGiveUpTimeoutId = -1;
    }
  }

  private markVisibleMessagesAsViewed(reason: string): void {
    if (!this.isPageVisible) {
      hilog.debug(DOMAIN, TAG, 'Skip viewMessages: page not visible (reason=%{public}s, chatId=%{public}s)',
        reason,
        this.chatId
      );
      return;
    }
    this.viewModel.viewMessages(this.chatId, this.messages);
  }

  private loadOlderMessagesByPull(): void {
    if (this.pullInFlight) {
      hilog.warn(DOMAIN, TAG, 'Older history pull ignored: cycle already in-flight (chatId=%{public}s)', this.chatId);
      return;
    }

    const olderHistoryPlan = this.viewModel.planOlderHistoryLoad(this.currentPageState());
    if (!olderHistoryPlan.shouldRequestOlderHistory) {
      this.applyPageState(olderHistoryPlan.nextPageState);
      return;
    }

    this.pullInFlight = true;
    this.olderPullStartedAtTop = this.lastVisibleWasAtTop;
    this.applyPageState(olderHistoryPlan.nextPageState);
    const outcome = this.viewModel.requestOlderChatHistory(olderHistoryPlan.chatId);
    hilog.info(DOMAIN, TAG, 'Older history request by pull (chatId=%{public}s, outcome=%{public}s)',
      olderHistoryPlan.chatId,
      outcome
    );

    if (outcome !== 'started') {
      this.applyPageState(this.viewModel.clearOlderHistoryLoading(this.currentPageState()));
      this.pullInFlight = false;
      this.olderPullStartedAtTop = false;
      if (outcome === 'no-more-pages') {
        this.showNoOlderHistoryToast();
      }
      return;
    }

    this.cancelPendingOlderHistoryTimeout();
    const scheduledChatId = this.chatId;
    this.pendingOlderHistoryTimeoutId = setTimeout((): void => {
      this.pendingOlderHistoryTimeoutId = -1;
      if (!this.viewModel.shouldProcessOlderHistoryTimeout(this.chatId, scheduledChatId, this.isLoadingOlder)) {
        return;
      }
      hilog.warn(DOMAIN, TAG, 'Older history pull timed out (chatId=%{public}s)', scheduledChatId);
      this.applyPageState(this.viewModel.clearOlderHistoryLoading(this.currentPageState()));
      this.pullInFlight = false;
      // Drain the TdClient-side pull-token registration so a late response cannot match it and
      // fire `historyPageResolved` for a pull the view has already abandoned.
      this.viewModel.abandonPendingPull(scheduledChatId);
    }, OLDER_HISTORY_PULL_TIMEOUT_MS);
  }

  /**
   * Returns the current mapped chat-details page state snapshot.
   *
   * @returns The current chat-details page state.
   */
  private currentPageState(): ChatDetailsPageState {
    return {
      chatId: this.chatId,
      chatTitle: this.chatTitle,
      chatUsername: this.chatUsername,
      messages: this.messages,
      pageMode: this.pageMode,
      isLoadingMessages: this.isLoadingMessages,
      isLoadingOlder: this.isLoadingOlder
    };
  }

  /**
   * Reads a message id without exposing list bounds handling to call sites.
   *
   * @param messages Message array to inspect.
   * @param index Message index.
   * @returns Message id, or an empty string when the index is outside the array.
   */
  private messageIdAt(messages: TdChatMessageItem[], index: number): string {
    if (index < 0 || index >= messages.length) {
      return '';
    }
    return messages[index].id;
  }

  /**
   * Applies one mapped chat-details page state to ArkUI-owned fields.
   *
   * @param nextPageState The mapped chat-details page state.
   */
  private applyPageState(nextPageState: ChatDetailsPageState): void {
    this.chatId = nextPageState.chatId;
    this.chatTitle = nextPageState.chatTitle;
    this.chatUsername = nextPageState.chatUsername;
    this.messages = nextPageState.messages;
    this.pageMode = nextPageState.pageMode;
    this.isLoadingMessages = nextPageState.isLoadingMessages;
    this.isLoadingOlder = nextPageState.isLoadingOlder;
  }

  private openComposeMessagePage(): void {
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/ComposeMessage',
        params: this.viewModel.createComposeRouteParams(this.currentPageState())
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'openComposeMessagePage failed: %{public}s', String(error));
    }
  }

  private openMessageRecorderPage(): void {
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/MessageRecorder',
        params: this.viewModel.createMessageRecorderRouteParams(this.currentPageState())
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'openMessageRecorderPage failed: %{public}s', String(error));
    }
  }

  private openUserProfile(message: TdChatMessageItem): void {
    const routeParams = this.viewModel.createUserProfileRouteParams(message);
    if (!routeParams) {
      return;
    }
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/UserProfile',
        params: routeParams
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'openUserProfile failed: %{public}s', String(error));
    }
  }

  private openMediaViewerPage(message: TdChatMessageItem): void {
    const routeParams = this.viewModel.createMediaViewerRouteParams(this.currentPageState(), message);
    if (!routeParams) {
      return;
    }
    // Capture the source message id so `onPageShow` can restore list position on return instead
    // of jumping to the latest message (the regression flagged in review #2389). Set BEFORE the
    // `pushUrl` so a synchronous push/show cycle still sees the anchor.
    this.returnAnchorMessageId = message.id;
    this.viewModel.saveScrollAnchor(this.chatId, message.id, false);
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/MediaViewer',
        params: routeParams
      });
    } catch (error) {
      // Push failed — the user stays on ChatDetails; drop the anchor so the next legitimate
      // page-show (e.g. from a different child route) does not re-target this message.
      this.returnAnchorMessageId = '';
      hilog.error(DOMAIN, TAG, 'openMediaViewerPage failed: %{public}s', String(error));
    }
  }

  private toggleVoiceNotePlayback(message: TdChatMessageItem): void {
    void this.toggleVoiceNotePlaybackAsync(message);
  }

  private async toggleVoiceNotePlaybackAsync(message: TdChatMessageItem): Promise<void> {
    try {
      await this.viewModel.toggleVoiceNotePlayback(message, (request: VoiceNotePlaybackRequest): void => {
        hilog.debug(
          DOMAIN,
          TAG,
          'Voice note toggle requested (messageId=%{public}s, path=%{public}s, mime=%{public}s, durationMs=%{public}d)',
          request.messageId,
          request.filePath,
          request.mimeType,
          request.durationMs
        );
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Voice note toggle failed: %{public}s', String(error));
    }
  }

  @Builder
  private buildComposerActions(): void {
    Row({ space: 14 }) {
      RoundIconActionButton({
        iconResource: $r('app.media.chat_icon_pencil_white'),
        buttonColor: '#2E7CC3',
        isEnabled: true,
        onButtonClick: (): void => {
          this.openComposeMessagePage();
        }
      })

      RoundIconActionButton({
        iconResource: $r('app.media.chat_icon_microphone_white'),
        buttonColor: '#29A35A',
        isEnabled: this.voiceNotePlayback.phase !== 'playing' &&
          this.voiceNotePlayback.phase !== 'loading',
        onButtonClick: (): void => {
          this.openMessageRecorderPage();
        }
      })
    }
    .width('75%')
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 8, right: 8, bottom: 32 })
    .alignRules({
      bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
      left: { anchor: '__container__', align: HorizontalAlign.Start },
      right: { anchor: '__container__', align: HorizontalAlign.End }
    })
  }

  build() {
    Stack() {
      Image($r('app.media.watch_wallpaper_466'))
        .width('100%')
        .align(Alignment.Center)

      RelativeContainer() {

        // G.2 structural test: ArcList and ArcScrollBar share an inner RelativeContainer so they
        // are direct physical siblings sharing the same parent layout context (per
        // `ArcScrollBar` SDK doc: "Only a one-to-one binding is allowed" plus the official sample
        // pattern of placing both inside the same layout container). The Refresh wrapper still
        // owns the pull-to-refresh gesture; its `single: true` constraint is satisfied by the
        // single inner RelativeContainer child.
        Refresh({ refreshing: this.isLoadingOlder }) {
          RelativeContainer() {
            ArcList({ scroller: this.messageScroller, initialIndex: 0 }) {
              ForEach(this.messages, (message: TdChatMessageItem) => {
                ChatMessageListItem({
                  message: message,
                  senderLabel: this.viewModel.senderLabel(this.chatTitle, message),
                  senderAvatarPaletteIndex: this.viewModel.senderAvatarPaletteIndex(this.chatTitle, message),
                  timeLabel: this.viewModel.formatMessageTime(message.date),
                  voiceNotePlayback: this.voiceNotePlayback,
                  onAvatarClick: (): void => {
                    this.openUserProfile(message);
                  },
                  onMediaClick: (selectedMessage: TdChatMessageItem): void => {
                    this.openMediaViewerPage(selectedMessage);
                  },
                  onVoiceNoteToggle: (selectedMessage: TdChatMessageItem): void => {
                    this.toggleVoiceNotePlayback(selectedMessage);
                  }
                })
              }, (message: TdChatMessageItem) => this.viewModel.messageRenderKey(message))
            }
            .scrollBar(BarState.Off)
            .cachedCount(CHAT_DETAILS_ARC_LIST_CACHED_COUNT)
            .width('100%')
            .height('100%')
            .onScrollIndex((start: number, end: number, center: number): void => {
              // Follow-latest signal for the snapshot path. `isAtLatest` flips to `false` the
              // moment the user scrolls up off the bottom, which suppresses programmatic
              // jump-to-end on live updates / delivery refreshes / avatar emits arriving while
              // they read older messages. Empty list (`messages.length === 0`) keeps the default
              // `true` so the very first non-empty snapshot still latches.
              const messageCount = this.messages.length;
              if (messageCount === 0) {
                return;
              }
              this.isAtLatest = end >= messageCount - 1;
              this.lastVisibleStartMessageId = this.messageIdAt(this.messages, start);
              this.lastVisibleCenterMessageId = this.messageIdAt(this.messages, center);
              this.lastVisibleEndMessageId = this.messageIdAt(this.messages, end);
              this.lastVisibleWasAtLatest = this.isAtLatest;
              this.lastVisibleWasAtTop = start === 0;
            })
            .onScrollStart((): void => {
              this.shouldPersistLoadedTopAnchor = false;
              // User-initiated scroll (touch / crown). Programmatic `scrollToIndex(_, false, _)`
              // calls without animation do not fire this. First gesture flips the gate and the
              // ArcScrollBar mounts via the `if (...)` below. Reset on each `aboutToAppear`.
              if (this.hasUserInitiatedScroll) {
                return;
              }
              this.hasUserInitiatedScroll = true;
              hilog.info(DOMAIN, TAG, 'ScrollBar gate: user-initiated scroll started');
            })

            // Mount only after the user actually starts scrolling. Programmatic scrolls
            // (initial latch / deeplink / return-anchor) don't fire `onScrollStart`, so the bar
            // stays out of the tree during automated positioning. The very first user gesture
            // (touch / crown) flips `hasUserInitiatedScroll` and the SDK renders the bar with
            // its native `BarState.Auto` fade-out behaviour from that point on.
            if (this.hasUserInitiatedScroll) {
              ArcScrollBar({ scroller: this.messageScroller, state: BarState.Auto })
            }
          }
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .onRefreshing(() => {
          this.loadOlderMessagesByPull();
        })

        Column({ space: 1 }) {
          Text(this.chatTitle.length > 0 ? this.chatTitle : $r('app.string.chat_details_title'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .width('100%')

          if (this.chatUsername.trim().length > 0) {
            Text(this.chatUsername)
              .fontSize(9)
              .fontColor('#CCD8E6')
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .width('100%')
          }
        }
          .id('chat-details-header')
          .width('100%')
          .height(40)
          .padding({ top: 8, bottom: 8 })
          .backgroundColor('#D9151A21')
          .alignRules({
            top: { anchor: '__container__', align: VerticalAlign.Top },
            left: { anchor: '__container__', align: HorizontalAlign.Start }
          })

        if (this.isLoadingMessages && this.messages.length === 0) {
          Column() {
            Text($r('app.string.chat_details_loading'))
              .fontSize(11)
              .fontColor('#B0B0B0')
              .textAlign(TextAlign.Center)
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .backgroundColor('#66000000')
              .borderRadius(14)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 52 })
          .alignRules({
            top: { anchor: '__container__', align: VerticalAlign.Top },
            left: { anchor: '__container__', align: HorizontalAlign.Start }
          })
        } else if (!this.isLoadingMessages && this.messages.length === 0) {
          Column() {
            Text($r('app.string.chat_details_empty'))
              .fontSize(11)
              .fontColor('#B0B0B0')
              .textAlign(TextAlign.Center)
              .maxLines(2)
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .backgroundColor('#66000000')
              .borderRadius(14)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 52 })
          .alignRules({
            top: { anchor: '__container__', align: VerticalAlign.Top },
            left: { anchor: '__container__', align: HorizontalAlign.Start }
          })
        }

        this.buildComposerActions()
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
