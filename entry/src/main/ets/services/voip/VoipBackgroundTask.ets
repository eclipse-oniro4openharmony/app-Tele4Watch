import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { Want, wantAgent } from '@kit.AbilityKit';
import type { WantAgent } from '@ohos.app.ability.wantAgent';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type common from '@ohos.app.ability.common';
import { appAbilityContextStore } from '../../app/AppAbilityContextStore';
import { buildErrorMessage } from '../../utils/ErrorMessage';

const DOMAIN = 0x2026;
const TAG = 'VoipBackgroundTask';
const BUNDLE_NAME = 'com.ostc.tele4watch';
const ENTRY_ABILITY_NAME = 'EntryAbility';

/**
 * Test seam for VoipBackgroundTask. The host owns the OHOS context lookup and
 * the BackgroundTaskManager calls; the task itself only serialises operations
 * and tracks the running flag. Tests provide a fake host that records the
 * start/stop sequence and can introduce delays to exercise the race window.
 *
 * Returns `true` when the system task was actually started/stopped, `false`
 * when the host had to skip the call (e.g. no UIAbility context available).
 * The task uses the result to keep its `running` flag in lockstep with the
 * real kernel-side state — addressing review #issuecomment-2077 non-blocking
 * note: a `running=true` set after a silent no-op start would have misled a
 * later `stop()` into asking the system to stop a task that never existed.
 */
export interface VoipBackgroundHost {
  startBackgroundRunning(): Promise<boolean>;
  stopBackgroundRunning(): Promise<boolean>;
}

class DefaultVoipBackgroundHost implements VoipBackgroundHost {
  async startBackgroundRunning(): Promise<boolean> {
    const context: common.UIAbilityContext | undefined = appAbilityContextStore.peek();
    if (context === undefined) {
      hilog.warn(DOMAIN, TAG, 'start skipped: no UIAbility context available');
      return false;
    }
    const launchWant: Want = {
      'bundleName': BUNDLE_NAME,
      'abilityName': ENTRY_ABILITY_NAME
    };
    const info: wantAgent.WantAgentInfo = {
      'wants': [launchWant],
      'operationType': wantAgent.OperationType.START_ABILITY,
      'requestCode': 0,
      'wantAgentFlags': [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    const agent: WantAgent = await wantAgent.getWantAgent(info);
    await backgroundTaskManager.startBackgroundRunning(
      context,
      backgroundTaskManager.BackgroundMode.VOIP,
      agent
    );
    return true;
  }

  async stopBackgroundRunning(): Promise<boolean> {
    const context: common.UIAbilityContext | undefined = appAbilityContextStore.peek();
    if (context === undefined) {
      hilog.warn(DOMAIN, TAG, 'stop skipped: no UIAbility context available');
      return false;
    }
    await backgroundTaskManager.stopBackgroundRunning(context);
    return true;
  }
}

/**
 * Keeps the app alive while a call is active (M2.4.3).
 *
 * Runs a `voip` continuous task via `backgroundTaskManager` so the native
 * tgcall session, its networking threads and the OHAudio capture/playback
 * survive the watch screen turning off mid-call. Lifetime is bound to the
 * active native call session — started when the call reaches `ready`, stopped
 * on discard/error/reset.
 *
 * `start()` and `stop()` are serialised through a FIFO promise queue so a
 * fast `start() → stop()` race during call negotiation cannot leave a system
 * background task running with no active call. The `running` flag flips
 * after the host's `await` returns successfully, never before it.
 */
export class VoipBackgroundTask {
  private running: boolean = false;
  // FIFO of pending operations. Each new start/stop chains onto this promise
  // so the actions execute strictly in invocation order. Both `.then`
  // handlers (resolve and reject) point to the same continuation so a
  // failure in an earlier step does not poison the chain for later operations.
  private inflight: Promise<void> = Promise.resolve();
  private readonly host: VoipBackgroundHost;

  constructor(host?: VoipBackgroundHost) {
    this.host = host ?? new DefaultVoipBackgroundHost();
  }

  /**
   * Starts the `voip` continuous task for the active call. Idempotent and
   * serialised with `stop()`.
   */
  async start(): Promise<void> {
    const next: Promise<void> = this.inflight.then(
      (): Promise<void> => this.doStart(),
      (): Promise<void> => this.doStart()
    );
    this.inflight = next;
    return next;
  }

  /**
   * Stops the `voip` continuous task. Idempotent and serialised with `start()`.
   */
  async stop(): Promise<void> {
    const next: Promise<void> = this.inflight.then(
      (): Promise<void> => this.doStop(),
      (): Promise<void> => this.doStop()
    );
    this.inflight = next;
    return next;
  }

  /** Whether the system task is believed to be running. Test-friendly probe. */
  isRunning(): boolean {
    return this.running;
  }

  private async doStart(): Promise<void> {
    if (this.running) {
      return;
    }
    try {
      const started: boolean = await this.host.startBackgroundRunning();
      if (!started) {
        // Host silently skipped (e.g. no UIAbility context). Keep
        // running=false so a later stop() does not believe there is a
        // system task to tear down.
        return;
      }
      // running flips AFTER the system acknowledged the start so an
      // interleaved stop() that wins the queue never observes a stale "true"
      // before the kernel-side task actually exists.
      this.running = true;
      hilog.info(DOMAIN, TAG, 'voip continuous task started');
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to start voip continuous task: %{public}s', buildErrorMessage(error));
    }
  }

  private async doStop(): Promise<void> {
    if (!this.running) {
      return;
    }
    try {
      const stopped: boolean = await this.host.stopBackgroundRunning();
      if (!stopped) {
        // Host could not stop the task (e.g. context vanished). Keep
        // running=true so a later stop() will retry — losing the flag now
        // would let an actually-running system task slip out of our reach.
        return;
      }
      this.running = false;
      hilog.info(DOMAIN, TAG, 'voip continuous task stopped');
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to stop voip continuous task: %{public}s', buildErrorMessage(error));
    }
  }
}

export const voipBackgroundTask: VoipBackgroundTask = new VoipBackgroundTask();
