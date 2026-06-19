import { tdClient } from '../services/td/TdClient';
import { ComposeMessagePageState } from '../models/chat/ComposeMessagePageState';
import { UiTextValue, createEmptyUiTextValue, createRawUiText, createResourceUiText } from '../models/ui/UiTextValue';

export interface ComposeMessageSendPlan {
  nextPageState: ComposeMessagePageState;
  shouldSend: boolean;
  chatId: string;
  messageText: string;
}

export class ComposeMessagePageViewModel {
  setMessageSendResultListener(listener: (chatId: string, ok: boolean, errorMessage: string) => void): void {
    tdClient.setMessageSendResultListener(listener);
  }

  clearMessageSendResultListener(): void {
    tdClient.setMessageSendResultListener((_chatId: string, _ok: boolean, _errorMessage: string): void => {
      // Intentionally reset listener to avoid mutating state after page is gone.
    });
  }

  setAuthStateListener(listener: (state: string) => void): void {
    tdClient.setAuthStateListener(listener);
  }

  getAuthorizationStateName(): string {
    return tdClient.getAuthorizationStateName();
  }

  sendChatTextMessage(chatId: string, text: string): boolean {
    return tdClient.sendChatTextMessage(chatId, text);
  }

  requestChatHistory(chatId: string, limit: number): void {
    tdClient.requestChatHistory(chatId, limit);
  }

  createInitialState(): ComposeMessagePageState {
    return {
      chatId: '',
      chatTitle: '',
      chatUsername: '',
      draftMessage: '',
      isSendingMessage: false,
      sendErrorText: createEmptyUiTextValue(),
      sendEnabled: false
    };
  }

  applyRoute(
    currentState: ComposeMessagePageState,
    chatId: string,
    chatTitle: string,
    chatUsername: string
  ): ComposeMessagePageState {
    return {
      chatId: chatId,
      chatTitle: chatTitle.length > 0 ? chatTitle : currentState.chatTitle,
      chatUsername: chatUsername,
      draftMessage: currentState.draftMessage,
      isSendingMessage: currentState.isSendingMessage,
      sendErrorText: currentState.sendErrorText,
      sendEnabled: this.canSendMessageForState(currentState.isSendingMessage, currentState.draftMessage)
    };
  }

  updateDraftMessage(currentState: ComposeMessagePageState, draftMessage: string): ComposeMessagePageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      draftMessage: draftMessage,
      isSendingMessage: currentState.isSendingMessage,
      sendErrorText: currentState.sendErrorText,
      sendEnabled: this.canSendMessageForState(currentState.isSendingMessage, draftMessage)
    };
  }

  createSendingState(currentState: ComposeMessagePageState): ComposeMessagePageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      draftMessage: currentState.draftMessage,
      isSendingMessage: true,
      sendErrorText: createEmptyUiTextValue(),
      sendEnabled: false
    };
  }

  createSendSuccessState(currentState: ComposeMessagePageState): ComposeMessagePageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      draftMessage: '',
      isSendingMessage: false,
      sendErrorText: createEmptyUiTextValue(),
      sendEnabled: false
    };
  }

  createSendErrorState(currentState: ComposeMessagePageState, errorMessage: string): ComposeMessagePageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      draftMessage: currentState.draftMessage,
      isSendingMessage: false,
      sendErrorText: this.mapSendError(errorMessage),
      sendEnabled: this.canSendMessageForState(false, currentState.draftMessage)
    };
  }

  createValidationErrorState(currentState: ComposeMessagePageState, errorText: UiTextValue): ComposeMessagePageState {
    return {
      chatId: currentState.chatId,
      chatTitle: currentState.chatTitle,
      chatUsername: currentState.chatUsername,
      draftMessage: currentState.draftMessage,
      isSendingMessage: false,
      sendErrorText: errorText,
      sendEnabled: this.canSendMessageForState(false, currentState.draftMessage)
    };
  }

  planMessageSend(currentState: ComposeMessagePageState): ComposeMessageSendPlan {
    if (currentState.isSendingMessage) {
      return {
        nextPageState: currentState,
        shouldSend: false,
        chatId: currentState.chatId,
        messageText: ''
      };
    }

    const trimmedMessage = currentState.draftMessage.trim();
    if (trimmedMessage.length === 0) {
      return {
        nextPageState: this.createValidationErrorState(
          currentState,
          createResourceUiText('compose_error_enter_message')
        ),
        shouldSend: false,
        chatId: currentState.chatId,
        messageText: ''
      };
    }

    if (currentState.chatId.trim().length === 0) {
      return {
        nextPageState: this.createValidationErrorState(
          currentState,
          createResourceUiText('compose_error_chat_unavailable')
        ),
        shouldSend: false,
        chatId: currentState.chatId,
        messageText: ''
      };
    }

    return {
      nextPageState: this.createSendingState(currentState),
      shouldSend: true,
      chatId: currentState.chatId,
      messageText: trimmedMessage
    };
  }

  mapSendError(errorMessage: string): UiTextValue {
    const trimmedMessage = errorMessage.trim();
    if (trimmedMessage.length === 0) {
      return createResourceUiText('compose_error_send_failed');
    }

    if (trimmedMessage.length <= 40) {
      return createRawUiText(trimmedMessage);
    }

    return createRawUiText(`${trimmedMessage.substring(0, 37)}...`);
  }

  private canSendMessageForState(sending: boolean, draftMessage: string): boolean {
    if (sending) {
      return false;
    }

    return draftMessage.trim().length > 0;
  }
}
