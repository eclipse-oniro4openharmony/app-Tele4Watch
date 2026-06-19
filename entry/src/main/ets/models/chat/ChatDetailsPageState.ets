import { TdChatMessageItem } from '../td/TdViewTypes';

/**
 * Enumerates routed chat-details page presentation modes.
 */
export enum ChatDetailsPageMode {
  Idle = 'idle',
  Loading = 'loading',
  Ready = 'ready',
  Empty = 'empty'
}

/**
 * Describes the presentation-safe state consumed by the routed chat-details page.
 */
export interface ChatDetailsPageState {
  chatId: string;
  chatTitle: string;
  chatUsername: string;
  messages: TdChatMessageItem[];
  pageMode: ChatDetailsPageMode;
  isLoadingMessages: boolean;
  isLoadingOlder: boolean;
}
