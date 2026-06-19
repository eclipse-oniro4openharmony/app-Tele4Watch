/**
 * Parsed `@extra` payload for chat-history requests.
 */
export interface TdMessagesExtraInfo {
  /** Chat id extracted from `messages:get:<chatId>:<fromMessageId>[:pull:<token>]`. */
  'chatId': string;
  /** Pagination cursor extracted from `@extra`; defaults to `'0'`. */
  'fromMessageId': string;
  /** User-pull correlation token extracted from the optional `:pull:<token>` suffix; `0` for
   *  non-pull requests (initial load, deeplink, internal probe/sparse retries). Lets
   *  `historyPageResolved` fire only for the matching response, never for unrelated history
   *  responses that happen to share the same `chatId`. */
  'pullToken': number;
}

/**
 * Parsed `@extra` payload for `sendMessage` requests.
 */
export interface TdSendMessageExtraInfo {
  /** Chat id extracted from `message:send:<chatId>:...` or `message:send:voice:<chatId>:...`. */
  'chatId': string;
}

/**
 * Parsed `@extra` payload for `getUserFullInfo` requests.
 */
export interface TdUserFullInfoExtraInfo {
  /** User id extracted from `user:full:<userId>`. */
  'userId': string;
}

/**
 * Raw TDLib payload for `updateDeleteMessages`.
 */
export interface TdUpdateDeleteMessagesPayload {
  /** Chat identifier that owns deleted messages. */
  'chat_id'?: number | string;
  /** List of deleted message ids. */
  'message_ids'?: Array<number | string>;
  /** Indicates whether delete operation is permanent. */
  'is_permanent'?: boolean;
  /** Indicates whether payload was emitted from local cache. */
  'from_cache'?: boolean;
}

/**
 * Message-media binding selector used to map `updateFile` to message fields.
 */
export type TdMessageMediaBindingType = 'main' | 'thumb';

/**
 * Parsed message-media binding token used in TdClient indexes.
 */
export interface TdParsedMessageBindingInfo {
  /** Chat id extracted from binding key. */
  'chatId': string;
  /** Message id extracted from binding key. */
  'messageId': string;
  /** Which media field this binding points to (`main` or `thumb`). */
  'bindingType': TdMessageMediaBindingType;
}
