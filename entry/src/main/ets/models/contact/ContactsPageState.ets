import { TdContactListItem } from '../td/TdViewTypes';

/**
 * Enumerates routed contacts-page presentation modes.
 */
export enum ContactsPageMode {
  Idle = 'idle',
  Loading = 'loading',
  Ready = 'ready',
  Empty = 'empty'
}

/**
 * Describes the presentation-safe state consumed by the routed contacts page.
 */
export interface ContactsPageState {
  contacts: TdContactListItem[];
  pageMode: ContactsPageMode;
  isLoading: boolean;
  isPullRefreshing: boolean;
}
