import { describe, expect, it } from '@ohos/hypium';
import { VoipBackgroundTask } from '../main/ets/services/voip/VoipBackgroundTask';
import type { VoipBackgroundHost } from '../main/ets/services/voip/VoipBackgroundTask';

/**
 * Fake host that records the systemic start/stop sequence and lets the test
 * control how long each await takes. The kernel-side ordering is exposed via
 * the `log` array so the test can assert that `start()`/`stop()` calls were
 * serialised correctly even when invoked concurrently.
 */
class FakeVoipBackgroundHost implements VoipBackgroundHost {
  startBackgroundRunningCalls: number = 0;
  stopBackgroundRunningCalls: number = 0;
  log: string[] = [];

  startDelayMs: number = 0;
  stopDelayMs: number = 0;

  // Simulate "no UIAbility context" — host warns + returns false instead of
  // actually starting/stopping the system task.
  startReturnsFalse: boolean = false;
  stopReturnsFalse: boolean = false;

  async startBackgroundRunning(): Promise<boolean> {
    this.log.push('start:begin');
    if (this.startDelayMs > 0) {
      await delayMs(this.startDelayMs);
    }
    if (this.startReturnsFalse) {
      this.log.push('start:skipped');
      return false;
    }
    this.startBackgroundRunningCalls += 1;
    this.log.push('start:end');
    return true;
  }

  async stopBackgroundRunning(): Promise<boolean> {
    this.log.push('stop:begin');
    if (this.stopDelayMs > 0) {
      await delayMs(this.stopDelayMs);
    }
    if (this.stopReturnsFalse) {
      this.log.push('stop:skipped');
      return false;
    }
    this.stopBackgroundRunningCalls += 1;
    this.log.push('stop:end');
    return true;
  }
}

function delayMs(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}

export default function voipBackgroundTaskTest() {
  describe('VoipBackgroundTask', () => {
    it('start_thenStop_serialisesAndLeavesSystemStopped', 0, async () => {
      const host = new FakeVoipBackgroundHost();
      host.startDelayMs = 30;
      const task = new VoipBackgroundTask(host);

      // Race scenario from review #2071: start() in-flight, fast stop() before
      // start completes. With the FIFO queue the stop must wait for the start
      // and then actually stop the system task.
      await Promise.all([task.start(), task.stop()]);

      expect(host.startBackgroundRunningCalls).assertEqual(1);
      expect(host.stopBackgroundRunningCalls).assertEqual(1);
      // Sequence guard: stop never overlaps with start.
      expect(host.log[0]).assertEqual('start:begin');
      expect(host.log[1]).assertEqual('start:end');
      expect(host.log[2]).assertEqual('stop:begin');
      expect(host.log[3]).assertEqual('stop:end');
      expect(task.isRunning()).assertEqual(false);
    });

    it('stop_thenStart_skipsStopAndStartsSystem', 0, async () => {
      const host = new FakeVoipBackgroundHost();
      const task = new VoipBackgroundTask(host);

      // stop() before any start is a no-op (running is false);
      // start() then runs normally.
      await Promise.all([task.stop(), task.start()]);

      expect(host.startBackgroundRunningCalls).assertEqual(1);
      expect(host.stopBackgroundRunningCalls).assertEqual(0);
      expect(task.isRunning()).assertEqual(true);
    });

    it('start_then_stop_sequentially_flipsRunningFlag', 0, async () => {
      const host = new FakeVoipBackgroundHost();
      const task = new VoipBackgroundTask(host);

      await task.start();
      expect(task.isRunning()).assertEqual(true);
      expect(host.startBackgroundRunningCalls).assertEqual(1);

      await task.stop();
      expect(task.isRunning()).assertEqual(false);
      expect(host.stopBackgroundRunningCalls).assertEqual(1);
    });

    it('repeated_start_is_idempotent_whileRunning', 0, async () => {
      const host = new FakeVoipBackgroundHost();
      const task = new VoipBackgroundTask(host);

      await task.start();
      await task.start();
      await task.start();

      expect(host.startBackgroundRunningCalls).assertEqual(1);
      expect(task.isRunning()).assertEqual(true);
    });

    it('repeated_stop_is_idempotent_whileStopped', 0, async () => {
      const host = new FakeVoipBackgroundHost();
      const task = new VoipBackgroundTask(host);

      await task.stop();
      await task.stop();

      expect(host.stopBackgroundRunningCalls).assertEqual(0);
      expect(task.isRunning()).assertEqual(false);
    });

    it('start_withSilentHostNoop_keepsRunningFalse', 0, async () => {
      // Review #issuecomment-2077 non-blocking note: if the host can't actually
      // start (no UIAbility context), the task must NOT claim running=true,
      // otherwise a later stop() asks the system to tear down a task that
      // never existed.
      const host = new FakeVoipBackgroundHost();
      host.startReturnsFalse = true;
      const task = new VoipBackgroundTask(host);

      await task.start();

      expect(host.startBackgroundRunningCalls).assertEqual(0);
      expect(task.isRunning()).assertEqual(false);
    });

    it('stop_withSilentHostNoop_keepsRunningTrueForRetry', 0, async () => {
      // Symmetric: if start succeeded but stop's host call could not run
      // (e.g. context vanished), keep running=true so the next stop() can
      // actually tear the system task down. Forgetting the flag here would
      // strand a running task.
      const host = new FakeVoipBackgroundHost();
      const task = new VoipBackgroundTask(host);

      await task.start();
      expect(task.isRunning()).assertEqual(true);

      host.stopReturnsFalse = true;
      await task.stop();
      expect(task.isRunning()).assertEqual(true);
      expect(host.stopBackgroundRunningCalls).assertEqual(0);

      // Context comes back, retry succeeds.
      host.stopReturnsFalse = false;
      await task.stop();
      expect(task.isRunning()).assertEqual(false);
      expect(host.stopBackgroundRunningCalls).assertEqual(1);
    });

    it('interleaved_start_stop_cycles_preserveOrdering', 0, async () => {
      const host = new FakeVoipBackgroundHost();
      host.startDelayMs = 3;
      host.stopDelayMs = 3;
      const task = new VoipBackgroundTask(host);

      // start, stop, start, stop, start — 3 starts + 2 stops, no interleaving,
      // ending in running=true (last op was start).
      await Promise.all([
        task.start(),
        task.stop(),
        task.start(),
        task.stop(),
        task.start()
      ]);

      expect(host.startBackgroundRunningCalls).assertEqual(3);
      expect(host.stopBackgroundRunningCalls).assertEqual(2);
      expect(task.isRunning()).assertEqual(true);
      // No two operations overlap in the systemic log.
      for (let i = 0; i < host.log.length; i += 2) {
        const beginTag = host.log[i];
        const endTag = host.log[i + 1];
        const op = beginTag.split(':')[0];
        expect(endTag).assertEqual(op + ':end');
      }
    });
  });
}
