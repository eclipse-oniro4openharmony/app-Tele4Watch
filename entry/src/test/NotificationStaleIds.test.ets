import { describe, expect, it } from '@ohos/hypium';
import { findStaleStableIds } from '../main/ets/services/notifications/NotificationStaleIds';

export default function notificationStaleIdsTest() {
  describe('findStaleStableIds', () => {
    it('marks_chat_ids_not_in_next_snapshot_as_stale', 0, () => {
      const active = new Set<number>([10, 11, 12]);
      const next = new Set<number>([10]);
      const calls = new Set<number>();

      const stale = findStaleStableIds(active, next, calls);

      expect(stale.length).assertEqual(2);
      expect(stale.includes(11)).assertTrue();
      expect(stale.includes(12)).assertTrue();
    });

    it('keeps_call_ids_alive_even_when_absent_from_chat_snapshot', 0, () => {
      // Review #issuecomment-2071 P2 scenario: ongoing call notification is
      // tracked in `activeStableIds` but is not part of the TD chat snapshot.
      const callId = 441041568;
      const active = new Set<number>([10, callId]);
      const next = new Set<number>([10]);
      const calls = new Set<number>([callId]);

      const stale = findStaleStableIds(active, next, calls);

      expect(stale.length).assertEqual(0);
    });

    it('marks_chat_id_stale_even_if_call_set_also_changes', 0, () => {
      const callId = 441041568;
      const active = new Set<number>([10, 11, callId]);
      const next = new Set<number>([10]);
      const calls = new Set<number>([callId]);

      const stale = findStaleStableIds(active, next, calls);

      expect(stale.length).assertEqual(1);
      expect(stale.includes(11)).assertTrue();
      expect(stale.includes(callId)).assertEqual(false);
    });

    it('empty_active_returns_empty_stale', 0, () => {
      const stale = findStaleStableIds(new Set<number>(), new Set<number>([1, 2]), new Set<number>());
      expect(stale.length).assertEqual(0);
    });

    it('all_chat_ids_present_returns_empty_stale', 0, () => {
      const active = new Set<number>([1, 2, 3]);
      const next = new Set<number>([1, 2, 3]);
      const stale = findStaleStableIds(active, next, new Set<number>());
      expect(stale.length).assertEqual(0);
    });
  });
}
