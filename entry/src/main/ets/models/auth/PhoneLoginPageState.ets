import { UiTextValue } from '../ui/UiTextValue';

/**
 * Enumerates routed phone-login page presentation modes.
 */
export enum PhoneLoginPageMode {
  Empty = 'empty',
  Loading = 'loading',
  Result = 'result',
  Error = 'error'
}

/**
 * Describes the presentation-safe state consumed by the routed phone-login page.
 */
export interface PhoneLoginPageState {
  currentAuthState: string;
  phoneNumberInput: string;
  pageMode: PhoneLoginPageMode;
  infoText: UiTextValue;
  errorText: UiTextValue;
  submitEnabled: boolean;
}
