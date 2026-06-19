import { tdClient } from '../services/td/TdClient';
import { TdChatListItem } from '../services/td/TdPayloadTypes';
import { ChatRouteParams, createChatRouteParams } from '../models/chat/ChatRouteParams';
import { ChatsPageMode, ChatsPageState } from '../models/chat/ChatsPageState';
import { formatUnreadBadgeCount, normalizeUnreadBadgeCount } from '../models/chat/UnreadBadgeFormatter';
import { ProfileRouteParams } from '../models/profile/ProfileRouteParams';
import { textSignature } from '../utils/TextSignature';
import { cloneUiTextValue } from '../models/ui/UiTextValue';

export interface ChatsAuthStatePlan {
  shouldNavigateToIndex: boolean;
  resetIndexNavigation: boolean;
}

export interface ChatsRefreshPlan {
  nextPageState: ChatsPageState;
  shouldRequestChats: boolean;
  requestLimit: number;
}

/**
 * Creates the typed state scaffold for the routed chats page.
 */
export class ChatsPageViewModel {
  /**
   * Registers one chat-list listener.
   *
   * @param listener The listener invoked after chat-list updates.
   */
  setChatsListener(listener: (items: TdChatListItem[]) => void): void {
    tdClient.setChatsListener(listener);
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
   * Requests the current chat list.
   *
   * @param limit The requested chat count.
   */
  requestChats(limit: number): void {
    tdClient.requestChats(limit);
  }

  /**
   * Creates typed route params for the chat-details screen.
   *
   * @param chat The selected chat row.
   * @returns The routed chat-details params.
   */
  createChatRouteParams(chat: TdChatListItem): ChatRouteParams {
    return createChatRouteParams(chat.id, chat.title, this.chatUsername(chat));
  }

  /**
   * Creates typed route params for the read-only user-profile screen.
   *
   * @param chat The selected private-chat row.
   * @returns Routed user-profile params or `undefined` when chat is not private.
   */
  createUserProfileRouteParams(chat: TdChatListItem): ProfileRouteParams | undefined {
    if (chat.chatKind !== 'private' || typeof chat.peerUserId !== 'string' || chat.peerUserId.length === 0) {
      return undefined;
    }

    const cachedProfile = tdClient.getUserProfile(chat.peerUserId);
    const fallbackUsername = this.normalizeRouteUsername(chat.username);
    const fallbackTitle = chat.title.trim();
    const avatarPath = typeof chat.avatarPath === 'string' ? chat.avatarPath : '';

    return {
      id: chat.peerUserId,
      firstName: cachedProfile && cachedProfile.firstName.length > 0 ? cachedProfile.firstName : fallbackTitle,
      lastName: cachedProfile ? cachedProfile.lastName : '',
      username: cachedProfile && cachedProfile.username.length > 0 ? cachedProfile.username : fallbackUsername,
      phoneNumber: cachedProfile ? cachedProfile.phoneNumber : '',
      avatarPath: cachedProfile && typeof cachedProfile.avatarPath === 'string' && cachedProfile.avatarPath.length > 0
        ? cachedProfile.avatarPath
        : avatarPath,
      avatarAnimationPath: cachedProfile ? cachedProfile.avatarAnimationPath : ''
    };
  }

  /**
   * Creates the placeholder state shown before the routed page binds live chat-list data.
   *
   * @returns The initial chats-page state.
   */
  createInitialState(): ChatsPageState {
    return {
      chats: [],
      pageMode: ChatsPageMode.Idle,
      isLoading: false,
      isPullRefreshing: false
    };
  }

  /**
   * Creates the transient loading state shown while the page reloads chats.
   *
   * @param currentState The current chats-page state.
   * @returns The updated chats-page state.
   */
  createLoadingState(currentState: ChatsPageState): ChatsPageState {
    return {
      chats: currentState.chats,
      pageMode: currentState.chats.length > 0 ? ChatsPageMode.Ready : ChatsPageMode.Loading,
      isLoading: true,
      isPullRefreshing: currentState.isPullRefreshing
    };
  }

  /**
   * Creates the transient pull-refresh state shown while the page refreshes chats.
   *
   * @param currentState The current chats-page state.
   * @returns The updated chats-page state.
   */
  createPullRefreshingState(currentState: ChatsPageState): ChatsPageState {
    return {
      chats: currentState.chats,
      pageMode: currentState.pageMode,
      isLoading: currentState.isLoading,
      isPullRefreshing: true
    };
  }

  /**
   * Plans one chats refresh request.
   *
   * @param currentState The current chats-page state.
   * @param limit The requested chat count.
   * @returns The next state and request decision.
   */
  planRefresh(currentState: ChatsPageState, limit: number): ChatsRefreshPlan {
    return {
      nextPageState: this.createLoadingState(currentState),
      shouldRequestChats: true,
      requestLimit: limit
    };
  }

  /**
   * Plans one pull-to-refresh request.
   *
   * @param currentState The current chats-page state.
   * @param limit The requested chat count.
   * @returns The next state and request decision.
   */
  planPullRefresh(currentState: ChatsPageState, limit: number): ChatsRefreshPlan {
    if (currentState.isLoading) {
      return {
        nextPageState: {
          chats: currentState.chats,
          pageMode: currentState.pageMode,
          isLoading: currentState.isLoading,
          isPullRefreshing: false
        },
        shouldRequestChats: false,
        requestLimit: limit
      };
    }

    return {
      nextPageState: this.createLoadingState(this.createPullRefreshingState(currentState)),
      shouldRequestChats: true,
      requestLimit: limit
    };
  }

  /**
   * Plans one auth-state reaction for the chats page.
   *
   * @param authState The latest TDLib authorization state.
   * @returns The redirect decision for the routed page.
   */
  planAuthStateChange(authState: string): ChatsAuthStatePlan {
    return {
      shouldNavigateToIndex: authState !== 'authorizationStateReady',
      resetIndexNavigation: authState === 'authorizationStateReady'
    };
  }

  /**
   * Applies one chat-list payload to presentation-safe chats-page state.
   *
   * @param items The latest chat-list payload.
   * @returns The updated chats-page state.
   */
  applyChats(items: TdChatListItem[]): ChatsPageState {
    const clonedChats = this.cloneChats(items);
    return {
      chats: clonedChats,
      pageMode: clonedChats.length > 0 ? ChatsPageMode.Ready : ChatsPageMode.Empty,
      isLoading: false,
      isPullRefreshing: false
    };
  }

  /**
   * Returns the formatted time label for one chat row.
   *
   * @param chat The chat item.
   * @returns The formatted chat time label.
   */
  chatTimeLabel(chat: TdChatListItem): string {
    if (typeof chat.lastMessageDate === 'number' && chat.lastMessageDate > 0) {
      return this.formatChatTime(chat.lastMessageDate);
    }

    return '--:--';
  }

  /**
   * Returns the stable render key for one chat row.
   *
   * @param chat The chat item.
   * @returns The row render key.
   */
  chatRenderKey(chat: TdChatListItem): string {
    const title = typeof chat.title === 'string' ? chat.title : '';
    const lastMessageDate = typeof chat.lastMessageDate === 'number' ? chat.lastMessageDate : 0;
    const lastMessageText = this.chatLastMessageText(chat);
    const lastMessageKind = typeof chat.lastMessageKind === 'string' ? chat.lastMessageKind : '';
    const lastMessageTextValue = chat.lastMessageTextValue ? chat.lastMessageTextValue.resourceName : '';
    const lastMessageDirection = chat.lastMessageIsOutgoing === true ? 'out' : 'in';
    const lastMessageCallStatus = typeof chat.lastMessageCallEventStatus === 'string' ? chat.lastMessageCallEventStatus : '';
    const avatarPath = typeof chat.avatarPath === 'string' ? chat.avatarPath : '';
    const unreadCount = this.chatUnreadCount(chat);
    const mutedFlag = this.chatIsMuted(chat) ? 'm' : 'a';
    return `${chat.id}:${title}:${lastMessageDate}:${lastMessageText}:${lastMessageTextValue}:${lastMessageKind}:${lastMessageDirection}:${lastMessageCallStatus}:${avatarPath}:${unreadCount}:${mutedFlag}`;
  }

  /**
   * Returns the latest message preview for one chat row.
   *
   * @param chat The chat item.
   * @returns Trimmed last-message text or empty string.
   */
  chatLastMessageText(chat: TdChatListItem): string {
    if (typeof chat.lastMessageText !== 'string') {
      return '';
    }
    return chat.lastMessageText.trim();
  }

  /**
   * Returns a presentation-safe unread counter for one chat row.
   *
   * @param chat The chat item.
   * @returns The normalized unread count.
   */
  chatUnreadCount(chat: TdChatListItem): number {
    return normalizeUnreadBadgeCount(chat.unreadCount);
  }

  /**
   * Returns whether one chat row should use muted notification styling.
   *
   * @param chat The chat item.
   * @returns `true` when TDLib marks the chat as muted.
   */
  chatIsMuted(chat: TdChatListItem): boolean {
    if (typeof chat.notificationMuteFor === 'number' && chat.notificationMuteFor > 0) {
      return true;
    }

    return chat.defaultDisableNotification === true;
  }

  /**
   * Formats unread counter text for the watch badge.
   *
   * @param count The unread count.
   * @returns Empty text for zero, a number for `1..99`, or `99+`.
   */
  formatUnreadBadge(count: number): string {
    return formatUnreadBadgeCount(count);
  }

  /**
   * Returns the username label for one chat row.
   *
   * @param chat The chat item.
   * @returns The username label or empty string.
   */
  chatUsername(chat: TdChatListItem): string {
    if (typeof chat.username === 'string' && chat.username.length > 0) {
      return chat.username;
    }

    return '';
  }

  /**
   * Returns the avatar path for one chat row.
   *
   * @param chat The chat item.
   * @returns The avatar path or empty string.
   */
  chatAvatarPath(chat: TdChatListItem): string {
    if (typeof chat.avatarPath === 'string' && chat.avatarPath.length > 0) {
      return chat.avatarPath;
    }

    return '';
  }

  /**
   * Returns deterministic palette index for one chat fallback avatar.
   *
   * @param chat The chat item.
   * @returns Palette index in range `0..7`.
   */
  chatAvatarPaletteIndex(chat: TdChatListItem): number {
    const sourceId = typeof chat.peerUserId === 'string' && chat.peerUserId.length > 0 ? chat.peerUserId : chat.id;
    return textSignature(sourceId) % 8;
  }

  /**
   * Creates a deep-enough clone of one TDLib chat-list payload for ArkUI state ownership.
   *
   * @param items The TDLib chat-list payload.
   * @returns The cloned chat-list payload.
   */
  private cloneChats(items: TdChatListItem[]): TdChatListItem[] {
    const clonedChats: TdChatListItem[] = [];
    for (let index = 0; index < items.length; index += 1) {
      const item = items[index];
      clonedChats.push({
        id: item.id,
        title: item.title,
        chatKind: item.chatKind,
        username: item.username,
        peerUserId: item.peerUserId,
        avatarPath: item.avatarPath,
        avatarFileId: item.avatarFileId,
        lastMessageDate: item.lastMessageDate,
        lastMessageText: item.lastMessageText,
        lastMessageTextValue: cloneUiTextValue(item.lastMessageTextValue),
        lastMessageKind: item.lastMessageKind,
        lastMessageIsOutgoing: item.lastMessageIsOutgoing,
        lastMessageCallEventStatus: item.lastMessageCallEventStatus,
        lastReadInboxMessageId: item.lastReadInboxMessageId,
        lastReadOutboxMessageId: item.lastReadOutboxMessageId,
        unreadCount: item.unreadCount,
        defaultDisableNotification: item.defaultDisableNotification,
        notificationMuteFor: item.notificationMuteFor
      });
    }

    return clonedChats;
  }

  /**
   * Formats one unix timestamp for the chat-list secondary label.
   *
   * @param unixSeconds The unix timestamp in seconds.
   * @returns The formatted label.
   */
  private formatChatTime(unixSeconds: number): string {
    if (unixSeconds <= 0) {
      return '';
    }

    const date = new Date(unixSeconds * 1000);
    const now = new Date();
    const sameDay = date.getFullYear() === now.getFullYear() &&
      date.getMonth() === now.getMonth() &&
      date.getDate() === now.getDate();
    if (sameDay) {
      const hours = date.getHours();
      const minutes = date.getMinutes();
      const hoursText = hours < 10 ? `0${hours}` : `${hours}`;
      const minutesText = minutes < 10 ? `0${minutes}` : `${minutes}`;
      return `${hoursText}:${minutesText}`;
    }

    const day = date.getDate();
    const month = date.getMonth() + 1;
    const dayText = day < 10 ? `0${day}` : `${day}`;
    const monthText = month < 10 ? `0${month}` : `${month}`;
    return `${dayText}.${monthText}`;
  }

  /**
   * Normalizes routed username by removing optional leading `@` marker.
   *
   * @param username The raw chat-list username label.
   * @returns Username accepted by `ProfileRouteParams`.
   */
  private normalizeRouteUsername(username: string | undefined): string {
    if (typeof username !== 'string') {
      return '';
    }
    const trimmedUsername = username.trim();
    if (trimmedUsername.startsWith('@')) {
      return trimmedUsername.substring(1);
    }
    return trimmedUsername;
  }

}
