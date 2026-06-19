import { tdClient } from '../services/td/TdClient';
import { TdMeInfo } from '../services/td/TdPayloadTypes';
import { QrLoginPageMode, QrLoginPageState } from '../models/auth/QrLoginPageState';
import { UiTextValue, createEmptyUiTextValue, createRawUiText, createResourceUiText } from '../models/ui/UiTextValue';

export interface QrLoginAuthStatePlan {
  nextPageState: QrLoginPageState;
  resetPreferenceRequest: boolean;
  shouldRequestQrPreference: boolean;
}

export class QrLoginPageViewModel {
  requestQrLoginPreference(): boolean {
    return tdClient.requestQrLoginPreference();
  }

  getQrAuthLink(): string {
    return tdClient.getQrAuthLink();
  }

  getQrAuthLinkUpdatedAtMs(): number {
    return tdClient.getQrAuthLinkUpdatedAtMs();
  }

  setAuthStateListener(listener: (state: string) => void): void {
    tdClient.setAuthStateListener(listener);
  }

  setQrAuthLinkListener(listener: (link: string, updatedAtMs: number) => void): void {
    tdClient.setQrAuthLinkListener(listener);
  }

  setMeListener(listener: (me: TdMeInfo) => void): void {
    tdClient.setMeListener(listener);
  }

  getAuthorizationStateName(): string {
    return tdClient.getAuthorizationStateName();
  }

  createInitialState(): QrLoginPageState {
    return {
      currentAuthState: 'unknown',
      qrAuthLink: '',
      lastNonEmptyQrAuthLink: '',
      qrAuthLinkUpdatedAtMs: 0,
      qrUiNowMs: 0,
      pageMode: QrLoginPageMode.Empty,
      infoText: createEmptyUiTextValue(),
      errorText: createEmptyUiTextValue()
    };
  }

