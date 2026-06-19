import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { appAbilityContextStore } from '../../app/AppAbilityContextStore';
import {
  NotificationBootstrapResult,
  NotificationBootstrapStatus,
  notificationBootstrapService
} from './NotificationBootstrapService';
import { tdNotificationsService } from './TdNotificationsService';
import { callRuntimeService } from '../voip/CallRuntimeService';
import { tdCallEventDispatcher } from '../td/TdCallEventDispatcher';
import {
  MicrophonePermissionResult,
  MicrophonePermissionResultStatus,
  MicrophonePermissionService
} from '../permissions/MicrophonePermissionService';

const DOMAIN = 0x2026;
const TAG = 'NotificationRuntimeService';

/**
 * Starts T4W notification runtime once the TDLib session is authorized.
 */
class NotificationRuntimeService {
  private bootstrapStarted: boolean = false;
  private notificationServiceStarted: boolean = false;
  private bootstrapGeneration: number = 0;
  private microphoneBootstrapAttempted: boolean = false;
  private readonly microphonePermissionService: MicrophonePermissionService = new MicrophonePermissionService();

  /**
   * Ensures notification permission, slots and TD notification listener are ready.
   *
   * @param source Screen or flow that observed `authorizationStateReady`.
   */
  ensureStarted(source: string): void {
    if (this.bootstrapStarted) {
      return;
    }

    callRuntimeService.ensureStarted(source);
    const abilityContext = appAbilityContextStore.peek();
    if (!abilityContext) {
      hilog.error(DOMAIN, TAG, 'Notification bootstrap skipped: ability context unavailable (source=%{public}s).',
        source);
      return;
    }

    this.bootstrapStarted = true;
    const currentGeneration = this.bootstrapGeneration;
    hilog.info(DOMAIN, TAG, 'Starting notification bootstrap (source=%{public}s).', source);
    void notificationBootstrapService.ensureReady(abilityContext).then((result: NotificationBootstrapResult): void => {
      // Microphone permission rides the startup bootstrap ON PURPOSE — sequenced
      // after the notification dialog settles, never inside the call flow. #65 E4
      // lesson: the in-accept permission dialog added ~9 s before `acceptCall`,
      // the TDLib connection flapped inside that window (watch Wi-Fi power save)
      // and the accept never reached Telegram — the call died as Missed. Accept
      // must dispatch instantly, so the grant has to be settled ahead of time.
      this.ensureMicrophonePermissionOnce(abilityContext);
      if (currentGeneration !== this.bootstrapGeneration) {
        hilog.info(DOMAIN, TAG, 'Notification bootstrap ignored after runtime reset (source=%{public}s).', source);
        return;
      }
      if (result.status === NotificationBootstrapStatus.Ready) {
        hilog.info(DOMAIN, TAG, 'Notification bootstrap ready (source=%{public}s).', source);
        this.startNotificationsServiceOnce();
        return;
      }
      if (result.status === NotificationBootstrapStatus.PermissionDenied) {
        this.bootstrapStarted = false;
        hilog.warn(DOMAIN, TAG, 'Notification permission is not enabled for T4W (source=%{public}s).', source);
        return;
      }
      this.bootstrapStarted = false;
      hilog.error(DOMAIN, TAG, 'Notification bootstrap failed (source=%{public}s): %{public}s',
        source, result.errorMessage);
    });
  }

  /**
   * Releases TD notification listeners and allows a later authorized session to re-bootstrap them.
   */
  releaseForLogout(): void {
    this.bootstrapGeneration++;
    this.bootstrapStarted = false;
    this.notificationServiceStarted = false;
    callRuntimeService.release();
    tdNotificationsService.release();
    tdCallEventDispatcher.stop();
    hilog.info(DOMAIN, TAG, 'Notification runtime released for logout.');
  }

  private startNotificationsServiceOnce(): void {
    if (this.notificationServiceStarted) {
      return;
    }

    this.notificationServiceStarted = true;
    tdNotificationsService.init();
  }

  /**
   * Requests the runtime microphone grant once per process. The service
   * short-circuits without a dialog when the grant already exists, and the
   * call proceeds receive-only when the user denies — the denial is only
   * logged here, the VoIP path itself never blocks on permissions.
   */
  private ensureMicrophonePermissionOnce(context: common.UIAbilityContext): void {
    if (this.microphoneBootstrapAttempted) {
      return;
    }
    this.microphoneBootstrapAttempted = true;
    void this.microphonePermissionService.requestPermission(context)
      .then((result: MicrophonePermissionResult): void => {
        if (result.status === MicrophonePermissionResultStatus.Granted) {
          hilog.info(DOMAIN, TAG, 'Microphone permission ready at bootstrap.');
          return;
        }
        hilog.warn(DOMAIN, TAG,
          'Microphone permission not granted at bootstrap (%{public}s) — calls stay receive-only until granted.',
          result.status);
      });
  }
}

export const notificationRuntimeService: NotificationRuntimeService = new NotificationRuntimeService();
