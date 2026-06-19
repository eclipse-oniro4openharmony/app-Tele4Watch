import { UiTextValue } from '../../models/ui/UiTextValue';

/**
 * TDLib response model for `getOption`.
 */
export interface TdGetOptionResponse {
  '@type'?: string;
  'value'?: string;
}

/**
 * Raw TDLib authorization-state payload.
 */
export interface TdAuthorizationStatePayload {
  '@type'?: string;
  /** QR login link for `authorizationStateWaitOtherDeviceConfirmation`. */
  'link'?: string;
  /** Snake-case TDLib code metadata for `authorizationStateWaitCode`. */
  'code_info'?: TdAuthorizationCodeInfoPayload;
  /** Camel-case compatibility variant used in some wrappers/tools. */
  'codeInfo'?: TdAuthorizationCodeInfoPayload;
}

/**
 * Raw TDLib wrapper used by `updateAuthorizationState` responses.
 */
export interface TdAuthorizationStateUpdatePayload {
  /** Snake-case variant used by TDLib JSON. */
  'authorization_state'?: TdAuthorizationStatePayload;
  /** Camel-case compatibility variant used in some wrappers/tools. */
  'authorizationState'?: TdAuthorizationStatePayload;
}

/**
 * Raw TDLib authentication-code type descriptor.
 */
export interface TdAuthorizationCodeTypePayload {
  '@type'?: string;
  'length'?: TdIntValue;
}

/**
 * Raw TDLib authentication-code metadata for `authorizationStateWaitCode`.
 */
export interface TdAuthorizationCodeInfoPayload {
  'type'?: TdAuthorizationCodeTypePayload;
}

/**
 * Raw TDLib user payload.
 */
export interface TdUserPayload {
  'id'?: number;
  'first_name'?: string;
  'last_name'?: string;
  'is_contact'?: boolean;
  'is_mutual_contact'?: boolean;
  'status'?: TdUserStatusPayload;
  'accent_color_id'?: TdIntValue;
  /** Legacy single username field. */
  'username'?: string;
  /** Newer username container. */
  'usernames'?: TdUsernamesPayload;
  /** Optional profile-photo payload. */
  'profile_photo'?: TdProfilePhotoPayload;
  'phone_number'?: string;
}

/**
 * Raw TDLib usernames container.
 */
export interface TdUsernamesPayload {
  'active_usernames'?: string[];
  'disabled_usernames'?: string[];
  'editable_username'?: string;
}

/**
 * Raw TDLib user-status payload.
 */
export interface TdUserStatusPayload {
  '@type'?: string;
  'expires'?: TdIntValue;
  'was_online'?: TdIntValue;
}

/**
 * Raw TDLib payload returned by `getContacts` / `searchContacts`.
 */
export interface TdUsersPayload {
  'user_ids'?: TdChatId[];
}

/**
 * Raw TDLib wrapper used by `updateUser`.
 */
export interface TdUpdateUserPayload {
  'user'?: TdUserPayload;
}

/**
 * UI-facing current-account model emitted by `TdClient`.
 */
export interface TdMeInfo {
  'id': number;
  'firstName': string;
  'lastName': string;
  'username': string;
  'phoneNumber': string;
  'avatarPath'?: string;
  'avatarAnimationPath'?: string;
}

/**
 * TDLib identifier that may arrive as number or string.
 */
export type TdChatId = number | string;

/**
 * TDLib integer value that may arrive as number or string.
 */
export type TdIntValue = number | string;

/**
 * Raw TDLib call protocol payload.
 */
export interface TdCallProtocolPayload {
  '@type'?: string;
  'udp_p2p'?: boolean;
  'udp_reflector'?: boolean;
  'min_layer'?: TdIntValue;
  'max_layer'?: TdIntValue;
  'library_versions'?: string[];
}

/**
 * Raw TDLib call-server type descriptor.
 */
export interface TdCallServerTypePayload {
  '@type'?: string;
  'peer_tag'?: string;
  'username'?: string;
  'password'?: string;
  'supports_turn'?: boolean;
  'supports_stun'?: boolean;
}

/**
 * Raw TDLib call server payload.
 */
export interface TdCallServerPayload {
  '@type'?: string;
  'id'?: TdIntValue;
  'ip_address'?: string;
  'ipv6_address'?: string;
  'port'?: TdIntValue;
  'type'?: TdCallServerTypePayload;
}

/**
 * Raw TDLib call discard reason payload.
 */
export interface TdCallDiscardReasonPayload {
  '@type'?: string;
}

