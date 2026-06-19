import { createResourceUiText, UiTextValue, cloneUiTextValue } from '../../models/ui/UiTextValue';
import { splitCallDurationParts } from '../../utils/CallDurationFormatter';
import { TdCallEventStatus, TdChatMessageItem, TdChatMessageKind } from './TdPayloadTypes';
import { formatChatMessagePreviewText } from './TdMessageParser';

/**
 * Chat-list preview data derived from one normalized TDLib message.
 */
export interface TdChatListMessagePreview {
  /** Plain fallback text for non-resource contexts and render keys. */
  'text'?: string;
  /** Resource-backed text resolved by ChatListItem when available. */
  'textValue'?: UiTextValue;
  /** Normalized kind for styling and optional call icon rendering. */
  'kind'?: TdChatMessageKind;
  /** Whether the message was sent by the local user. */
  'isOutgoing'?: boolean;
  /** Call outcome for call-event preview icon rendering. */
  'callEventStatus'?: TdCallEventStatus;
}

/**
 * Builds the chat-list preview model for one already-normalized message.
 *
 * This mapper is intentionally separate from `TdChatMessageItem` parsing:
 * message models keep raw content semantics for ChatDetails, while the chat
 * list gets its own presentation summary such as "You sent a photo" or
 * "Outgoing Call (49 s)".
 *
 * @param message Normalized message item.
 * @returns Chat-list preview text, optional resource value and call metadata.
 */
export function buildChatListMessagePreview(message: TdChatMessageItem): TdChatListMessagePreview {
  const kind = message.kind;
  const isOutgoing = message.isOutgoing === true;
  if (kind === 'callEvent') {
    return buildCallEventPreview(message, isOutgoing);
  }

  if (isMediaPlaceholderKind(kind)) {
    const caption = trimOptionalText(message.caption);
    if (caption.length > 0 && mediaKindSupportsUserCaption(kind)) {
      return {
        'text': caption,
        'kind': kind,
        'isOutgoing': isOutgoing
      };
    }
    return buildMediaPlaceholderPreview(kind, isOutgoing);
  }

  const caption = trimOptionalText(message.caption);
  if (caption.length > 0) {
    return {
      'text': caption,
      'kind': kind,
      'isOutgoing': isOutgoing
    };
  }

  const textValue = cloneUiTextValue(message.textValue);
  const fallbackText = formatChatMessagePreviewText(message).trim();
  return {
    'text': fallbackText.length > 0 ? fallbackText : undefined,
    'textValue': textValue,
    'kind': kind,
    'isOutgoing': isOutgoing,
    'callEventStatus': message.callEventStatus
  };
}

/**
 * Checks whether a message kind should use direction-aware media placeholder
 * text in the chat list when no caption is present.
 *
 * @param kind Normalized message kind.
 * @returns `true` for media placeholder kinds.
 */
function isMediaPlaceholderKind(kind: TdChatMessageKind | undefined): boolean {
  return kind === 'photo'
    || kind === 'animation'
    || kind === 'video'
    || kind === 'videoNote'
    || kind === 'voiceNote'
    || kind === 'sticker'
    || kind === 'animatedEmoji';
}

/**
 * Checks whether a media kind can carry a user-authored caption. Stickers and
 * animated emoji expose emoji metadata through `caption`, but that metadata is
 * not a message caption and must not replace the required direction-aware
 * preview text.
 *
 * @param kind Normalized message kind.
 * @returns `true` when `caption` is user-authored text.
 */
function mediaKindSupportsUserCaption(kind: TdChatMessageKind | undefined): boolean {
  return kind === 'photo'
    || kind === 'animation'
    || kind === 'video'
    || kind === 'voiceNote';
}

/**
 * Builds direction-aware media placeholder preview.
 *
 * @param kind Media message kind.
 * @param isOutgoing Whether the message was sent by the local user.
 * @returns Chat-list preview for one media placeholder kind.
 */
function buildMediaPlaceholderPreview(
  kind: TdChatMessageKind | undefined,
  isOutgoing: boolean
): TdChatListMessagePreview {
  const resourceName = mediaPlaceholderResourceName(kind, isOutgoing);
  return {
    'text': mediaPlaceholderFallbackText(kind, isOutgoing),
    'textValue': createResourceUiText(resourceName),
    'kind': kind,
    'isOutgoing': isOutgoing
  };
}

/**
 * Selects media placeholder string resource name.
 *
 * @param kind Media message kind.
 * @param isOutgoing Whether the message was sent by the local user.
 * @returns Resource name for the preview text.
 */
function mediaPlaceholderResourceName(kind: TdChatMessageKind | undefined, isOutgoing: boolean): string {
  if (kind === 'photo') {
    return isOutgoing ? 'chat_preview_outgoing_photo' : 'chat_preview_incoming_photo';
  }
  if (kind === 'animation') {
    return isOutgoing ? 'chat_preview_outgoing_animation' : 'chat_preview_incoming_animation';
  }
  if (kind === 'video') {
    return isOutgoing ? 'chat_preview_outgoing_video' : 'chat_preview_incoming_video';
  }
  if (kind === 'videoNote') {
    return isOutgoing ? 'chat_preview_outgoing_video_note' : 'chat_preview_incoming_video_note';
  }
  if (kind === 'voiceNote') {
    return isOutgoing ? 'chat_preview_outgoing_voice_note' : 'chat_preview_incoming_voice_note';
  }
  if (kind === 'sticker') {
    return isOutgoing ? 'chat_preview_outgoing_sticker' : 'chat_preview_incoming_sticker';
  }
  return isOutgoing ? 'chat_preview_outgoing_animated_emoji' : 'chat_preview_incoming_animated_emoji';
}

