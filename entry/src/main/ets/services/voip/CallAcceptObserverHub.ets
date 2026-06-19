import { hilog } from '@kit.PerformanceAnalysisKit';
import { buildErrorMessage } from '../../utils/ErrorMessage';

const DOMAIN = 0x2026;
const TAG = 'CallAcceptObserverHub';

/**
 * Listener invoked when an accept request was dispatched for `callId` from a
 * path that bypasses `CallScreenViewModel` (today: the notification answer
 * shortcut handled directly by `EntryAbility`).
 */
export type CallAcceptObserverListener = (callId: number) => void;

class CallAcceptObserverListenerEntry {
  readonly id: number;
  readonly listener: CallAcceptObserverListener;

  constructor(id: number, listener: CallAcceptObserverListener) {
    this.id = id;
    this.listener = listener;
  }
}

/**
 * Lightweight broadcast hub that lets components outside `CallScreenViewModel`
 * signal "this call has been accepted" without holding a reference to the
 * live VM instance. The VM subscribes for the duration of its event
 * subscription and flips its internal `acceptDispatched` / phase state as
 * soon as the hub fires — that closes the race where the notification
 * answer shortcut sends `tdClient.acceptCall` directly while the screen is
 * still showing the Decline button in `incomingRinging`.
 */
export class CallAcceptObserverHub {
  private nextSubscriptionId: number = 1;
  private listeners: CallAcceptObserverListenerEntry[] = [];

  /**
   * Registers one accept-notification subscriber.
   *
   * @param listener Subscriber callback invoked with the accepted call id.
   * @returns Subscription id used by `unsubscribe`.
   */
  subscribe(listener: CallAcceptObserverListener): number {
    const subscriptionId = this.nextSubscriptionId;
    this.nextSubscriptionId += 1;
    this.listeners.push(new CallAcceptObserverListenerEntry(subscriptionId, listener));
    return subscriptionId;
  }

  /**
   * Removes one accept-notification subscriber.
   *
   * @param subscriptionId Subscription id returned by `subscribe`.
   */
  unsubscribe(subscriptionId: number): void {
    if (subscriptionId <= 0 || this.listeners.length === 0) {
      return;
    }
    const remaining: CallAcceptObserverListenerEntry[] = [];
    for (const entry of this.listeners) {
      if (entry.id !== subscriptionId) {
        remaining.push(entry);
      }
    }
    this.listeners = remaining;
  }

  /**
   * Broadcasts that the given call id was accepted via an external path
   * (e.g. notification answer shortcut in `EntryAbility`).
   *
   * @param callId TDLib call id whose accept has just been dispatched.
   */
  notifyAccepted(callId: number): void {
    if (callId <= 0) {
      return;
    }
    const currentListeners: CallAcceptObserverListenerEntry[] = [...this.listeners];
    hilog.info(DOMAIN, TAG, 'notifyAccepted callId=%{public}d subscribers=%{public}d',
      callId,
      currentListeners.length
    );
    for (const entry of currentListeners) {
      try {
        entry.listener(callId);
      } catch (error) {
        hilog.warn(
          DOMAIN,
          TAG,
          'Accept observer subscriber failed id=%{public}d: %{public}s',
          entry.id,
          buildErrorMessage(error)
        );
      }
    }
  }

  /**
   * Returns the current subscriber count, for tests and diagnostics.
   */
  subscriberCount(): number {
    return this.listeners.length;
  }
}

export const callAcceptObserverHub: CallAcceptObserverHub = new CallAcceptObserverHub();