/**
 * Raw TDLib error payload.
 */
export interface TdErrorPayload {
  '@type'?: string;
  'code'?: TdIntValue;
  'message'?: string;
}

/**
 * Raw TDLib call-state payload.
 */
export interface TdCallStatePayload {
  '@type'?: string;
  'is_created'?: boolean;
  'is_received'?: boolean;
  'protocol'?: TdCallProtocolPayload;
  'servers'?: TdCallServerPayload[];
  'config'?: string;
  'encryption_key'?: string;
  'emojis'?: string[];
  'allow_p2p'?: boolean;
  'is_group_call_supported'?: boolean;
  'custom_parameters'?: string;
  'reason'?: TdCallDiscardReasonPayload;
  'need_rating'?: boolean;
  'need_debug_information'?: boolean;
  'need_log'?: boolean;
  'error'?: TdErrorPayload;
}

/**
 * Raw TDLib call payload.
 */
export interface TdCallPayload {
  'id'?: TdIntValue;
  'unique_id'?: TdIntValue;
  'user_id'?: TdChatId;
  'is_outgoing'?: boolean;
  'is_video'?: boolean;
  'state'?: TdCallStatePayload;
}

/**
 * Raw TDLib wrapper used by `updateCall`.
 */
export interface TdUpdateCallPayload {
  'call'?: TdCallPayload;
}

/**
 * Raw TDLib `callId` payload returned synchronously by `createCall`.
 *
 * The `@extra` correlation token is read from the raw payload string via
 * `extractExtra`, since ArkTS forbids indexed access to `@`-prefixed fields.
 */
export interface TdCallIdPayload {
  'id'?: TdIntValue;
}

/**
 * Raw TDLib wrapper used by `updateNewCallSignalingData`.
 */
export interface TdUpdateNewCallSignalingDataPayload {
  'call_id'?: TdIntValue;
  'data'?: string;
}

/**
 * Normalized call-state variants emitted by `TdCallParser`.
 */
export type TdParsedCallStateKind = 'pending' | 'exchangingKeys' | 'ready' | 'hangingUp' | 'discarded' | 'error';

/**
 * Normalized TDLib call protocol.
 */
export interface TdParsedCallProtocolPayload {
  'udpP2p': boolean;
  'udpReflector': boolean;
  'minLayer': number;
  'maxLayer': number;
  'libraryVersions': string[];
}

/**
 * Normalized TDLib call server.
 */
export interface TdParsedCallServerPayload {
  'id': string;
  'ipAddress': string;
  'ipv6Address': string;
  'port': number;
  'type': string;
  'peerTag'?: string;
  'username'?: string;
  'password'?: string;
  'supportsTurn'?: boolean;
  'supportsStun'?: boolean;
}

/**
 * Normalized TDLib call state.
 */
export interface TdParsedCallStatePayload {
  'kind': TdParsedCallStateKind;
  'tdType': string;
  'isCreated'?: boolean;
  'isReceived'?: boolean;
  'protocol'?: TdParsedCallProtocolPayload;
  'servers'?: TdParsedCallServerPayload[];
  'config'?: string;
  'encryptionKey'?: string;
  'emojis'?: string[];
  'allowP2p'?: boolean;
  'isGroupCallSupported'?: boolean;
  'customParameters'?: string;
  'discardReason'?: string;
  'needRating'?: boolean;
  'needDebugInformation'?: boolean;
  'needLog'?: boolean;
  'errorCode'?: number;
  'errorMessage'?: string;
}

/**
 * Normalized TDLib call payload emitted to app services.
 */
export interface TdParsedCallPayload {
  'id': number;
  'uniqueId': string;
  'userId': string;
  'isOutgoing': boolean;
  'isVideo': boolean;
  'state': TdParsedCallStatePayload;
}

/**
 * Normalized TDLib call event variants emitted by the client layer.
 */
export type TdCallEventKind = 'call' | 'signalingData';

/**
 * UI/service-facing call event emitted by TdClient.
 */
export interface TdCallEvent {
  'kind': TdCallEventKind;
  'call'?: TdParsedCallPayload;
  'callId'?: number;
  'data'?: string;
}

/**
 * Raw TDLib payload returned by `getChats`.
 */
export interface TdChatsPayload {
  'chat_ids'?: TdChatId[];
}

/**
 * Raw TDLib chat-folder descriptor.
 */
export interface TdChatFolderInfoPayload {
  'id'?: number;
}

/**
 * Raw TDLib payload returned by `getChatFolders`.
 */
