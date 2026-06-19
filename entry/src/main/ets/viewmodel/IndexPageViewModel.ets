import { tdClient } from '../services/td/TdClient';
import { TdMeInfo } from '../services/td/TdPayloadTypes';
import { IndexPageMode, IndexPageState } from '../models/auth/IndexPageState';
import { UiTextValue, createEmptyUiTextValue, createRawUiText, createResourceUiText } from '../models/ui/UiTextValue';

export interface IndexAuthStatePlan {
  nextPageState: IndexPageState;
  resetProfileNavigation: boolean;
  shouldRestartBootstrap: boolean;
}

/**
 * Creates the typed state scaffold for the routed index page.
 */
export class IndexPageViewModel {
  startAuthorizationBootstrap(): void {
    tdClient.startAuthorizationBootstrap();
  }

  getVersion(): string {
    return tdClient.getVersion();
  }

  getAuthorizationStateName(): string {
    return tdClient.getAuthorizationStateName();
  }

  setMeListener(listener: (me: TdMeInfo) => void): void {
    tdClient.setMeListener(listener);
  }

  setAuthStateListener(listener: (state: string) => void): void {
    tdClient.setAuthStateListener(listener);
  }

  createInitialState(): IndexPageState {
    return {
      tdlibVersion: '',
      currentAuthState: 'unknown',
      infoText: createEmptyUiTextValue(),
      errorText: createEmptyUiTextValue(),
      pageMode: IndexPageMode.Empty,
      canChooseQr: false,
      canChoosePhone: false
    };
  }

  applyTdlibVersion(currentState: IndexPageState, version: string): IndexPageState {
    return {
      tdlibVersion: version,
      currentAuthState: currentState.currentAuthState,
      infoText: currentState.infoText,
      errorText: currentState.errorText,
      pageMode: currentState.pageMode,
      canChooseQr: currentState.canChooseQr,
      canChoosePhone: currentState.canChoosePhone
    };
  }

  applyAuthState(currentState: IndexPageState, authState: string): IndexPageState {
    if (authState === 'authorizationStateReady') {
      return this.createMappedState(
        currentState,
        authState,
        IndexPageMode.Result,
        createResourceUiText('index_info_session_active_opening_profile'),
        createEmptyUiTextValue(),
        false,
        false
      );
    }

    if (authState === 'authorizationStateClosed') {
      return this.createMappedState(
        currentState,
        authState,
        IndexPageMode.Loading,
        createResourceUiText('index_info_session_closed_restarting_authorization'),
        createEmptyUiTextValue(),
        false,
        false
      );
    }

    if (authState === 'authorizationStateWaitTdlibParameters'
      || authState === 'authorizationStateWaitNetwork'
      || authState === 'authorizationStateClosing'
      || authState === 'authorizationStateLoggingOut'
      || authState === 'unknown') {
      return this.createMappedState(
        currentState,
        authState,
        IndexPageMode.Loading,
        createResourceUiText('index_info_preparing_telegram_authorization'),
        createEmptyUiTextValue(),
        false,
        false
      );
    }

    if (authState === 'authorizationStateWaitPhoneNumber') {
      return this.createMappedState(
        currentState,
        authState,
        IndexPageMode.Result,
        createResourceUiText('index_info_choose_login_method'),
        createEmptyUiTextValue(),
        true,
        true
      );
    }

    if (authState === 'authorizationStateWaitCode') {
      return this.createMappedState(
        currentState,
        authState,
        IndexPageMode.Result,
        createResourceUiText('index_info_phone_continue'),
        createEmptyUiTextValue(),
        false,
        true
      );
    }

    if (authState === 'authorizationStateWaitOtherDeviceConfirmation') {
      return this.createMappedState(
        currentState,
        authState,
        IndexPageMode.Result,
        createResourceUiText('index_info_qr_continue'),
        createEmptyUiTextValue(),
        true,
        false
      );
    }

    if (authState === 'authorizationStateWaitPassword') {
      return this.createMappedState(
        currentState,
        authState,
        IndexPageMode.Result,
        createResourceUiText('index_info_password_required'),
        createEmptyUiTextValue(),
        false,
        false
      );
    }

    return this.createMappedState(
      currentState,
      authState,
      IndexPageMode.Result,
      createResourceUiText('index_info_choose_next_action'),
      createEmptyUiTextValue(),
      false,
      false
    );
  }

  planAuthStateChange(currentState: IndexPageState, authState: string): IndexAuthStatePlan {
    return {
      nextPageState: this.applyAuthState(currentState, authState),
      resetProfileNavigation: authState !== 'authorizationStateReady',
      shouldRestartBootstrap: authState === 'authorizationStateClosed'
    };
  }

  createBootstrapStartingState(currentState: IndexPageState): IndexPageState {
    return {
      tdlibVersion: currentState.tdlibVersion,
      currentAuthState: currentState.currentAuthState,
      infoText: createResourceUiText('index_info_starting_tdlib_bootstrap'),
      errorText: createEmptyUiTextValue(),
      pageMode: IndexPageMode.Loading,
      canChooseQr: false,
      canChoosePhone: false
    };
  }

  createBootstrapErrorState(currentState: IndexPageState, errorText: string): IndexPageState {
    return {
      tdlibVersion: currentState.tdlibVersion,
      currentAuthState: currentState.currentAuthState,
      infoText: createResourceUiText('index_info_bootstrap_failed'),
      errorText: createRawUiText(errorText),
      pageMode: IndexPageMode.Error,
      canChooseQr: false,
      canChoosePhone: false
    };
  }

  shouldShowAuthChoices(currentState: IndexPageState): boolean {
    return currentState.pageMode === IndexPageMode.Result &&
      currentState.currentAuthState !== 'authorizationStateReady';
  }

  private createMappedState(
    currentState: IndexPageState,
    authState: string,
    pageMode: IndexPageMode,
    infoText: UiTextValue,
    errorText: UiTextValue,
    canChooseQr: boolean,
    canChoosePhone: boolean
  ): IndexPageState {
    return {
      tdlibVersion: currentState.tdlibVersion,
      currentAuthState: authState,
      infoText: infoText,
      errorText: errorText,
      pageMode: pageMode,
      canChooseQr: canChooseQr,
      canChoosePhone: canChoosePhone
    };
  }
}
