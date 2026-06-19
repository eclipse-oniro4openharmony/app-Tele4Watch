/**
 * Source surface that opened the quick-reply picker.
 */
export type QuickReplyPickerSource = 'notification' | 'chatDetails';

/**
 * Quick-reply template shown in notification reply surfaces.
 */
export interface QuickReplyTemplate {
  id: string;
  text: string;
  userDefined: boolean;
}

/**
 * Router params accepted by the QuickReplyPicker page.
 */
export interface QuickReplyPickerRouteParams {
  chatId: string;
  notificationId?: number;
  source: QuickReplyPickerSource;
}

export const DEFAULT_QUICK_REPLY_TEMPLATE_IDS: string[] = [
  'ok',
  'thumbs_up',
  'smile',
  'call_back',
  'on_my_way',
  'cant_talk'
];

/**
 * Builds route params for the quick-reply picker.
 *
 * @param chatId Target TDLib chat id.
 * @param source Surface that opens the picker.
 * @param notificationId Optional NotificationKit id to cancel after confirmed send.
 * @returns Quick-reply picker route params.
 */
export function createQuickReplyPickerRouteParams(
  chatId: string,
  source: QuickReplyPickerSource,
  notificationId?: number
): QuickReplyPickerRouteParams {
  return {
    chatId: chatId,
    notificationId: notificationId,
    source: source
  };
}
