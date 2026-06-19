import { describe, it, expect } from '@ohos/hypium';
import { TdChatMessageItem, TdUserProfileItem } from '../main/ets/services/td/TdPayloadTypes';
import {
  ChatDetailsPageViewModel,
  ChatDetailsVisibleScrollAnchorState
} from '../main/ets/viewmodel/ChatDetailsPageViewModel';
import { ChatDetailsPageMode } from '../main/ets/models/chat/ChatDetailsPageState';
import { createEmptyUiTextValue } from '../main/ets/models/ui/UiTextValue';

function buildVisibleScrollAnchorState(): ChatDetailsVisibleScrollAnchorState {
  return {
    explicitReturnAnchorMessageId: '',
    persistedScrollAnchorMessageId: '',
    topMessageId: '',
    lastVisibleStartMessageId: '',
    lastVisibleCenterMessageId: '',
    lastVisibleEndMessageId: '',
    lastVisibleWasAtLatest: false,
    lastVisibleWasAtTop: false,
    shouldPersistLoadedTopAnchor: false
  };
}

function buildMessage(overrides?: Partial<TdChatMessageItem>): TdChatMessageItem {
  return {
    id: overrides?.id ?? '1',
    chatId: overrides?.chatId ?? '55',
    senderUserId: overrides?.senderUserId ?? '77',
    senderChatId: overrides?.senderChatId,
    senderAvatarPath: overrides?.senderAvatarPath,
    sendingState: overrides?.sendingState,
    deliveryState: overrides?.deliveryState,
    kind: overrides?.kind ?? 'text',
    text: overrides?.text ?? 'hello',
    textValue: overrides?.textValue ?? createEmptyUiTextValue(),
    caption: overrides?.caption,
    mediaFileId: overrides?.mediaFileId,
    mediaThumbFileId: overrides?.mediaThumbFileId,
    mediaMinithumbnailData: overrides?.mediaMinithumbnailData,
    mediaLocalPath: overrides?.mediaLocalPath,
    mediaThumbPath: overrides?.mediaThumbPath,
    mediaWidth: overrides?.mediaWidth,
    mediaHeight: overrides?.mediaHeight,
    mediaMimeType: overrides?.mediaMimeType,
    mediaIsAnimated: overrides?.mediaIsAnimated,
    mediaDurationSec: overrides?.mediaDurationSec,
    voiceNoteWaveform: overrides?.voiceNoteWaveform,
    voiceNoteIsListened: overrides?.voiceNoteIsListened,
    callEventStatus: overrides?.callEventStatus,
    callEventDurationSec: overrides?.callEventDurationSec,
    callEventIsVideo: overrides?.callEventIsVideo,
    isOutgoing: overrides?.isOutgoing ?? false,
    date: overrides?.date ?? 1710000000
  };
}

function buildUserProfile(overrides?: Partial<TdUserProfileItem>): TdUserProfileItem {
  return {
    id: overrides?.id ?? '77',
    firstName: overrides?.firstName ?? 'Ada',
    lastName: overrides?.lastName ?? 'Lovelace',
    username: overrides?.username ?? '@ada',
    phoneNumber: overrides?.phoneNumber ?? '48123456789',
    avatarPath: overrides?.avatarPath,
    avatarAnimationPath: overrides?.avatarAnimationPath
  };
}

