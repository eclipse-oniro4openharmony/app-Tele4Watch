import { TdContactListItem, TdUserPayload } from './TdPayloadTypes';
import { mapContactFromUser } from './TdUserParser';

/**
 * Pure contact-list orchestration helper used by `TdClient`.
 *
 * Responsibilities:
 * - keep ordered Telegram contact ids returned by `getContacts`
 * - keep cached contact rows mapped from `user` / `updateUser`
 * - avoid premature empty emissions before any known contact is hydrated
 */
export class TdContactsCoordinator {
  private contactUserIds: string[] = [];
  private contactItemByUserId: Map<string, TdContactListItem> = new Map<string, TdContactListItem>();

  /**
   * Replaces current contact order with ids returned by TDLib.
   *
   * @param userIds Ordered contact user ids.
   */
  setContactUserIds(userIds: string[]): void {
    const nextUserIds: string[] = [];
    for (let index = 0; index < userIds.length; index += 1) {
      const userId = userIds[index].trim();
      if (userId.length > 0) {
        nextUserIds.push(userId);
      }
    }
    this.contactUserIds = nextUserIds;
  }

  /**
   * Returns current ordered contact user ids.
   *
   * @returns Cloned ordered contact user ids.
   */
  getContactUserIds(): string[] {
    const clonedUserIds: string[] = [];
    for (let index = 0; index < this.contactUserIds.length; index += 1) {
      clonedUserIds.push(this.contactUserIds[index]);
    }
    return clonedUserIds;
  }

  /**
   * Applies one TDLib user payload to cached contact rows.
   *
   * @param userObj Raw TDLib user object.
   * @returns `true` when current contacts snapshot changed.
   */
  applyUserUpdate(userObj: TdUserPayload): boolean {
    if (typeof userObj.id !== 'number' || userObj.id <= 0) {
      return false;
    }

    const userId = String(userObj.id);
    const isKnownContactId = this.contactUserIds.indexOf(userId) >= 0;
    const mappedContact = mapContactFromUser(userObj);
    if (!mappedContact) {
      if (!isKnownContactId && !this.contactItemByUserId.has(userId)) {
        return false;
      }
      this.contactItemByUserId.delete(userId);
      this.removeContactUserId(userId);
      return true;
    }

    if (!isKnownContactId) {
      return false;
    }

    this.contactItemByUserId.set(userId, mappedContact);
    return true;
  }

  /**
   * Returns whether current contacts state should react to updates of given user.
   *
   * @param userId TDLib user id as string.
   * @returns `true` when user belongs to current contacts state.
   */
  shouldIncludeUser(userId: string): boolean {
    if (this.contactItemByUserId.has(userId)) {
      return true;
    }
    return this.contactUserIds.indexOf(userId) >= 0;
  }

  /**
   * Builds ordered contacts snapshot for UI emission.
   *
   * Returns `undefined` when contact ids are already known but no contact row
   * has been hydrated yet. This prevents premature empty-state rendering.
   *
   * @returns Ordered contact rows, empty list, or `undefined`.
   */
  buildContactsSnapshot(): TdContactListItem[] | undefined {
    const contacts: TdContactListItem[] = [];
    for (let index = 0; index < this.contactUserIds.length; index += 1) {
      const userId = this.contactUserIds[index];
      const cachedContact = this.contactItemByUserId.get(userId);
      if (!cachedContact) {
        continue;
      }
      contacts.push(this.cloneContact(cachedContact));
    }

    if (contacts.length <= 0 && this.contactUserIds.length > 0) {
      return undefined;
    }
    return contacts;
  }

  /**
   * Clears all cached contact state.
   */
  reset(): void {
    this.contactUserIds = [];
    this.contactItemByUserId.clear();
  }

  /**
   * Removes one user id from current contact order.
   *
   * @param userId User id as TDLib int64 string.
   */
  private removeContactUserId(userId: string): void {
    const nextContactUserIds: string[] = [];
    for (let index = 0; index < this.contactUserIds.length; index += 1) {
      const currentUserId = this.contactUserIds[index];
      if (currentUserId !== userId) {
        nextContactUserIds.push(currentUserId);
      }
    }
    this.contactUserIds = nextContactUserIds;
  }

  /**
   * Creates ArkTS-safe clone of cached contact row.
   *
   * @param contact Cached contact row.
   * @returns Cloned contact row.
   */
  private cloneContact(contact: TdContactListItem): TdContactListItem {
    return {
      'id': contact.id,
      'firstName': contact.firstName,
      'lastName': contact.lastName,
      'username': contact.username,
      'phoneNumber': contact.phoneNumber,
      'avatarPath': contact.avatarPath,
      'avatarFileId': contact.avatarFileId,
      'isMutualContact': contact.isMutualContact,
      'statusKind': contact.statusKind,
      'lastSeenAt': contact.lastSeenAt,
      'accentColorId': contact.accentColorId
    };
  }
}
