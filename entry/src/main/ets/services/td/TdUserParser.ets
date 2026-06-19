import {
  TdContactStatusKind,
  TdContactListItem,
  TdIntValue,
  TdUpdateUserFullInfoPayload,
  TdUpdateUserPayload,
  TdUserFullInfoPayload,
  TdUserPayload,
  TdUserStatusPayload,
  TdUsersPayload
} from './TdPayloadTypes';

/**
 * Result of user payload parsing.
 */
export interface TdParsedUserResult {
  /** Whether payload was parsed and contains user with numeric id. */
  'ok': boolean;
  /** Parsed user object when `ok` is true. */
  'user'?: TdUserPayload;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of `users` payload parsing.
 */
export interface TdParsedUsersResult {
  /** Whether payload was parsed and contains user ids array. */
  'ok': boolean;
  /** Parsed user identifiers normalized as strings. */
  'userIds'?: string[];
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of user-full-info payload parsing.
 */
export interface TdParsedUserFullInfoResult {
  /** Whether payload was parsed and contains user full info object. */
  'ok': boolean;
  /** Parsed user identifier for update payloads. */
  'userId'?: string;
  /** Parsed user full info payload. */
  'userFullInfo'?: TdUserFullInfoPayload;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Parses TDLib payload that should contain `users` object.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with normalized user ids.
 */
export function parseUsersPayload(payload: string): TdParsedUsersResult {
  try {
    const parsed = JSON.parse(payload) as TdUsersPayload;
    const rawUserIds = parsed.user_ids;
    if (!Array.isArray(rawUserIds)) {
      return { 'ok': false };
    }

    const userIds: string[] = [];
    for (let index = 0; index < rawUserIds.length; index += 1) {
      const rawUserId = rawUserIds[index];
      if (typeof rawUserId === 'number' && rawUserId > 0) {
        userIds.push(String(rawUserId));
      } else if (typeof rawUserId === 'string' && rawUserId.length > 0) {
        userIds.push(rawUserId);
      }
    }

    return {
      'ok': true,
      'userIds': userIds
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Maps one TDLib user payload into contact-list item when the user is a Telegram contact.
 *
 * @param user Raw TDLib user payload.
 * @returns Normalized contact-list item or `undefined` when payload is not a contact.
 */
export function mapContactFromUser(user: TdUserPayload): TdContactListItem | undefined {
  if (typeof user.id !== 'number' || user.id <= 0 || user.is_contact !== true) {
    return undefined;
  }

  let avatarFileId: number | undefined = undefined;
  let avatarPath: string | undefined = undefined;
  const profilePhoto = user.profile_photo;
  if (profilePhoto && profilePhoto.small) {
    const smallPhoto = profilePhoto.small;
    if (typeof smallPhoto.id === 'number' && smallPhoto.id > 0) {
      avatarFileId = smallPhoto.id;
    }
    const localPhoto = smallPhoto.local;
    if (localPhoto && typeof localPhoto.path === 'string' && localPhoto.path.length > 0) {
      avatarPath = localPhoto.path;
    }
  }

  const firstName = typeof user.first_name === 'string' ? user.first_name : '';
  const lastName = typeof user.last_name === 'string' ? user.last_name : '';
  const username = resolveUsername(user);
  const phoneNumber = typeof user.phone_number === 'string' ? user.phone_number : '';
  const statusKind = mapContactStatusKind(user);
  const lastSeenAt = resolveLastSeenAt(user);
  const accentColorId = parseIntValue(user.accent_color_id);

  return {
    'id': String(user.id),
    'firstName': firstName,
    'lastName': lastName,
    'username': username,
    'phoneNumber': phoneNumber,
    'avatarPath': avatarPath,
    'avatarFileId': avatarFileId,
    'isMutualContact': user.is_mutual_contact === true,
    'statusKind': statusKind,
    'lastSeenAt': lastSeenAt > 0 ? lastSeenAt : undefined,
    'accentColorId': accentColorId >= 0 ? accentColorId : undefined
  };
}

/**
 * Parses TDLib payload that should contain direct `user` object.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with user data or parsing diagnostics.
 */
export function parseUserPayload(payload: string): TdParsedUserResult {
  try {
    const parsed = JSON.parse(payload) as TdUserPayload;
    if (typeof parsed.id !== 'number') {
      return { 'ok': false };
    }
    return {
      'ok': true,
      'user': parsed
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain `updateUser` with nested `user`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with user data or parsing diagnostics.
 */
export function parseUpdateUserPayload(payload: string): TdParsedUserResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateUserPayload;
    const userObj = parsed.user;
    if (!userObj || typeof userObj.id !== 'number') {
      return { 'ok': false };
    }
    return {
      'ok': true,
      'user': userObj
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain direct `userFullInfo` object.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with user-full-info payload.
 */
export function parseUserFullInfoPayload(payload: string): TdParsedUserFullInfoResult {
  try {
    const parsed = JSON.parse(payload) as TdUserFullInfoPayload;
    return {
      'ok': true,
      'userFullInfo': parsed
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain `updateUserFullInfo`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with user id and user-full-info payload.
 */
export function parseUpdateUserFullInfoPayload(payload: string): TdParsedUserFullInfoResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateUserFullInfoPayload;
    const rawUserId = parsed.user_id;
    if (typeof rawUserId !== 'number' && typeof rawUserId !== 'string') {
      return { 'ok': false };
    }
    const userFullInfo = parsed.user_full_info;
    if (!userFullInfo) {
      return { 'ok': false };
    }
    return {
      'ok': true,
      'userId': String(rawUserId),
      'userFullInfo': userFullInfo
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Resolves preferred username from legacy and container fields.
 *
 * @param user Raw TDLib user payload.
 * @returns Preferred username or empty string when unavailable.
 */
export function resolveUsername(user: TdUserPayload): string {
  if (typeof user.username === 'string' && user.username.length > 0) {
    return user.username;
  }

  const usernames = user.usernames;
  if (!usernames) {
    return '';
  }
  const activeUsernames = usernames.active_usernames;
  if (Array.isArray(activeUsernames) && activeUsernames.length > 0) {
    for (let index = 0; index < activeUsernames.length; index += 1) {
      const username = activeUsernames[index];
      if (typeof username === 'string' && username.length > 0) {
        return username;
      }
    }
  }
  if (typeof usernames.editable_username === 'string' && usernames.editable_username.length > 0) {
    return usernames.editable_username;
  }

  return '';
}

function parseIntValue(value: TdIntValue | undefined): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === 'string' && value.length > 0) {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return -1;
}

function mapContactStatusKind(user: TdUserPayload): TdContactStatusKind {
  const status = user.status;
  const statusType = readUserStatusType(status);
  if (statusType === 'userStatusOnline') {
    return 'online';
  }
  if (statusType === 'userStatusOffline') {
    return 'offline';
  }
  if (statusType === 'userStatusRecently') {
    return 'recently';
  }
  if (statusType === 'userStatusLastWeek') {
    return 'lastWeek';
  }
  if (statusType === 'userStatusLastMonth') {
    return 'lastMonth';
  }
  return 'empty';
}

function resolveLastSeenAt(user: TdUserPayload): number {
  const status = user.status;
  const statusType = readUserStatusType(status);
  if (statusType !== 'userStatusOffline') {
    return 0;
  }
  return parseIntValue(status?.was_online);
}

function readUserStatusType(value: TdUserStatusPayload | undefined): string {
  if (!value) {
    return '';
  }
  const serialized = JSON.stringify(value);
  const match = serialized.match(/\"@type\"\s*:\s*\"([^\"]+)\"/);
  if (!match || match.length < 2) {
    return '';
  }
  return match[1];
}
