import { CallScreenDirection, CallScreenMockMode } from './CallScreenTypes';

/**
 * Router params accepted by `pages/CallScreen`. The screen is opened from:
 * - notification answer/resume action (legacy path: notification answer
 *   already called `acceptCall` before routing — `pendingAccept` is `false`),
 * - auto-open on `updateCall pending isOutgoing=false` (Task 4.6 F2 —
 *   `pendingAccept` is `true`, VM waits for user `Accept` / `Reject` tap),
 * - outgoing call action from `UserProfile` (direction `outgoing`).
 */
export interface CallScreenRouteParams {
  direction?: CallScreenDirection;
  callId?: number | string;
  userId?: string;
  peerName?: string;
  /** When true, re-attach to an already-active call instead of initiating one. */
  resume?: boolean;
  /**
   * When true, the screen is opened for an incoming call that has NOT been
   * accepted yet — the VM must show Accept/Reject buttons and only call
   * `acceptCall` / `discardCall` on user tap. When false (legacy notification
   * answer action), the VM calls `acceptCall` immediately.
   */
  pendingAccept?: boolean;
  /**
   * Debug-only — when set, VM enters mock mode (no TDLib subscription, no
   * real `acceptCall` / `discardCall`) and renders the requested phase for
   * UI polish on real hardware.
   *
   * TODO(task-4.6 cleanup): remove with the Profile debug entry.
   */
  mockMode?: CallScreenMockMode;
}
