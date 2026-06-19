import { UiTextValue } from '../ui/UiTextValue';

/**
 * Enumerates routed index-page presentation modes.
 */
export enum IndexPageMode {
  Empty = 'empty',
  Loading = 'loading',
  Result = 'result',
  Error = 'error'
}

/**
 * Describes the presentation-safe state consumed by the routed index page.
 */
export interface IndexPageState {
  tdlibVersion: string;
  currentAuthState: string;
  infoText: UiTextValue;
  errorText: UiTextValue;
  pageMode: IndexPageMode;
  canChooseQr: boolean;
  canChoosePhone: boolean;
}
