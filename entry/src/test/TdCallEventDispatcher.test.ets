import { describe, expect, it } from '@ohos/hypium';
import { TdCallEventDispatcher } from '../main/ets/services/td/TdCallEventDispatcher';
import type { TdCallEvent } from '../main/ets/services/td/TdPayloadTypes';

class CountingCallEventListener {
  calls: number = 0;
  shouldThrow: boolean = false;

  handle(event: TdCallEvent): void {
    if (event.kind === 'call') {
      this.calls += 1;
    }
    if (this.shouldThrow) {
      throw new Error('listener failed');
    }
  }
}

class ReentrantCallEventListener {
  calls: number = 0;
  private readonly dispatcher: TdCallEventDispatcher;
  private subscriptionId: number = 0;

  constructor(dispatcher: TdCallEventDispatcher) {
    this.dispatcher = dispatcher;
  }

  setSubscriptionId(subscriptionId: number): void {
    this.subscriptionId = subscriptionId;
  }

  handle(event: TdCallEvent): void {
    if (event.kind === 'call') {
      this.calls += 1;
    }
    if (this.subscriptionId > 0) {
      this.dispatcher.unsubscribe(this.subscriptionId);
    }
  }
}

function buildSignalingEvent(): TdCallEvent {
  return {
    'kind': 'signalingData',
    'callId': 43,
    'data': 'AQID'
  };
}

function buildCallEvent(): TdCallEvent {
  return {
    'kind': 'call'
  };
}

export default function tdCallEventDispatcherTest() {
  describe('TdCallEventDispatcherTest', () => {
    it('shouldBroadcastCallEventsToAllSubscribers', 0, () => {
      const dispatcher = new TdCallEventDispatcher(false);
      const first = new CountingCallEventListener();
      const second = new CountingCallEventListener();

      dispatcher.subscribe((event: TdCallEvent): void => {
        first.handle(event);
      });
      dispatcher.subscribe((event: TdCallEvent): void => {
        second.handle(event);
      });
      dispatcher.dispatch(buildCallEvent());

      expect(first.calls).assertEqual(1);
      expect(second.calls).assertEqual(1);
      expect(dispatcher.getSubscriberCount()).assertEqual(2);
    });

    it('shouldUnsubscribeOneSubscriber', 0, () => {
      const dispatcher = new TdCallEventDispatcher(false);
      const first = new CountingCallEventListener();
      const second = new CountingCallEventListener();

      const firstSubscriptionId = dispatcher.subscribe((event: TdCallEvent): void => {
        first.handle(event);
      });
      dispatcher.subscribe((event: TdCallEvent): void => {
        second.handle(event);
      });
      dispatcher.unsubscribe(firstSubscriptionId);
      dispatcher.dispatch(buildCallEvent());

      expect(first.calls).assertEqual(0);
      expect(second.calls).assertEqual(1);
      expect(dispatcher.getSubscriberCount()).assertEqual(1);
    });

    it('shouldContinueDispatchWhenSubscriberThrows', 0, () => {
      const dispatcher = new TdCallEventDispatcher(false);
      const first = new CountingCallEventListener();
      first.shouldThrow = true;
      const second = new CountingCallEventListener();

      dispatcher.subscribe((event: TdCallEvent): void => {
        first.handle(event);
      });
      dispatcher.subscribe((event: TdCallEvent): void => {
        second.handle(event);
      });
      dispatcher.dispatch(buildCallEvent());

      expect(first.calls).assertEqual(1);
      expect(second.calls).assertEqual(1);
      expect(dispatcher.getSubscriberCount()).assertEqual(2);
    });

    it('shouldIgnoreUnknownUnsubscribeIds', 0, () => {
      const dispatcher = new TdCallEventDispatcher(false);

      dispatcher.unsubscribe(777);
      dispatcher.dispatch(buildSignalingEvent());

      expect(dispatcher.getSubscriberCount()).assertEqual(0);
    });

    it('shouldReturnMonotonicSubscriptionIds', 0, () => {
      const dispatcher = new TdCallEventDispatcher(false);

      const firstSubscriptionId = dispatcher.subscribe((event: TdCallEvent): void => {
        if (event.kind === 'call') {
          return;
        }
      });
      const secondSubscriptionId = dispatcher.subscribe((event: TdCallEvent): void => {
        if (event.kind === 'call') {
          return;
        }
      });

      expect(firstSubscriptionId).assertEqual(1);
      expect(secondSubscriptionId).assertEqual(2);
    });

    it('shouldStopAndClearSubscribers', 0, () => {
      const dispatcher = new TdCallEventDispatcher(false);
      const listener = new CountingCallEventListener();

      dispatcher.start();
      dispatcher.subscribe((event: TdCallEvent): void => {
        listener.handle(event);
      });
      dispatcher.stop();
      dispatcher.dispatch(buildCallEvent());

      expect(dispatcher.isStarted()).assertFalse();
      expect(dispatcher.getSubscriberCount()).assertEqual(0);
      expect(listener.calls).assertEqual(0);
    });

    it('shouldUseDispatchSnapshotWhenSubscriberUnsubscribesDuringDispatch', 0, () => {
      const dispatcher = new TdCallEventDispatcher(false);
      const stableListener = new CountingCallEventListener();
      const reentrantListener = new ReentrantCallEventListener(dispatcher);

      const firstSubscriptionId = dispatcher.subscribe((event: TdCallEvent): void => {
        reentrantListener.handle(event);
      });
      reentrantListener.setSubscriptionId(firstSubscriptionId);
      dispatcher.subscribe((event: TdCallEvent): void => {
        stableListener.handle(event);
      });

      dispatcher.dispatch(buildCallEvent());
      dispatcher.dispatch(buildCallEvent());

      expect(reentrantListener.calls).assertEqual(1);
      expect(stableListener.calls).assertEqual(2);
      expect(dispatcher.getSubscriberCount()).assertEqual(1);
    });
  });
}
