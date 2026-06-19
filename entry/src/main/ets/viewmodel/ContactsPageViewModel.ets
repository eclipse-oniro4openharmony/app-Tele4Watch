import { ContactsPageMode, ContactsPageState } from '../models/contact/ContactsPageState';
import { ProfileRouteParams } from '../models/profile/ProfileRouteParams';
import { tdClient } from '../services/td/TdClient';
import { TdContactListItem, TdContactStatusKind, TdMeInfo } from '../services/td/TdPayloadTypes';
import { textSignature } from '../utils/TextSignature';

export interface ContactsAuthStatePlan {
  shouldNavigateToIndex: boolean;
  resetIndexNavigation: boolean;
}

export interface ContactsRefreshPlan {
  nextPageState: ContactsPageState;
  shouldRequestContacts: boolean;
}

/**
 * Creates the typed state scaffold for the routed contacts page.
 */
export class ContactsPageViewModel {
  /**
   * Registers one contacts-list listener.
   *
   * @param listener The listener invoked after contacts-list updates.
   */
  setContactsListener(listener: (items: TdContactListItem[]) => void): void {
    tdClient.setContactsListener(listener);
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
   * Registers one current-user listener.
   *
   * @param listener The listener invoked after current-user updates.
   */
  setMeListener(listener: (me: TdMeInfo) => void): void {
    tdClient.setMeListener(listener);
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
   * Requests the current contacts list.
   */
  requestContacts(): void {
    tdClient.requestContacts();
  }

  /**
   * Creates the placeholder state shown before the routed page binds live contacts data.
   *
   * @returns The initial contacts-page state.
   */
  createInitialState(): ContactsPageState {
    return {
      contacts: [],
      pageMode: ContactsPageMode.Idle,
      isLoading: false,
      isPullRefreshing: false
    };
  }

  /**
   * Creates the transient loading state shown while the page reloads contacts.
   *
   * @param currentState The current contacts-page state.
   * @returns The updated contacts-page state.
   */
  createLoadingState(currentState: ContactsPageState): ContactsPageState {
    return {
      contacts: currentState.contacts,
      pageMode: currentState.contacts.length > 0 ? ContactsPageMode.Ready : ContactsPageMode.Loading,
      isLoading: true,
      isPullRefreshing: currentState.isPullRefreshing
    };
  }

  /**
   * Creates the transient pull-refresh state shown while the page refreshes contacts.
   *
   * @param currentState The current contacts-page state.
   * @returns The updated contacts-page state.
   */
  createPullRefreshingState(currentState: ContactsPageState): ContactsPageState {
    return {
      contacts: currentState.contacts,
      pageMode: currentState.pageMode,
      isLoading: currentState.isLoading,
      isPullRefreshing: true
    };
  }

  /**
   * Plans one contacts refresh request.
   *
   * @param currentState The current contacts-page state.
   * @returns The next state and request decision.
   */
  planRefresh(currentState: ContactsPageState): ContactsRefreshPlan {
    return {
      nextPageState: this.createLoadingState(currentState),
      shouldRequestContacts: true
    };
  }

  /**
   * Plans one pull-to-refresh request.
   *
   * @param currentState The current contacts-page state.
   * @returns The next state and request decision.
   */
  planPullRefresh(currentState: ContactsPageState): ContactsRefreshPlan {
    if (currentState.isLoading) {
      return {
        nextPageState: {
          contacts: currentState.contacts,
          pageMode: currentState.pageMode,
          isLoading: currentState.isLoading,
          isPullRefreshing: false
        },
        shouldRequestContacts: false
      };
    }

    return {
      nextPageState: this.createLoadingState(this.createPullRefreshingState(currentState)),
      shouldRequestContacts: true
    };
  }

  /**
   * Plans one auth-state reaction for the contacts page.
   *
   * @param authState The latest TDLib authorization state.
   * @returns The redirect decision for the routed page.
   */
  planAuthStateChange(authState: string): ContactsAuthStatePlan {
    return {
      shouldNavigateToIndex: authState !== 'authorizationStateReady',
      resetIndexNavigation: authState === 'authorizationStateReady'
    };
  }

  /**
   * Applies one contacts-list payload to presentation-safe contacts-page state.
   *
   * @param items The latest contacts-list payload.
   * @returns The updated contacts-page state.
   */
  applyContacts(items: TdContactListItem[]): ContactsPageState {
    const clonedContacts = this.cloneContacts(items);
    return {
      contacts: clonedContacts,
      pageMode: clonedContacts.length > 0 ? ContactsPageMode.Ready : ContactsPageMode.Empty,
      isLoading: false,
      isPullRefreshing: false
    };
  }

  /**
   * Returns the primary label for one contact row.
   *
   * @param contact The contact item.
   * @returns The display name used by the list row.
   */
  contactDisplayName(contact: TdContactListItem): string {
    const firstName = contact.firstName.trim();
    const lastName = contact.lastName.trim();
    if (firstName.length > 0 && lastName.length > 0) {
      return `${firstName} ${lastName}`;
    }
    if (firstName.length > 0) {
      return firstName;
    }
    if (lastName.length > 0) {
      return lastName;
    }
    if (contact.username.trim().length > 0) {
      return `@${contact.username.trim()}`;
    }
    if (contact.phoneNumber.trim().length > 0) {
      return contact.phoneNumber.trim();
    }
    return contact.id;
  }

  /**
   * Returns the secondary label for one contact row.
   *
   * @param contact The contact item.
   * @returns The username or phone number shown below the title.
   */
  contactSecondaryLine(contact: TdContactListItem): string {
    const username = contact.username.trim();
    if (username.length > 0) {
      return `@${username}`;
    }
    return contact.phoneNumber.trim();
  }

  /**
   * Returns the normalized contact-status kind.
   *
   * @param contact The contact item.
   * @returns The normalized status kind.
   */
  contactStatusKind(contact: TdContactListItem): TdContactStatusKind {
    if (contact.statusKind === 'online' ||
      contact.statusKind === 'offline' ||
      contact.statusKind === 'recently' ||
      contact.statusKind === 'lastWeek' ||
      contact.statusKind === 'lastMonth') {
      return contact.statusKind;
    }
    return 'empty';
  }

  /**
   * Returns the last-seen timestamp in unix seconds.
   *
   * @param contact The contact item.
   * @returns The last-seen timestamp or `0`.
   */
  contactLastSeenAt(contact: TdContactListItem): number {
    if (typeof contact.lastSeenAt === 'number' && contact.lastSeenAt > 0) {
      return contact.lastSeenAt;
    }
    return 0;
  }

  /**
   * Returns the avatar path for one contact row.
   *
   * @param contact The contact item.
   * @returns The avatar path or empty string.
   */
  contactAvatarPath(contact: TdContactListItem): string {
    if (typeof contact.avatarPath === 'string' && contact.avatarPath.length > 0) {
      return contact.avatarPath;
    }
    return '';
  }

  /**
   * Returns the animated avatar path for one contact row.
   *
   * @param contact The contact item.
   * @returns The animated avatar path or empty string.
   */
  contactAvatarAnimationPath(contact: TdContactListItem): string {
    if (typeof contact.avatarAnimationPath === 'string' && contact.avatarAnimationPath.length > 0) {
      return contact.avatarAnimationPath;
    }
    return '';
  }

  /**
   * Returns the stable render key for one contact row.
   *
   * @param contact The contact item.
   * @returns The row render key.
   */
  contactRenderKey(contact: TdContactListItem): string {
    const avatarFileId = typeof contact.avatarFileId === 'number' ? contact.avatarFileId : 0;
    const username = contact.username.trim();
    return `${contact.id}:${avatarFileId}:${username}`;
  }

  /**
   * Returns deterministic palette index for one fallback avatar.
   *
   * @param contact The contact item.
   * @returns Palette index in range `0..7`.
   */
  contactAvatarPaletteIndex(contact: TdContactListItem): number {
    return this.resolveContactAvatarPaletteIndex(contact);
  }

  /**
   * Maps current account info to one synthetic contact row.
   *
   * @param me Current account payload.
   * @returns Synthetic contact row shown above Telegram contacts.
   */
  mapMeToContact(me: TdMeInfo): TdContactListItem {
    return {
      id: String(me.id),
      firstName: me.firstName,
      lastName: me.lastName,
      username: me.username,
      phoneNumber: me.phoneNumber,
      avatarPath: me.avatarPath,
      avatarAnimationPath: me.avatarAnimationPath,
      isMutualContact: false,
      statusKind: 'online'
    };
  }

  /**
   * Maps one contact row to routed user-profile params.
   *
   * @param contact The contact row selected by the user.
   * @returns Router params consumed by the user-profile page.
   */
  createUserProfileRouteParams(contact: TdContactListItem): ProfileRouteParams {
    return {
      id: contact.id,
      firstName: contact.firstName,
      lastName: contact.lastName,
      username: contact.username,
      phoneNumber: contact.phoneNumber,
      avatarPath: this.contactAvatarPath(contact),
      avatarAnimationPath: this.contactAvatarAnimationPath(contact)
    };
  }

  /**
   * Prepends synthetic current-account row when it is available and not duplicated.
   *
   * @param meContact Synthetic current-account row.
   * @param contacts Contact rows returned from TDLib.
   * @returns Ordered rows rendered by the contacts page.
   */
  visibleContacts(meContact: TdContactListItem | undefined, contacts: TdContactListItem[]): TdContactListItem[] {
    if (!meContact) {
      return contacts;
    }

    const nextContacts: TdContactListItem[] = [meContact];
    for (let index = 0; index < contacts.length; index += 1) {
      const contact = contacts[index];
      if (contact.id !== meContact.id) {
        nextContacts.push(contact);
      }
    }
    return nextContacts;
  }

  /**
   * Creates a deep-enough clone of one TDLib contacts payload for ArkUI state ownership.
   *
   * @param items The TDLib contacts payload.
   * @returns The cloned contacts payload.
   */
  private cloneContacts(items: TdContactListItem[]): TdContactListItem[] {
    const clonedContacts: TdContactListItem[] = [];
    for (let index = 0; index < items.length; index += 1) {
      const item = items[index];
      clonedContacts.push({
        id: item.id,
        firstName: item.firstName,
        lastName: item.lastName,
        username: item.username,
        phoneNumber: item.phoneNumber,
        avatarPath: item.avatarPath,
        avatarAnimationPath: item.avatarAnimationPath,
        avatarFileId: item.avatarFileId,
        isMutualContact: item.isMutualContact,
        statusKind: item.statusKind,
        lastSeenAt: item.lastSeenAt,
        accentColorId: item.accentColorId
      });
    }

    return clonedContacts;
  }

  /**
   * Resolves deterministic palette index for contact fallback avatar.
   *
   * @param contact The contact item.
   * @returns Palette index in range `0..7`.
   */
  private resolveContactAvatarPaletteIndex(contact: TdContactListItem): number {
    if (typeof contact.accentColorId === 'number' && contact.accentColorId >= 0) {
      return contact.accentColorId % 8;
    }
    return textSignature(contact.id) % 8;
  }
}
