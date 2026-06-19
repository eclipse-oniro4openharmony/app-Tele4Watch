import { tdClient } from '../services/td/TdClient';
import { TdMeInfo } from '../services/td/TdPayloadTypes';
import { CodeLoginPageMode, CodeLoginPageState } from '../models/auth/CodeLoginPageState';
import { UiTextValue, createEmptyUiTextValue, createResourceUiText } from '../models/ui/UiTextValue';

export interface CodeLoginSubmitPlan {
  nextPageState: CodeLoginPageState;
  shouldSubmit: boolean;
  loginCodeInput: string;
}

export enum CodeLoginRouteTarget {
  None = 'none',
  PhoneLogin = 'phone-login'
}

export interface CodeLoginAuthStatePlan {
  nextPageState: CodeLoginPageState;
  resetProfileNavigation: boolean;
  resetPhoneNavigation: boolean;
  nextRoute: CodeLoginRouteTarget;
}

const CODE_LOGIN_DEFAULT_CODE_LENGTH: number = 5;

export class CodeLoginPageViewModel {
  submitCode(loginCodeInput: string): void {
    tdClient.submitCode(loginCodeInput);
  }

  setAuthStateListener(listener: (state: string) => void): void {
    tdClient.setAuthStateListener(listener);
  }

  setMeListener(listener: (me: TdMeInfo) => void): void {
    tdClient.setMeListener(listener);
  }

  setAuthErrorListener(listener: (extra: string, code: number, message: string) => void): void {
    tdClient.setAuthErrorListener(listener);
  }

  getAuthorizationStateName(): string {
    return tdClient.getAuthorizationStateName();
  }

  getExpectedCodeLength(): number {
    return this.normalizedExpectedCodeLength(tdClient.getExpectedAuthenticationCodeLength());
  }

  createInitialState(): CodeLoginPageState {
    return {
      currentAuthState: 'unknown',
      loginCodeInput: '',
      pageMode: CodeLoginPageMode.Empty,
      infoText: createEmptyUiTextValue(),
      errorText: createEmptyUiTextValue(),
      expectedCodeLength: this.getExpectedCodeLength(),
      submitEnabled: false
    };
  }

  updateCodeInput(currentState: CodeLoginPageState, loginCodeInput: string): CodeLoginPageState {
    return {
      currentAuthState: currentState.currentAuthState,
      loginCodeInput: loginCodeInput,
      pageMode: currentState.pageMode,
      infoText: currentState.infoText,
      errorText: currentState.errorText,
      expectedCodeLength: currentState.expectedCodeLength,
      submitEnabled: currentState.currentAuthState === 'authorizationStateWaitCode' &&
        this.hasValidCodeInput(loginCodeInput, currentState.expectedCodeLength)
    };
  }

  applyAuthState(currentState: CodeLoginPageState, authState: string): CodeLoginPageState {
    const expectedCodeLength = authState === 'authorizationStateWaitCode'
      ? this.getExpectedCodeLength()
      : currentState.expectedCodeLength;

    if (authState === 'authorizationStateReady') {
      return {
        currentAuthState: authState,
        loginCodeInput: currentState.loginCodeInput,
        pageMode: CodeLoginPageMode.Loading,
        infoText: createResourceUiText('code_login_info_authorization_complete'),
        errorText: createEmptyUiTextValue(),
        expectedCodeLength: expectedCodeLength,
        submitEnabled: false
      };
    }

    if (authState === 'authorizationStateWaitCode') {
      return {
        currentAuthState: authState,
        loginCodeInput: currentState.loginCodeInput,
        pageMode: CodeLoginPageMode.Result,
        infoText: createResourceUiText('code_login_info_enter_code'),
        errorText: createEmptyUiTextValue(),
        expectedCodeLength: expectedCodeLength,
        submitEnabled: this.hasValidCodeInput(currentState.loginCodeInput, expectedCodeLength)
      };
    }

    if (authState === 'authorizationStateWaitPhoneNumber') {
      return {
        currentAuthState: authState,
        loginCodeInput: currentState.loginCodeInput,
        pageMode: CodeLoginPageMode.Loading,
        infoText: createResourceUiText('code_login_info_phone_required_opening'),
        errorText: createEmptyUiTextValue(),
        expectedCodeLength: expectedCodeLength,
        submitEnabled: false
      };
    }

    if (authState === 'authorizationStateWaitTdlibParameters'
      || authState === 'authorizationStateWaitNetwork'
      || authState === 'authorizationStateClosing'
      || authState === 'authorizationStateLoggingOut'
      || authState === 'unknown') {
      return {
        currentAuthState: authState,
        loginCodeInput: currentState.loginCodeInput,
        pageMode: CodeLoginPageMode.Loading,
        infoText: createResourceUiText('code_login_info_preparing_service'),
        errorText: createEmptyUiTextValue(),
        expectedCodeLength: expectedCodeLength,
        submitEnabled: false
      };
    }

    if (authState === 'authorizationStateWaitOtherDeviceConfirmation') {
      return {
        currentAuthState: authState,
        loginCodeInput: currentState.loginCodeInput,
        pageMode: CodeLoginPageMode.Error,
        infoText: currentState.infoText,
        errorText: createResourceUiText('code_login_error_flow_qr'),
        expectedCodeLength: expectedCodeLength,
        submitEnabled: false
      };
    }

    if (authState === 'authorizationStateWaitPassword') {
      return {
        currentAuthState: authState,
        loginCodeInput: currentState.loginCodeInput,
        pageMode: CodeLoginPageMode.Error,
        infoText: currentState.infoText,
        errorText: createResourceUiText('code_login_error_password_required'),
        expectedCodeLength: expectedCodeLength,
        submitEnabled: false
      };
    }

    if (authState === 'authorizationStateClosed') {
      return {
        currentAuthState: authState,
        loginCodeInput: currentState.loginCodeInput,
        pageMode: CodeLoginPageMode.Error,
        infoText: currentState.infoText,
        errorText: createResourceUiText('code_login_error_session_closed'),
        expectedCodeLength: expectedCodeLength,
        submitEnabled: false
      };
    }

    return {
      currentAuthState: authState,
      loginCodeInput: currentState.loginCodeInput,
      pageMode: CodeLoginPageMode.Error,
      infoText: currentState.infoText,
      errorText: createResourceUiText('code_login_error_unsupported_state'),
      expectedCodeLength: expectedCodeLength,
      submitEnabled: false
    };
  }