/**
 * Builds plain English media placeholder fallback.
 *
 * @param kind Media message kind.
 * @param isOutgoing Whether the message was sent by the local user.
 * @returns Plain preview text.
 */
function mediaPlaceholderFallbackText(kind: TdChatMessageKind | undefined, isOutgoing: boolean): string {
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
  return isOutgoing ? 'You sent an emoji' : 'You received an emoji';
}

/**
 * Builds direction/status-aware call-event preview.
 *
 * @param message Call-event message item.
 * @param isOutgoing Whether the message was sent by the local user.
 * @returns Chat-list preview for one call event.
 */
function buildCallEventPreview(
  message: TdChatMessageItem,
  isOutgoing: boolean
): TdChatListMessagePreview {
  const status = normalizeCallEventStatus(message.callEventStatus);
  const durationSec = typeof message.callEventDurationSec === 'number' && message.callEventDurationSec > 0
    ? Math.floor(message.callEventDurationSec)
    : 0;

  if (status === 'answered') {
    if (durationSec > 0) {
      return buildAnsweredCallWithDurationPreview(isOutgoing, durationSec);
    }
    return {
      'text': isOutgoing ? 'Outgoing Call' : 'Incoming Call',
      'textValue': createResourceUiText(isOutgoing
        ? 'chat_preview_call_outgoing'
        : 'chat_preview_call_incoming'),
      'kind': 'callEvent',
      'isOutgoing': isOutgoing,
      'callEventStatus': status
    };
  }

  if (status === 'missed') {
    return buildStatusOnlyCallPreview('Missed Call', 'chat_preview_call_missed', isOutgoing, status);
  }
  if (status === 'declined') {
    return buildStatusOnlyCallPreview('Declined Call', 'chat_preview_call_declined', isOutgoing, status);
  }
  return buildStatusOnlyCallPreview('Cancelled Call', 'chat_preview_call_cancelled', isOutgoing, status);
}

/**
 * Builds answered call preview including short duration.
 *
 * @param isOutgoing Whether the call was outgoing.
 * @param durationSec Positive call duration in seconds.
 * @returns Chat-list preview for an answered call with duration.
 */
function buildAnsweredCallWithDurationPreview(
  isOutgoing: boolean,
  durationSec: number
): TdChatListMessagePreview {
  const parts = splitCallDurationParts(durationSec);
  const directionText = isOutgoing ? 'Outgoing Call' : 'Incoming Call';
  const fallbackDuration = parts.minutes > 0
    ? `${parts.minutes} min ${parts.seconds} s`
    : `${parts.seconds} s`;
  const resourceName = answeredCallDurationResourceName(isOutgoing, parts.minutes > 0);
  const textValue = parts.minutes > 0
    ? createResourceUiText(resourceName, parts.minutes, parts.seconds)
    : createResourceUiText(resourceName, parts.seconds);
  return {
    'text': `${directionText} (${fallbackDuration})`,
    'textValue': textValue,
    'kind': 'callEvent',
    'isOutgoing': isOutgoing,
    'callEventStatus': 'answered'
  };
}

/**
 * Selects answered call duration resource.
 *
 * @param isOutgoing Whether the call was outgoing.
 * @param hasMinutes Whether the duration includes whole minutes.
 * @returns Resource name for answered call preview.
 */
function answeredCallDurationResourceName(isOutgoing: boolean, hasMinutes: boolean): string {
  if (isOutgoing) {
    return hasMinutes
      ? 'chat_preview_call_outgoing_minutes_seconds_format'
      : 'chat_preview_call_outgoing_seconds_format';
  }
  return hasMinutes
    ? 'chat_preview_call_incoming_minutes_seconds_format'
    : 'chat_preview_call_incoming_seconds_format';
}

/**
 * Builds a call-event preview with no duration suffix.
 *
 * @param fallbackText Plain English fallback.
 * @param resourceName Resource name.
 * @param isOutgoing Whether the call was outgoing.
 * @param status Normalized call status.
 * @returns Chat-list call preview.
 */
function buildStatusOnlyCallPreview(
  fallbackText: string,
  resourceName: string,
  isOutgoing: boolean,
  status: TdCallEventStatus
): TdChatListMessagePreview {
  return {
    'text': fallbackText,
    'textValue': createResourceUiText(resourceName),
    'kind': 'callEvent',
    'isOutgoing': isOutgoing,
    'callEventStatus': status
  };
}

/**
 * Normalizes missing call-event status to the same defensive default used by
 * the ChatDetails bubble renderer.
 *
 * @param status Optional parsed call status.
 * @returns Valid call status.
 */
function normalizeCallEventStatus(status: TdCallEventStatus | undefined): TdCallEventStatus {
  if (status === 'missed' || status === 'declined' || status === 'cancelled') {
    return status;
  }
  return 'answered';
}

/**
 * Trims optional text.
 *
 * @param value Optional text.
 * @returns Trimmed value or empty string.
 */
function trimOptionalText(value: string | undefined): string {
  if (typeof value !== 'string') {
    return '';
  }
  return value.trim();
}
