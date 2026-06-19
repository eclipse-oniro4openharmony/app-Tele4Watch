import { UiTextValue } from '../ui/UiTextValue';

/**
 * Enumerates routed QR-login page presentation modes.
 */
export enum QrLoginPageMode {
  Empty = 'empty',
  Loading = 'loading',
  Result = 'result',
  Error = 'error'
}

/**
 * Describes the presentation-safe state consumed by the routed QR-login page.
 */
export interface QrLoginPageState {
  currentAuthState: string;
  qrAuthLink: string;
  lastNonEmptyQrAuthLink: string;
  qrAuthLinkUpdatedAtMs: number;
  qrUiNowMs: number;
  pageMode: QrLoginPageMode;
  infoText: UiTextValue;
  errorText: UiTextValue;
}
