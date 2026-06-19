import { tdClient } from '../td/TdClient';
import { tdNotificationsService } from '../notifications/TdNotificationsService';
import {
  QuickReplyMessageSender,
  QuickReplyNotificationCanceller,
  QuickReplySendResult
} from './QuickReplyService';

export interface QuickReplyTdSendGateway {
  'sendChatTextMessageWithConfirm': (
    chatId: string,
    text: string,
    listener: (ok: boolean, errorMessage: string) => void
  ) => boolean;
}

export interface QuickReplyNotificationGateway {
  'handleQuickReplySent': (chatId: string, notificationId?: number) => Promise<void>;
}

/**
 * TDLib-backed quick-reply sender that resolves only after final send confirmation.
 */
export class QuickReplyTdMessageSender implements QuickReplyMessageSender {
  private readonly tdGateway: QuickReplyTdSendGateway;

  constructor(tdGateway?: QuickReplyTdSendGateway) {
    this.tdGateway = tdGateway ? tdGateway : tdClient;
  }

  /**
   * Sends one quick-reply text through TDLib and waits for final confirmation.
   *
   * @param chatId Target chat id as TDLib int64 string.
   * @param text Plain text from selected quick-reply template.
   * @returns Confirmed send result for `QuickReplyService`.
   */
  async sendTextMessage(chatId: string, text: string): Promise<QuickReplySendResult> {
    return new Promise<QuickReplySendResult>((resolve: (value: QuickReplySendResult) => void): void => {
      const started = this.tdGateway.sendChatTextMessageWithConfirm(
        chatId,
        text,
        (ok: boolean, errorMessage: string): void => {
          if (ok) {
            resolve({ kind: 'ok' });
            return;
          }
          resolve({
            kind: 'error',
            errorMessage: errorMessage
          });
        }
      );

      if (!started) {
        resolve({
          kind: 'error',
          errorMessage: 'send unavailable'
        });
      }
    });
  }
}

/**
 * Notification-backed quick-reply canceller that delegates to the notification owner service.
 */
export class QuickReplyNotificationServiceCanceller implements QuickReplyNotificationCanceller {
  private readonly notificationGateway: QuickReplyNotificationGateway;

  constructor(notificationGateway?: QuickReplyNotificationGateway) {
    this.notificationGateway = notificationGateway ? notificationGateway : tdNotificationsService;
  }

  /**
   * Cancels the source chat notification after a quick reply send has been confirmed.
   *
   * @param chatId Target TDLib chat id.
   * @param notificationId Optional source notification id.
   */
  async cancelSentReplyNotification(chatId: string, notificationId?: number): Promise<void> {
    await this.notificationGateway.handleQuickReplySent(chatId, notificationId);
  }
}
