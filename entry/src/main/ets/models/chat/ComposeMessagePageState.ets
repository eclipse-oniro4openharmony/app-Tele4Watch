import { UiTextValue } from '../ui/UiTextValue';

/**
 * Describes the presentation-safe state consumed by the routed compose-message page.
 */
export interface ComposeMessagePageState {
  chatId: string;
  chatTitle: string;
  chatUsername: string;
  draftMessage: string;
  isSendingMessage: boolean;
  sendErrorText: UiTextValue;
  sendEnabled: boolean;
}