export default function chatDetailsPageViewModelTest() {
  describe('ChatDetailsPageViewModelTest', () => {
    it('shouldSkipUserProfileRouteWhenSenderIdIsEmpty', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();

      const params = viewModel.mapUserProfileRouteParams('', buildUserProfile(), '/tmp/message.jpg');

      expect(params).assertUndefined();
    });

    it('shouldSkipUserProfileRouteWhenProfileSnapshotIsMissing', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const message = buildMessage({ senderUserId: '77', senderAvatarPath: '/tmp/message.jpg' });

      const params = viewModel.mapUserProfileRouteParams(message.senderUserId ?? '', undefined, message.senderAvatarPath);

      expect(params).assertUndefined();
    });

    it('shouldCreateUserProfileRouteFromCachedProfile', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const message = buildMessage({ senderUserId: '77', senderAvatarPath: '/tmp/message.jpg' });
      const cachedProfile = buildUserProfile({
        avatarPath: '/tmp/profile.jpg',
        avatarAnimationPath: '/tmp/profile.tgs'
      });

      const params = viewModel.mapUserProfileRouteParams(message.senderUserId ?? '', cachedProfile, message.senderAvatarPath);

      expect(params?.id).assertEqual('77');
      expect(params?.firstName).assertEqual('Ada');
      expect(params?.lastName).assertEqual('Lovelace');
      expect(params?.username).assertEqual('ada');
      expect(params?.phoneNumber).assertEqual('48123456789');
      expect(params?.avatarPath).assertEqual('/tmp/profile.jpg');
      expect(params?.avatarAnimationPath).assertEqual('/tmp/profile.tgs');
    });

    it('shouldFallbackToMessageAvatarWhenProfileAvatarIsMissing', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const cachedProfile = buildUserProfile({
        avatarPath: '',
        avatarAnimationPath: ''
      });

      const params = viewModel.mapUserProfileRouteParams('77', cachedProfile, '/tmp/message.jpg');

      expect(params?.avatarPath).assertEqual('/tmp/message.jpg');
      expect(params?.avatarAnimationPath).assertEqual('');
    });

    it('shouldPreferCachedSenderNameForIncomingGroupAvatarFallback', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const message = buildMessage({
        senderUserId: '77',
        isOutgoing: false
      });

      const senderLabel = viewModel.senderLabel(
        'OSTC Team',
        message,
        buildUserProfile({ firstName: 'Marta', lastName: 'Mandes', username: 'mmandes' })
      );

      expect(senderLabel).assertEqual('Marta Mandes');
    });

    it('shouldCloneVoiceNoteMetadataInAppliedMessages', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const initialState = viewModel.createInitialState();
      const sourceMessage = buildMessage({
        kind: 'voiceNote',
        mediaDurationSec: 21,
        voiceNoteWaveform: [1, 3, 5],
        voiceNoteIsListened: false
      });

      const nextState = viewModel.applyMessages(initialState, [sourceMessage]);
      const clonedMessage = nextState.messages[0];

      expect(nextState.messages.length).assertEqual(1);
      expect(clonedMessage.kind).assertEqual('voiceNote');
      expect(clonedMessage.mediaDurationSec).assertEqual(21);
      expect(clonedMessage.voiceNoteIsListened).assertFalse();
      if (clonedMessage.voiceNoteWaveform) {
        expect(clonedMessage.voiceNoteWaveform.length).assertEqual(3);
        expect(clonedMessage.voiceNoteWaveform[0]).assertEqual(1);
        expect(clonedMessage.voiceNoteWaveform[1]).assertEqual(3);
        expect(clonedMessage.voiceNoteWaveform[2]).assertEqual(5);
      } else {
        expect(false).assertTrue();
      }

      if (sourceMessage.voiceNoteWaveform) {
        sourceMessage.voiceNoteWaveform[0] = 99;
      }

      if (clonedMessage.voiceNoteWaveform) {
        expect(clonedMessage.voiceNoteWaveform[0]).assertEqual(1);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldCloneVideoNoteMinithumbnailMetadataInAppliedMessages', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const initialState = viewModel.createInitialState();
      const sourceMessage = buildMessage({
        kind: 'videoNote',
        mediaDurationSec: 12,
        mediaMinithumbnailData: 'bWluaS1qcGVn',
        mediaWidth: 240,
        mediaHeight: 240
      });

      const nextState = viewModel.applyMessages(initialState, [sourceMessage]);
      const clonedMessage = nextState.messages[0];

      expect(clonedMessage.kind).assertEqual('videoNote');
      expect(clonedMessage.mediaDurationSec).assertEqual(12);
      expect(clonedMessage.mediaMinithumbnailData).assertEqual('bWluaS1qcGVn');
      expect(clonedMessage.mediaWidth).assertEqual(240);
      expect(clonedMessage.mediaHeight).assertEqual(240);

      sourceMessage.mediaMinithumbnailData = 'mutated';
      expect(clonedMessage.mediaMinithumbnailData).assertEqual('bWluaS1qcGVn');
    });

    it('shouldFindMessageIndexById', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();

      const index = viewModel.findMessageIndexById(
        [
          buildMessage({ id: '100' }),
          buildMessage({ id: '200' }),
          buildMessage({ id: '300' })
        ],
        '200'
      );

      expect(index).assertEqual(1);
    });

    it('shouldReturnMinusOneWhenMessageIndexIsMissing', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();

      const missingIndex = viewModel.findMessageIndexById(
        [
          buildMessage({ id: '100' }),
          buildMessage({ id: '200' })
        ],
        '300'
      );
      const emptyIndex = viewModel.findMessageIndexById([buildMessage({ id: '100' })], '');

      expect(missingIndex).assertEqual(-1);
      expect(emptyIndex).assertEqual(-1);
    });

    it('shouldKeepInitialMessageScrollPendingForSparseAnchorPage', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();

      expect(viewModel.shouldClearInitialMessageScroll(1)).assertFalse();
      expect(viewModel.shouldClearInitialMessageScroll(2)).assertTrue();
    });

    it('shouldRefuseOlderHistoryLoadWhenChatIdIsEmpty', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const currentState = viewModel.createInitialState();

      const plan = viewModel.planOlderHistoryLoad(currentState);

      expect(plan.shouldRequestOlderHistory).assertFalse();
      expect(plan.chatId).assertEqual('');
      // Refused plan MUST NOT flip `isLoadingOlder` to true. A spurious flag would block the next
      // pull cycle by tripping the in-flight guard inside `loadOlderMessagesByPull`.
      expect(plan.nextPageState.isLoadingOlder).assertFalse();
      // The state reference must pass through unchanged — no clone-of-clone for a no-op plan.
      expect(plan.nextPageState).assertEqual(currentState);
    });

    it('shouldEnterOlderHistoryLoadingWhenChatIdIsPresent', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const routedState = viewModel.applyRoute(viewModel.createInitialState(), '55', 'Chat', '');

      const plan = viewModel.planOlderHistoryLoad(routedState);

      expect(plan.shouldRequestOlderHistory).assertTrue();
      expect(plan.chatId).assertEqual('55');
      expect(plan.nextPageState.isLoadingOlder).assertTrue();
    });

    it('shouldClearOlderHistoryLoadingFlagWithoutTouchingMessages', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const baseState = viewModel.applyMessages(
        viewModel.applyRoute(viewModel.createInitialState(), '55', 'Chat', ''),
        [
          buildMessage({ id: '100' }),
          buildMessage({ id: '200' })
        ]
      );
      const loadingState = viewModel.planOlderHistoryLoad(baseState).nextPageState;
      expect(loadingState.isLoadingOlder).assertTrue();

      const cleared = viewModel.clearOlderHistoryLoading(loadingState);

      expect(cleared.isLoadingOlder).assertFalse();
      // Same `messages` reference — no rerender of the ForEach for a no-op payload.
      expect(cleared.messages === loadingState.messages).assertTrue();
    });

    it('shouldReturnSameStateWhenClearingAlreadyIdleLoading', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const idleState = viewModel.applyMessages(
        viewModel.applyRoute(viewModel.createInitialState(), '55', 'Chat', ''),
        [buildMessage({ id: '100' })]
      );
      expect(idleState.isLoadingOlder).assertFalse();

      const cleared = viewModel.clearOlderHistoryLoading(idleState);

      // Idle in, idle out — must be the same object reference, not a new allocation.
      expect(cleared === idleState).assertTrue();
    });

    it('shouldCloseInitialLoadSpinnerOnFirstApplyMessagesIncludingEmptyChat', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const loadingState = viewModel.planRefresh(
        viewModel.applyRoute(viewModel.createInitialState(), '55', 'Chat', ''),
        20
      ).nextPageState;
      expect(loadingState.isLoadingMessages).assertTrue();

      // Truly empty chat: TdClient.handleChatHistory initializes the cache to [] and emits,
      // so the first applyMessages MUST close the initial-load spinner — otherwise the loading
      // view would stick forever for empty chats.
      const emptyChat = viewModel.applyMessages(loadingState, []);
      expect(emptyChat.isLoadingMessages).assertFalse();
      expect(emptyChat.pageMode).assertEqual(ChatDetailsPageMode.Empty);

      // Non-empty initial response also closes the spinner and flips to Ready.
      const populatedChat = viewModel.applyMessages(loadingState, [buildMessage({ id: '100' })]);
      expect(populatedChat.isLoadingMessages).assertFalse();
      expect(populatedChat.pageMode).assertEqual(ChatDetailsPageMode.Ready);
    });

    // @regression-for #56 (PR #59) — load-bearing test, do not relax assertions.
    it('shouldPreserveIsLoadingOlderAcrossApplyMessages', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const loadingState = viewModel.planOlderHistoryLoad(
        viewModel.applyRoute(viewModel.createInitialState(), '55', 'Chat', '')
      ).nextPageState;
      expect(loadingState.isLoadingOlder).assertTrue();

      // applyMessages handles SNAPSHOTS — live updates, read-outbox events, probe responses.
      // It MUST preserve `isLoadingOlder` so a non-pull emit mid-pull cannot close the spinner
      // ahead of the correlated historyPageResolved event.
      const settled = viewModel.applyMessages(loadingState, [buildMessage({ id: '100' })]);
      expect(settled.isLoadingOlder).assertTrue();

      const settledEmpty = viewModel.applyMessages(loadingState, []);
      expect(settledEmpty.isLoadingOlder).assertTrue();

      // ... and when not pulling, applyMessages also preserves the (false) flag — no spurious flip.
      const idleState = viewModel.applyRoute(viewModel.createInitialState(), '55', 'Chat', '');
      const stillIdle = viewModel.applyMessages(idleState, [buildMessage({ id: '101' })]);
      expect(stillIdle.isLoadingOlder).assertFalse();
    });

    it('shouldProcessOlderHistoryTimeoutOnlyWhenChatStableAndPullStillInFlight', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();

      // Happy path: routed chat unchanged, pull still loading.
      expect(viewModel.shouldProcessOlderHistoryTimeout('55', '55', true)).assertTrue();

      // User navigated away mid-pull — timeout body MUST NOT touch state for a chat no longer
      // routed (would clobber the new chat's `isLoadingOlder`).
      expect(viewModel.shouldProcessOlderHistoryTimeout('77', '55', true)).assertFalse();

      // Pull already resolved (e.g. `historyPageResolved` fired before the timeout) — no-op.
      expect(viewModel.shouldProcessOlderHistoryTimeout('55', '55', false)).assertFalse();
    });

    it('shouldGiveUpOnDeeplinkOnlyWhenChatAndTargetMatchScheduled', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();

      // Happy path: same chat, same pending target as when the timer was armed.
      expect(viewModel.shouldGiveUpOnDeeplink('55', '55', 'msg-100', 'msg-100')).assertTrue();

      // User navigated away — do not touch the new chat's `pendingInitialMessageId`.
      expect(viewModel.shouldGiveUpOnDeeplink('77', '55', 'msg-100', 'msg-100')).assertFalse();

      // A fresh deeplink request superseded the original (different target id pending). The new
      // request has its own timer; this stale fire MUST NOT clear the now-current target.
      expect(viewModel.shouldGiveUpOnDeeplink('55', '55', 'msg-200', 'msg-100')).assertFalse();

      // Pending target already cleared (e.g. successful scroll happened) — no-op.
      expect(viewModel.shouldGiveUpOnDeeplink('55', '55', '', 'msg-100')).assertFalse();
    });

    it('shouldRunInitialAutoScrollLatchOnFirstReadyNonEmptySnapshot', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const pageMode = ChatDetailsPageMode.Ready;

      // Happy path: latch has not fired yet, page is Ready with data, no deeplink, no pull.
      expect(viewModel.shouldRunInitialAutoScrollLatch(false, pageMode, 5, '', false)).assertTrue();

      // Latch is single-shot — second invocation is suppressed.
      expect(viewModel.shouldRunInitialAutoScrollLatch(true, pageMode, 5, '', false)).assertFalse();

      // Page not yet Ready (Loading on entry, Idle on tear-down) — wait for the next snapshot.
      expect(viewModel.shouldRunInitialAutoScrollLatch(false, ChatDetailsPageMode.Loading, 5, '', false)).assertFalse();
      expect(viewModel.shouldRunInitialAutoScrollLatch(false, ChatDetailsPageMode.Idle, 5, '', false)).assertFalse();
      expect(viewModel.shouldRunInitialAutoScrollLatch(false, ChatDetailsPageMode.Empty, 0, '', false)).assertFalse();

      // Empty timeline — no last index to scroll to.
      expect(viewModel.shouldRunInitialAutoScrollLatch(false, pageMode, 0, '', false)).assertFalse();

      // Deeplink active — `scheduleScrollToInitialMessageIfNeeded` owns the scroll target.
      expect(viewModel.shouldRunInitialAutoScrollLatch(false, pageMode, 5, 'msg-1', false)).assertFalse();

      // Pull cycle in flight — older-history prepend will reshape the timeline; let it settle first.
      expect(viewModel.shouldRunInitialAutoScrollLatch(false, pageMode, 5, '', true)).assertFalse();
    });

    it('shouldFollowLatestOnSnapshotOnlyWhenUserIsParkedAtBottom', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const pageMode = ChatDetailsPageMode.Ready;

      // Happy path: user is at latest, new snapshot arrives — keep them pinned to the bottom.
      expect(viewModel.shouldFollowLatestOnSnapshot(true, pageMode, 5, '', false)).assertTrue();

      // User scrolled up — live update / delivery / avatar emit MUST NOT jump the list to the end.
      expect(viewModel.shouldFollowLatestOnSnapshot(false, pageMode, 5, '', false)).assertFalse();

      // Same blockers as the initial latch: deeplink and pull cycle own the scroll target.
      expect(viewModel.shouldFollowLatestOnSnapshot(true, pageMode, 5, 'msg-1', false)).assertFalse();
      expect(viewModel.shouldFollowLatestOnSnapshot(true, pageMode, 5, '', true)).assertFalse();

      // Mode/empty sanity.
      expect(viewModel.shouldFollowLatestOnSnapshot(true, ChatDetailsPageMode.Loading, 5, '', false)).assertFalse();
      expect(viewModel.shouldFollowLatestOnSnapshot(true, pageMode, 0, '', false)).assertFalse();
    });

    it('shouldRestoreSavedScrollAnchorWhenNoDeeplinkOwnsTheRoute', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      viewModel.clearScrollAnchor('anchor-chat-1');

      viewModel.saveScrollAnchor('anchor-chat-1', 'msg-30', false);

      expect(viewModel.getRestorableScrollAnchorMessageId('anchor-chat-1', '')).assertEqual('msg-30');
      expect(viewModel.getRestorableScrollAnchorMessageId('anchor-chat-1', 'msg-99')).assertEqual('');

      viewModel.clearScrollAnchor('anchor-chat-1');
      expect(viewModel.getRestorableScrollAnchorMessageId('anchor-chat-1', '')).assertEqual('');
    });

    it('shouldClearSavedScrollAnchorWhenLeavingAtLatest', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      viewModel.clearScrollAnchor('anchor-chat-2');

      viewModel.saveScrollAnchor('anchor-chat-2', 'msg-10', false);
      expect(viewModel.getRestorableScrollAnchorMessageId('anchor-chat-2', '')).assertEqual('msg-10');

      viewModel.saveScrollAnchor('anchor-chat-2', 'msg-99', true);

      expect(viewModel.getRestorableScrollAnchorMessageId('anchor-chat-2', '')).assertEqual('');
    });

    it('shouldOverwriteSavedScrollAnchorForSameChat', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      viewModel.clearScrollAnchor('anchor-chat-3');

      viewModel.saveScrollAnchor('anchor-chat-3', 'msg-10', false);
      viewModel.saveScrollAnchor('anchor-chat-3', 'msg-20', false);

      expect(viewModel.getRestorableScrollAnchorMessageId('anchor-chat-3', '')).assertEqual('msg-20');

      viewModel.clearScrollAnchor('anchor-chat-3');
    });

    it('shouldNotClearSavedScrollAnchorWhenLatestPositionIsUnknown', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      viewModel.clearScrollAnchor('anchor-chat-4');

      viewModel.saveScrollAnchor('anchor-chat-4', 'msg-10', false);
      viewModel.saveScrollAnchor('anchor-chat-4', '', true);

      expect(viewModel.getRestorableScrollAnchorMessageId('anchor-chat-4', '')).assertEqual('msg-10');

      viewModel.clearScrollAnchor('anchor-chat-4');
    });

    it('shouldSelectPersistableScrollAnchorByPriority', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const explicitState = buildVisibleScrollAnchorState();
      explicitState.explicitReturnAnchorMessageId = ' msg-return ';
      explicitState.lastVisibleCenterMessageId = 'msg-center';
      const explicitPlan = viewModel.selectPersistableScrollAnchor(explicitState);
      expect(explicitPlan.shouldPersist).assertTrue();
      expect(explicitPlan.messageId).assertEqual('msg-return');
      expect(explicitPlan.isAtLatest).assertFalse();

      const topState = buildVisibleScrollAnchorState();
      topState.shouldPersistLoadedTopAnchor = true;
      topState.topMessageId = 'msg-top';
      topState.lastVisibleCenterMessageId = 'msg-center';
      const topPlan = viewModel.selectPersistableScrollAnchor(topState);
      expect(topPlan.shouldPersist).assertTrue();
      expect(topPlan.messageId).assertEqual('msg-top');
      expect(topPlan.isAtLatest).assertFalse();

      const centerState = buildVisibleScrollAnchorState();
      centerState.lastVisibleCenterMessageId = 'msg-center';
      centerState.lastVisibleWasAtLatest = true;
      const centerPlan = viewModel.selectPersistableScrollAnchor(centerState);
      expect(centerPlan.shouldPersist).assertTrue();
      expect(centerPlan.messageId).assertEqual('msg-center');
      expect(centerPlan.isAtLatest).assertTrue();

      const startState = buildVisibleScrollAnchorState();
      startState.lastVisibleStartMessageId = 'msg-start';
      const startPlan = viewModel.selectPersistableScrollAnchor(startState);
      expect(startPlan.shouldPersist).assertTrue();
      expect(startPlan.messageId).assertEqual('msg-start');

      const endState = buildVisibleScrollAnchorState();
      endState.lastVisibleEndMessageId = 'msg-end';
      const endPlan = viewModel.selectPersistableScrollAnchor(endState);
      expect(endPlan.shouldPersist).assertTrue();
      expect(endPlan.messageId).assertEqual('msg-end');

      const persistedState = buildVisibleScrollAnchorState();
      persistedState.persistedScrollAnchorMessageId = 'msg-persisted';
      persistedState.lastVisibleWasAtLatest = true;
      const persistedPlan = viewModel.selectPersistableScrollAnchor(persistedState);
      expect(persistedPlan.shouldPersist).assertTrue();
      expect(persistedPlan.messageId).assertEqual('msg-persisted');
      expect(persistedPlan.isAtLatest).assertFalse();

      const unknownState = buildVisibleScrollAnchorState();
      unknownState.lastVisibleWasAtLatest = true;
      const unknownPlan = viewModel.selectPersistableScrollAnchor(unknownState);
      expect(unknownPlan.shouldPersist).assertFalse();
      expect(unknownPlan.messageId).assertEqual('');
    });

    it('shouldEvictOldestScrollAnchorsWhenCapacityIsExceeded', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      for (let index = 0; index < 70; index += 1) {
        viewModel.clearScrollAnchor(`cap-chat-${index}`);
      }

      for (let index = 0; index < 70; index += 1) {
        viewModel.saveScrollAnchor(`cap-chat-${index}`, `msg-${index}`, false);
      }

      expect(viewModel.getRestorableScrollAnchorMessageId('cap-chat-0', '')).assertEqual('');
      expect(viewModel.getRestorableScrollAnchorMessageId('cap-chat-5', '')).assertEqual('');
      expect(viewModel.getRestorableScrollAnchorMessageId('cap-chat-6', '')).assertEqual('msg-6');
      expect(viewModel.getRestorableScrollAnchorMessageId('cap-chat-69', '')).assertEqual('msg-69');

      for (let index = 0; index < 70; index += 1) {
        viewModel.clearScrollAnchor(`cap-chat-${index}`);
      }
    });

    it('shouldClosePullCycleOnApplyHistoryPageResolvedPageLoaded', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const loadingState = viewModel.planOlderHistoryLoad(
        viewModel.applyRoute(viewModel.createInitialState(), '55', 'Chat', '')
      ).nextPageState;
      expect(loadingState.isLoadingOlder).assertTrue();

      const resolution = viewModel.applyHistoryPageResolved(loadingState, 'page-loaded');

      expect(resolution.nextPageState.isLoadingOlder).assertFalse();
      expect(resolution.shouldShowNoOlderHistoryToast).assertFalse();
    });

    it('shouldClosePullCycleAndRequestToastOnNoMoreOutcome', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const loadingState = viewModel.planOlderHistoryLoad(
        viewModel.applyRoute(viewModel.createInitialState(), '55', 'Chat', '')
      ).nextPageState;

      const resolution = viewModel.applyHistoryPageResolved(loadingState, 'no-more');

      expect(resolution.nextPageState.isLoadingOlder).assertFalse();
      expect(resolution.shouldShowNoOlderHistoryToast).assertTrue();
    });

    it('shouldClosePullCycleWithoutToastOnRejectedOutcome', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const loadingState = viewModel.planOlderHistoryLoad(
        viewModel.applyRoute(viewModel.createInitialState(), '55', 'Chat', '')
      ).nextPageState;

      const resolution = viewModel.applyHistoryPageResolved(loadingState, 'rejected');

      expect(resolution.nextPageState.isLoadingOlder).assertFalse();
      // 'rejected' means TDLib refused the request; no "no earlier messages" hint is appropriate.
      expect(resolution.shouldShowNoOlderHistoryToast).assertFalse();
    });

    it('shouldResetIsLoadingOlderWhenApplyingRoute', 0, () => {
      const viewModel = new ChatDetailsPageViewModel();
      const stuckState = viewModel.planOlderHistoryLoad(
        viewModel.applyRoute(viewModel.createInitialState(), '55', 'Chat', '')
      ).nextPageState;
      expect(stuckState.isLoadingOlder).assertTrue();

      // Re-entry into the page (or a switch to a different chat) MUST drop in-flight loading
      // flags so the next pull cycle is not pre-blocked.
      const reentered = viewModel.applyRoute(stuckState, '77', 'OtherChat', '');

      expect(reentered.isLoadingOlder).assertFalse();
      expect(reentered.isLoadingMessages).assertFalse();
      expect(reentered.chatId).assertEqual('77');
    });

  });
}