export interface TdChatFoldersPayload {
  'chat_folders'?: TdChatFolderInfoPayload[];
}

/**
 * Raw TDLib chat type payload.
 */
export interface TdChatTypePayload {
  '@type'?: string;
  'user_id'?: TdChatId;
  'basic_group_id'?: TdChatId;
  'supergroup_id'?: TdChatId;
  'is_channel'?: boolean;
}

/**
 * Raw TDLib per-chat notification settings payload.
 */
export interface TdChatNotificationSettingsPayload {
  'mute_for'?: TdIntValue;
}

/**
 * Raw TDLib chat-list discriminator.
 */
export interface TdChatListPayload {
  '@type'?: string;
  'chat_folder_id'?: TdIntValue;
}

/**
 * Raw TDLib chat position inside one chat list.
 */
export interface TdChatPositionPayload {
  'list'?: TdChatListPayload;
  'order'?: TdIntValue;
  'is_pinned'?: boolean;
}

/**
 * Raw TDLib local-file descriptor.
 */
export interface TdLocalFilePayload {
  'path'?: string;
  'is_downloading_completed'?: boolean;
}

/**
 * Raw TDLib file descriptor.
 */
export interface TdFilePayload {
  'id'?: number;
  'local'?: TdLocalFilePayload;
}

/**
 * Raw TDLib profile photo payload.
 */
export interface TdProfilePhotoPayload {
  'small'?: TdFilePayload;
  'has_animation'?: boolean;
}

/**
 * Raw TDLib chat avatar info payload.
 */
export interface TdChatPhotoInfoPayload {
  'small'?: TdFilePayload;
}

/**
 * Raw TDLib animated chat photo payload.
 */
export interface TdAnimatedChatPhotoPayload {
  'file'?: TdFilePayload;
}

/**
 * Raw TDLib full chat photo payload with static and animated entries.
 */
export interface TdChatPhotoPayload {
  'animation'?: TdAnimatedChatPhotoPayload;
  'small_animation'?: TdAnimatedChatPhotoPayload;
}

/**
 * Raw TDLib `userFullInfo` payload.
 */
export interface TdUserFullInfoPayload {
  'personal_photo'?: TdChatPhotoPayload;
  'photo'?: TdChatPhotoPayload;
  'public_photo'?: TdChatPhotoPayload;
}

/**
 * Raw TDLib wrapper used by `updateUserFullInfo`.
 */
export interface TdUpdateUserFullInfoPayload {
  'user_id'?: TdChatId;
  'user_full_info'?: TdUserFullInfoPayload;
}

/**
 * Raw TDLib formatted text payload.
 */
export interface TdFormattedTextPayload {
  'text'?: string;
}

/**
 * TDLib formatted text value that may be nested object or plain string.
 */
export type TdFormattedTextValue = TdFormattedTextPayload | string;

/**
 * Raw TDLib photo-size payload.
 */
export interface TdPhotoSizePayload {
  'type'?: string;
  'photo'?: TdFilePayload;
  'width'?: TdIntValue;
  'height'?: TdIntValue;
}

/**
 * Raw TDLib photo payload.
 */
export interface TdPhotoPayload {
  'sizes'?: TdPhotoSizePayload[];
}

/**
 * Raw TDLib thumbnail payload.
 */
export interface TdThumbnailPayload {
  'file'?: TdFilePayload;
  'width'?: TdIntValue;
  'height'?: TdIntValue;
}

/**
 * Raw TDLib minithumbnail payload.
 */
export interface TdMinithumbnailPayload {
  'width'?: TdIntValue;
  'height'?: TdIntValue;
  'data'?: string;
}

/**
 * Raw TDLib animation payload.
 */
export interface TdAnimationPayload {
  'animation'?: TdFilePayload;
  'thumbnail'?: TdThumbnailPayload;
  'width'?: TdIntValue;
  'height'?: TdIntValue;
  'mime_type'?: string;
}

/**
 * Raw TDLib video payload.
 */
export interface TdVideoPayload {
  'video'?: TdFilePayload;
  'thumbnail'?: TdThumbnailPayload;
  'width'?: TdIntValue;
  'height'?: TdIntValue;
  'duration'?: TdIntValue;
  'mime_type'?: string;
}

/**
 * Raw TDLib voice-note payload.
 */
export interface TdVoiceNotePayload {
  'voice'?: TdFilePayload;
  'duration'?: TdIntValue;
  'waveform'?: string;
  'mime_type'?: string;
}

