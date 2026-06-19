import { describe, it, expect } from '@ohos/hypium';
import { CallAcceptObserverHub } from '../main/ets/services/voip/CallAcceptObserverHub';

export default function callAcceptObserverHubTest() {
  describe('CallAcceptObserverHubTest', () => {
    it('shouldDeliverNotificationToSubscribers', 0, () => {
      const hub = new CallAcceptObserverHub();
      const received: number[] = [];
      hub.subscribe((callId: number): void => {
        received.push(callId);
      });

      hub.notifyAccepted(42);

      expect(received.length).assertEqual(1);
      expect(received[0]).assertEqual(42);
    });

    it('shouldFanOutToMultipleSubscribers', 0, () => {
      const hub = new CallAcceptObserverHub();
      let firstSeen = 0;
      let secondSeen = 0;
      hub.subscribe((callId: number): void => {
        firstSeen = callId;
      });
      hub.subscribe((callId: number): void => {
        secondSeen = callId;
      });

      hub.notifyAccepted(7);

      expect(firstSeen).assertEqual(7);
      expect(secondSeen).assertEqual(7);
      expect(hub.subscriberCount()).assertEqual(2);
    });

    it('shouldDropUnsubscribedListeners', 0, () => {
      const hub = new CallAcceptObserverHub();
      let received = 0;
      const subscriptionId = hub.subscribe((callId: number): void => {
        received = callId;
      });

      hub.unsubscribe(subscriptionId);
      hub.notifyAccepted(99);

      expect(received).assertEqual(0);
      expect(hub.subscriberCount()).assertEqual(0);
    });

    it('shouldIgnoreInvalidCallIds', 0, () => {
      const hub = new CallAcceptObserverHub();
      let invocations = 0;
      hub.subscribe((): void => {
        invocations += 1;
      });

      hub.notifyAccepted(0);
      hub.notifyAccepted(-1);

      expect(invocations).assertEqual(0);
    });

    it('shouldContinueDispatchWhenOneListenerThrows', 0, () => {
      const hub = new CallAcceptObserverHub();
      let secondReceived = 0;
      hub.subscribe((): void => {
        throw new Error('boom');
      });
      hub.subscribe((callId: number): void => {
        secondReceived = callId;
      });

      hub.notifyAccepted(11);

      expect(secondReceived).assertEqual(11);
    });

    it('shouldNoOpOnInvalidSubscriptionId', 0, () => {
      const hub = new CallAcceptObserverHub();
      hub.unsubscribe(0);
      hub.unsubscribe(-5);
      hub.unsubscribe(999);
      // No assertion — the test passes if the calls don't throw.
    });
  });
}
