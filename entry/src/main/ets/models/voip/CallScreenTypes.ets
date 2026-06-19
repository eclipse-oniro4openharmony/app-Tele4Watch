/**
 * Direction selected by the route that opens `pages/CallScreen`.
 *
 * `incoming` enters either pre-accept (`pendingAccept=true`, auto-open from
 * `updateCall pending isOutgoing=false`) or post-accept (notification answer
 * action already called `acceptCall`); `outgoing` enters from the contact
 * profile and places the call here.
 *
 * Kept in the `models/voip` neutral layer so the route params and the view
 * model can both depend on it without the model layer reaching back into
 * the view model.
 */
export type CallScreenDirection = 'incoming' | 'outgoing';

/**
 * Debug-only mock phase requested via route params. When non-empty,
 * `CallScreenViewModel.startMockCall` renders the screen in that phase
 * without subscribing to TDLib events and without dispatching real
 * `acceptCall` / `discardCall` requests — purely for UI polish.
 *
 * TODO(task-4.6 cleanup): remove together with the Profile debug entry
 * once layout iteration is done.
 */
export type CallScreenMockMode = 'incomingRinging' | 'connected' | 'outgoing';