/**
 * Raw TDLib video-note payload.
 */
export interface TdVideoNotePayload {
  'video'?: TdFilePayload;
  'duration'?: TdIntValue;
  'length'?: TdIntValue;
  'waveform'?: string;
  'minithumbnail'?: TdMinithumbnailPayload;
  'thumbnail'?: TdThumbnailPayload;
}

/**
 * Raw TDLib sticker format descriptor.
 */
export interface TdStickerFormatPayload {
  '@type'?: string;
}

/**
 * Raw TDLib sticker payload.
 */
export interface TdStickerPayload {
  'sticker'?: TdFilePayload;
  'thumbnail'?: TdThumbnailPayload;
  'width'?: TdIntValue;
  'height'?: TdIntValue;
  'emoji'?: string;
  'format'?: TdStickerFormatPayload;
}

/**
 * Raw TDLib animated-emoji payload.
 */
export interface TdAnimatedEmojiPayload {
  'sticker'?: TdStickerPayload;
}

/**
 * Raw TDLib message content payload.
 */
export interface TdServiceMessageContentPayload {
  'title'?: string;
  'member_user_ids'?: TdChatId[];
  'user_id'?: TdChatId;
  'message_id'?: TdChatId;
  'supergroup_id'?: TdChatId;
  'basic_group_id'?: TdChatId;
  'discard_reason'?: TdCallDiscardReasonPayload;
  'duration'?: TdIntValue;
  'is_video'?: boolean;
}

/**
 * Raw TDLib message content payload.
 */
export interface TdMessageContentPayload extends TdServiceMessageContentPayload {
  '@type'?: string;
  'text'?: TdFormattedTextValue;
  'caption'?: TdFormattedTextPayload;
  'photo'?: TdPhotoPayload;
  'animation'?: TdAnimationPayload;
  'video'?: TdVideoPayload;
  'video_note'?: TdVideoNotePayload;
  'voice_note'?: TdVoiceNotePayload;
  'is_listened'?: boolean;
  'sticker'?: TdStickerPayload;
  'animated_emoji'?: TdAnimatedEmojiPayload;
}

/**
 * Raw TDLib sender descriptor used by messages.
 */
export interface TdMessageSenderPayload {
  '@type'?: string;
  'user_id'?: TdChatId;
  'chat_id'?: TdChatId;
}

/**
 * Raw TDLib message sending-state payload.
 */
export interface TdMessageSendingStatePayload {
  '@type'?: string;
}

/**
 * Raw TDLib chat message payload.
 */
export interface TdChatMessagePayload {
  'id'?: TdIntValue;
  'chat_id'?: TdChatId;
  'date'?: TdIntValue;
  'is_outgoing'?: boolean;
  'sender_id'?: TdMessageSenderPayload;
  'sending_state'?: TdMessageSendingStatePayload;
  'content'?: TdMessageContentPayload;
}

/**
 * Raw TDLib wrapper used by `updateNewMessage`.
 */
export interface TdUpdateNewMessagePayload {
  'message'?: TdChatMessagePayload;
}

/**
 * Raw TDLib notification-group type descriptor.
 */
export interface TdNotificationGroupTypePayload {
  '@type'?: string;
}

/**
 * Raw TDLib notification-type payload.
 */
export interface TdNotificationTypePayload {
  '@type'?: string;
  'message'?: TdChatMessagePayload;
  'show_preview'?: boolean;
}

/**
 * Raw TDLib notification payload.
 */
export interface TdNotificationPayload {
  'id'?: TdIntValue;
  'date'?: TdIntValue;
  'is_silent'?: boolean;
  'type'?: TdNotificationTypePayload;
}

/**
 * Raw TDLib wrapper used by `updateNotification`.
 */
export interface TdUpdateNotificationPayload {
  'notification_group_id'?: TdIntValue;
  'notification'?: TdNotificationPayload;
}

/**
 * Raw TDLib wrapper used by `updateNotificationGroup`.
 */
export interface TdUpdateNotificationGroupPayload {
  'notification_group_id'?: TdIntValue;
  'type'?: TdNotificationGroupTypePayload;
  'chat_id'?: TdChatId;
  'notification_settings_chat_id'?: TdChatId;
  'notification_sound_id'?: TdIntValue;
  'total_count'?: TdIntValue;
  'added_notifications'?: TdNotificationPayload[];
  'removed_notification_ids'?: TdIntValue[];
}

/**
 * Raw TDLib notification group snapshot used by `updateActiveNotifications`.
 */
