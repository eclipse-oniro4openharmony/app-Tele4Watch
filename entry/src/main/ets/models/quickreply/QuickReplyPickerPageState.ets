import { UiTextValue } from '../ui/UiTextValue';
import { QuickReplyPickerSource, QuickReplyTemplate } from './QuickReplyTemplate';

/**
 * Enumerates quick-reply picker presentation modes.
 */
export enum QuickReplyPickerPageMode {
  Idle = 'idle',
  Loading = 'loading',
  Ready = 'ready',
  Empty = 'empty',
  Sending = 'sending',
  Sent = 'sent',
  Error = 'error'
}

/**
 * Describes presentation-safe state consumed by the quick-reply picker page.
 */
export interface QuickReplyPickerPageState {
  chatId: string;
  notificationId?: number;
  source: QuickReplyPickerSource;
  templates: QuickReplyTemplate[];
  pageMode: QuickReplyPickerPageMode;
  isLoading: boolean;
  isSending: boolean;
  selectedTemplateId: string;
  statusText: UiTextValue;
  errorText: UiTextValue;
  canPickTemplate: boolean;
  shouldClose: boolean;
  notificationCancelled: boolean;
}
