import { describe, it, expect } from '@ohos/hypium';
import { mapContactFromUser, parseUsersPayload } from '../main/ets/services/td/TdUserParser';
import { TdUserPayload } from '../main/ets/services/td/TdPayloadTypes';

export default function tdUserParserTest() {
  describe('TdUserParserTest', () => {
    it('shouldParseUsersPayloadIds', 0, () => {
      const result = parseUsersPayload('{"user_ids":[123,"456",0,""]}');
      expect(result.ok).assertTrue();
      if (result.userIds) {
        expect(result.userIds.length).assertEqual(2);
        expect(result.userIds[0]).assertEqual('123');
        expect(result.userIds[1]).assertEqual('456');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldRejectUsersPayloadWhenJsonIsInvalid', 0, () => {
      const result = parseUsersPayload('{"user_ids":[');
      expect(result.ok).assertFalse();
      expect(typeof result.error === 'string' && result.error.length > 0).assertTrue();
    });

    it('shouldRejectUsersPayloadWhenUserIdsAreMissing', 0, () => {
      const result = parseUsersPayload('{"@type":"users"}');
      expect(result.ok).assertFalse();
    });

    it('shouldRejectUsersPayloadWhenUserIdsAreNull', 0, () => {
      const result = parseUsersPayload('{"user_ids":null}');
      expect(result.ok).assertFalse();
    });

    it('shouldMapTelegramContactFromUserPayload', 0, () => {
      const user: TdUserPayload = {
        'id': 42,
        'first_name': 'Ada',
        'last_name': 'Lovelace',
        'is_contact': true,
        'is_mutual_contact': true,
        'accent_color_id': 6,
        'phone_number': '48123456789',
        'status': {
          '@type': 'userStatusOffline',
          'was_online': 1710000000
        },
        'usernames': {
          'active_usernames': ['adal'],
          'disabled_usernames': [],
          'editable_username': ''
        },
        'profile_photo': {
          'small': {
            'id': 77,
            'local': {
              'path': '/tmp/avatar.jpg',
              'is_downloading_completed': true
            }
          },
          'has_animation': false
        }
      };

      const contact = mapContactFromUser(user);
      expect(contact !== undefined).assertTrue();
      if (contact) {
        expect(contact.id).assertEqual('42');
        expect(contact.firstName).assertEqual('Ada');
        expect(contact.lastName).assertEqual('Lovelace');
        expect(contact.username).assertEqual('adal');
        expect(contact.phoneNumber).assertEqual('48123456789');
        expect(contact.avatarFileId).assertEqual(77);
        expect(contact.avatarPath).assertEqual('/tmp/avatar.jpg');
        expect(contact.isMutualContact).assertTrue();
        expect(contact.statusKind).assertEqual('offline');
        expect(contact.lastSeenAt).assertEqual(1710000000);
        expect(contact.accentColorId).assertEqual(6);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldIgnoreNonContactUsers', 0, () => {
      const user: TdUserPayload = {
        'id': 99,
        'first_name': 'Visitor',
        'is_contact': false
      };

      const contact = mapContactFromUser(user);
      expect(contact === undefined).assertTrue();
    });

    it('shouldUseEditableUsernameWhenActiveUsernamesAreEmpty', 0, () => {
      const user: TdUserPayload = {
        'id': 7,
        'is_contact': true,
        'usernames': {
          'active_usernames': [],
          'disabled_usernames': [],
          'editable_username': 'editableName'
        }
      };

      const contact = mapContactFromUser(user);
      expect(contact !== undefined).assertTrue();
      if (contact) {
        expect(contact.username).assertEqual('editableName');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldKeepUsernameEmptyWhenUserHasNoUsernameFields', 0, () => {
      const user: TdUserPayload = {
        'id': 55,
        'first_name': 'NoName',
        'is_contact': true
      };

      const contact = mapContactFromUser(user);
      expect(contact !== undefined).assertTrue();
      if (contact) {
        expect(contact.username).assertEqual('');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldMapOnlineStatusKindForContact', 0, () => {
      const user: TdUserPayload = {
        'id': 88,
        'first_name': 'Online',
        'is_contact': true,
        'status': {
          '@type': 'userStatusOnline',
          'expires': 1710001234
        }
      };

      const contact = mapContactFromUser(user);
      expect(contact !== undefined).assertTrue();
      if (contact) {
        expect(contact.statusKind).assertEqual('online');
        expect(contact.lastSeenAt === undefined).assertTrue();
      } else {
        expect(false).assertTrue();
      }
    });
  });
}
