import { tdClient } from '../services/td/TdClient';
import { TdChatListItem, TdMeInfo } from '../services/td/TdPayloadTypes';
import { ChatRouteParams, createChatRouteParams } from '../models/chat/ChatRouteParams';
import { ProfilePageState } from '../models/profile/ProfilePageState';

/**
 * Creates the typed state scaffold for the routed profile page.
 */
export class ProfilePageViewModel {
  /**
   * Registers one current-user listener.
   *
   * @param listener The listener invoked after current-user payload updates.
   */
  setMeListener(listener: (me: TdMeInfo) => void): void {
    tdClient.setMeListener(listener);
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
   * Creates the placeholder state shown before the routed page binds live current-user data.
   *
   * @returns The initial profile-page state.
   */
  createInitialState(): ProfilePageState {
    return {
      userId: '-',
      fullName: '-',
      username: '-',
      phoneNumber: '-',
      avatarPath: '',
      avatarAnimationPath: ''
    };
  }

  /**
   * Maps routed profile parameters to presentation-safe profile state.
   *
   * @param userId The routed user identifier.
   * @param firstName The routed first name.
   * @param lastName The routed last name.
   * @param username The routed username.
   * @param phoneNumber The routed phone number.
   * @param avatarPath The routed avatar path.
   * @param avatarAnimationPath The routed animated avatar path.
   * @returns The mapped profile-page state.
   */
  createStateFromRoute(
    userId: string,
    firstName: string,
    lastName: string,
    username: string,
    phoneNumber: string,
    avatarPath: string,
    avatarAnimationPath: string
  ): ProfilePageState {
    return {
      userId: this.normalizeText(userId, '-'),
      fullName: this.buildFullName(firstName, lastName),
      username: this.buildUsername(username),
      phoneNumber: this.normalizeText(phoneNumber, '-'),
      avatarPath: avatarPath,
      avatarAnimationPath: avatarAnimationPath
    };
  }

  /**
   * Maps the current-user payload emitted by TDLib to presentation-safe profile state.
   *
   * @param me The current-user payload emitted by TDLib.
   * @returns The mapped profile-page state.
   */
  applyMeInfo(me: TdMeInfo): ProfilePageState {
    return {
      userId: String(me.id),
      fullName: this.buildFullName(me.firstName, me.lastName),
      username: this.buildUsername(me.username),
      phoneNumber: this.normalizeText(me.phoneNumber, '-'),
      avatarPath: this.normalizeOptionalText(me.avatarPath),
      avatarAnimationPath: this.normalizeOptionalText(me.avatarAnimationPath)
    };
  }

  /**
   * Requests real private-chat route params for a user profile.
   *
   * @param userId Profile user id.
   * @param fullName Profile display name fallback.
   * @param username Profile display username fallback.
   * @param listener Callback invoked with route params or error message.
   * @returns `true` when cached chat exists or TDLib request was sent.
   */
  requestUserChatRouteParams(
    userId: string,
    fullName: string,
    username: string,
    listener: (routeParams: ChatRouteParams | undefined, errorMessage: string) => void
  ): boolean {
    const safeUserId = userId.trim();
    if (safeUserId.length === 0 || safeUserId === '-') {
      listener(undefined, 'Missing user id.');
      return false;
    }

    return tdClient.requestPrivateChat(safeUserId, (chat: TdChatListItem | undefined, errorMessage: string): void => {
      if (!chat) {
        listener(undefined, errorMessage.length > 0 ? errorMessage : 'Chat unavailable.');
        return;
      }

      listener(this.createChatRouteParams(chat, fullName, username), '');
    });
  }

  /**
   * Checks whether the profile has enough identity data to open a chat.
   *
   * @param userId Profile user id.
   * @returns `true` when chat route params can be created.
   */
  canOpenUserChat(userId: string): boolean {
    const safeUserId = userId.trim();
    return safeUserId.length > 0 && safeUserId !== '-';
  }

  /**
   * Checks whether the profile has a valid numeric user id required to place a call.
   *
   * @param userId Profile user id.
   * @returns `true` when a call can be created for the user.
   */
  canCallUser(userId: string): boolean {
    const safeUserId = userId.trim();
    if (safeUserId.length === 0 || safeUserId === '-') {
      return false;
    }
    const numericUserId = Number.parseInt(safeUserId, 10);
    return !Number.isNaN(numericUserId) && numericUserId > 0;
  }

  /**
   * Builds the display name shown on the profile page.
   *
   * @param firstName The first-name part.
   * @param lastName The last-name part.
   * @returns The mapped display name or fallback marker.
   */
  private buildFullName(firstName: string, lastName: string): string {
    const mergedName = `${firstName} ${lastName}`.trim();
    if (mergedName.length > 0) {
      return mergedName;
    }

    return '-';
  }

  /**
   * Builds the username label shown on the profile page.
   *
   * @param username The raw username value.
   * @returns The prefixed username label or fallback marker.
   */
  private buildUsername(username: string): string {
    const trimmedUsername = username.trim();
    if (trimmedUsername.length > 0) {
      return `@${trimmedUsername}`;
    }

    return '-';
  }

  /**
   * Creates chat-details route params from a real TDLib chat.
   *
   * @param chat Opened private chat.
   * @param fallbackFullName Profile display name fallback.
   * @param fallbackUsername Profile display username fallback.
   * @returns Chat-details route params.
   */
  private createChatRouteParams(
    chat: TdChatListItem,
    fallbackFullName: string,
    fallbackUsername: string
  ): ChatRouteParams {
    const routedUsername = typeof chat.username === 'string' && chat.username.length > 0
      ? chat.username
      : fallbackUsername;
    return createChatRouteParams(
      chat.id,
      this.buildChatTitle(chat.title, fallbackFullName, fallbackUsername, chat.id),
      this.normalizeRouteUsername(routedUsername)
    );
  }

  /**
   * Builds chat-details title from TDLib chat title and profile display fields.
   *
   * @param chatTitle TDLib chat title.
   * @param fullName Profile display name fallback.
   * @param username Profile display username fallback.
   * @param userId User id fallback.
   * @returns Chat title shown in chat details.
   */
  private buildChatTitle(chatTitle: string, fullName: string, username: string, userId: string): string {
    const safeChatTitle = chatTitle.trim();
    if (safeChatTitle.length > 0 && safeChatTitle !== 'Unknown chat') {
      return safeChatTitle;
    }

    const safeFullName = fullName.trim();
    if (safeFullName.length > 0 && safeFullName !== '-') {
      return safeFullName;
    }

    const safeUsername = username.trim();
    if (safeUsername.length > 0 && safeUsername !== '-') {
      return safeUsername;
    }

    return userId;
  }

  /**
   * Normalizes profile-card username for chat route params.
   *
   * @param username Profile-card username, possibly prefixed with `@`.
   * @returns Username without display prefix or empty string.
   */
  private normalizeRouteUsername(username: string): string {
    const safeUsername = username.trim();
    if (safeUsername.length === 0 || safeUsername === '-') {
      return '';
    }
    if (safeUsername.startsWith('@')) {
      return safeUsername.substring(1);
    }
    return safeUsername;
  }

  /**
   * Normalizes one required text value with a fallback.
   *
   * @param value The raw text value.
   * @param fallback The fallback value.
   * @returns The normalized text.
   */
  private normalizeText(value: string, fallback: string): string {
    if (value.trim().length > 0) {
      return value;
    }

    return fallback;
  }

  /**
   * Normalizes one optional text value.
   *
   * @param value The optional text value.
   * @returns The normalized text or empty string.
   */
  private normalizeOptionalText(value: string | undefined): string {
    if (typeof value === 'string' && value.length > 0) {
      return value;
    }

    return '';
  }
}
