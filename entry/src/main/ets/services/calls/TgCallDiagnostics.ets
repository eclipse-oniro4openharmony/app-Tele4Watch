import { tgCallNativeBridge, tgCallSessionClient } from 'tgcall';
import type { TgCallDiagnosticBridge, TgCallStartRequest } from 'tgcall';
import { buildErrorMessage } from '../../utils/ErrorMessage';
import type { TgCallSessionBridge } from '../voip/TgCallSessionBridge';

const RAW_SIGNALING_SUCCESS_MESSAGE: string = 'Raw signaling crypto probe passed.';
const RAW_SIGNALING_FAILURE_MESSAGE: string = 'Raw signaling crypto probe failed.';
const FACTORY_REGISTRY_SUCCESS_MESSAGE: string = 'Real factory registry probe passed.';
const FACTORY_REGISTRY_FAILURE_MESSAGE: string = 'Real factory registry probe found no registered versions.';
const WEBK_SIGNALING_SUCCESS_MESSAGE: string = 'Web-K signaling 4.0.0 probe passed.';
const WEBK_SIGNALING_FAILURE_MESSAGE: string = 'Web-K signaling 4.0.0 probe failed.';
const WEBK_MEDIA_PATH_SUCCESS_MESSAGE: string = 'Web-K media path 4.0.0 probe passed.';
const WEBK_MEDIA_PATH_SIGNALING_FAILURE_MESSAGE: string = 'Web-K media path 4.0.0 probe failed: signaling unavailable.';
const WEBK_MEDIA_PATH_FACTORY_FAILURE_PREFIX: string =
  'Web-K media path 4.0.0 probe failed: media factory does not advertise 4.0.0. supported=';
const WEBK_MEDIA_PATH_EMPTY_VERSIONS_MESSAGE: string = '<empty>';
const WEBK_MEDIA_PATH_PROTOCOL_VERSION: string = '4.0.0';
const SESSION_LIFECYCLE_SUCCESS_MESSAGE: string = 'Session lifecycle probe passed.';
const SESSION_LIFECYCLE_INVALID_INSTANCE_MESSAGE: string = 'Session lifecycle probe returned invalid instance id.';
const SESSION_LIFECYCLE_PROTOCOL_VERSION: string = '8.0.0';
const SESSION_LIFECYCLE_SERVERS_JSON: string = '[]';
const SESSION_LIFECYCLE_ENCRYPTION_KEY_BASE64: string =
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    + 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    + 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==';
const SESSION_LIFECYCLE_CUSTOM_PARAMETERS: string = '{"probe":"s2"}';
const SESSION_LIFECYCLE_SIGNALING_DATA_BASE64: string = 'AQID';

export type TgCallDiagnosticStatus = 'passed' | 'failed';

export interface TgCallDiagnosticResult {
  'status': TgCallDiagnosticStatus;
  'message': string;
}

export interface TgCallNativeBridge extends TgCallDiagnosticBridge {}

function containsVersion(versions: string[], expectedVersion: string): boolean {
  for (const version of versions) {
    if (version === expectedVersion) {
      return true;
    }
  }
  return false;
}

function buildSupportedVersionsText(versions: string[]): string {
  if (versions.length === 0) {
    return WEBK_MEDIA_PATH_EMPTY_VERSIONS_MESSAGE;
  }
  return versions.join(',');
}

export class TgCallDiagnostics {
  private readonly bridge: TgCallNativeBridge;
  private readonly sessionBridge: TgCallSessionBridge;

  constructor(bridge?: TgCallNativeBridge, sessionBridge?: TgCallSessionBridge) {
    this.bridge = bridge ? bridge : tgCallNativeBridge;
    this.sessionBridge = sessionBridge ? sessionBridge : tgCallSessionClient;
  }

  /**
   * Runs the minimal native tgcalls signaling crypto probe.
   *
   * @returns Diagnostic result with a stable pass/fail status.
   */
  runRawSignalingCryptoProbe(): TgCallDiagnosticResult {
    try {
      const probePassed = this.bridge.runRawSignalingCryptoProbe();
      if (probePassed) {
        return {
          'status': 'passed',
          'message': RAW_SIGNALING_SUCCESS_MESSAGE
        };
      }

      return {
        'status': 'failed',
        'message': RAW_SIGNALING_FAILURE_MESSAGE
      };
    } catch (error) {
      const errorMessage = buildErrorMessage(error);
      return {
        'status': 'failed',
        'message': errorMessage
      };
    }
  }

