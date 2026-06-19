import { hilog } from '@kit.PerformanceAnalysisKit';
import util from '@ohos.util';
import { UiTextValue, createResourceUiText } from '../../models/ui/UiTextValue';
import {
  TdAnimatedEmojiPayload,
  TdAnimationPayload,
  TdCallDiscardReasonPayload,
  TdCallEventStatus,
  TdChatMessageItem,
  TdChatMessageKind,
  TdChatMessagePayload,
  TdFilePayload,
  TdFormattedTextValue,
  TdIntValue,
  TdMessageContentPayload,
  TdMessageSendingState,
  TdMessageSendingStatePayload,
  TdMessageSenderPayload,
  TdMessagesPayload,
  TdMinithumbnailPayload,
  TdPhotoSizePayload,
  TdServiceMessageContentPayload,
  TdStickerFormatPayload,
  TdStickerPayload,
  TdUpdateMessageSendSucceededPayload,
  TdUpdateNewMessagePayload,
  TdVideoNotePayload,
  TdVoiceNotePayload,
  TdVideoPayload
} from './TdPayloadTypes';

const DOMAIN = 0x2026;
const TAG = 'TdMessageParser';

/**
 * Result of parsing `messages` payload.
 */
export interface TdParsedMessagesResult {
  /** Whether payload was parsed and contains message array. */
  'ok': boolean;
  /** Parsed and normalized chat messages. */
  'messages'?: TdChatMessageItem[];
  /** Total message count reported by TDLib for this history request. */
  'totalCount'?: number;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing `updateNewMessage` payload.
 */
export interface TdParsedUpdateNewMessageResult {
  /** Whether payload was parsed and contains normalized message item. */
  'ok': boolean;
  /** Chat id that owns the incoming message. */
  'chatId'?: string;
  /** Parsed and normalized message item. */
  'message'?: TdChatMessageItem;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing top-level `message` payload returned by `sendMessage`.
 */
export interface TdParsedMessageResult {
  /** Whether payload was parsed and contains normalized message item. */
  'ok': boolean;
  /** Chat id that owns the returned message. */
  'chatId'?: string;
  /** Parsed and normalized message item. */
  'message'?: TdChatMessageItem;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing `updateMessageSendSucceeded` payload.
 */
export interface TdParsedUpdateMessageSendSucceededResult {
  /** Whether payload was parsed and contains normalized message item. */
  'ok': boolean;
  /** Chat id that owns the confirmed message. */
  'chatId'?: string;
  /** TDLib id of stale pending message that should be replaced. */
  'oldMessageId'?: string;
  /** Parsed and normalized confirmed message item. */
  'message'?: TdChatMessageItem;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

interface TdParsedMessageContent {
  'kind': TdChatMessageKind;
  'text': string;
  'textValue'?: UiTextValue;
  'caption'?: string;
  'mediaFileId'?: number;
  'mediaThumbFileId'?: number;
  'mediaMinithumbnailData'?: string;
  'mediaLocalPath'?: string;
  'mediaThumbPath'?: string;
  'mediaWidth'?: number;
  'mediaHeight'?: number;
  'mediaMimeType'?: string;
  'mediaIsAnimated'?: boolean;
  'mediaDurationSec'?: number;
  'voiceNoteWaveform'?: number[];
  'voiceNoteIsListened'?: boolean;
  'callEventStatus'?: TdCallEventStatus;
  'callEventDurationSec'?: number;
  'callEventIsVideo'?: boolean;
}

/**
 * Normalizes TDLib message sending-state payload.
 *
 * @param sendingState TDLib sending-state object.
 * @returns Normalized state or `undefined` when message is already confirmed.
 */
function parseSendingState(sendingState: TdMessageSendingStatePayload | undefined): TdMessageSendingState | undefined {
  const payloadType = readPayloadType(sendingState);
  if (payloadType === 'messageSendingStatePending') {
    return 'pending';
  }
  if (payloadType === 'messageSendingStateFailed') {
    return 'failed';
  }
  return undefined;
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
 * Reads plain text from TDLib formatted text object.
 *
 * @param value TDLib formatted text object.
 * @returns Plain text or empty string when unavailable.
 */
function readFormattedText(value: TdFormattedTextValue | undefined): string {
  if (typeof value === 'string') {
    return value;
  }
  if (!value) {
    return '';
  }
  if (typeof value.text !== 'string') {
    return '';
  }
  return value.text;
}

/**
 * Parses animated-emoji payload variant.
 *
 * @param animatedEmoji TDLib animated-emoji payload.
 * @param fallbackText Message fallback text extracted from content.
 * @returns Parsed animated-emoji metadata with loop-ready media fields.
 */
function parseAnimatedEmojiPayload(
  animatedEmoji: TdAnimatedEmojiPayload | undefined,
  fallbackText: string
): TdParsedMessageContent {
  const stickerValue = animatedEmoji ? animatedEmoji.sticker : undefined;
  const stickerParsed = parseStickerPayload(stickerValue);
  let textValue = fallbackText;
  if (textValue.length === 0) {
    if (typeof stickerParsed.caption === 'string' && stickerParsed.caption.length > 0) {
      textValue = stickerParsed.caption;
    } else {
      textValue = '[animated emoji]';
    }
  }

  return {
    'kind': 'animatedEmoji',
    'text': textValue,
    'mediaFileId': stickerParsed.mediaFileId,
    'mediaThumbFileId': stickerParsed.mediaThumbFileId,
    'mediaLocalPath': stickerParsed.mediaLocalPath,
    'mediaThumbPath': stickerParsed.mediaThumbPath,
    'mediaWidth': stickerParsed.mediaWidth,
    'mediaHeight': stickerParsed.mediaHeight,
    'mediaMimeType': stickerParsed.mediaMimeType,
    'mediaIsAnimated': true
  };
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
  value: TdMessageSenderPayload
    | TdMessageContentPayload
    | TdMessageSendingStatePayload
    | TdCallDiscardReasonPayload
    | undefined
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
 * Reads TDLib file id when available.
 *
 * @param file TDLib file object.
 * @returns Positive file id or `undefined` when unavailable.
 */
function parseFileId(file: TdFilePayload | undefined): number | undefined {
  if (!file || typeof file.id !== 'number' || file.id <= 0) {
    return undefined;
  }
  return file.id;
}

/**
 * Reads local filesystem path from TDLib file object.
 *
 * @param file TDLib file object.
 * @returns Local file path or `undefined` when unavailable.
 */
function parseLocalPath(file: TdFilePayload | undefined): string | undefined {
  if (!file || !file.local || typeof file.local.path !== 'string') {
    return undefined;
  }
  if (file.local.is_downloading_completed === false) {
    return undefined;
  }
  const trimmedPath = file.local.path.trim();
  if (trimmedPath.length === 0) {
    return undefined;
  }
  return trimmedPath;
}

/**
 * Reads base64 JPEG data from TDLib minithumbnail payload.
 *
 * @param minithumbnail TDLib minithumbnail payload.
 * @returns Trimmed base64 JPEG data or `undefined` when unavailable.
 */
function parseMinithumbnailData(minithumbnail: TdMinithumbnailPayload | undefined): string | undefined {
  if (!minithumbnail || typeof minithumbnail.data !== 'string') {
    return undefined;
  }
  const trimmedData = minithumbnail.data.trim();
  if (trimmedData.length === 0) {
    return undefined;
  }
  return trimmedData;
}

/**
 * Computes area metric for photo size ranking.
 *
 * @param size TDLib photo size descriptor.
 * @returns Positive area value or `0` when unavailable.
 */
function parsePhotoSizeArea(size: TdPhotoSizePayload): number {
  const width = parseIntValue(size.width);
  const height = parseIntValue(size.height);
  if (width <= 0 || height <= 0) {
    return 0;
  }
  return width * height;
}

/**
 * Selects the best photo size for chat bubble rendering.
 *
 * Preference:
 * 1) local file available + largest area
 * 2) largest area regardless of local path
 *
 * @param sizes TDLib photo sizes array.
 * @returns Selected size or `undefined` when array is empty.
 */
function selectBestPhotoSize(sizes: TdPhotoSizePayload[] | undefined): TdPhotoSizePayload | undefined {
  if (!sizes || sizes.length === 0) {
    return undefined;
  }

  let bestWithPath: TdPhotoSizePayload | undefined = undefined;
  let bestWithPathArea: number = -1;
  let bestAny: TdPhotoSizePayload | undefined = undefined;
  let bestAnyArea: number = -1;

  for (const size of sizes) {
    const area = parsePhotoSizeArea(size);
    if (area > bestAnyArea) {
      bestAny = size;
      bestAnyArea = area;
    }

    const localPath = parseLocalPath(size.photo);
    if (typeof localPath === 'string' && area > bestWithPathArea) {
      bestWithPath = size;
      bestWithPathArea = area;
    }
  }

  if (bestWithPath) {
    return bestWithPath;
  }
  return bestAny;
}

/**
 * Selects a local thumbnail-like path from available photo sizes.
 *
 * @param sizes TDLib photo sizes array.
 * @returns Path for smallest available local size or `undefined`.
 */
function selectPhotoThumbPath(sizes: TdPhotoSizePayload[] | undefined): string | undefined {
  if (!sizes || sizes.length === 0) {
    return undefined;
  }

  let thumbPath: string | undefined = undefined;
  let thumbArea: number = 2147483647;

  for (const size of sizes) {
    const candidatePath = parseLocalPath(size.photo);
    if (typeof candidatePath !== 'string') {
      continue;
    }
    const area = parsePhotoSizeArea(size);
    if (area > 0 && area < thumbArea) {
      thumbArea = area;
      thumbPath = candidatePath;
      continue;
    }
    if (typeof thumbPath !== 'string') {
      thumbPath = candidatePath;
    }
  }

  return thumbPath;
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
  const rawUserId = sender.user_id;
  if (typeof rawUserId === 'string' && rawUserId.length > 0) {
    return rawUserId;
  }
  if (typeof rawUserId === 'number' && rawUserId > 0) {
    return String(rawUserId);
  }
  return undefined;
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
  const rawChatId = sender.chat_id;
  if (typeof rawChatId === 'string' && rawChatId.length > 0) {
    return rawChatId;
  }
  if (typeof rawChatId === 'number' && rawChatId !== 0) {
    return String(rawChatId);
  }
  return undefined;
}

/**
 * Reads TDLib id-like value as non-empty string.
 *
 * @param value TDLib id represented as number or string.
 * @returns Id string or empty string when value is invalid.
 */
function parseIdString(value: TdIntValue | undefined): string {
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
 * Reads positive-count vector length from TDLib id array.
 *
 * @param value Raw TDLib id array.
 * @returns Number of valid ids contained in the array.
 */
function parseIdArrayLength(value: TdIntValue[] | undefined): number {
  if (!Array.isArray(value)) {
    return 0;
  }
  let count = 0;
  for (const item of value) {
    const parsedId = parseIdString(item);
    if (parsedId.length > 0) {
      count += 1;
    }
  }
  return count;
}

/**
 * Logs normalized service-event parsing result for manual smoke validation.
 *
 * @param contentType Raw TDLib service message type.
 * @param textValue Resource-backed text descriptor emitted to UI.
 */
function logServiceEvent(contentType: string, textValue: UiTextValue): void {
  const argsSummary = textValue.args.length > 0 ? JSON.stringify(textValue.args) : '[]';
  hilog.info(
    DOMAIN,
    TAG,
    'Parsed service event type=%{public}s resource=%{public}s args=%{public}s',
    contentType,
    textValue.resourceName,
    argsSummary
  );
}

/**
 * Creates one resource-backed service event payload.
 *
 * @param resourceName The `string.json` key without `app.string.` prefix.
 * @param args Optional format arguments.
 * @returns Parsed service-event content.
 */
function createServiceEventContent(resourceName: string, ...args: Array<string | number>): TdParsedMessageContent {
  return {
    'kind': 'serviceEvent',
    'text': '',
    'textValue': createResourceUiText(resourceName, ...args)
  };
}

/**
 * Creates one resource-backed service event payload with plain fallback text.
 *
 * @param resourceName The `string.json` key without `app.string.` prefix.
 * @param fallbackText English fallback used by non-resource preview surfaces.
 * @param args Optional format arguments.
 * @returns Parsed service-event content.
 */
function createServiceEventContentWithFallback(
  resourceName: string,
  fallbackText: string,
  ...args: Array<string | number>
): TdParsedMessageContent {
  return {
    'kind': 'serviceEvent',
    'text': fallbackText,
    'textValue': createResourceUiText(resourceName, ...args)
  };
}

/**
 * Formats a call duration for compact call-event labels.
 *
 * @param durationSec Raw TDLib call duration in seconds.
 * @returns Duration label in `m:ss` or `h:mm:ss` form.
 */
function formatCallDuration(durationSec: number): string {
  const hours = Math.floor(durationSec / 3600);
  const minutes = Math.floor((durationSec % 3600) / 60);
  const seconds = durationSec % 60;
  const secondsText = seconds < 10 ? `0${seconds}` : `${seconds}`;
  if (hours <= 0) {
    return `${minutes}:${secondsText}`;
  }

  const minutesText = minutes < 10 ? `0${minutes}` : `${minutes}`;
  return `${hours}:${minutesText}:${secondsText}`;
}

/**
 * Converts TDLib `messageCall` content into a `callEvent` chat-message kind
 * (Task 4.7). The renderer in `ChatMessageListItem` paints a direction-aware
 * bubble using `isOutgoing` + the derived `callEventStatus`; this function
 * stays out of UI concerns and only normalises the TDLib payload.
 *
 * Discard-reason mapping (cross-product with `isOutgoing`):
 *   missed       -> always `missed` (TDLib only emits it for incoming).
 *   declined     -> `declined` either way: incoming = rejected by local
 *                   user, outgoing = rejected by remote peer.
 *   empty        -> `answered` when `duration > 0`, otherwise `cancelled`.
 *   hungUp       -> same fallback: duration drives answered / cancelled.
 *   disconnected -> same fallback: graceful network drop falls under
 *                   `cancelled` when nothing was spoken.
 *
 * @param content Typed TDLib call-message content.
 * @param isOutgoing `true` when the parent message is outgoing.
 * @returns Parsed call-event content.
 */
function parseCallEventContent(
  content: TdServiceMessageContentPayload,
  isOutgoing: boolean
): TdParsedMessageContent {
  const isVideo = content.is_video === true;
  const durationSec = parseIntValue(content.duration);
  const discardReasonType = readPayloadType(content.discard_reason);
  const status = resolveCallEventStatus(discardReasonType, durationSec, isOutgoing);
  const previewText = buildCallEventPreviewText(status, durationSec, isVideo);
  return {
    'kind': 'callEvent',
    'text': previewText.text,
    'textValue': previewText.textValue,
    'callEventStatus': status,
    'callEventDurationSec': durationSec > 0 ? durationSec : 0,
    'callEventIsVideo': isVideo
  };
}

/**
 * Builds the short fallback text (and i18n `textValue`) used by the chat-list
 * preview row for call-event messages. The chat-detail renderer ignores this
 * text and lays out the full call bubble from `callEvent*` fields directly,
 * but the chat-list row only sees `lastMessageText` / `lastMessageTextValue`,
 * so we still need a localised summary like "Missed voice call" or
 * "Voice call (1:23)".
 *
 * @param status Resolved call-event status.
 * @param durationSec Duration in seconds (used for the answered preview).
 * @param isVideo `true` when the call is a video call.
 * @returns Plain-text fallback paired with a resource-based `textValue`.
 */
function buildCallEventPreviewText(
  status: TdCallEventStatus,
  durationSec: number,
  isVideo: boolean
): TdParsedMessageContent {
  if (status === 'missed') {
    return isVideo
      ? createServiceEventContentWithFallback('chat_service_video_call_missed', 'Missed video call')
      : createServiceEventContentWithFallback('chat_service_voice_call_missed', 'Missed voice call');
  }
  if (status === 'declined') {
    return isVideo
      ? createServiceEventContentWithFallback('chat_service_video_call_declined', 'Declined video call')
      : createServiceEventContentWithFallback('chat_service_voice_call_declined', 'Declined voice call');
  }
  if (status === 'cancelled') {
    return isVideo
      ? createServiceEventContentWithFallback('chat_service_video_call_cancelled', 'Cancelled video call')
      : createServiceEventContentWithFallback('chat_service_voice_call_cancelled', 'Cancelled voice call');
  }
  // answered
  if (durationSec > 0) {
    const durationText = formatCallDuration(durationSec);
    return isVideo
      ? createServiceEventContentWithFallback(
        'chat_service_video_call_duration_format',
        `Video call (${durationText})`,
        durationText
      )
      : createServiceEventContentWithFallback(
        'chat_service_voice_call_duration_format',
        `Voice call (${durationText})`,
        durationText
      );
  }
  return isVideo
    ? createServiceEventContentWithFallback('chat_service_video_call', 'Video call')
    : createServiceEventContentWithFallback('chat_service_voice_call', 'Voice call');
}

/**
 * Maps a TDLib discard reason to a semantic call-event status. The mapping
 * is direction-aware: TDLib emits the same `callDiscardReasonMissed` payload
 * on both sides of a call that ended before pickup, but the side that
 * initiated the call interprets it as "I cancelled before they picked up"
 * (status `cancelled`) while the receiving side reads it as "they called
 * and I never answered" (status `missed`). `duration` arbitrates the
 * `hungUp` / `disconnected` / `empty` reasons into `answered` versus
 * `cancelled` based on whether the call actually carried audio.
 *
 * @param discardReasonType TDLib `discard_reason` `@type` value, if present.
 * @param durationSec Parsed `duration` field in seconds (already `>= 0`).
 * @param isOutgoing `true` when the parent message is outgoing.
 * @returns Normalized `TdCallEventStatus`.
 */
function resolveCallEventStatus(
  discardReasonType: string,
  durationSec: number,
  isOutgoing: boolean
): TdCallEventStatus {
  if (discardReasonType === 'callDiscardReasonMissed') {
    return isOutgoing ? 'cancelled' : 'missed';
  }
  if (discardReasonType === 'callDiscardReasonDeclined') {
    return 'declined';
  }
  if (durationSec > 0) {
    return 'answered';
  }
  // duration === 0 path. TDLib `callDiscardReasonHungUp` means the call was
  // answered and then ended — duration=0 is an edge case (peer picked up and
  // hung up immediately, or timing race in the audio path). Telegram-Android
  // still surfaces these as a regular Outgoing/Incoming Call without any
  // cancellation flag, so we keep them as `answered` (the bubble then just
  // shows the timestamp without the duration suffix).
  if (discardReasonType === 'callDiscardReasonHungUp') {
    return 'answered';
  }
  // `Disconnected` / `Empty` / unknown without duration — the call never
  // actually carried audio, render as `cancelled`.
  return 'cancelled';
}

/**
 * Returns one service-event payload enriched with photo-preview metadata.
 *
 * @param serviceEvent Base service-event result.
 * @param content TDLib message content that may expose `photo.sizes`.
 * @returns Service event enriched with optional preview fields.
 */
function attachServiceEventPhotoPreview(
  serviceEvent: TdParsedMessageContent,
  content: TdMessageContentPayload
): TdParsedMessageContent {
  const photoPreview = parsePhotoMessageContent(content);
  return {
    'kind': serviceEvent.kind,
    'text': serviceEvent.text,
    'textValue': serviceEvent.textValue,
    'caption': serviceEvent.caption,
    'mediaFileId': photoPreview.mediaFileId,
    'mediaThumbFileId': photoPreview.mediaThumbFileId,
    'mediaLocalPath': photoPreview.mediaLocalPath,
    'mediaThumbPath': photoPreview.mediaThumbPath,
    'mediaWidth': photoPreview.mediaWidth,
    'mediaHeight': photoPreview.mediaHeight,
    'mediaMimeType': photoPreview.mediaMimeType,
    'mediaIsAnimated': photoPreview.mediaIsAnimated,
    'mediaDurationSec': photoPreview.mediaDurationSec
  };
}

/**
 * Builds readable fallback text for one service/system message.
 *
 * @param contentType TDLib message content type.
 * @param content Typed service-message payload.
 * @param senderUserId Sender user id when the message sender is a user.
 * @returns Normalized service-event content.
 */
function parseServiceMessageContent(
  contentType: string,
  content: TdMessageContentPayload,
  senderUserId: string | undefined
): TdParsedMessageContent {
  const title = typeof content.title === 'string' ? content.title.trim() : '';
  const memberCount = parseIdArrayLength(content.member_user_ids);
  const deletedUserId = parseIdString(content.user_id);
  let parsedContent: TdParsedMessageContent | undefined = undefined;

  if (contentType === 'messageBasicGroupChatCreate') {
    parsedContent = title.length > 0
      ? createServiceEventContent('chat_service_basic_group_created_format', title)
      : createServiceEventContent('chat_service_basic_group_created');
  } else if (contentType === 'messageSupergroupChatCreate') {
    parsedContent = title.length > 0
      ? createServiceEventContent('chat_service_supergroup_created_format', title)
      : createServiceEventContent('chat_service_supergroup_created');
  } else if (contentType === 'messageChatChangeTitle') {
    parsedContent = title.length > 0
      ? createServiceEventContent('chat_service_title_changed_format', title)
      : createServiceEventContent('chat_service_title_changed');
  } else if (contentType === 'messageChatChangePhoto') {
    parsedContent = attachServiceEventPhotoPreview(
      createServiceEventContent('chat_service_photo_changed'),
      content
    );
  } else if (contentType === 'messageChatAddMembers') {
    parsedContent = memberCount === 1
      ? createServiceEventContent('chat_service_member_added_single')
      : createServiceEventContent('chat_service_members_added_multiple');
  } else if (contentType === 'messageChatJoinByLink') {
    parsedContent = createServiceEventContent('chat_service_joined_by_link');
  } else if (contentType === 'messageChatDeleteMember') {
    const didLeave = senderUserId !== undefined && senderUserId.length > 0 && senderUserId === deletedUserId;
    parsedContent = didLeave
      ? createServiceEventContent('chat_service_user_left')
      : createServiceEventContent('chat_service_user_removed');
  } else if (contentType === 'messageChatUpgradeTo') {
    parsedContent = createServiceEventContent('chat_service_upgraded_to_supergroup');
  } else if (contentType === 'messageChatUpgradeFrom') {
    parsedContent = title.length > 0
      ? createServiceEventContent('chat_service_upgraded_from_group_format', title)
      : createServiceEventContent('chat_service_upgraded_from_group');
  } else if (contentType === 'messagePinMessage') {
    parsedContent = createServiceEventContent('chat_service_message_pinned');
  } else if (contentType === 'messageScreenshotTaken') {
    parsedContent = createServiceEventContent('chat_service_screenshot_taken');
  } else if (contentType === 'messageContactRegistered') {
    parsedContent = createServiceEventContent('chat_service_contact_registered');
  }

  if (parsedContent && parsedContent.textValue) {
    logServiceEvent(contentType, parsedContent.textValue);
    return parsedContent;
  }

  return {
    'kind': 'unsupported',
    'text': `[${contentType}]`
  };
}

/**
 * Parses text-message content variant.
 *
 * @param content TDLib message content object.
 * @returns Parsed text-message metadata.
 */
function parseTextMessageContent(content: TdMessageContentPayload): TdParsedMessageContent {
  const textValue = readFormattedText(content.text);
  if (textValue.length > 0) {
    return {
      'kind': 'text',
      'text': textValue
    };
  }
  return {
    'kind': 'text',
    'text': '(empty message)'
  };
}

/**
 * Parses photo-message content variant.
 *
 * @param content TDLib message content object.
 * @returns Parsed photo-message metadata.
 */
function parsePhotoMessageContent(content: TdMessageContentPayload): TdParsedMessageContent {
  const caption = readFormattedText(content.caption);
  const fallbackText = caption.length > 0 ? caption : '[photo]';
  const result: TdParsedMessageContent = {
    'kind': 'photo',
    'text': fallbackText,
    'mediaIsAnimated': false
  };

  if (caption.length > 0) {
    result.caption = caption;
  }

  if (!content.photo || !content.photo.sizes || content.photo.sizes.length === 0) {
    return result;
  }

  const bestSize = selectBestPhotoSize(content.photo.sizes);
  if (bestSize) {
    const fileId = parseFileId(bestSize.photo);
    if (typeof fileId === 'number') {
      result.mediaFileId = fileId;
    }

    const localPath = parseLocalPath(bestSize.photo);
    if (typeof localPath === 'string') {
      result.mediaLocalPath = localPath;
    }

    const width = parseIntValue(bestSize.width);
    const height = parseIntValue(bestSize.height);
    if (width > 0) {
      result.mediaWidth = width;
    }
    if (height > 0) {
      result.mediaHeight = height;
    }
  }

  const thumbPath = selectPhotoThumbPath(content.photo.sizes);
  if (typeof thumbPath === 'string') {
    result.mediaThumbPath = thumbPath;
  }

  return result;
}

/**
 * Parses animation-message content variant.
 *
 * @param animation TDLib animation object.
 * @param caption Message caption text.
 * @returns Parsed animation-message metadata.
 */
function parseAnimationPayload(animation: TdAnimationPayload | undefined, caption: string): TdParsedMessageContent {
  const fallbackText = caption.length > 0 ? caption : '[animation]';
  const result: TdParsedMessageContent = {
    'kind': 'animation',
    'text': fallbackText,
    'mediaIsAnimated': true
  };

  if (caption.length > 0) {
    result.caption = caption;
  }

  if (!animation) {
    return result;
  }

  const fileId = parseFileId(animation.animation);
  if (typeof fileId === 'number') {
    result.mediaFileId = fileId;
  }

  const localPath = parseLocalPath(animation.animation);
  if (typeof localPath === 'string') {
    result.mediaLocalPath = localPath;
  }

  const thumbPath = animation.thumbnail ? parseLocalPath(animation.thumbnail.file) : undefined;
  if (typeof thumbPath === 'string') {
    result.mediaThumbPath = thumbPath;
  }
  if (animation.thumbnail && animation.thumbnail.file) {
    const thumbFileId = parseFileId(animation.thumbnail.file);
    if (typeof thumbFileId === 'number') {
      result.mediaThumbFileId = thumbFileId;
    }
  }

  const width = parseIntValue(animation.width);
  const height = parseIntValue(animation.height);
  if (width > 0) {
    result.mediaWidth = width;
  }
  if (height > 0) {
    result.mediaHeight = height;
  }

  if (typeof animation.mime_type === 'string' && animation.mime_type.length > 0) {
    result.mediaMimeType = animation.mime_type;
  }

  return result;
}

/**
 * Parses video-message content variant.
 *
 * @param video TDLib video payload.
 * @param caption Message caption text.
 * @returns Parsed video-message metadata.
 */
function parseVideoPayload(video: TdVideoPayload | undefined, caption: string): TdParsedMessageContent {
  const fallbackText = caption.length > 0 ? caption : '[video]';
  const result: TdParsedMessageContent = {
    'kind': 'video',
    'text': fallbackText,
    'mediaIsAnimated': true
  };

  if (caption.length > 0) {
    result.caption = caption;
  }
  if (!video) {
    return result;
  }

  const fileId = parseFileId(video.video);
  if (typeof fileId === 'number') {
    result.mediaFileId = fileId;
  }

  const localPath = parseLocalPath(video.video);
  if (typeof localPath === 'string') {
    result.mediaLocalPath = localPath;
  }

  const thumbPath = video.thumbnail ? parseLocalPath(video.thumbnail.file) : undefined;
  if (typeof thumbPath === 'string') {
    result.mediaThumbPath = thumbPath;
  }
  if (video.thumbnail && video.thumbnail.file) {
    const thumbFileId = parseFileId(video.thumbnail.file);
    if (typeof thumbFileId === 'number') {
      result.mediaThumbFileId = thumbFileId;
    }
  }

  const width = parseIntValue(video.width);
  const height = parseIntValue(video.height);
  if (width > 0) {
    result.mediaWidth = width;
  }
  if (height > 0) {
    result.mediaHeight = height;
  }

  const durationSec = parseIntValue(video.duration);
  if (durationSec > 0) {
    result.mediaDurationSec = durationSec;
  }

  if (typeof video.mime_type === 'string' && video.mime_type.length > 0) {
    result.mediaMimeType = video.mime_type;
  } else {
    result.mediaMimeType = 'video/mp4';
  }

  return result;
}

/**
 * Decodes TDLib voice-note waveform encoded as Base64 5-bit samples.
 *
 * @param waveform Base64 encoded waveform payload from TDLib.
 * @returns Decoded waveform samples in range `0..31`.
 */
function decodeVoiceWaveform(waveform: string | undefined): number[] {
  if (typeof waveform !== 'string') {
    return [];
  }

  const trimmedWaveform = waveform.trim();
  if (trimmedWaveform.length === 0) {
    return [];
  }

  let bytes: Uint8Array;
  try {
    const base64Helper = new util.Base64Helper();
    bytes = base64Helper.decodeSync(trimmedWaveform);
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'Failed to decode voice waveform: %{public}s', String(error));
    return [];
  }

  const samples: number[] = [];
  const totalBits = bytes.length * 8;
  let bitOffset = 0;
  while (bitOffset + 5 <= totalBits) {
    const byteIndex = Math.floor(bitOffset / 8);
    const bitIndex = bitOffset % 8;
    let sample = (bytes[byteIndex] >> bitIndex) & 0x1F;
    if (bitIndex > 3 && byteIndex + 1 < bytes.length) {
      sample |= (bytes[byteIndex + 1] << (8 - bitIndex)) & 0x1F;
    }
    samples.push(sample);
    bitOffset += 5;
  }
  return samples;
}

/**
 * Parses voice-note content variant.
 *
 * @param voiceNote TDLib voice-note payload.
 * @param caption Message caption text.
 * @param isListened Whether the incoming voice note was already listened to.
 * @returns Parsed voice-note metadata.
 */
function parseVoiceNotePayload(
  voiceNote: TdVoiceNotePayload | undefined,
  caption: string,
  isListened: boolean | undefined
): TdParsedMessageContent {
  const result: TdParsedMessageContent = {
    'kind': 'voiceNote',
    'text': caption.length > 0 ? caption : ''
  };

  if (caption.length > 0) {
    result.caption = caption;
  } else {
    result.textValue = createResourceUiText('chat_message_voice_note_fallback');
  }
  if (!voiceNote) {
    return result;
  }

  const fileId = parseFileId(voiceNote.voice);
  if (typeof fileId === 'number') {
    result.mediaFileId = fileId;
  }

  const localPath = parseLocalPath(voiceNote.voice);
  if (typeof localPath === 'string') {
    result.mediaLocalPath = localPath;
  }

  const durationSec = parseIntValue(voiceNote.duration);
  if (durationSec > 0) {
    result.mediaDurationSec = durationSec;
  }

  const waveform = decodeVoiceWaveform(voiceNote.waveform);
  if (waveform.length > 0) {
    result.voiceNoteWaveform = waveform;
  }

  if (typeof isListened === 'boolean') {
    result.voiceNoteIsListened = isListened;
  }

  if (typeof voiceNote.mime_type === 'string' && voiceNote.mime_type.length > 0) {
    result.mediaMimeType = voiceNote.mime_type;
  }

  return result;
}

/**
 * Parses video-note content variant.
 *
 * @param videoNote TDLib video-note payload.
 * @returns Parsed video-note metadata.
 */
function parseVideoNotePayload(videoNote: TdVideoNotePayload | undefined): TdParsedMessageContent {
  const result: TdParsedMessageContent = {
    'kind': 'videoNote',
    'text': '[video note]',
    'mediaIsAnimated': true,
    'mediaMimeType': 'video/mp4'
  };

  if (!videoNote) {
    return result;
  }

  const fileId = parseFileId(videoNote.video);
  if (typeof fileId === 'number') {
    result.mediaFileId = fileId;
  }

  const localPath = parseLocalPath(videoNote.video);
  if (typeof localPath === 'string') {
    result.mediaLocalPath = localPath;
  }

  const thumbPath = videoNote.thumbnail ? parseLocalPath(videoNote.thumbnail.file) : undefined;
  if (typeof thumbPath === 'string') {
    result.mediaThumbPath = thumbPath;
  }
  if (videoNote.thumbnail && videoNote.thumbnail.file) {
    const thumbFileId = parseFileId(videoNote.thumbnail.file);
    if (typeof thumbFileId === 'number') {
      result.mediaThumbFileId = thumbFileId;
    }
  }

  const minithumbnailData = parseMinithumbnailData(videoNote.minithumbnail);
  if (typeof minithumbnailData === 'string') {
    result.mediaMinithumbnailData = minithumbnailData;
  }

  const sideLength = parseIntValue(videoNote.length);
  if (sideLength > 0) {
    result.mediaWidth = sideLength;
    result.mediaHeight = sideLength;
  }

  const durationSec = parseIntValue(videoNote.duration);
  if (durationSec > 0) {
    result.mediaDurationSec = durationSec;
  }

  return result;
}

/**
 * Converts TDLib sticker format type to mime-like value used by UI.
 *
 * @param format Sticker format payload.
 * @returns Mime-like label or `undefined` when unknown.
 */
function parseStickerMimeType(format: TdStickerFormatPayload | undefined): string | undefined {
  if (!format) {
    return undefined;
  }

  const serialized = JSON.stringify(format);
  const match = serialized.match(/\"@type\"\s*:\s*\"([^\"]+)\"/);
  if (!match || match.length < 2) {
    return undefined;
  }
  const formatType = match[1];
  if (formatType === 'stickerFormatWebp') {
    return 'image/webp';
  }
  if (formatType === 'stickerFormatWebm') {
    return 'video/webm';
  }
  if (formatType === 'stickerFormatTgs') {
    return 'application/x-tgsticker';
  }
  return undefined;
}

/**
 * Parses sticker-message content variant.
 *
 * @param sticker TDLib sticker payload.
 * @returns Parsed sticker-message metadata.
 */
function parseStickerPayload(sticker: TdStickerPayload | undefined): TdParsedMessageContent {
  const result: TdParsedMessageContent = {
    'kind': 'sticker',
    'text': '[sticker]'
  };
  if (!sticker) {
    return result;
  }

  if (typeof sticker.emoji === 'string' && sticker.emoji.length > 0) {
    result.caption = sticker.emoji;
  }

  const fileId = parseFileId(sticker.sticker);
  if (typeof fileId === 'number') {
    result.mediaFileId = fileId;
  }

  const localPath = parseLocalPath(sticker.sticker);
  if (typeof localPath === 'string') {
    result.mediaLocalPath = localPath;
  }

  const thumbPath = sticker.thumbnail ? parseLocalPath(sticker.thumbnail.file) : undefined;
  if (typeof thumbPath === 'string') {
    result.mediaThumbPath = thumbPath;
  }
  if (sticker.thumbnail && sticker.thumbnail.file) {
    const thumbFileId = parseFileId(sticker.thumbnail.file);
    if (typeof thumbFileId === 'number') {
      result.mediaThumbFileId = thumbFileId;
    }
  }

  const width = parseIntValue(sticker.width);
  const height = parseIntValue(sticker.height);
  if (width > 0) {
    result.mediaWidth = width;
  }
  if (height > 0) {
    result.mediaHeight = height;
  }

  const mimeType = parseStickerMimeType(sticker.format);
  if (typeof mimeType === 'string') {
    result.mediaMimeType = mimeType;
    if (mimeType === 'video/webm' || mimeType === 'application/x-tgsticker') {
      result.mediaIsAnimated = true;
    } else {
      result.mediaIsAnimated = false;
    }
  }

  return result;
}

/**
 * Parses unsupported-message content variant.
 *
 * @param contentType TDLib message content type.
 * @param content TDLib message content object.
 * @returns Parsed unsupported-message metadata.
 */
function parseUnsupportedContent(contentType: string, content: TdMessageContentPayload | undefined): TdParsedMessageContent {
  const captionValue = readFormattedText(content ? content.caption : undefined);
  if (contentType.length === 0) {
    if (captionValue.length > 0) {
      return {
        'kind': 'unsupported',
        'text': captionValue,
        'caption': captionValue
      };
    }
    return {
      'kind': 'unsupported',
      'text': '(unsupported message)'
    };
  }

  if (captionValue.length > 0) {
    return {
      'kind': 'unsupported',
      'text': `[${contentType}] ${captionValue}`,
      'caption': captionValue
    };
  }

  return {
    'kind': 'unsupported',
    'text': `[${contentType}]`
  };
}

/**
 * Parses TDLib message content into normalized UI-friendly metadata.
 *
 * @param content TDLib message content object.
 * @returns Parsed content metadata and fallback text.
 */
function parseMessageContent(
  content: TdMessageContentPayload | undefined,
  sender: TdMessageSenderPayload | undefined,
  isOutgoing: boolean
): TdParsedMessageContent {
  if (!content) {
    return {
      'kind': 'unsupported',
      'text': '(unsupported message)'
    };
  }

  const contentType = readPayloadType(content);
  if (contentType === 'messageCall') {
    return parseCallEventContent(content, isOutgoing);
  }
  if (contentType === 'messageText') {
    return parseTextMessageContent(content);
  }
  if (contentType === 'messagePhoto') {
    return parsePhotoMessageContent(content);
  }
  if (contentType === 'messageAnimation') {
    const caption = readFormattedText(content.caption);
    return parseAnimationPayload(content.animation, caption);
  }
  if (contentType === 'messageVideo') {
    const caption = readFormattedText(content.caption);
    return parseVideoPayload(content.video, caption);
  }
  if (contentType === 'messageVideoNote') {
    return parseVideoNotePayload(content.video_note);
  }
  if (contentType === 'messageVoiceNote') {
    const caption = readFormattedText(content.caption);
    return parseVoiceNotePayload(content.voice_note, caption, content.is_listened);
  }
  if (contentType === 'messageSticker') {
    return parseStickerPayload(content.sticker);
  }
  if (contentType === 'messageAnimatedEmoji') {
    const animatedText = readFormattedText(content.text);
    return parseAnimatedEmojiPayload(content.animated_emoji, animatedText);
  }
  if (contentType === 'messageBasicGroupChatCreate'
    || contentType === 'messageSupergroupChatCreate'
    || contentType === 'messageChatChangeTitle'
    || contentType === 'messageChatChangePhoto'
    || contentType === 'messageChatAddMembers'
    || contentType === 'messageChatJoinByLink'
    || contentType === 'messageChatDeleteMember'
    || contentType === 'messageChatUpgradeTo'
    || contentType === 'messageChatUpgradeFrom'
    || contentType === 'messagePinMessage'
    || contentType === 'messageScreenshotTaken'
    || contentType === 'messageContactRegistered') {
    return parseServiceMessageContent(contentType, content, parseSenderUserId(sender));
  }

  return parseUnsupportedContent(contentType, content);
}

/**
 * Converts single TDLib message payload into UI message model.
 *
 * @param message TDLib message object.
 * @param chatId Parent chat id.
 * @returns Normalized message item or `undefined` when required fields are missing.
 */
function parseSingleMessage(message: TdChatMessagePayload, chatId: string): TdChatMessageItem | undefined {
  const rawId = message.id;
  if (typeof rawId !== 'string' && typeof rawId !== 'number') {
    return undefined;
  }

  const isOutgoing = message.is_outgoing === true;
  const parsedContent = parseMessageContent(message.content, message.sender_id, isOutgoing);

  return {
    'id': String(rawId),
    'chatId': chatId,
    'senderUserId': parseSenderUserId(message.sender_id),
    'senderChatId': parseSenderChatId(message.sender_id),
    'kind': parsedContent.kind,
    'sendingState': parseSendingState(message.sending_state),
    'text': parsedContent.text,
    'textValue': parsedContent.textValue,
    'caption': parsedContent.caption,
    'mediaFileId': parsedContent.mediaFileId,
    'mediaThumbFileId': parsedContent.mediaThumbFileId,
    'mediaMinithumbnailData': parsedContent.mediaMinithumbnailData,
    'mediaLocalPath': parsedContent.mediaLocalPath,
    'mediaThumbPath': parsedContent.mediaThumbPath,
    'mediaWidth': parsedContent.mediaWidth,
    'mediaHeight': parsedContent.mediaHeight,
    'mediaMimeType': parsedContent.mediaMimeType,
    'mediaIsAnimated': parsedContent.mediaIsAnimated,
    'mediaDurationSec': parsedContent.mediaDurationSec,
    'voiceNoteWaveform': parsedContent.voiceNoteWaveform,
    'voiceNoteIsListened': parsedContent.voiceNoteIsListened,
    'callEventStatus': parsedContent.callEventStatus,
    'callEventDurationSec': parsedContent.callEventDurationSec,
    'callEventIsVideo': parsedContent.callEventIsVideo,
    'isOutgoing': isOutgoing,
    'date': parseIntValue(message.date)
  };
}

/**
 * Converts single TDLib message payload into UI message model.
 *
 * @param message TDLib message object.
 * @param chatId Parent chat id.
 * @returns Normalized message item or `undefined` when required fields are missing.
 */
export function parseChatMessagePayload(message: TdChatMessagePayload, chatId: string): TdChatMessageItem | undefined {
  return parseSingleMessage(message, chatId);
}

/**
 * Builds a compact preview text from normalized message fields.
 *
 * @param message Parsed TDLib message.
 * @returns Human-readable chat-list/notification preview.
 */
export function formatChatMessagePreviewText(message: TdChatMessageItem): string {
  const text = message.text.trim();
  if (text.length > 0) {
    return text;
  }

  const caption = message.caption;
  if (caption !== undefined) {
    const trimmedCaption = caption.trim();
    if (trimmedCaption.length > 0) {
      return trimmedCaption;
    }
  }

  const kind = message.kind;
  const isOutgoing = message.isOutgoing;
  if (kind === 'photo') {
    return isOutgoing ? 'You sent a photo' : 'You received a photo';
  }
  if (kind === 'animation') {
    return isOutgoing ? 'You sent a GIF' : 'You received a GIF';
  }
  if (kind === 'video') {
    return isOutgoing ? 'You sent a video' : 'You received a video';
  }
  if (kind === 'videoNote') {
    return isOutgoing ? 'You sent a video message' : 'You received a video message';
  }
  if (kind === 'voiceNote') {
    return isOutgoing ? 'You sent a voice message' : 'You received a voice message';
  }
  if (kind === 'sticker') {
    return isOutgoing ? 'You sent a sticker' : 'You received a sticker';
  }
  if (kind === 'animatedEmoji') {
    return isOutgoing ? 'You sent an emoji' : 'You received an emoji';
  }
  if (kind === 'serviceEvent') {
    return '[service message]';
  }
  if (kind === 'callEvent') {
    return '[call]';
  }
  return 'New message';
}

/**
 * Parses TDLib payload that should contain `messages` object.
 *
 * @param payload Raw TDLib JSON payload.
 * @param chatId Chat id that owns this response.
 * @returns Structured parser result with normalized chat messages.
 */
export function parseMessagesPayload(payload: string, chatId: string): TdParsedMessagesResult {
  try {
    const parsed = JSON.parse(payload) as TdMessagesPayload;
    if (!Array.isArray(parsed.messages)) {
      return { 'ok': false };
    }

    const parsedItems: TdChatMessageItem[] = [];
    for (const rawMessage of parsed.messages) {
      const parsedMessage = parseSingleMessage(rawMessage, chatId);
      if (parsedMessage) {
        parsedItems.push(parsedMessage);
      }
    }

    // TDLib returns newest-first for this request; UI expects oldest-first.
    const orderedItems: TdChatMessageItem[] = [];
    for (let index = parsedItems.length - 1; index >= 0; index--) {
      orderedItems.push(parsedItems[index]);
    }

    const totalCount = parseIntValue(parsed.total_count);
    return {
      'ok': true,
      'messages': orderedItems,
      'totalCount': totalCount
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain `updateNewMessage`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with normalized message item.
 */
export function parseUpdateNewMessagePayload(payload: string): TdParsedUpdateNewMessageResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateNewMessagePayload;
    if (!parsed.message) {
      return { 'ok': false };
    }

    const chatId = parseIdString(parsed.message.chat_id);
    if (chatId.length === 0) {
      return { 'ok': false };
    }

    const message = parseSingleMessage(parsed.message, chatId);
    if (!message) {
      return { 'ok': false };
    }

    return {
      'ok': true,
      'chatId': chatId,
      'message': message
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses top-level TDLib `message` payload returned by `sendMessage`.
 *
 * @param payload Raw TDLib JSON payload.
 * @param fallbackChatId Chat id extracted from the request `@extra`.
 * @returns Structured parser result with normalized message item.
 */
export function parseMessagePayload(payload: string, fallbackChatId: string): TdParsedMessageResult {
  try {
    const parsed = JSON.parse(payload) as TdChatMessagePayload;
    const chatId = parseIdString(parsed.chat_id);
    const resolvedChatId = chatId.length > 0 ? chatId : fallbackChatId.trim();
    if (resolvedChatId.length === 0) {
      return { 'ok': false };
    }

    const message = parseSingleMessage(parsed, resolvedChatId);
    if (!message) {
      return { 'ok': false };
    }

    return {
      'ok': true,
      'chatId': resolvedChatId,
      'message': message
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain `updateMessageSendSucceeded`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with pending/final message identifiers.
 */
export function parseUpdateMessageSendSucceededPayload(payload: string): TdParsedUpdateMessageSendSucceededResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateMessageSendSucceededPayload;
    if (!parsed.message) {
      return { 'ok': false };
    }

    const chatId = parseIdString(parsed.message.chat_id);
    const oldMessageId = parseIdString(parsed.old_message_id);
    if (chatId.length === 0 || oldMessageId.length === 0) {
      return { 'ok': false };
    }

    const message = parseSingleMessage(parsed.message, chatId);
    if (!message) {
      return { 'ok': false };
    }

    return {
      'ok': true,
      'chatId': chatId,
      'oldMessageId': oldMessageId,
      'message': message
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}