export interface TdActiveNotificationGroupPayload {
  'id'?: TdIntValue;
  'type'?: TdNotificationGroupTypePayload;
  'chat_id'?: TdChatId;
  'total_count'?: TdIntValue;
  'notifications'?: TdNotificationPayload[];
}

/**
 * Raw TDLib wrapper used by `updateActiveNotifications`.
 */
export interface TdUpdateActiveNotificationsPayload {
  'groups'?: TdActiveNotificationGroupPayload[];
}

/**
 * Raw TDLib wrapper used by `updateMessageSendSucceeded`.
 */
export interface TdUpdateMessageSendSucceededPayload {
  'message'?: TdChatMessagePayload;
  'old_message_id'?: TdChatId;
}

/**
 * Raw TDLib payload returned by `getChatHistory`.
 */
export interface TdMessagesPayload {
  'total_count'?: TdIntValue;
  'messages'?: TdChatMessagePayload[];
}

/**
 * Raw TDLib chat payload.
 */
export interface TdChatPayload {
  'id'?: TdChatId;
  'title'?: string;
  'type'?: TdChatTypePayload;
  'photo'?: TdChatPhotoInfoPayload;
  'last_message'?: TdChatMessagePayload;
  'default_disable_notification'?: boolean;
  'last_read_inbox_message_id'?: TdChatId;
  'last_read_outbox_message_id'?: TdChatId;
  'unread_count'?: TdIntValue;
  'notification_settings'?: TdChatNotificationSettingsPayload;
}

/**
 * Raw TDLib wrapper used by `updateNewChat`.
 */
export interface TdUpdateNewChatPayload {
  'chat'?: TdChatPayload;
}

/**
 * Raw TDLib wrapper used by `updateFile`.
 */
export interface TdUpdateFilePayload {
  'file'?: TdFilePayload;
}

/**
 * Raw TDLib wrapper used by `updateChatLastMessage`.
 */
export interface TdUpdateChatLastMessagePayload {
  'chat_id'?: TdChatId;
  'last_message'?: TdChatMessagePayload;
}

/**
 * Raw TDLib wrapper used by `updateChatTitle`.
 */
export interface TdUpdateChatTitlePayload {
  'chat_id'?: TdChatId;
  'title'?: string;
}

/**
 * Raw TDLib wrapper used by `updateChatPhoto`.
 */
export interface TdUpdateChatPhotoPayload {
  'chat_id'?: TdChatId;
  'photo'?: TdChatPhotoInfoPayload | null;
}

/**
 * Raw TDLib wrapper used by `updateChatReadInbox`.
 */
export interface TdUpdateChatReadInboxPayload {
  'chat_id'?: TdChatId;
  'last_read_inbox_message_id'?: TdChatId;
  'unread_count'?: TdIntValue;
}

/**
 * Raw TDLib wrapper used by `updateChatReadOutbox`.
 */
export interface TdUpdateChatReadOutboxPayload {
  'chat_id'?: TdChatId;
  'last_read_outbox_message_id'?: TdChatId;
}

/**
 * Raw TDLib wrapper used by `updateChatNotificationSettings`.
 */
export interface TdUpdateChatNotificationSettingsPayload {
  'chat_id'?: TdChatId;
  'notification_settings'?: TdChatNotificationSettingsPayload;
}

/**
 * Raw TDLib wrapper used by `updateChatPosition`.
 */
export interface TdUpdateChatPositionPayload {
  'chat_id'?: TdChatId;
  'position'?: TdChatPositionPayload;
}

/**
 * Raw TDLib wrapper used by `updateChatAddedToList` and `updateChatRemovedFromList`.
 */
export interface TdUpdateChatListMembershipPayload {
  'chat_id'?: TdChatId;
  'chat_list'?: TdChatListPayload;
}

/**
 * UI-facing chat-list item model.
 */
export interface TdChatListItem {
  'id': string;
  'title': string;
  'chatKind': TdChatKind;
  'username'?: string;
  'peerUserId'?: string;
  'avatarPath'?: string;
  'avatarFileId'?: number;
  'lastMessageDate'?: number;
  'lastMessageText'?: string;
  'lastMessageTextValue'?: UiTextValue;
  'lastMessageKind'?: TdChatMessageKind;
  'lastMessageIsOutgoing'?: boolean;
  'lastMessageCallEventStatus'?: TdCallEventStatus;
  'lastReadInboxMessageId'?: string;
  'lastReadOutboxMessageId'?: string;
  'unreadCount'?: number;
  'defaultDisableNotification'?: boolean;
  'notificationMuteFor'?: number;
}

