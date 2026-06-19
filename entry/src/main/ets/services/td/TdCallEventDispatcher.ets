import { hilog } from '@kit.PerformanceAnalysisKit';
import { buildErrorMessage } from '../../utils/ErrorMessage';
import { tdClient } from './TdClient';
import type { TdCallEvent } from './TdPayloadTypes';

const DOMAIN = 0x2026;
const TAG = 'TdCallEventDispatcher';

export type TdCallEventListener = (event: TdCallEvent) => void;

class TdCallEventListenerEntry {
  readonly id: number;
  readonly listener: TdCallEventListener;

  constructor(id: number, listener: TdCallEventListener) {
    this.id = id;
    this.listener = listener;
  }
}

export class TdCallEventDispatcher {
  private readonly shouldStartSourceOnSubscribe: boolean;
  private started: boolean = false;
  private nextSubscriptionId: number = 1;
  private listeners: TdCallEventListenerEntry[] = [];

  constructor(shouldStartSourceOnSubscribe?: boolean) {
    this.shouldStartSourceOnSubscribe = shouldStartSourceOnSubscribe !== false;
  }

  /**
   * Starts the single TDLib call listener that feeds this dispatcher.
   */
  start(): void {
    if (this.started) {
      return;
    }

    this.started = true;
    if (this.shouldStartSourceOnSubscribe) {
      tdClient.setCallListener((event: TdCallEvent): void => {
        this.dispatch(event);
      });
    }
    hilog.info(DOMAIN, TAG, 'TD call event dispatcher started.');
  }

  /**
   * Stops the TDLib call listener and removes all subscribers.
   */
  stop(): void {
    if (!this.started && this.listeners.length === 0) {
      return;
    }

    this.started = false;
    this.listeners = [];
    if (this.shouldStartSourceOnSubscribe) {
      tdClient.setCallListener(undefined);
    }
    hilog.info(DOMAIN, TAG, 'TD call event dispatcher stopped.');
  }

  /**
   * Registers one call-event subscriber.
   *
   * @param listener Subscriber callback.
   * @returns Subscription id used by `unsubscribe`.
   */
  subscribe(listener: TdCallEventListener): number {
    if (this.shouldStartSourceOnSubscribe) {
      this.start();
    }
    const subscriptionId = this.nextSubscriptionId;
    this.nextSubscriptionId += 1;
    this.listeners.push(new TdCallEventListenerEntry(subscriptionId, listener));
    return subscriptionId;
  }

  /**
   * Removes one call-event subscriber.
   *
   * @param subscriptionId Subscription id returned by `subscribe`.
   */
  unsubscribe(subscriptionId: number): void {
    if (subscriptionId <= 0 || this.listeners.length === 0) {
      return;
    }

    const remainingListeners: TdCallEventListenerEntry[] = [];
    for (const entry of this.listeners) {
      if (entry.id !== subscriptionId) {
        remainingListeners.push(entry);
      }
    }
    this.listeners = remainingListeners;
  }

  /**
   * Broadcasts one parsed TDLib call event to all current subscribers.
   *
   * @param event Parsed call event.
   */
  dispatch(event: TdCallEvent): void {
    const currentListeners: TdCallEventListenerEntry[] = [...this.listeners];
    for (const entry of currentListeners) {
      try {
        entry.listener(event);
      } catch (error) {
        hilog.warn(
          DOMAIN,
          TAG,
          'Call event subscriber failed subscriptionId=%{public}d: %{public}s',
          entry.id,
          buildErrorMessage(error)
        );
      }
    }
  }

  /**
   * Returns current subscriber count for tests and diagnostics.
   *
   * @returns Number of registered subscribers.
   */
  getSubscriberCount(): number {
    return this.listeners.length;
  }

  /**
   * Returns whether the dispatcher source listener is started.
   *
   * @returns `true` when the TDLib source listener is active.
   */
  isStarted(): boolean {
    return this.started;
  }
}

export const tdCallEventDispatcher: TdCallEventDispatcher = new TdCallEventDispatcher();
