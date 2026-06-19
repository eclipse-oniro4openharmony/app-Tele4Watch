import { UiTextValue } from '../ui/UiTextValue';

/**
 * Enumerates routed message-recorder phases rendered by the template shell.
 */
export enum MessageRecorderPhase {
  Idle = 'idle',
  RequestingPermission = 'requesting-permission',
  Recording = 'recording',
  Stopping = 'stopping',
  Sending = 'sending',
  Error = 'error'
}

/**
 * Enumerates error subtypes rendered by the message-recorder shell.
 */
export enum MessageRecorderErrorKind {
  None = 'none',
  PermissionDenied = 'permission-denied',
  RequestFailed = 'request-failed',
  RecordingFailed = 'recording-failed',
  SendFailed = 'send-failed'
}

/**
 * Describes the presentation-safe state consumed by the routed message-recorder page.
 */
export interface MessageRecorderPageState {
  chatId: string;
  chatTitle: string;
  chatUsername: string;
  phase: MessageRecorderPhase;
  errorKind: MessageRecorderErrorKind;
  elapsedSeconds: number;
  statusText: UiTextValue;
  errorText: UiTextValue;
  primaryActionText: UiTextValue;
  secondaryActionText: UiTextValue;
  primaryActionEnabled: boolean;
  secondaryActionEnabled: boolean;
  secondaryActionVisible: boolean;
}
