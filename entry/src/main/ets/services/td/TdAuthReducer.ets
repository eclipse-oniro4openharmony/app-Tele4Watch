/**
 * Side effects emitted by auth reducer and later executed by `TdClient`.
 */
export type TdAuthAction =
  'sendTdlibParameters' |
  'requestMe' |
  'waitPhoneNumber' |
  'waitOtherDeviceConfirmation' |
  'waitNetwork' |
  'waitCode' |
  'waitPassword' |
  'ready' |
  'lifecycleReset';

/**
 * Input snapshot used to compute next authorization transition.
 */
export interface TdAuthTransitionInput {
  /** Previous authorization state known by the client wrapper. */
  currentState: string;
  /** New authorization state extracted from incoming TDLib payload. */
  nextState: string;
  /** Flag indicating whether `setTdlibParameters` was already sent in current lifecycle. */
  tdlibParametersSent: boolean;
  /** Flag indicating whether `getMe` was already requested in `authorizationStateReady`. */
  meRequested: boolean;
}

/**
 * Pure transition result returned by reducer.
 */
export interface TdAuthTransitionResult {
  /** Whether state value changed compared to previous snapshot. */
  stateChanged: boolean;
  /** New state that should be stored by the client wrapper. */
  nextState: string;
  /** Updated `setTdlibParameters` guard. */
  tdlibParametersSent: boolean;
  /** Updated `getMe` guard. */
  meRequested: boolean;
  /** Whether session-scoped fields should be reset by client wrapper. */
  shouldResetSession: boolean;
  /** Ordered list of side effects to execute after state update. */
  actions: TdAuthAction[];
}

/**
 * Computes deterministic auth transition for one incoming authorization state.
 *
 * This function is intentionally pure (no IO, no timers) to keep behavior
 * easy to test and safe to refactor.
 *
 * @param input Current reducer snapshot with previous and next state values.
 * @returns Transition object with updated flags and side effects.
 */
export function computeTdAuthTransition(input: TdAuthTransitionInput): TdAuthTransitionResult {
  const actions: TdAuthAction[] = [];
  let tdlibParametersSent = input.tdlibParametersSent;
  let meRequested = input.meRequested;
  let shouldResetSession = false;

  const next = input.nextState;
  if (next === 'authorizationStateWaitTdlibParameters') {
    if (input.currentState !== 'authorizationStateWaitTdlibParameters') {
      tdlibParametersSent = false;
      meRequested = false;
    }
    if (!tdlibParametersSent) {
      tdlibParametersSent = true;
      actions.push('sendTdlibParameters');
    }
  } else if (next === 'authorizationStateWaitPhoneNumber') {
    actions.push('waitPhoneNumber');
  } else if (next === 'authorizationStateWaitOtherDeviceConfirmation') {
    actions.push('waitOtherDeviceConfirmation');
  } else if (next === 'authorizationStateWaitNetwork') {
    actions.push('waitNetwork');
  } else if (next === 'authorizationStateWaitCode') {
    actions.push('waitCode');
  } else if (next === 'authorizationStateWaitPassword') {
    actions.push('waitPassword');
  } else if (next === 'authorizationStateReady') {
    actions.push('ready');
    if (!meRequested) {
      meRequested = true;
      actions.push('requestMe');
    }
  } else if (
    next === 'authorizationStateClosing' ||
    next === 'authorizationStateClosed' ||
    next === 'authorizationStateLoggingOut'
  ) {
    tdlibParametersSent = false;
    meRequested = false;
    shouldResetSession = true;
    actions.push('lifecycleReset');
  }

  return {
    stateChanged: next !== input.currentState,
    nextState: next,
    tdlibParametersSent,
    meRequested,
    shouldResetSession,
    actions
  };
}
