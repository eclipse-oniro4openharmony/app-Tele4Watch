import { describe, it, expect } from '@ohos/hypium';
import { TdUserPayload } from '../main/ets/services/td/TdPayloadTypes';
import { TdContactsCoordinator } from '../main/ets/services/td/TdContactsCoordinator';

/**
 * Builds a minimal TDLib `user` payload used by contacts-coordinator tests.
 *
 * @param userId TDLib user id.
 * @param firstName Visible first name used in assertions.
 * @returns Typed TDLib user payload.
 */
function buildContactUser(userId: number, firstName: string): TdUserPayload {
  return {
    'id': userId,
    'first_name': firstName,
    'last_name': 'Example',
    'is_contact': true,
    'is_mutual_contact': true,
    'phone_number': `48${userId}`,
    'status': {
      '@type': 'userStatusOnline'
    },
    'usernames': {
      'active_usernames': [`user${userId}`],
      'disabled_usernames': [],
      'editable_username': ''
    }
  };
}

export default function tdContactsCoordinatorTest() {
  describe('TdContactsCoordinatorTest', () => {
    it('shouldNotEmitPrematureEmptyListBeforeAnyKnownContactIsHydrated', 0, () => {
      const coordinator = new TdContactsCoordinator();
      coordinator.setContactUserIds(['1001', '1002']);

      const snapshot = coordinator.buildContactsSnapshot();
      expect(snapshot === undefined).assertTrue();
    });

    it('shouldEmitEmptyListForEmptyContactsPayload', 0, () => {
      const coordinator = new TdContactsCoordinator();
      coordinator.setContactUserIds([]);

      const snapshot = coordinator.buildContactsSnapshot();
      expect(snapshot !== undefined).assertTrue();
      if (snapshot) {
        expect(snapshot.length).assertEqual(0);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldHydrateContactsIncrementallyInDeclaredOrder', 0, () => {
      const coordinator = new TdContactsCoordinator();
      coordinator.setContactUserIds(['1001', '1002', '1003']);

      expect(coordinator.applyUserUpdate(buildContactUser(1002, 'Bob'))).assertTrue();
      let snapshot = coordinator.buildContactsSnapshot();
      expect(snapshot !== undefined).assertTrue();
      if (snapshot) {
        expect(snapshot.length).assertEqual(1);
        expect(snapshot[0].id).assertEqual('1002');
      } else {
        expect(false).assertTrue();
      }

      expect(coordinator.applyUserUpdate(buildContactUser(1001, 'Alice'))).assertTrue();
      snapshot = coordinator.buildContactsSnapshot();
      expect(snapshot !== undefined).assertTrue();
      if (snapshot) {
        expect(snapshot.length).assertEqual(2);
        expect(snapshot[0].id).assertEqual('1001');
        expect(snapshot[1].id).assertEqual('1002');
      } else {
        expect(false).assertTrue();
      }

      expect(coordinator.applyUserUpdate(buildContactUser(1003, 'Carol'))).assertTrue();
      snapshot = coordinator.buildContactsSnapshot();
      expect(snapshot !== undefined).assertTrue();
      if (snapshot) {
        expect(snapshot.length).assertEqual(3);
        expect(snapshot[0].id).assertEqual('1001');
        expect(snapshot[1].id).assertEqual('1002');
        expect(snapshot[2].id).assertEqual('1003');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldRefreshKnownContactOnly', 0, () => {
      const coordinator = new TdContactsCoordinator();
      coordinator.setContactUserIds(['1001']);
      coordinator.applyUserUpdate(buildContactUser(1001, 'Alice'));

      const updatedUser = buildContactUser(1001, 'Alice Updated');
      expect(coordinator.applyUserUpdate(updatedUser)).assertTrue();

      const snapshot = coordinator.buildContactsSnapshot();
      expect(snapshot !== undefined).assertTrue();
      if (snapshot) {
        expect(snapshot.length).assertEqual(1);
        expect(snapshot[0].firstName).assertEqual('Alice Updated');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldIgnoreUnknownUserUpdatesForContactsList', 0, () => {
      const coordinator = new TdContactsCoordinator();
      coordinator.setContactUserIds(['1001']);
      coordinator.applyUserUpdate(buildContactUser(1001, 'Alice'));

      const changed = coordinator.applyUserUpdate(buildContactUser(2002, 'Ghost'));
      expect(changed).assertFalse();

      const snapshot = coordinator.buildContactsSnapshot();
      expect(snapshot !== undefined).assertTrue();
      if (snapshot) {
        expect(snapshot.length).assertEqual(1);
        expect(snapshot[0].id).assertEqual('1001');
        expect(snapshot[0].firstName).assertEqual('Alice');
      } else {
        expect(false).assertTrue();
      }
    });
  });
}
