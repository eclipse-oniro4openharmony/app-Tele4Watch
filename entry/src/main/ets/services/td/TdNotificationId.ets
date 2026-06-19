const MAX_TD_NOTIFICATION_ID = 2147483647;

/**
 * Builds a stable positive int32 NotificationKit id for synthetic fallback notifications.
 *
 * TDLib message ids are unique inside one chat, but not globally across chats. Fallback
 * notifications emitted from `updateNewMessage` must therefore always include `chatId`
 * in the stable id source.
 *
 * @param chatId TDLib chat id.
 * @param messageId TDLib message id.
 * @returns Positive int32 id.
 */
export function buildFallbackNotificationId(chatId: string, messageId: string): number {
  const source = chatId.trim() + ':' + messageId.trim();
  let hash = 17;
  for (let index = 0; index < source.length; index++) {
    hash = (hash * 31 + source.charCodeAt(index)) % MAX_TD_NOTIFICATION_ID;
  }
  if (hash <= 0) {
    return 1;
  }
  return hash;
}
