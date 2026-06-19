import { TdChatListItem } from '../td/TdViewTypes';

/**
 * Enumerates routed chats-page presentation modes.
 */
export enum ChatsPageMode {
  Idle = 'idle',
  Loading = 'loading',
  Ready = 'ready',
  Empty = 'empty'
}

/**
 * Describes the presentation-safe state consumed by the routed chats page.
 */
export interface ChatsPageState {
  chats: TdChatListItem[];
  pageMode: ChatsPageMode;
  isLoading: boolean;
  isPullRefreshing: boolean;
}