  applyAuthState(currentState: QrLoginPageState, authState: string): QrLoginPageState {
    if (authState === 'authorizationStateReady') {
      return {
        currentAuthState: authState,
        qrAuthLink: currentState.qrAuthLink,
        lastNonEmptyQrAuthLink: currentState.lastNonEmptyQrAuthLink,
        qrAuthLinkUpdatedAtMs: currentState.qrAuthLinkUpdatedAtMs,
        qrUiNowMs: currentState.qrUiNowMs,
        pageMode: QrLoginPageMode.Result,
        infoText: createResourceUiText('qr_login_info_authorization_complete'),
        errorText: createEmptyUiTextValue()
      };
    }

    if (authState === 'authorizationStateWaitPhoneNumber') {
      return {
        currentAuthState: authState,
        qrAuthLink: currentState.qrAuthLink,
        lastNonEmptyQrAuthLink: currentState.lastNonEmptyQrAuthLink,
        qrAuthLinkUpdatedAtMs: currentState.qrAuthLinkUpdatedAtMs,
        qrUiNowMs: currentState.qrUiNowMs,
        pageMode: QrLoginPageMode.Loading,
        infoText: createResourceUiText('qr_login_info_requesting_link'),
        errorText: createEmptyUiTextValue()
      };
    }

    if (authState === 'authorizationStateWaitOtherDeviceConfirmation') {
      if (currentState.qrAuthLink.length > 0) {
        return {
          currentAuthState: authState,
          qrAuthLink: currentState.qrAuthLink,
          lastNonEmptyQrAuthLink: currentState.lastNonEmptyQrAuthLink,
          qrAuthLinkUpdatedAtMs: currentState.qrAuthLinkUpdatedAtMs,
          qrUiNowMs: currentState.qrUiNowMs,
          pageMode: QrLoginPageMode.Result,
          infoText: this.getQrFreshnessText(currentState),
          errorText: createEmptyUiTextValue()
        };
      }

      return {
        currentAuthState: authState,
        qrAuthLink: currentState.qrAuthLink,
        lastNonEmptyQrAuthLink: currentState.lastNonEmptyQrAuthLink,
        qrAuthLinkUpdatedAtMs: currentState.qrAuthLinkUpdatedAtMs,
        qrUiNowMs: currentState.qrUiNowMs,
        pageMode: QrLoginPageMode.Loading,
        infoText: createResourceUiText('qr_login_info_waiting_link'),
        errorText: createEmptyUiTextValue()
      };
    }

    if (authState === 'authorizationStateWaitTdlibParameters'
      || authState === 'authorizationStateWaitNetwork'
      || authState === 'authorizationStateClosing'
      || authState === 'authorizationStateLoggingOut'
      || authState === 'unknown') {
      return {
        currentAuthState: authState,
        qrAuthLink: currentState.qrAuthLink,
        lastNonEmptyQrAuthLink: currentState.lastNonEmptyQrAuthLink,
        qrAuthLinkUpdatedAtMs: currentState.qrAuthLinkUpdatedAtMs,
        qrUiNowMs: currentState.qrUiNowMs,
        pageMode: QrLoginPageMode.Loading,
        infoText: createResourceUiText('qr_login_info_preparing_service'),
        errorText: createEmptyUiTextValue()
      };
    }

    if (authState === 'authorizationStateClosed') {
      return {
        currentAuthState: authState,
        qrAuthLink: currentState.qrAuthLink,
        lastNonEmptyQrAuthLink: currentState.lastNonEmptyQrAuthLink,
        qrAuthLinkUpdatedAtMs: currentState.qrAuthLinkUpdatedAtMs,
        qrUiNowMs: currentState.qrUiNowMs,
        pageMode: QrLoginPageMode.Error,
        infoText: currentState.infoText,
        errorText: createResourceUiText('qr_login_error_session_closed')
      };
    }

    if (authState === 'authorizationStateWaitCode') {
      return {
        currentAuthState: authState,
        qrAuthLink: currentState.qrAuthLink,
        lastNonEmptyQrAuthLink: currentState.lastNonEmptyQrAuthLink,
        qrAuthLinkUpdatedAtMs: currentState.qrAuthLinkUpdatedAtMs,
        qrUiNowMs: currentState.qrUiNowMs,
        pageMode: QrLoginPageMode.Error,
        infoText: currentState.infoText,
        errorText: createResourceUiText('qr_login_error_wait_code')
      };
    }

    if (authState === 'authorizationStateWaitPassword') {
      return {
        currentAuthState: authState,
        qrAuthLink: currentState.qrAuthLink,
        lastNonEmptyQrAuthLink: currentState.lastNonEmptyQrAuthLink,
        qrAuthLinkUpdatedAtMs: currentState.qrAuthLinkUpdatedAtMs,
        qrUiNowMs: currentState.qrUiNowMs,
        pageMode: QrLoginPageMode.Error,
        infoText: currentState.infoText,
        errorText: createResourceUiText('qr_login_error_password_required')
      };
    }

    return {
      currentAuthState: authState,
      qrAuthLink: currentState.qrAuthLink,
      lastNonEmptyQrAuthLink: currentState.lastNonEmptyQrAuthLink,
      qrAuthLinkUpdatedAtMs: currentState.qrAuthLinkUpdatedAtMs,
      qrUiNowMs: currentState.qrUiNowMs,
      pageMode: QrLoginPageMode.Error,
      infoText: currentState.infoText,
      errorText: createResourceUiText('qr_login_error_unsupported_state')
    };
  }

  planAuthStateChange(
    currentState: QrLoginPageState,
    authState: string,
    preferenceAlreadyRequested: boolean
  ): QrLoginAuthStatePlan {
    return {
      nextPageState: this.applyAuthState(currentState, authState),
      resetPreferenceRequest: authState !== 'authorizationStateWaitPhoneNumber',
      shouldRequestQrPreference: authState === 'authorizationStateWaitPhoneNumber' && !preferenceAlreadyRequested
    };
  }

  applyQrLinkUpdate(currentState: QrLoginPageState, qrAuthLink: string, updatedAtMs: number): QrLoginPageState {
    const lastNonEmptyQrAuthLink = qrAuthLink.length > 0 ? qrAuthLink : currentState.lastNonEmptyQrAuthLink;
    const nextState: QrLoginPageState = {
      currentAuthState: currentState.currentAuthState,
      qrAuthLink: qrAuthLink,
      lastNonEmptyQrAuthLink: lastNonEmptyQrAuthLink,
      qrAuthLinkUpdatedAtMs: updatedAtMs,
      qrUiNowMs: currentState.qrUiNowMs,
      pageMode: currentState.pageMode,
      infoText: currentState.infoText,
      errorText: currentState.errorText
    };

    if (nextState.currentAuthState === 'authorizationStateWaitOtherDeviceConfirmation') {
      if (qrAuthLink.length > 0) {
        return {
          currentAuthState: nextState.currentAuthState,
          qrAuthLink: nextState.qrAuthLink,
          lastNonEmptyQrAuthLink: nextState.lastNonEmptyQrAuthLink,
          qrAuthLinkUpdatedAtMs: nextState.qrAuthLinkUpdatedAtMs,
          qrUiNowMs: nextState.qrUiNowMs,
          pageMode: QrLoginPageMode.Result,
          infoText: this.getQrFreshnessText(nextState),
          errorText: createEmptyUiTextValue()
        };
      }

      return {
        currentAuthState: nextState.currentAuthState,
        qrAuthLink: nextState.qrAuthLink,
        lastNonEmptyQrAuthLink: nextState.lastNonEmptyQrAuthLink,
        qrAuthLinkUpdatedAtMs: nextState.qrAuthLinkUpdatedAtMs,
        qrUiNowMs: nextState.qrUiNowMs,
        pageMode: QrLoginPageMode.Loading,
        infoText: createResourceUiText('qr_login_info_waiting_link'),
        errorText: createEmptyUiTextValue()
      };
    }

    return nextState;
  }

