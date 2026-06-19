import {
  TdActiveNotificationGroupPayload,
  TdChatId,
  TdFormattedTextValue,
  TdIntValue,
  TdMessageContentPayload,
  TdMessageSenderPayload,
  TdNotificationContentKind,
  TdNotificationContentPayload,
  TdNotificationGroupPayload,
  TdNotificationGroupTypePayload,
  TdNotificationItem,
  TdNotificationPayload,
  TdNotificationTypePayload,
  TdUpdateActiveNotificationsPayload,
  TdUpdateNotificationGroupPayload,
  TdUpdateNotificationPayload
} from './TdPayloadTypes';

/**
 * Result of parsing `updateNotification` payload.
 */
export interface TdParsedUpdateNotificationResult {
  /** Whether payload was parsed and contains a usable notification item. */
  'ok': boolean;
  /** Parsed notification group id. */
  'groupId'?: number;
  /** Parsed notification item. */
  'item'?: TdNotificationItem;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing `updateNotificationGroup` payload.
 */
export interface TdParsedUpdateNotificationGroupResult {
  /** Whether payload was parsed and contains a usable notification group. */
  'ok': boolean;
  /** Parsed notification group payload. */
  'group'?: TdNotificationGroupPayload;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing `updateActiveNotifications` payload.
 */
export interface TdParsedUpdateActiveNotificationsResult {
  /** Whether payload was parsed and contains active notification groups. */
  'ok': boolean;
  /** Parsed active notification groups. */
  'groups'?: TdNotificationGroupPayload[];
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Reads TDLib `@type` field from payload object.
 *
 * ArkTS does not allow direct typed access to the `@type` field without unsafe
 * dynamic indexing, so parser code extracts it from serialized TDLib payloads.
 *
 * @param value Parsed TDLib object that may contain `@type`.
 * @returns Type string or empty string when unavailable.
 */
function readPayloadType(
  value: TdNotificationTypePayload | TdNotificationGroupTypePayload | TdMessageSenderPayload |
    TdMessageContentPayload | undefined
): string {
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

/**
 * Reads TDLib id-like value as non-empty string.
 *
 * @param value TDLib id represented as number or string.
 * @returns Id string or empty string when value is invalid.
 */
function parseIdString(value: TdChatId | TdIntValue | undefined): string {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed.length > 0) {
      return trimmed;
    }
    return '';
  }
  if (typeof value === 'number' && value !== 0) {
    return String(value);
  }
  return '';
}

/**
 * Normalizes a TDLib integer-like value to positive number.
 *
 * @param value Number or numeric string from TDLib payload.
 * @returns Positive integer or `0` when invalid.
 */
function parsePositiveInt(value: TdIntValue | undefined): number {
  if (typeof value === 'number' && value > 0) {
    return Math.trunc(value);
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
 * Normalizes a TDLib integer-like value to non-negative number.
 *
 * @param value Number or numeric string from TDLib payload.
 * @returns Non-negative integer or `0` when invalid.
 */
function parseNonNegativeInt(value: TdIntValue | undefined): number {
  if (typeof value === 'number' && value >= 0) {
    return Math.trunc(value);
  }
  if (typeof value === 'string' && value.length > 0) {
    const parsed = Number.parseInt(value, 10);
    if (!Number.isNaN(parsed) && parsed >= 0) {
      return parsed;
    }
  }
  return 0;
}

/**
 * Reads plain text from TDLib formatted text object.
 *
 * @param value TDLib formatted text object.
 * @returns Plain text or empty string when unavailable.
 */
function readFormattedText(value: TdFormattedTextValue | undefined): string {
  if (typeof value === 'string') {
    return value;
  }
  if (!value || typeof value.text !== 'string') {
    return '';
  }
  return value.text;
}

/**
 * Extracts sender user id from TDLib sender object.
 *
 * @param sender TDLib sender object.
 * @returns User id string for user senders, otherwise `undefined`.
 */
function parseSenderUserId(sender: TdMessageSenderPayload | undefined): string | undefined {
  if (!sender || readPayloadType(sender) !== 'messageSenderUser') {
    return undefined;
  }
  const userId = parseIdString(sender.user_id);
  return userId.length > 0 ? userId : undefined;
}

/**
 * Extracts sender chat id from TDLib sender object.
 *
 * @param sender TDLib sender object.
 * @returns Chat id string for chat senders, otherwise `undefined`.
 */
function parseSenderChatId(sender: TdMessageSenderPayload | undefined): string | undefined {
  if (!sender || readPayloadType(sender) !== 'messageSenderChat') {
    return undefined;
  }
  const chatId = parseIdString(sender.chat_id);
  return chatId.length > 0 ? chatId : undefined;
}

/**
 * Maps TDLib message-content type to notification content kind.
 *
 * @param contentType TDLib message content `@type`.
 * @returns Normalized notification content kind.
 */
function parseContentKind(contentType: string): TdNotificationContentKind {
  if (contentType === 'messageText') {
    return 'text';
  }
  if (contentType === 'messagePhoto') {
    return 'photo';
  }
  if (contentType === 'messageAnimation') {
    return 'animation';
  }
  if (contentType === 'messageVideo') {
    return 'video';
  }
  if (contentType === 'messageVideoNote') {
    return 'videoNote';
  }
  if (contentType === 'messageVoiceNote') {
    return 'voiceNote';
  }
  if (contentType === 'messageSticker') {
    return 'sticker';
  }
  if (contentType === 'messageAnimatedEmoji') {
    return 'animatedEmoji';
  }
  if (contentType.startsWith('messageChat') ||
    contentType === 'messageBasicGroupChatCreate' ||
    contentType === 'messageSupergroupChatCreate' ||
    contentType === 'messagePinMessage' ||
    contentType === 'messageScreenshotTaken' ||
    contentType === 'messageContactRegistered') {
    return 'serviceEvent';
  }
  return 'unsupported';
}

/**
 * Builds a safe notification preview for one TDLib message content payload.
 *
 * @param content TDLib message content payload.
 * @param showPreview Whether TDLib allows showing message preview text.
 * @returns Notification content payload.
 */
function parseNotificationContent(
  content: TdMessageContentPayload | undefined,
  showPreview: boolean
): TdNotificationContentPayload {
  if (!content) {
    return {
      'kind': 'unsupported',
      'text': showPreview ? '(unsupported message)' : 'New message',
      'showPreview': showPreview
    };
  }

  const contentType = readPayloadType(content);
  const kind = parseContentKind(contentType);
  if (!showPreview) {
    return {
      'kind': kind,
      'text': 'New message',
      'showPreview': false
    };
  }

  if (kind === 'text') {
    const text = readFormattedText(content.text);
    return {
      'kind': kind,
      'text': text.length > 0 ? text : '(empty message)',
      'showPreview': true
    };
  }

  const caption = readFormattedText(content.caption);
  if (caption.length > 0) {
    return {
      'kind': kind,
      'text': caption,
      'showPreview': true
    };
  }

  if (kind === 'photo') {
    return { 'kind': kind, 'text': '[photo]', 'showPreview': true };
  }
  if (kind === 'animation') {
    return { 'kind': kind, 'text': '[animation]', 'showPreview': true };
  }
  if (kind === 'video') {
    return { 'kind': kind, 'text': '[video]', 'showPreview': true };
  }
  if (kind === 'videoNote') {
    return { 'kind': kind, 'text': '[video note]', 'showPreview': true };
  }
  if (kind === 'voiceNote') {
    return { 'kind': kind, 'text': '[voice note]', 'showPreview': true };
  }
  if (kind === 'sticker') {
    if (content.sticker && typeof content.sticker.emoji === 'string' && content.sticker.emoji.length > 0) {
      return { 'kind': kind, 'text': content.sticker.emoji, 'showPreview': true };
    }
    return { 'kind': kind, 'text': '[sticker]', 'showPreview': true };
  }
  if (kind === 'animatedEmoji') {
    const animatedText = readFormattedText(content.text);
    return {
      'kind': kind,
      'text': animatedText.length > 0 ? animatedText : '[animated emoji]',
      'showPreview': true
    };
  }
  if (kind === 'serviceEvent') {
    return { 'kind': kind, 'text': '[service message]', 'showPreview': true };
  }

  return {
    'kind': 'unsupported',
    'text': contentType.length > 0 ? `[${contentType}]` : '(unsupported message)',
    'showPreview': true
  };
}

/**
 * Parses one TDLib notification into a UI-facing notification item.
 *
 * @param notification Raw TDLib notification object.
 * @param groupId Parent TDLib notification group id.
 * @param fallbackChatId Top-level chat id from group payload.
 * @returns Parsed notification item or `undefined` when required fields are missing.
 */
function parseNotificationItem(
  notification: TdNotificationPayload,
  groupId: number,
  fallbackChatId: string
): TdNotificationItem | undefined {
  const notificationId = parsePositiveInt(notification.id);
  if (notificationId <= 0) {
    return undefined;
  }

  const notificationType = notification.type;
  if (!notificationType || readPayloadType(notificationType) !== 'notificationTypeNewMessage') {
    return undefined;
  }

  const message = notificationType.message;
  if (!message) {
    return undefined;
  }

  let chatId = parseIdString(message.chat_id);
  if (chatId.length === 0) {
    chatId = fallbackChatId;
  }
  if (chatId.length === 0) {
    return undefined;
  }

  const messageId = parseIdString(message.id);
  const showPreview = notificationType.show_preview === true;
  const parsedItem: TdNotificationItem = {
    'id': notificationId,
    'groupId': groupId,
    'chatId': chatId,
    'messageId': messageId.length > 0 ? messageId : undefined,
    'senderUserId': parseSenderUserId(message.sender_id),
    'senderChatId': parseSenderChatId(message.sender_id),
    'date': parseNonNegativeInt(notification.date),
    'isSilent': notification.is_silent === true,
    'content': parseNotificationContent(message.content, showPreview)
  };
  return parsedItem;
}

/**
 * Parses removed notification ids from TDLib update payload.
 *
 * @param rawIds Raw TDLib notification ids.
 * @returns Positive notification ids.
 */
function parseRemovedNotificationIds(rawIds: TdIntValue[] | undefined): number[] {
  const parsedIds: number[] = [];
  if (!Array.isArray(rawIds)) {
    return parsedIds;
  }

  for (const rawId of rawIds) {
    const parsedId = parsePositiveInt(rawId);
    if (parsedId > 0) {
      parsedIds.push(parsedId);
    }
  }
  return parsedIds;
}

/**
 * Parses TDLib notification array into UI-facing notification items.
 *
 * @param notifications Raw TDLib notification array.
 * @param groupId Parent TDLib notification group id.
 * @param chatId Parent chat id.
 * @returns Parsed notification items.
 */
function parseNotificationItems(
  notifications: TdNotificationPayload[] | undefined,
  groupId: number,
  chatId: string
): TdNotificationItem[] {
  const items: TdNotificationItem[] = [];
  if (!Array.isArray(notifications)) {
    return items;
  }

  for (const notification of notifications) {
    const item = parseNotificationItem(notification, groupId, chatId);
    if (item) {
      items.push(item);
    }
  }
  return items;
}

/**
 * Parses raw active notification group into UI-facing group payload.
 *
 * @param rawGroup TDLib active notification group snapshot.
 * @returns Parsed group payload or `undefined` when required fields are missing.
 */
function parseActiveNotificationGroup(
  rawGroup: TdActiveNotificationGroupPayload
): TdNotificationGroupPayload | undefined {
  const groupId = parsePositiveInt(rawGroup.id);
  const chatId = parseIdString(rawGroup.chat_id);
  if (groupId <= 0 || chatId.length === 0) {
    return undefined;
  }

  return {
    'groupId': groupId,
    'chatId': chatId,
    'totalCount': parseNonNegativeInt(rawGroup.total_count),
    'items': parseNotificationItems(rawGroup.notifications, groupId, chatId),
    'removedNotificationIds': []
  };
}

/**
 * Parses TDLib payload that should contain `updateNotification`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with normalized notification item.
 */
export function parseUpdateNotification(payload: string): TdParsedUpdateNotificationResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateNotificationPayload;
    const groupId = parsePositiveInt(parsed.notification_group_id);
    if (groupId <= 0 || !parsed.notification) {
      return { 'ok': false };
    }

    const item = parseNotificationItem(parsed.notification, groupId, '');
    if (!item) {
      return { 'ok': false };
    }

    return {
      'ok': true,
      'groupId': groupId,
      'item': item
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain `updateNotificationGroup`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with normalized notification group.
 */
export function parseUpdateNotificationGroup(payload: string): TdParsedUpdateNotificationGroupResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateNotificationGroupPayload;
    const groupId = parsePositiveInt(parsed.notification_group_id);
    const chatId = parseIdString(parsed.chat_id);
    if (groupId <= 0 || chatId.length === 0) {
      return { 'ok': false };
    }

    const notificationSettingsChatId = parseIdString(parsed.notification_settings_chat_id);
    const group: TdNotificationGroupPayload = {
      'groupId': groupId,
      'chatId': chatId,
      'notificationSettingsChatId': notificationSettingsChatId.length > 0 ? notificationSettingsChatId : undefined,
      'totalCount': parseNonNegativeInt(parsed.total_count),
      'items': parseNotificationItems(parsed.added_notifications, groupId, chatId),
      'removedNotificationIds': parseRemovedNotificationIds(parsed.removed_notification_ids)
    };
    return {
      'ok': true,
      'group': group
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain `updateActiveNotifications`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with normalized active notification groups.
 */
export function parseUpdateActiveNotifications(payload: string): TdParsedUpdateActiveNotificationsResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateActiveNotificationsPayload;
    const rawGroups = parsed.groups;
    if (!Array.isArray(rawGroups)) {
      return { 'ok': false };
    }

    const groups: TdNotificationGroupPayload[] = [];
    for (const rawGroup of rawGroups) {
      const group = parseActiveNotificationGroup(rawGroup);
      if (group) {
        groups.push(group);
      }
    }

    return {
      'ok': true,
      'groups': groups
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}
