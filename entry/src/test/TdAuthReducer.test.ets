import { describe, it, expect } from '@ohos/hypium';
import { computeTdAuthTransition } from '../main/ets/services/td/TdAuthReducer';

export default function tdAuthReducerTest() {
  describe('TdAuthReducerTest', () => {
    it('shouldSendTdlibParametersOnlyOnce', 0, () => {
      const first = computeTdAuthTransition({
        currentState: 'unknown',
        nextState: 'authorizationStateWaitTdlibParameters',
        tdlibParametersSent: false,
        meRequested: false
      });
      expect(first.actions.indexOf('sendTdlibParameters') >= 0).assertTrue();
      expect(first.tdlibParametersSent).assertTrue();

      const second = computeTdAuthTransition({
        currentState: 'authorizationStateWaitTdlibParameters',
        nextState: 'authorizationStateWaitTdlibParameters',
        tdlibParametersSent: true,
        meRequested: false
      });
      expect(second.actions.indexOf('sendTdlibParameters')).assertEqual(-1);
      expect(second.tdlibParametersSent).assertTrue();
    });

    it('shouldRequestMeAfterReadyOnlyOnce', 0, () => {
      const first = computeTdAuthTransition({
        currentState: 'authorizationStateWaitCode',
        nextState: 'authorizationStateReady',
        tdlibParametersSent: true,
        meRequested: false
      });
      expect(first.actions.indexOf('ready') >= 0).assertTrue();
      expect(first.actions.indexOf('requestMe') >= 0).assertTrue();
      expect(first.meRequested).assertTrue();

      const second = computeTdAuthTransition({
        currentState: 'authorizationStateReady',
        nextState: 'authorizationStateReady',
        tdlibParametersSent: true,
        meRequested: true
      });
      expect(second.actions.indexOf('requestMe')).assertEqual(-1);
      expect(second.meRequested).assertTrue();
    });

    it('shouldHandleQrConfirmationState', 0, () => {
      const result = computeTdAuthTransition({
        currentState: 'authorizationStateWaitTdlibParameters',
        nextState: 'authorizationStateWaitOtherDeviceConfirmation',
        tdlibParametersSent: true,
        meRequested: false
      });
      expect(result.actions.indexOf('waitOtherDeviceConfirmation') >= 0).assertTrue();
      expect(result.shouldResetSession).assertFalse();
      expect(result.meRequested).assertFalse();
      expect(result.tdlibParametersSent).assertTrue();
    });

    it('shouldResetFlagsOnLifecycleEnd', 0, () => {
      const result = computeTdAuthTransition({
        currentState: 'authorizationStateReady',
        nextState: 'authorizationStateClosed',
        tdlibParametersSent: true,
        meRequested: true
      });
      expect(result.shouldResetSession).assertTrue();
      expect(result.tdlibParametersSent).assertFalse();
      expect(result.meRequested).assertFalse();
      expect(result.actions.indexOf('lifecycleReset') >= 0).assertTrue();
    });

    it('shouldSendTdlibParametersAgainAfterLifecycleReentry', 0, () => {
      const result = computeTdAuthTransition({
        currentState: 'authorizationStateReady',
        nextState: 'authorizationStateWaitTdlibParameters',
        tdlibParametersSent: true,
        meRequested: true
      });
      expect(result.actions.indexOf('sendTdlibParameters') >= 0).assertTrue();
      expect(result.tdlibParametersSent).assertTrue();
      expect(result.meRequested).assertFalse();
    });
  });
}