/**
 * Normalized chat kinds exposed to the chat list UI.
 */
export type TdChatKind = 'private' | 'basicGroup' | 'supergroup' | 'channel' | 'unknown';

/**
 * UI-facing Telegram contact list item model.
 */
export interface TdContactListItem {
  'id': string;
  'firstName': string;
  'lastName': string;
  'username': string;
  'phoneNumber': string;
  'avatarPath'?: string;
  'avatarAnimationPath'?: string;
  'avatarFileId'?: number;
  'isMutualContact': boolean;
  'statusKind'?: TdContactStatusKind;
  'lastSeenAt'?: number;
  'accentColorId'?: number;
}

/**
 * UI-facing user-profile snapshot built from TDLib user caches.
 */
export interface TdUserProfileItem {
  'id': string;
  'firstName': string;
  'lastName': string;
  'username': string;
  'phoneNumber': string;
  'avatarPath'?: string;
  'avatarAnimationPath'?: string;
}

/**
 * Normalized user-status kinds used by contact list rows.
 */
export type TdContactStatusKind = 'online' | 'offline' | 'recently' | 'lastWeek' | 'lastMonth' | 'empty';

/**
 * UI-facing chat message item model.
 */
export interface TdChatMessageItem {
  'id': string;
  'chatId': string;
  'senderUserId'?: string;
  'senderChatId'?: string;
  'senderAvatarPath'?: string;
  'sendingState'?: TdMessageSendingState;
  'deliveryState'?: TdMessageDeliveryState;
  'kind'?: TdChatMessageKind;
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
  'isOutgoing': boolean;
  'date': number;
}

/**
 * Normalized notification content kinds supported by notification rendering.
 */
export type TdNotificationContentKind =
  'text' | 'photo' | 'animation' | 'video' | 'videoNote' | 'voiceNote' | 'sticker' | 'animatedEmoji' |
  'serviceEvent' |
  'unsupported';

/**
 * UI-facing notification preview payload.
 */
export interface TdNotificationContentPayload {
  'kind': TdNotificationContentKind;
  'text': string;
  'showPreview': boolean;
}

/**
 * UI-facing TDLib notification item emitted by notification updates.
 */
export interface TdNotificationItem {
  'id': number;
  'groupId': number;
  'chatId': string;
  'messageId'?: string;
  'senderUserId'?: string;
  'senderChatId'?: string;
  'date': number;
  'isSilent': boolean;
  'content': TdNotificationContentPayload;
}

/**
 * UI-facing TDLib notification group payload.
 */
export interface TdNotificationGroupPayload {
  'groupId': number;
  'chatId': string;
  'notificationSettingsChatId'?: string;
  'totalCount': number;
  'items': TdNotificationItem[];
  'removedNotificationIds': number[];
}

/**
 * TDLib notification event variants emitted by the client layer.
 */
export type TdNotificationEventKind = 'notification' | 'group' | 'active';

/**
 * UI-facing notification event emitted by TdClient.
 */
export interface TdNotificationEvent {
  'kind': TdNotificationEventKind;
  'groupId'?: number;
  'item'?: TdNotificationItem;
  'group'?: TdNotificationGroupPayload;
  'groups'?: TdNotificationGroupPayload[];
}

/**
 * Normalized message content kinds supported by UI renderer.
 */
export type TdChatMessageKind =
  'text' | 'photo' | 'animation' | 'video' | 'videoNote' | 'voiceNote' | 'sticker' | 'animatedEmoji' |
  'serviceEvent' | 'callEvent' |
  'unsupported';

/**
 * Semantic outcome of a `messageCall` history entry, derived from TDLib
 * `discard_reason` together with the message direction.
 *
 * - `answered`  — call connected and lasted `duration > 0` seconds.
 * - `missed`    — incoming call that the local user never picked up.
 * - `declined`  — incoming call rejected by the local user, or outgoing
 *                 call rejected by the remote peer.
 * - `cancelled` — call ended before connecting for any non-decline reason
 *                 (caller hung up before pickup, network drop, etc.).
 */
export type TdCallEventStatus = 'answered' | 'missed' | 'declined' | 'cancelled';

/**
 * Normalized sending-state variants used by outgoing messages.
 */
export type TdMessageSendingState = 'pending' | 'failed';

/**
 * Normalized delivery-state variants used by outgoing messages.
 */
export type TdMessageDeliveryState = 'pending' | 'failed' | 'sent' | 'read';
