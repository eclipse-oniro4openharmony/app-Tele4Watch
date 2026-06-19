import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x2026;
const TAG = 'SubscriptionHub';

/**
 * Fan-out subscription registry with stable per-subscriber tokens.
 *
 * Provides the `Map<number, Listener>` + `nextId` + `subscribe/unsubscribe/clear` + isolated
 * `forEach` fan-out pattern used by every TdClient subscription stream. Kept dependency-free
 * (no TdClient imports) so callers freely pick their own listener signature.
 *
 * Token convention: first issued token is `1`; callers use `0` as the "not subscribed" sentinel.
 * `unsubscribe(0)` is a no-op, so views can safely call it from `aboutToDisappear` without
 * tracking whether `subscribe` actually ran.
 *
 * @param Listener The callable shape of one subscriber. The hub does not invoke it directly —
 * `forEach` hands one listener at a time to the caller-supplied invoker, leaving payload shape
 * to the caller.
 */
export class SubscriptionHub<Listener> {
  private readonly subscribers: Map<number, Listener> = new Map<number, Listener>();
  private nextToken: number = 1;
  private readonly name: string;

  /**
   * @param name Short identifier used in subscriber-threw warn logs (e.g. `'chatMessages'`).
   */
  constructor(name: string) {
    this.name = name;
  }

  /**
   * Registers a listener and returns its token.
   *
   * @param listener Subscriber callback.
   * @returns Token to pass to `unsubscribe` later. Always `>= 1`.
   */
  subscribe(listener: Listener): number {
    const token = this.nextToken;
    this.nextToken = token + 1;
    this.subscribers.set(token, listener);
    return token;
  }

  /**
   * Removes a previously-registered listener. Idempotent on unknown tokens AND on the `0`
   * sentinel.
   *
   * @param token Token returned by `subscribe`, or `0`.
   */
  unsubscribe(token: number): void {
    if (token <= 0) {
      return;
    }
    this.subscribers.delete(token);
  }

  /**
   * Invokes the caller-supplied invoker once per subscriber. A throwing subscriber is logged and
   * skipped so it cannot block the rest of the fan-out.
   *
   * @param invoker Caller-supplied function that knows how to apply its payload to one listener.
   */
  forEach(invoker: (listener: Listener) => void): void {
    if (this.subscribers.size === 0) {
      return;
    }
    for (const listener of this.subscribers.values()) {
      try {
        invoker(listener);
      } catch (error) {
        hilog.error(DOMAIN, TAG, '%{public}s subscriber threw: %{public}s', this.name, String(error));
      }
    }
  }

  /**
   * Drops all subscribers. Intended for sign-out / re-init.
   */
  clear(): void {
    this.subscribers.clear();
  }

  /**
   * Number of currently-registered subscribers. Useful for short-circuiting expensive payload
   * construction when no one is listening.
   */
  isEmpty(): boolean {
    return this.subscribers.size === 0;
  }
}
