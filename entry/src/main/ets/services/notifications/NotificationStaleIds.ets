/**
 * Picks stable IDs that are tracked locally but no longer present in the next
 * TDLib chat-notification snapshot — they need to be cancelled. Call
 * notifications are tracked by `TdNotificationsService` through a separate
 * lifecycle (driven by call events, not TDLib notification group updates), so
 * `callStableIds` are explicitly skipped: addressing review #issuecomment-2071
 * P2 where `reconcileAll()` was cancelling an active ongoing-call notification
 * whenever a chat notification update arrived.
 */
export function findStaleStableIds(
  activeStableIds: Set<number>,
  nextActiveStableIds: Set<number>,
  callStableIds: Set<number>
): number[] {
  const stale: number[] = [];
  for (const stableId of activeStableIds.values()) {
    if (callStableIds.has(stableId)) {
      continue;
    }
    if (!nextActiveStableIds.has(stableId)) {
      stale.push(stableId);
    }
  }
  return stale;
}
