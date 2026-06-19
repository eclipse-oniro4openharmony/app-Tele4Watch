export interface ChatRouteParams {
  chatId: string;
  chatTitle: string;
  chatUsername: string;
}

export function createChatRouteParams(chatId: string, chatTitle: string, chatUsername: string): ChatRouteParams {
  return {
    chatId: chatId,
    chatTitle: chatTitle,
    chatUsername: chatUsername.trim().length > 0 ? chatUsername : ''
  };
}
