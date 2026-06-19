import { hilog } from '@kit.PerformanceAnalysisKit';
import { buildErrorMessage } from '../../utils/ErrorMessage';
import { tdCallEventDispatcher } from '../td/TdCallEventDispatcher';
import { tdClient } from '../td/TdClient';
import type { TdCallEvent } from '../td/TdPayloadTypes';
import { CallSessionController } from './CallSessionController';
import type { CallSignalingSender } from './CallSessionController';

const DOMAIN = 0x2026;
const TAG = 'CallRuntimeService';

class TdClientCallSignalingSender implements CallSignalingSender {
  sendCallSignalingData(callId: number, data: string): boolean {
    return tdClient.sendCallSignalingData(callId, data);
  }
}

const callSessionController: CallSessionController =
  new CallSessionController(undefined, new TdClientCallSignalingSender());

/**
 * Wires TDLib call events into the VoIP session controller.
 */
class CallRuntimeService {
  private subscriptionId: number = 0;

  /**
   * Starts VoIP call runtime once TDLib authorization is ready.
   *
   * @param source Screen or flow that observed `authorizationStateReady`.
   */
  ensureStarted(source: string): void {
    if (this.subscriptionId > 0) {
      return;
    }

    this.subscriptionId = tdCallEventDispatcher.subscribe((event: TdCallEvent): void => {
      try {
        callSessionController.handleCallEvent(event);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Unhandled call session event error: %{public}s', buildErrorMessage(error));
      }
    });
    hilog.info(DOMAIN, TAG, 'Call runtime started (source=%{public}s).', source);
  }

  /**
   * Mutes or unmutes the microphone for the active native call session.
   *
   * @param muted `true` to mute the outgoing microphone, `false` to unmute.
   * @returns `true` when the request was forwarded to an active native session.
   */
  setMuteMicrophone(muted: boolean): boolean {
    return callSessionController.setMuteMicrophone(muted);
  }

  /**
   * Registers the listener notified with the active call's outgoing-microphone level
   * (M2.4.2). Pass `undefined` to clear.
   *
   * @param listener Callback invoked with a level in [0.0, 1.0].
   */
  setAudioLevelListener(listener: ((level: number) => void) | undefined): void {
    callSessionController.setAudioLevelListener(listener);
  }

  /**
   * Releases VoIP call runtime and stops active native call session.
   */
  release(): void {
    if (this.subscriptionId > 0) {
      tdCallEventDispatcher.unsubscribe(this.subscriptionId);
      this.subscriptionId = 0;
    }
    callSessionController.reset();
    hilog.info(DOMAIN, TAG, 'Call runtime released.');
  }
}

export const callRuntimeService: CallRuntimeService = new CallRuntimeService();
