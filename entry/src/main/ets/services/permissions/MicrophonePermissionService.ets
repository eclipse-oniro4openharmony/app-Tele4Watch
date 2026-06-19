import abilityAccessCtrl, { Context, Permissions } from '@ohos.abilityAccessCtrl';
import { hilog } from '@kit.PerformanceAnalysisKit';

export enum MicrophonePermissionResultStatus {
  Granted = 'granted',
  Denied = 'denied',
  Error = 'error'
}

export interface MicrophonePermissionResult {
  status: MicrophonePermissionResultStatus;
  errorMessage: string;
}

const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
const DOMAIN = 0x2026;
const TAG = 'MicrophonePermissionService';

/**
 * Encapsulates runtime microphone permission checks and requests.
 */
export class MicrophonePermissionService {
  private readonly atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();

  /**
   * Returns whether the current application already has microphone access.
   *
   * @param context Stage-model context bound to the current page.
   * @returns `true` when microphone permission is already granted.
   */
  hasPermission(context: Context): boolean {
    try {
      const grantStatus = this.atManager.checkAccessTokenSync(
        context.applicationInfo.accessTokenId,
        MICROPHONE_PERMISSION
      );
      return grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to check microphone permission: %{public}s', String(error));
      return false;
    }
  }

  /**
   * Requests microphone permission using the standard runtime dialog.
   *
   * @param context Stage-model context bound to the current page.
   * @returns Permission request outcome.
   */
  async requestPermission(context: Context): Promise<MicrophonePermissionResult> {
    if (this.hasPermission(context)) {
      return this.createGrantedResult();
    }

    try {
      const requestResult = await this.atManager.requestPermissionsFromUser(context, [MICROPHONE_PERMISSION]);
      return this.mapGrantStatuses(requestResult.authResults);
    } catch (error) {
      return this.createErrorResult(String(error));
    }
  }

  /**
   * Requests microphone permission from the system settings dialog shown after denial.
   *
   * @param context Stage-model context bound to the current page.
   * @returns Permission request outcome.
   */
  async requestPermissionOnSetting(context: Context): Promise<MicrophonePermissionResult> {
    if (this.hasPermission(context)) {
      return this.createGrantedResult();
    }

    try {
      const grantStatuses = await this.atManager.requestPermissionOnSetting(context, [MICROPHONE_PERMISSION]);
      return this.mapGrantStatuses(grantStatuses);
    } catch (error) {
      return this.createErrorResult(String(error));
    }
  }

  private mapGrantStatuses(grantStatuses: Array<number>): MicrophonePermissionResult {
    for (let index = 0; index < grantStatuses.length; index += 1) {
      if (grantStatuses[index] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return {
          status: MicrophonePermissionResultStatus.Denied,
          errorMessage: ''
        };
      }
    }
    return this.createGrantedResult();
  }

  private createGrantedResult(): MicrophonePermissionResult {
    return {
      status: MicrophonePermissionResultStatus.Granted,
      errorMessage: ''
    };
  }

  private createErrorResult(errorMessage: string): MicrophonePermissionResult {
    return {
      status: MicrophonePermissionResultStatus.Error,
      errorMessage: errorMessage
    };
  }
}