  planAuthStateChange(currentState: CodeLoginPageState, authState: string): CodeLoginAuthStatePlan {
    return {
      nextPageState: this.applyAuthState(currentState, authState),
      resetProfileNavigation: authState !== 'authorizationStateReady',
      resetPhoneNavigation: authState === 'authorizationStateWaitCode',
      nextRoute: authState === 'authorizationStateWaitPhoneNumber'
        ? CodeLoginRouteTarget.PhoneLogin
        : CodeLoginRouteTarget.None
    };
  }

  createSubmittingState(currentState: CodeLoginPageState, loginCodeInput: string): CodeLoginPageState {
    return {
      currentAuthState: currentState.currentAuthState,
      loginCodeInput: loginCodeInput,
      pageMode: CodeLoginPageMode.Loading,
      infoText: createResourceUiText('code_login_info_verifying'),
      errorText: createEmptyUiTextValue(),
      expectedCodeLength: currentState.expectedCodeLength,
      submitEnabled: false
    };
  }

  planCodeSubmit(currentState: CodeLoginPageState): CodeLoginSubmitPlan {
    if (currentState.currentAuthState !== 'authorizationStateWaitCode') {
      return {
        nextPageState: this.createValidationErrorState(
          currentState,
          createResourceUiText('code_login_error_input_unexpected')
        ),
        shouldSubmit: false,
        loginCodeInput: currentState.loginCodeInput
      };
    }

    const safeLoginCodeInput = currentState.loginCodeInput.trim();
    if (!this.hasValidCodeInput(safeLoginCodeInput, currentState.expectedCodeLength)) {
      return {
        nextPageState: this.createValidationErrorState(
          currentState,
          createResourceUiText('code_login_error_enter_code')
        ),
        shouldSubmit: false,
        loginCodeInput: currentState.loginCodeInput
      };
    }

    return {
      nextPageState: this.createSubmittingState(currentState, safeLoginCodeInput),
      shouldSubmit: true,
      loginCodeInput: safeLoginCodeInput
    };
  }

  createValidationErrorState(currentState: CodeLoginPageState, errorText: UiTextValue): CodeLoginPageState {
    return {
      currentAuthState: currentState.currentAuthState,
      loginCodeInput: currentState.loginCodeInput,
      pageMode: CodeLoginPageMode.Error,
      infoText: currentState.infoText,
      errorText: errorText,
      expectedCodeLength: currentState.expectedCodeLength,
      submitEnabled: currentState.currentAuthState === 'authorizationStateWaitCode' &&
        this.hasValidCodeInput(currentState.loginCodeInput, currentState.expectedCodeLength)
    };
  }

  createAuthErrorState(currentState: CodeLoginPageState, code: number, message: string): CodeLoginPageState {
    return {
      currentAuthState: currentState.currentAuthState,
      loginCodeInput: currentState.loginCodeInput,
      pageMode: CodeLoginPageMode.Error,
      infoText: createResourceUiText('code_login_info_enter_code'),
      errorText: this.mapCodeAuthError(code, message),
      expectedCodeLength: currentState.expectedCodeLength,
      submitEnabled: this.hasValidCodeInput(currentState.loginCodeInput, currentState.expectedCodeLength)
    };
  }

  hasValidCodeInput(loginCodeInput: string, expectedCodeLength: number = CODE_LOGIN_DEFAULT_CODE_LENGTH): boolean {
    const safeLoginCodeInput = loginCodeInput.trim();
    if (safeLoginCodeInput.length !== this.normalizedExpectedCodeLength(expectedCodeLength)) {
      return false;
    }
    for (let index = 0; index < safeLoginCodeInput.length; index += 1) {
      const codeCharacter = safeLoginCodeInput.charAt(index);
      if (codeCharacter < '0' || codeCharacter > '9') {
        return false;
      }
    }
    return true;
  }

  normalizedExpectedCodeLength(expectedCodeLength: number): number {
    if (expectedCodeLength <= 0) {
      return CODE_LOGIN_DEFAULT_CODE_LENGTH;
    }
    const normalizedLength = Math.round(expectedCodeLength);
    if (normalizedLength <= 0) {
      return CODE_LOGIN_DEFAULT_CODE_LENGTH;
    }
    return normalizedLength;
  }

  mapCodeAuthError(code: number, message: string): UiTextValue {
    if (message === 'PHONE_CODE_INVALID') {
      return createResourceUiText('code_login_error_invalid');
    }
    if (message === 'PHONE_CODE_EXPIRED') {
      return createResourceUiText('code_login_error_expired');
    }
    if (message === 'PHONE_CODE_EMPTY') {
      return createResourceUiText('code_login_error_empty');
    }
    if (message.length > 0) {
      return createResourceUiText('code_login_error_failed_format', message);
    }

    return createResourceUiText('code_login_error_failed_code_format', code);
  }
}
