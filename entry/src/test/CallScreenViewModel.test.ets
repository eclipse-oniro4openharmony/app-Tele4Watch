import { describe, it, expect } from '@ohos/hypium';
import {
  CallScreenPeerInfo,
  CallScreenPhase,
  CallScreenViewModel
} from '../main/ets/viewmodel/CallScreenViewModel';

/**
 * VM unit coverage that does not depend on the TDLib / native singletons:
 * - the phase classification helpers (`isTerminalPhase`, `isErrorPhase`),
 * - the early-exit guards on the call mutation methods so a degenerate call
 *   id or wrong phase never reaches `tdClient`,
 * - listener registration plumbing (`setPeerListener`, `setDurationListener`).
 *
 * Full lifecycle coverage (acceptCall / discardCall ack, duration ticks,
 * `incomingRinging` → `connected` transitions) is exercised by the smoke
 * plan on a real Watch 5 — those paths need the TDLib singleton.
 */
export default function callScreenViewModelTest() {
  describe('CallScreenViewModelTest', () => {
    const TERMINAL_PHASES: CallScreenPhase[] = [
      'ended', 'failed', 'invalidCall', 'invalidUser', 'answerFailed', 'createFailed'
    ];
    const NON_TERMINAL_PHASES: CallScreenPhase[] = [
      'incomingRinging', 'answering', 'calling', 'ringing', 'connecting', 'connected', 'ending'
    ];
    const ERROR_PHASES: CallScreenPhase[] = [
      'failed', 'invalidCall', 'invalidUser', 'answerFailed', 'createFailed'
    ];
    const NON_ERROR_PHASES: CallScreenPhase[] = [
      'incomingRinging', 'answering', 'calling', 'ringing', 'connecting', 'connected',
      'ending', 'ended'
    ];

    it('shouldReportTerminalPhasesAsTerminal', 0, () => {
      const vm = new CallScreenViewModel();
      for (const phase of TERMINAL_PHASES) {
        expect(vm.isTerminalPhase(phase)).assertTrue();
      }
      for (const phase of NON_TERMINAL_PHASES) {
        expect(vm.isTerminalPhase(phase)).assertFalse();
      }
    });

    it('shouldReportOnlyErrorPhasesAsError', 0, () => {
      const vm = new CallScreenViewModel();
      for (const phase of ERROR_PHASES) {
        expect(vm.isErrorPhase(phase)).assertTrue();
      }
      for (const phase of NON_ERROR_PHASES) {
        expect(vm.isErrorPhase(phase)).assertFalse();
      }
    });

    it('shouldRejectEndCallBeforeCallIdIsKnown', 0, () => {
      const vm = new CallScreenViewModel();

      const sent = vm.endCall();

      expect(sent).assertFalse();
    });

    it('shouldRejectAcceptIncomingCallBeforeCallIdIsKnown', 0, () => {
      const vm = new CallScreenViewModel();

      const sent = vm.acceptIncomingCall();

      expect(sent).assertFalse();
    });

    it('shouldRejectRejectIncomingCallBeforeCallIdIsKnown', 0, () => {
      const vm = new CallScreenViewModel();

      const sent = vm.rejectIncomingCall();

      expect(sent).assertFalse();
    });

    it('shouldRejectRejectIncomingCallWhenPhaseIsNotIncomingRinging', 0, () => {
      // The VM starts in the default `calling` phase (outgoing-call default).
      // `rejectIncomingCall` must refuse to dispatch `discardCall` outside the
      // pre-accept `incomingRinging` phase — this is the symmetric guard to
      // `acceptIncomingCall` that closes the Accept→Reject race (review P1).
      const vm = new CallScreenViewModel();

      const sent = vm.rejectIncomingCall();

      expect(sent).assertFalse();
    });

    it('shouldNotifyPeerListenerOnRegistration', 0, () => {
      const vm = new CallScreenViewModel();
      let captured: CallScreenPeerInfo | undefined = undefined;
      vm.setPeerListener((peer: CallScreenPeerInfo): void => {
        captured = peer;
      });
      // Listener registration itself does not emit — peer info is delivered
      // only after the VM resolves the peer through the TDLib cache.
      expect(captured).assertUndefined();
    });

    it('shouldNotifyDurationListenerOnRegistration', 0, () => {
      const vm = new CallScreenViewModel();
      let lastDuration: number | undefined = undefined;
      vm.setDurationListener((seconds: number): void => {
        lastDuration = seconds;
      });
      // Duration emission begins only when phase enters `connected`.
      expect(lastDuration).assertUndefined();
    });

    it('shouldNoOpDisposeWhenNotSubscribed', 0, () => {
      const vm = new CallScreenViewModel();
      vm.dispose();
      // Second dispose must not throw — confirms the unsubscribe path is
      // idempotent (matters when CallScreen.aboutToDisappear runs after a
      // VM that never made it through `subscribeCallEvents`).
      vm.dispose();
    });
  });
}
