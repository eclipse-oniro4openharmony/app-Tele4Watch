import { UiTextValue } from '../ui/UiTextValue';

/**
 * Enumerates routed logout page presentation modes.
 */
export enum LogoutPageMode {
  Empty = 'empty',
  Loading = 'loading',
  Result = 'result',
  Error = 'error'
}

/**
 * Describes the presentation-safe state consumed by the routed logout page.
 */
export interface LogoutPageState {
  currentAuthState: string;
  pageMode: LogoutPageMode;
  infoText: UiTextValue;
  errorText: UiTextValue;
  confirmVisible: boolean;
  actionEnabled: boolean;
}
