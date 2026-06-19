import { common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x2026;
const TAG = 'NotificationBootstrapService';

export enum NotificationBootstrapStatus {
  Ready = 'ready',
  PermissionDenied = 'permissionDenied',
  Error = 'error'
}

export interface NotificationBootstrapResult {
  status: NotificationBootstrapStatus;
  errorMessage: string;
}

/**
 * Prepares system notification permission and channel slots for T4W notifications.
 */
class NotificationBootstrapService {
  private slotsConfigured: boolean = false;
  private enableRequestAttempted: boolean = false;

  /**
   * Ensures notification slots exist and asks the user to enable notifications when needed.
   *
   * @param context Current UIAbility context used by the system notification dialog.
   * @returns Bootstrap result suitable for logging or settings UI.
   */
  async ensureReady(context: common.UIAbilityContext): Promise<NotificationBootstrapResult> {
    const slotResult = await this.ensureSlots();
    if (slotResult.status !== NotificationBootstrapStatus.Ready) {
      return slotResult;
    }

    return this.ensureEnabled(context);
  }

  private async ensureSlots(): Promise<NotificationBootstrapResult> {
    if (this.slotsConfigured) {
      return this.createReadyResult();
    }

    try {
      await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION);
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
      this.slotsConfigured = true;
      hilog.info(DOMAIN, TAG, 'Notification slots configured.');
      return this.createReadyResult();
    } catch (error) {
      const errorMessage = String(error);
      hilog.error(DOMAIN, TAG, 'Failed to configure notification slots: %{public}s', errorMessage);
      return {
        status: NotificationBootstrapStatus.Error,
        errorMessage: errorMessage
      };
    }
  }

  private async ensureEnabled(context: common.UIAbilityContext): Promise<NotificationBootstrapResult> {
    let isEnabled = false;
    try {
      isEnabled = await notificationManager.isNotificationEnabled();
    } catch (error) {
      const errorMessage = String(error);
      hilog.error(DOMAIN, TAG, 'Failed to check notification permission: %{public}s', errorMessage);
      return {
        status: NotificationBootstrapStatus.Error,
        errorMessage: errorMessage
      };
    }

    if (isEnabled) {
      return this.createReadyResult();
    }
    if (this.enableRequestAttempted) {
      hilog.warn(DOMAIN, TAG, 'Notification permission remains disabled after request.');
      return {
        status: NotificationBootstrapStatus.PermissionDenied,
        errorMessage: ''
      };
    }

    this.enableRequestAttempted = true;
    try {
      await notificationManager.requestEnableNotification(context);
      const granted = await notificationManager.isNotificationEnabled();
      if (granted) {
        hilog.info(DOMAIN, TAG, 'Notification permission granted.');
        return this.createReadyResult();
      }

      hilog.warn(DOMAIN, TAG, 'Notification permission denied by user.');
      return {
        status: NotificationBootstrapStatus.PermissionDenied,
        errorMessage: ''
      };
    } catch (error) {
      const errorMessage = String(error);
      hilog.warn(DOMAIN, TAG, 'Notification permission request failed or was denied: %{public}s', errorMessage);
      return {
        status: NotificationBootstrapStatus.PermissionDenied,
        errorMessage: errorMessage
      };
    }
  }

  private createReadyResult(): NotificationBootstrapResult {
    return {
      status: NotificationBootstrapStatus.Ready,
      errorMessage: ''
    };
  }
}

export const notificationBootstrapService: NotificationBootstrapService = new NotificationBootstrapService();
