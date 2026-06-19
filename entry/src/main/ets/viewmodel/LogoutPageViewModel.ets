import { tdClient } from '../services/td/TdClient';
import { LogoutPageMode, LogoutPageState } from '../models/auth/LogoutPageState';
import { createEmptyUiTextValue, createResourceUiText } from '../models/ui/UiTextValue';

export interface LogoutAuthStatePlan {
  nextPageState: LogoutPageState;
  shouldHideConfirm: boolean;
  shouldNavigateToIndex: boolean;
}

export class LogoutPageViewModel {
  logout(): void {
    tdClient.logout();
  }

  setAuthStateListener(listener: (state: string) => void): void {
    tdClient.setAuthStateListener(listener);
  }

  getAuthorizationStateName(): string {
    return tdClient.getAuthorizationStateName();
  }

  createInitialState(): LogoutPageState {
    return {
      currentAuthState: 'unknown',
      pageMode: LogoutPageMode.Empty,
      infoText: createEmptyUiTextValue(),
      errorText: createEmptyUiTextValue(),
      confirmVisible: false,
      actionEnabled: false
    };
  }

  applyAuthState(currentState: LogoutPageState, authState: string): LogoutPageState {
    if (authState === 'authorizationStateReady') {
      return {
        currentAuthState: authState,
        pageMode: LogoutPageMode.Result,
        infoText: createResourceUiText('logout_info_active'),
        errorText: createEmptyUiTextValue(),
        confirmVisible: currentState.confirmVisible,
        actionEnabled: true
      };
    }

    if (authState === 'authorizationStateLoggingOut' || authState === 'authorizationStateClosing') {
      return {
        currentAuthState: authState,
        pageMode: LogoutPageMode.Loading,
        infoText: createResourceUiText('logout_info_in_progress'),
        errorText: createEmptyUiTextValue(),
        confirmVisible: false,
        actionEnabled: false
      };
    }

    if (authState === 'authorizationStateWaitPhoneNumber'
      || authState === 'authorizationStateWaitCode'
      || authState === 'authorizationStateWaitOtherDeviceConfirmation'
      || authState === 'authorizationStateWaitPassword') {
      return {
        currentAuthState: authState,
        pageMode: LogoutPageMode.Result,
        infoText: createResourceUiText('logout_info_no_active'),
        errorText: createEmptyUiTextValue(),
        confirmVisible: false,
        actionEnabled: false
      };
    }

    if (authState === 'authorizationStateWaitTdlibParameters'
      || authState === 'authorizationStateWaitNetwork'
      || authState === 'unknown') {
      return {
        currentAuthState: authState,
        pageMode: LogoutPageMode.Loading,
        infoText: createResourceUiText('logout_info_waiting_service'),
        errorText: createEmptyUiTextValue(),
        confirmVisible: false,
        actionEnabled: false
      };
    }

    if (authState === 'authorizationStateClosed') {
      return {
        currentAuthState: authState,
        pageMode: LogoutPageMode.Loading,
        infoText: createResourceUiText('logout_info_complete'),
        errorText: createEmptyUiTextValue(),
        confirmVisible: false,
        actionEnabled: false
      };
    }

    return {
      currentAuthState: authState,
      pageMode: LogoutPageMode.Error,
      infoText: currentState.infoText,
      errorText: createResourceUiText('logout_error_unsupported_state'),
      confirmVisible: false,
      actionEnabled: false
    };
  }

  planAuthStateChange(currentState: LogoutPageState, authState: string): LogoutAuthStatePlan {
    return {
      nextPageState: this.applyAuthState(currentState, authState),
      shouldHideConfirm: authState !== 'authorizationStateReady',
      shouldNavigateToIndex: authState === 'authorizationStateClosed'
    };
  }

  showConfirmDialog(currentState: LogoutPageState): LogoutPageState {
    return {
      currentAuthState: currentState.currentAuthState,
      pageMode: currentState.pageMode,
      infoText: currentState.infoText,
      errorText: currentState.errorText,
      confirmVisible: currentState.actionEnabled,
      actionEnabled: currentState.actionEnabled
    };
  }

  hideConfirmDialog(currentState: LogoutPageState): LogoutPageState {
    return {
      currentAuthState: currentState.currentAuthState,
      pageMode: currentState.pageMode,
      infoText: currentState.infoText,
      errorText: currentState.errorText,
      confirmVisible: false,
      actionEnabled: currentState.actionEnabled
    };
  }

  createLogoutRequestedState(currentState: LogoutPageState): LogoutPageState {
    return {
      currentAuthState: currentState.currentAuthState,
      pageMode: LogoutPageMode.Loading,
      infoText: createResourceUiText('logout_info_requested'),
      errorText: createEmptyUiTextValue(),
      confirmVisible: false,
      actionEnabled: false
    };
  }
}
