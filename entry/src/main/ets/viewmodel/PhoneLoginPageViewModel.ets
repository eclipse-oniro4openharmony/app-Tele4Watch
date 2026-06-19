import { tdClient } from '../services/td/TdClient';
import { TdMeInfo } from '../services/td/TdPayloadTypes';
import { PhoneLoginPageMode, PhoneLoginPageState } from '../models/auth/PhoneLoginPageState';
import { UiTextValue, createEmptyUiTextValue, createResourceUiText } from '../models/ui/UiTextValue';

export interface PhoneLoginSubmitPlan {
  nextPageState: PhoneLoginPageState;
  shouldSubmit: boolean;
  phoneNumberInput: string;
}

export enum PhoneLoginRouteTarget {
  None = 'none',
  CodeLogin = 'code-login'
}

export interface PhoneLoginAuthStatePlan {
  nextPageState: PhoneLoginPageState;
  resetProfileNavigation: boolean;
  resetCodeNavigation: boolean;
  nextRoute: PhoneLoginRouteTarget;
}

export class PhoneLoginPageViewModel {
  submitPhoneNumber(phoneNumberInput: string): void {
    tdClient.submitPhoneNumber(phoneNumberInput);
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

  createInitialState(): PhoneLoginPageState {
    return {
      currentAuthState: 'unknown',
      phoneNumberInput: '',
      pageMode: PhoneLoginPageMode.Empty,
      infoText: createEmptyUiTextValue(),
      errorText: createEmptyUiTextValue(),
      submitEnabled: false
    };
  }

  updatePhoneNumberInput(currentState: PhoneLoginPageState, phoneNumberInput: string): PhoneLoginPageState {
    return {
      currentAuthState: currentState.currentAuthState,
      phoneNumberInput: phoneNumberInput,
      pageMode: currentState.pageMode,
      infoText: currentState.infoText,
      errorText: currentState.errorText,
      submitEnabled: currentState.currentAuthState === 'authorizationStateWaitPhoneNumber' &&
        this.hasValidPhoneInput(phoneNumberInput)
    };
  }

  applyAuthState(currentState: PhoneLoginPageState, authState: string): PhoneLoginPageState {
    if (authState === 'authorizationStateReady') {
      return {
        currentAuthState: authState,
        phoneNumberInput: currentState.phoneNumberInput,
        pageMode: PhoneLoginPageMode.Loading,
        infoText: createResourceUiText('phone_login_info_authorization_complete'),
        errorText: createEmptyUiTextValue(),
        submitEnabled: false
      };
    }

    if (authState === 'authorizationStateWaitPhoneNumber') {
      return {
        currentAuthState: authState,
        phoneNumberInput: currentState.phoneNumberInput,
        pageMode: PhoneLoginPageMode.Result,
        infoText: createResourceUiText('phone_login_info_enter_number'),
        errorText: createEmptyUiTextValue(),
        submitEnabled: this.hasValidPhoneInput(currentState.phoneNumberInput)
      };
    }

    if (authState === 'authorizationStateWaitCode') {
      return {
        currentAuthState: authState,
        phoneNumberInput: currentState.phoneNumberInput,
        pageMode: PhoneLoginPageMode.Loading,
        infoText: createResourceUiText('phone_login_info_code_required_opening'),
        errorText: createEmptyUiTextValue(),
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
        phoneNumberInput: currentState.phoneNumberInput,
        pageMode: PhoneLoginPageMode.Loading,
        infoText: createResourceUiText('phone_login_info_preparing_service'),
        errorText: createEmptyUiTextValue(),
        submitEnabled: false
      };
    }

    if (authState === 'authorizationStateWaitOtherDeviceConfirmation') {
      return {
        currentAuthState: authState,
        phoneNumberInput: currentState.phoneNumberInput,
        pageMode: PhoneLoginPageMode.Error,
        infoText: currentState.infoText,
        errorText: createResourceUiText('phone_login_error_flow_qr'),
        submitEnabled: false
      };
    }

    if (authState === 'authorizationStateWaitPassword') {
      return {
        currentAuthState: authState,
        phoneNumberInput: currentState.phoneNumberInput,
        pageMode: PhoneLoginPageMode.Error,
        infoText: currentState.infoText,
        errorText: createResourceUiText('phone_login_error_password_required'),
        submitEnabled: false
      };
    }

    if (authState === 'authorizationStateClosed') {
      return {
        currentAuthState: authState,
        phoneNumberInput: currentState.phoneNumberInput,
        pageMode: PhoneLoginPageMode.Error,
        infoText: currentState.infoText,
        errorText: createResourceUiText('phone_login_error_session_closed'),
        submitEnabled: false
      };
    }

    return {
      currentAuthState: authState,
      phoneNumberInput: currentState.phoneNumberInput,
      pageMode: PhoneLoginPageMode.Error,
      infoText: currentState.infoText,
      errorText: createResourceUiText('phone_login_error_unsupported_state'),
      submitEnabled: false
    };
  }

  planAuthStateChange(currentState: PhoneLoginPageState, authState: string): PhoneLoginAuthStatePlan {
    return {
      nextPageState: this.applyAuthState(currentState, authState),
      resetProfileNavigation: authState !== 'authorizationStateReady',
      resetCodeNavigation: authState === 'authorizationStateWaitPhoneNumber',
      nextRoute: authState === 'authorizationStateWaitCode'
        ? PhoneLoginRouteTarget.CodeLogin
        : PhoneLoginRouteTarget.None
    };
  }

  createSubmittingState(currentState: PhoneLoginPageState): PhoneLoginPageState {
    return {
      currentAuthState: currentState.currentAuthState,
      phoneNumberInput: currentState.phoneNumberInput,
      pageMode: PhoneLoginPageMode.Loading,
      infoText: createResourceUiText('phone_login_info_sending_number'),
      errorText: createEmptyUiTextValue(),
      submitEnabled: false
    };
  }

  planPhoneNumberSubmit(currentState: PhoneLoginPageState): PhoneLoginSubmitPlan {
    if (currentState.currentAuthState !== 'authorizationStateWaitPhoneNumber') {
      return {
        nextPageState: this.createValidationErrorState(
          currentState,
          createResourceUiText('phone_login_error_input_unexpected')
        ),
        shouldSubmit: false,
        phoneNumberInput: currentState.phoneNumberInput
      };
    }

    if (!this.hasValidPhoneInput(currentState.phoneNumberInput)) {
      return {
        nextPageState: this.createValidationErrorState(
          currentState,
          createResourceUiText('phone_login_error_enter_number_example')
        ),
        shouldSubmit: false,
        phoneNumberInput: currentState.phoneNumberInput
      };
    }

    return {
      nextPageState: this.createSubmittingState(currentState),
      shouldSubmit: true,
      phoneNumberInput: currentState.phoneNumberInput
    };
  }

  createValidationErrorState(currentState: PhoneLoginPageState, errorText: UiTextValue): PhoneLoginPageState {
    return {
      currentAuthState: currentState.currentAuthState,
      phoneNumberInput: currentState.phoneNumberInput,
      pageMode: PhoneLoginPageMode.Error,
      infoText: currentState.infoText,
      errorText: errorText,
      submitEnabled: currentState.currentAuthState === 'authorizationStateWaitPhoneNumber' &&
        this.hasValidPhoneInput(currentState.phoneNumberInput)
    };
  }

  createAuthErrorState(currentState: PhoneLoginPageState, code: number, message: string): PhoneLoginPageState {
    return {
      currentAuthState: currentState.currentAuthState,
      phoneNumberInput: currentState.phoneNumberInput,
      pageMode: PhoneLoginPageMode.Error,
      infoText: createResourceUiText('phone_login_info_enter_number'),
      errorText: this.mapPhoneAuthError(code, message),
      submitEnabled: this.hasValidPhoneInput(currentState.phoneNumberInput)
    };
  }

  hasValidPhoneInput(phoneNumberInput: string): boolean {
    return phoneNumberInput.trim().length >= 6;
  }

  mapPhoneAuthError(code: number, message: string): UiTextValue {
    if (message === 'PHONE_NUMBER_INVALID') {
      return createResourceUiText('phone_login_error_invalid');
    }
    if (message === 'PHONE_NUMBER_BANNED') {
      return createResourceUiText('phone_login_error_banned');
    }
    if (message === 'PHONE_NUMBER_FLOOD') {
      return createResourceUiText('phone_login_error_flood');
    }
    if (message.length > 0) {
      return createResourceUiText('phone_login_error_rejected_format', message);
    }

    return createResourceUiText('phone_login_error_rejected_code_format', code);
  }
}
