import {
  TdChatFoldersPayload,
  TdChatKind,
  TdChatListPayload,
  TdChatListItem,
  TdCallEventStatus,
  TdChatMessageKind,
  TdChatNotificationSettingsPayload,
  TdChatPhotoInfoPayload,
  TdChatPayload,
  TdChatTypePayload,
  TdChatsPayload,
  TdFilePayload,
  TdIntValue,
  TdChatMessagePayload,
  TdUpdateChatReadInboxPayload,
  TdUpdateChatLastMessagePayload,
  TdUpdateChatListMembershipPayload,
  TdUpdateChatNotificationSettingsPayload,
  TdUpdateChatPhotoPayload,
  TdUpdateChatPositionPayload,
  TdUpdateChatReadOutboxPayload,
  TdUpdateChatTitlePayload,
  TdUpdateFilePayload,
  TdUpdateNewChatPayload
} from './TdPayloadTypes';
import {
  parseChatMessagePayload
} from './TdMessageParser';
import {
  buildChatListMessagePreview,
  TdChatListMessagePreview
} from './TdChatPreviewMapper';
import { UiTextValue } from '../../models/ui/UiTextValue';

/**
 * Result of parsing `chats` payload (list of chat ids).
 */
export interface TdParsedChatsResult {
  /** Whether payload was parsed and contains chat ids array. */
  'ok': boolean;
  /** Normalized chat ids as strings. */
  'chatIds'?: string[];
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing `chatFolders` payload.
 */
export interface TdParsedChatFoldersResult {
  /** Whether payload was parsed and contains folder ids array. */
  'ok': boolean;
  /** Normalized folder ids. */
  'folderIds'?: number[];
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing single `chat` payload.
 */
export interface TdParsedChatResult {
  /** Whether payload was parsed and contains chat id. */
  'ok': boolean;
  /** Parsed chat list item when `ok` is true. */
  'chat'?: TdChatListItem;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing `updateFile` payload.
 */
export interface TdParsedUpdateFileResult {
  /** Whether payload was parsed and contains file id. */
  'ok': boolean;
  /** Parsed file id when `ok` is true. */
  'fileId'?: number;
  /** Parsed local file path when available. */
  'localPath'?: string;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing `updateChatLastMessage` payload.
 */
export interface TdParsedUpdateChatLastMessageResult {
  /** Whether payload was parsed and contains chat id plus timestamp. */
  'ok': boolean;
  /** Parsed chat id when `ok` is true. */
  'chatId'?: string;
  /** Parsed unix timestamp (seconds) for last message. */
  'lastMessageDate'?: number;
  /** Parsed text preview for last message. */
  'lastMessageText'?: string;
  /** Parsed resource-backed text preview for last message. */
  'lastMessageTextValue'?: UiTextValue;
  /** Parsed normalized kind for last message. */
  'lastMessageKind'?: TdChatMessageKind;
  /** Whether the last message was sent by the local user. */
  'lastMessageIsOutgoing'?: boolean;
  /** Call-event outcome for the last message when it is a `callEvent`. */
  'lastMessageCallEventStatus'?: TdCallEventStatus;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

type TdParsedLastMessagePreview = TdChatListMessagePreview;

/**
 * Result of parsing `updateChatTitle`.
 */
export interface TdParsedUpdateChatTitleResult {
  /** Whether payload was parsed and contains chat id plus title. */
  'ok': boolean;
  /** Parsed chat id when `ok` is true. */
  'chatId'?: string;
  /** Parsed chat title. */
  'title'?: string;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing `updateChatPhoto`.
 */
export interface TdParsedUpdateChatPhotoResult {
  /** Whether payload was parsed and contains chat id plus photo state. */
  'ok': boolean;
  /** Parsed chat id when `ok` is true. */
  'chatId'?: string;
  /** Whether TDLib reports an active chat photo. */
  'hasPhoto'?: boolean;
  /** TDLib small avatar file id when available. */
  'avatarFileId'?: number;
  /** Local avatar path when already available. */
  'avatarPath'?: string;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing `updateChatReadInbox` payload.
 */
export interface TdParsedUpdateChatReadInboxResult {
  /** Whether payload was parsed and contains chat id. */
  'ok': boolean;
  /** Parsed chat id when `ok` is true. */
  'chatId'?: string;
  /** Parsed last read inbox message id. */
  'lastReadInboxMessageId'?: string;
  /** Parsed unread counter. */
  'unreadCount'?: number;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing `updateChatReadOutbox` payload.
 */
export interface TdParsedUpdateChatReadOutboxResult {
  /** Whether payload was parsed and contains chat id. */
  'ok': boolean;
  /** Parsed chat id when `ok` is true. */
  'chatId'?: string;
  /** Parsed last read outbox message id. */
  'lastReadOutboxMessageId'?: string;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing `updateChatNotificationSettings` payload.
 */
export interface TdParsedUpdateChatNotificationSettingsResult {
  /** Whether payload was parsed and contains chat notification settings. */
  'ok': boolean;
  /** Parsed chat id when `ok` is true. */
  'chatId'?: string;
  /** Parsed mute duration left in seconds. */
  'muteFor'?: number;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing `updateChatPosition`.
 */
export interface TdParsedUpdateChatPositionResult {
  /** Whether payload was parsed and contains chat position metadata. */
  'ok': boolean;
  /** Parsed chat id when `ok` is true. */
  'chatId'?: string;
  /** Whether the position belongs to the main chat list. */
  'isMainList'?: boolean;
  /** TDLib order string, or `0` when the chat is removed from this list. */
  'order'?: string;
  /** Whether TDLib marks this position as pinned. */
  'isPinned'?: boolean;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing chat-list membership updates.
 */
export interface TdParsedChatListMembershipResult {
  /** Whether payload was parsed and contains chat-list membership metadata. */
  'ok': boolean;
  /** Parsed chat id when `ok` is true. */
  'chatId'?: string;
  /** Whether the event targets the main chat list. */
  'isMainList'?: boolean;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Normalizes TDLib integer-like values to number.
 *
 * @param value Number or numeric string from TDLib payload.
 * @returns Parsed positive integer or `0` when invalid.
 */
function parseIntValue(value: TdIntValue | undefined): number {
  if (typeof value === 'number' && value > 0) {
    return value;
  }
  if (typeof value === 'string' && value.length > 0) {
    const parsed = Number.parseInt(value, 10);
    if (!Number.isNaN(parsed) && parsed > 0) {
      return parsed;
    }
  }
  return 0;
}

/**
 * Parses the remaining mute duration from chat notification settings.
 *
 * @param settings Raw TDLib chat notification settings.
 * @returns Mute duration left in seconds or `0` when chat is not muted.
 */
function parseNotificationMuteFor(settings: TdChatNotificationSettingsPayload | undefined): number {
  if (!settings) {
    return 0;
  }
  return parseIntValue(settings.mute_for);
}

/**
 * Extracts unix timestamp (seconds) from TDLib message payload.
 *
 * @param message Raw TDLib message object.
 * @returns Parsed timestamp in seconds or `0` when missing.
 */
function parseMessageDate(message: TdChatMessagePayload | undefined): number {
  if (!message) {
    return 0;
  }
  return parseIntValue(message.date);
}

/**
 * Extracts display preview data from TDLib last-message payload.
 *
 * @param message Raw TDLib message object.
 * @param chatId Parent chat id.
 * @returns Trimmed preview text and optional resource-backed descriptor.
 */
function parseLastMessagePreview(
  message: TdChatMessagePayload | undefined,
  chatId: string
): TdParsedLastMessagePreview {
  if (!message) {
    return {};
  }
  const parsedMessage = parseChatMessagePayload(message, chatId);
  if (!parsedMessage) {
    return {};
  }

  return buildChatListMessagePreview(parsedMessage);
}

/**
 * Normalizes user-like chat peer id to string when available.
 *
 * @param chatType Raw TDLib chat type payload.
 * @returns Peer user id for private-like chats, otherwise `undefined`.
 */
function parsePeerUserId(chatType: TdChatTypePayload | undefined): string | undefined {
  if (!chatType) {
    return undefined;
  }
  const rawUserId = chatType.user_id;
  if (typeof rawUserId === 'string' && rawUserId.length > 0) {
    return rawUserId;
  }
  if (typeof rawUserId === 'number' && rawUserId > 0) {
    return String(rawUserId);
  }
  return undefined;
}

/**
 * ArkTS does not allow direct typed access to the `@type` field without unsafe
 * dynamic indexing, so parser code extracts it from serialized TDLib payloads.
 *
 * @param chatType Parsed TDLib chat-type object.
 * @returns Type string or empty string when unavailable.
 */
function readPayloadType(chatType: TdChatTypePayload | undefined): string {
  if (!chatType) {
    return '';
  }
  const serialized = JSON.stringify(chatType);
  const match = serialized.match(/\"@type\"\s*:\s*\"([^\"]+)\"/);
  if (!match || match.length < 2) {
    return '';
  }
  return match[1];
}

/**
 * Extracts TDLib `@type` from a chat-list payload without dynamic field access.
 *
 * @param chatList Parsed TDLib chat-list object.
 * @returns Type string or empty string when unavailable.
 */
function readChatListType(chatList: TdChatListPayload | undefined): string {
  if (!chatList) {
    return '';
  }
  const serialized = JSON.stringify(chatList);
  const match = serialized.match(/\"@type\"\s*:\s*\"([^\"]+)\"/);
  if (!match || match.length < 2) {
    return '';
  }
  return match[1];
}

/**
 * Normalizes TDLib chat-position order to a string.
 *
 * @param value Raw order value.
 * @returns Normalized numeric text or empty string when invalid.
 */
function parseChatPositionOrder(value: TdIntValue | undefined): string {
  if (typeof value === 'number') {
    if (value > 0) {
      return String(value);
    }
    if (value === 0) {
      return '0';
    }
    return '';
  }
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed.length === 0) {
      return '';
    }
    const parsed = Number.parseInt(trimmed, 10);
    if (!Number.isNaN(parsed) && parsed >= 0) {
      return trimmed;
    }
  }
  return '';
}

/**
 * Resolves normalized chat kind from TDLib chat-type payload.
 *
 * @param chatType Raw TDLib chat type payload.
 * @returns Normalized UI-facing chat kind.
 */
function parseChatKind(chatType: TdChatTypePayload | undefined): TdChatKind {
  const payloadType = readPayloadType(chatType);
  if (payloadType === 'chatTypePrivate') {
    return 'private';
  }
  if (payloadType === 'chatTypeBasicGroup') {
    return 'basicGroup';
  }
  if (payloadType === 'chatTypeSupergroup') {
    const isChannel = chatType !== undefined && chatType.is_channel === true;
    return isChannel ? 'channel' : 'supergroup';
  }
  return 'unknown';
}

/**
 * Extracts small chat-avatar file id from TDLib chat photo info.
 *
 * @param chatPhoto Raw TDLib chat photo info.
 * @returns Positive file id or `undefined`.
 */
function parseAvatarFileId(chatPhoto: TdChatPhotoInfoPayload | undefined | null): number | undefined {
  if (!chatPhoto || !chatPhoto.small) {
    return undefined;
  }
  const smallPhoto = chatPhoto.small;
  if (typeof smallPhoto.id === 'number' && smallPhoto.id > 0) {
    return smallPhoto.id;
  }
  return undefined;
}

/**
 * Extracts completed local small-avatar path from TDLib chat photo info.
 *
 * @param chatPhoto Raw TDLib chat photo info.
 * @returns Local path or `undefined`.
 */
function parseAvatarPath(chatPhoto: TdChatPhotoInfoPayload | undefined | null): string | undefined {
  if (!chatPhoto || !chatPhoto.small) {
    return undefined;
  }
  const localPhoto = chatPhoto.small.local;
  if (localPhoto
    && localPhoto.is_downloading_completed !== false
    && typeof localPhoto.path === 'string'
    && localPhoto.path.length > 0) {
    return localPhoto.path;
  }
  return undefined;
}

/**
 * Converts raw TDLib chat object into normalized chat list item.
 *
 * @param chat Raw TDLib chat object.
 * @returns Normalized chat list item or `undefined` when required fields are missing.
 */
function normalizeChatPayload(chat: TdChatPayload | undefined): TdChatListItem | undefined {
  if (!chat || (typeof chat.id !== 'string' && typeof chat.id !== 'number')) {
    return undefined;
  }

  const chatId = String(chat.id);
  const title = (typeof chat.title === 'string' && chat.title.length > 0)
    ? chat.title
    : 'Unknown chat';
  const chatType = chat.type;
  const peerUserId = parsePeerUserId(chatType);
  const chatKind = parseChatKind(chatType);

  let avatarPath: string | undefined = undefined;
  let avatarFileId: number | undefined = undefined;
  const chatPhoto = chat.photo;
  avatarFileId = parseAvatarFileId(chatPhoto);
  avatarPath = parseAvatarPath(chatPhoto);

  let lastMessageDate: number | undefined = undefined;
  const parsedDate = parseMessageDate(chat.last_message);
  if (parsedDate > 0) {
    lastMessageDate = parsedDate;
  }
  const lastMessagePreview = parseLastMessagePreview(chat.last_message, chatId);

  let lastReadInboxMessageId: string | undefined = undefined;
  if (typeof chat.last_read_inbox_message_id === 'number') {
    lastReadInboxMessageId = String(chat.last_read_inbox_message_id);
  } else if (typeof chat.last_read_inbox_message_id === 'string') {
    lastReadInboxMessageId = chat.last_read_inbox_message_id;
  }

  let lastReadOutboxMessageId: string | undefined = undefined;
  if (typeof chat.last_read_outbox_message_id === 'number') {
    lastReadOutboxMessageId = String(chat.last_read_outbox_message_id);
  } else if (typeof chat.last_read_outbox_message_id === 'string') {
    lastReadOutboxMessageId = chat.last_read_outbox_message_id;
  }

  let unreadCount: number | undefined = undefined;
  if (typeof chat.unread_count === 'number' || typeof chat.unread_count === 'string') {
    unreadCount = parseIntValue(chat.unread_count);
  }

  let defaultDisableNotification: boolean | undefined = undefined;
  if (typeof chat.default_disable_notification === 'boolean') {
    defaultDisableNotification = chat.default_disable_notification;
  }

  const notificationMuteFor = parseNotificationMuteFor(chat.notification_settings);

  return {
    'id': chatId,
    'title': title,
    'chatKind': chatKind,
    'peerUserId': peerUserId,
    'avatarPath': avatarPath,
    'avatarFileId': avatarFileId,
    'lastMessageDate': lastMessageDate,
    'lastMessageText': lastMessagePreview.text,
    'lastMessageTextValue': lastMessagePreview.textValue,
    'lastMessageKind': lastMessagePreview.kind,
    'lastMessageIsOutgoing': lastMessagePreview.isOutgoing,
    'lastMessageCallEventStatus': lastMessagePreview.callEventStatus,
    'lastReadInboxMessageId': lastReadInboxMessageId,
    'lastReadOutboxMessageId': lastReadOutboxMessageId,
    'unreadCount': unreadCount,
    'defaultDisableNotification': defaultDisableNotification,
    'notificationMuteFor': notificationMuteFor
  };
}

/**
 * Parses TDLib payload that should contain `chats` object.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with normalized chat ids.
 */
export function parseChatsPayload(payload: string): TdParsedChatsResult {
  try {
    const parsed = JSON.parse(payload) as TdChatsPayload;
    const rawIds = parsed.chat_ids;
    if (!Array.isArray(rawIds)) {
      return { 'ok': false };
    }

    const chatIds: string[] = [];
    for (const rawId of rawIds) {
      if (typeof rawId === 'string' && rawId.length > 0) {
        chatIds.push(rawId);
      } else if (typeof rawId === 'number') {
        chatIds.push(String(rawId));
      }
    }

    return {
      'ok': true,
      'chatIds': chatIds
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain `chatFolders` object.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with normalized folder ids.
 */
export function parseChatFoldersPayload(payload: string): TdParsedChatFoldersResult {
  try {
    const parsed = JSON.parse(payload) as TdChatFoldersPayload;
    const rawFolders = parsed.chat_folders;
    if (!Array.isArray(rawFolders)) {
      return { 'ok': false };
    }

    const folderIds: number[] = [];
    for (const folder of rawFolders) {
      if (typeof folder.id === 'number' && folder.id > 0) {
        folderIds.push(folder.id);
      }
    }

    return {
      'ok': true,
      'folderIds': folderIds
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain single `chat` object.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with normalized chat list item.
 */
export function parseChatPayload(payload: string): TdParsedChatResult {
  try {
    const parsed = JSON.parse(payload) as TdChatPayload;
    const chat = normalizeChatPayload(parsed);
    if (!chat) {
      return { 'ok': false };
    }

    return {
      'ok': true,
      'chat': chat
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain `updateNewChat` with nested chat object.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with normalized chat list item.
 */
export function parseUpdateNewChatPayload(payload: string): TdParsedChatResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateNewChatPayload;
    const chat = normalizeChatPayload(parsed.chat);
    if (!chat) {
      return { 'ok': false };
    }
    return {
      'ok': true,
      'chat': chat
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain `updateFile`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with file id and optional local file path.
 */
export function parseUpdateFilePayload(payload: string): TdParsedUpdateFileResult {
  try {
    const wrapped = JSON.parse(payload) as TdUpdateFilePayload;
    let fileObj: TdFilePayload | undefined = undefined;
    if (wrapped.file) {
      fileObj = wrapped.file;
    } else {
      const direct = JSON.parse(payload) as TdFilePayload;
      if (typeof direct.id === 'number') {
        fileObj = direct;
      }
    }
    if (!fileObj || typeof fileObj.id !== 'number' || fileObj.id <= 0) {
      return { 'ok': false };
    }
    const localObj = fileObj.local;
    let localPath: string | undefined = undefined;
    if (localObj
      && localObj.is_downloading_completed !== false
      && typeof localObj.path === 'string'
      && localObj.path.length > 0) {
      localPath = localObj.path;
    }
    return {
      'ok': true,
      'fileId': fileObj.id,
      'localPath': localPath
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain `updateChatLastMessage`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with chat id and unix timestamp.
 */
export function parseUpdateChatLastMessagePayload(payload: string): TdParsedUpdateChatLastMessageResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateChatLastMessagePayload;
    if (typeof parsed.chat_id !== 'string' && typeof parsed.chat_id !== 'number') {
      return { 'ok': false };
    }
    const chatId = String(parsed.chat_id);
    const lastMessageDate = parseMessageDate(parsed.last_message);
    if (lastMessageDate <= 0) {
      return { 'ok': false };
    }
    const lastMessagePreview = parseLastMessagePreview(parsed.last_message, chatId);
    return {
      'ok': true,
      'chatId': chatId,
      'lastMessageDate': lastMessageDate,
      'lastMessageText': lastMessagePreview.text,
      'lastMessageTextValue': lastMessagePreview.textValue,
      'lastMessageKind': lastMessagePreview.kind,
      'lastMessageIsOutgoing': lastMessagePreview.isOutgoing,
      'lastMessageCallEventStatus': lastMessagePreview.callEventStatus
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib `updateChatTitle` payload.
 *
 * @param payload Raw TDLib payload.
 * @returns Structured result with chat id and normalized title.
 */
export function parseUpdateChatTitlePayload(payload: string): TdParsedUpdateChatTitleResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateChatTitlePayload;
    const rawChatId = parsed.chat_id;
    if (typeof rawChatId !== 'string' && typeof rawChatId !== 'number') {
      return { 'ok': false };
    }

    if (typeof parsed.title !== 'string') {
      return { 'ok': false };
    }

    const title = parsed.title.trim();
    if (title.length === 0) {
      return { 'ok': false };
    }

    return {
      'ok': true,
      'chatId': String(rawChatId),
      'title': title
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib `updateChatPhoto` payload.
 *
 * @param payload Raw TDLib payload.
 * @returns Structured result with chat id and avatar file metadata.
 */
export function parseUpdateChatPhotoPayload(payload: string): TdParsedUpdateChatPhotoResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateChatPhotoPayload;
    const rawChatId = parsed.chat_id;
    if (typeof rawChatId !== 'string' && typeof rawChatId !== 'number') {
      return { 'ok': false };
    }

    const chatPhoto = parsed.photo;
    if (!chatPhoto) {
      return {
        'ok': true,
        'chatId': String(rawChatId),
        'hasPhoto': false
      };
    }

    const avatarFileId = parseAvatarFileId(chatPhoto);
    const avatarPath = parseAvatarPath(chatPhoto);
    return {
      'ok': true,
      'chatId': String(rawChatId),
      'hasPhoto': true,
      'avatarFileId': avatarFileId,
      'avatarPath': avatarPath
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain `updateChatReadInbox`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with normalized read-inbox metadata.
 */
export function parseUpdateChatReadInboxPayload(payload: string): TdParsedUpdateChatReadInboxResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateChatReadInboxPayload;
    const chatId = typeof parsed.chat_id === 'number'
      ? String(parsed.chat_id)
      : (typeof parsed.chat_id === 'string' ? parsed.chat_id : '');
    if (chatId.length === 0) {
      return { 'ok': false };
    }

    const lastReadInboxMessageId = typeof parsed.last_read_inbox_message_id === 'number'
      ? String(parsed.last_read_inbox_message_id)
      : (typeof parsed.last_read_inbox_message_id === 'string' ? parsed.last_read_inbox_message_id : '0');
    const unreadCount = parseIntValue(parsed.unread_count);

    return {
      'ok': true,
      'chatId': chatId,
      'lastReadInboxMessageId': lastReadInboxMessageId.length > 0 ? lastReadInboxMessageId : '0',
      'unreadCount': unreadCount
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain `updateChatReadOutbox`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with normalized read-outbox metadata.
 */
export function parseUpdateChatReadOutboxPayload(payload: string): TdParsedUpdateChatReadOutboxResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateChatReadOutboxPayload;
    const chatId = typeof parsed.chat_id === 'number'
      ? String(parsed.chat_id)
      : (typeof parsed.chat_id === 'string' ? parsed.chat_id : '');
    if (chatId.length === 0) {
      return { 'ok': false };
    }

    const lastReadOutboxMessageId = typeof parsed.last_read_outbox_message_id === 'number'
      ? String(parsed.last_read_outbox_message_id)
      : (typeof parsed.last_read_outbox_message_id === 'string' ? parsed.last_read_outbox_message_id : '0');

    return {
      'ok': true,
      'chatId': chatId,
      'lastReadOutboxMessageId': lastReadOutboxMessageId.length > 0 ? lastReadOutboxMessageId : '0'
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib `updateChatNotificationSettings` payload.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with chat id and mute duration.
 */
export function parseUpdateChatNotificationSettingsPayload(
  payload: string
): TdParsedUpdateChatNotificationSettingsResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateChatNotificationSettingsPayload;
    const rawChatId = parsed.chat_id;
    if (typeof rawChatId !== 'string' && typeof rawChatId !== 'number') {
      return { 'ok': false };
    }

    return {
      'ok': true,
      'chatId': String(rawChatId),
      'muteFor': parseNotificationMuteFor(parsed.notification_settings)
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib `updateChatPosition` payload.
 *
 * @param payload Raw TDLib payload.
 * @returns Structured result with chat id, main-list flag, and order.
 */
export function parseUpdateChatPositionPayload(payload: string): TdParsedUpdateChatPositionResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateChatPositionPayload;
    const rawChatId = parsed.chat_id;
    if (typeof rawChatId !== 'string' && typeof rawChatId !== 'number') {
      return { 'ok': false };
    }

    const position = parsed.position;
    if (!position) {
      return { 'ok': false };
    }

    const order = parseChatPositionOrder(position.order);
    if (order.length === 0) {
      return { 'ok': false };
    }

    return {
      'ok': true,
      'chatId': String(rawChatId),
      'isMainList': readChatListType(position.list) === 'chatListMain',
      'order': order,
      'isPinned': position.is_pinned === true
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib chat-list membership update payloads.
 *
 * @param payload Raw TDLib payload.
 * @returns Structured result with chat id and main-list flag.
 */
export function parseChatListMembershipPayload(payload: string): TdParsedChatListMembershipResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateChatListMembershipPayload;
    const rawChatId = parsed.chat_id;
    if (typeof rawChatId !== 'string' && typeof rawChatId !== 'number') {
      return { 'ok': false };
    }

    return {
      'ok': true,
      'chatId': String(rawChatId),
      'isMainList': readChatListType(parsed.chat_list) === 'chatListMain'
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}
