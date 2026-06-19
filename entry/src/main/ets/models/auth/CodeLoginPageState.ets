import { UiTextValue } from '../ui/UiTextValue';

/**
 * Enumerates routed code-login page presentation modes.
 */
export enum CodeLoginPageMode {
  Empty = 'empty',
  Loading = 'loading',
  Result = 'result',
  Error = 'error'
}

/**
 * Describes the presentation-safe state consumed by the routed code-login page.
 */
export interface CodeLoginPageState {
  currentAuthState: string;
  loginCodeInput: string;
  pageMode: CodeLoginPageMode;
  infoText: UiTextValue;
  errorText: UiTextValue;
  expectedCodeLength: number;
  submitEnabled: boolean;
}