  updateQrUiNow(currentState: QrLoginPageState, nowMs: number): QrLoginPageState {
    const nextState: QrLoginPageState = {
      currentAuthState: currentState.currentAuthState,
      qrAuthLink: currentState.qrAuthLink,
      lastNonEmptyQrAuthLink: currentState.lastNonEmptyQrAuthLink,
      qrAuthLinkUpdatedAtMs: currentState.qrAuthLinkUpdatedAtMs,
      qrUiNowMs: nowMs,
      pageMode: currentState.pageMode,
      infoText: currentState.infoText,
      errorText: currentState.errorText
    };

    if (nextState.currentAuthState === 'authorizationStateWaitOtherDeviceConfirmation' &&
      nextState.qrAuthLink.length > 0) {
      return {
        currentAuthState: nextState.currentAuthState,
        qrAuthLink: nextState.qrAuthLink,
        lastNonEmptyQrAuthLink: nextState.lastNonEmptyQrAuthLink,
        qrAuthLinkUpdatedAtMs: nextState.qrAuthLinkUpdatedAtMs,
        qrUiNowMs: nextState.qrUiNowMs,
        pageMode: nextState.pageMode,
        infoText: this.getQrFreshnessText(nextState),
        errorText: nextState.errorText
      };
    }

    return nextState;
  }

  createQrPreferenceRequestErrorState(currentState: QrLoginPageState): QrLoginPageState {
    return {
      currentAuthState: currentState.currentAuthState,
      qrAuthLink: currentState.qrAuthLink,
      lastNonEmptyQrAuthLink: currentState.lastNonEmptyQrAuthLink,
      qrAuthLinkUpdatedAtMs: currentState.qrAuthLinkUpdatedAtMs,
      qrUiNowMs: currentState.qrUiNowMs,
      pageMode: QrLoginPageMode.Error,
      infoText: currentState.infoText,
      errorText: createResourceUiText('qr_login_error_request_link')
    };
  }

  getRenderableQrLink(currentState: QrLoginPageState): string {
    if (currentState.qrAuthLink.length > 0) {
      return currentState.qrAuthLink;
    }
    if (currentState.currentAuthState === 'authorizationStateReady') {
      return currentState.lastNonEmptyQrAuthLink;
    }

    return '';
  }

  getQrFreshnessText(currentState: QrLoginPageState): UiTextValue {
    if (currentState.qrAuthLink.length === 0) {
      return createResourceUiText('qr_login_info_waiting_link');
    }
    const ageSeconds = this.getQrLinkAgeSeconds(currentState);
    if (ageSeconds >= 55) {
      return createResourceUiText('qr_login_info_qr_may_be_expired_format', ageSeconds);
    }

    return createResourceUiText('qr_login_info_qr_refreshed_format', ageSeconds);
  }

  getQrTokenPreview(currentState: QrLoginPageState): UiTextValue {
    const qrLink = this.getRenderableQrLink(currentState);
    const tokenMatch = qrLink.match(/token=([A-Za-z0-9_-]+)/);
    if (!tokenMatch || tokenMatch.length < 2) {
      return createResourceUiText('qr_login_token_unavailable');
    }

    const token = tokenMatch[1];
    if (token.length <= 16) {
      return createRawUiText(`token: ${token}`);
    }

    const prefix = token.substring(0, 8);
    const suffix = token.substring(token.length - 8);
    return createRawUiText(`token: ${prefix}...${suffix}`);
  }

  private getQrLinkAgeSeconds(currentState: QrLoginPageState): number {
    if (currentState.qrAuthLinkUpdatedAtMs <= 0 || currentState.qrUiNowMs <= 0) {
      return 0;
    }

    const deltaMs = currentState.qrUiNowMs - currentState.qrAuthLinkUpdatedAtMs;
    if (deltaMs <= 0) {
      return 0;
    }

    return Math.floor(deltaMs / 1000);
  }
}