  /**
   * Checks whether the native tgcalls Meta factory has registered real implementations.
   *
   * @returns Diagnostic result with a stable pass/fail status.
   */
  runFactoryRegistryProbe(): TgCallDiagnosticResult {
    try {
      const probePassed = this.bridge.runFactoryRegistryProbe();
      if (probePassed) {
        return {
          'status': 'passed',
          'message': FACTORY_REGISTRY_SUCCESS_MESSAGE
        };
      }

      return {
        'status': 'failed',
        'message': FACTORY_REGISTRY_FAILURE_MESSAGE
      };
    } catch (error) {
      const errorMessage = buildErrorMessage(error);
      return {
        'status': 'failed',
        'message': errorMessage
      };
    }
  }

  /**
   * Checks whether the Web-K negotiated 4.0.0 signaling payload shape is available natively.
   *
   * @returns Diagnostic result with a stable pass/fail status.
   */
  runWebKSignalingProbe(): TgCallDiagnosticResult {
    try {
      const probePassed = this.bridge.runWebKSignalingProbe();
      if (probePassed) {
        return {
          'status': 'passed',
          'message': WEBK_SIGNALING_SUCCESS_MESSAGE
        };
      }

      return {
        'status': 'failed',
        'message': WEBK_SIGNALING_FAILURE_MESSAGE
      };
    } catch (error) {
      const errorMessage = buildErrorMessage(error);
      return {
        'status': 'failed',
        'message': errorMessage
      };
    }
  }

  /**
   * Checks whether Web-K 4.0.0 can progress past signaling into a registered media factory.
   *
   * @returns Diagnostic result with a stable pass/fail status.
   */
  runWebKMediaPathProbe(): TgCallDiagnosticResult {
    try {
      const signalingProbePassed = this.bridge.runWebKSignalingProbe();
      if (!signalingProbePassed) {
        return {
          'status': 'failed',
          'message': WEBK_MEDIA_PATH_SIGNALING_FAILURE_MESSAGE
        };
      }

      const supportedVersions = this.bridge.getSupportedVersions();
      if (containsVersion(supportedVersions, WEBK_MEDIA_PATH_PROTOCOL_VERSION)) {
        return {
          'status': 'passed',
          'message': WEBK_MEDIA_PATH_SUCCESS_MESSAGE
        };
      }

      return {
        'status': 'failed',
        'message': WEBK_MEDIA_PATH_FACTORY_FAILURE_PREFIX + buildSupportedVersionsText(supportedVersions)
      };
    } catch (error) {
      const errorMessage = buildErrorMessage(error);
      return {
        'status': 'failed',
        'message': errorMessage
      };
    }
  }

  /**
   * Runs a minimal native session lifecycle probe.
   *
   * @returns Diagnostic result with a stable pass/fail status.
   */
  runSessionLifecycleProbe(): TgCallDiagnosticResult {
    let instanceId = 0;
    try {
      const request: TgCallStartRequest = {
        'protocolVersion': SESSION_LIFECYCLE_PROTOCOL_VERSION,
        'serversJson': SESSION_LIFECYCLE_SERVERS_JSON,
        'encryptionKeyBase64': SESSION_LIFECYCLE_ENCRYPTION_KEY_BASE64,
        'isOutgoing': false,
        'allowP2p': false,
        'customParameters': SESSION_LIFECYCLE_CUSTOM_PARAMETERS
      };
      instanceId = this.sessionBridge.startDiagnosticCall(request);
      if (instanceId <= 0) {
        return {
          'status': 'failed',
          'message': SESSION_LIFECYCLE_INVALID_INSTANCE_MESSAGE
        };
      }

      this.sessionBridge.feedSignalingData(instanceId, SESSION_LIFECYCLE_SIGNALING_DATA_BASE64);
      this.sessionBridge.stopCall(instanceId);
      instanceId = 0;
      return {
        'status': 'passed',
        'message': SESSION_LIFECYCLE_SUCCESS_MESSAGE
      };
    } catch (error) {
      const errorMessage = buildErrorMessage(error);
      return {
        'status': 'failed',
        'message': errorMessage
      };
    } finally {
      if (instanceId > 0) {
        try {
          this.sessionBridge.stopCall(instanceId);
        } catch (error) {
          // Best-effort cleanup only; the primary probe result is reported above.
        }
      }
    }
  }
}

export const tgCallDiagnostics: TgCallDiagnostics = new TgCallDiagnostics();
