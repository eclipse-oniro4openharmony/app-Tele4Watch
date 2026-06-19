import { describe, it, expect } from '@ohos/hypium';
import { ContactsPageMode, ContactsPageState } from '../main/ets/models/contact/ContactsPageState';
import { TdContactListItem, TdMeInfo } from '../main/ets/services/td/TdPayloadTypes';
import { ContactsPageViewModel } from '../main/ets/viewmodel/ContactsPageViewModel';

function buildContact(overrides?: Partial<TdContactListItem>): TdContactListItem {
  return {
    id: overrides?.id ?? '42',
    firstName: overrides?.firstName ?? 'Ada',
    lastName: overrides?.lastName ?? 'Lovelace',
    username: overrides?.username ?? 'adal',
    phoneNumber: overrides?.phoneNumber ?? '48123456789',
    avatarPath: overrides?.avatarPath ?? '/tmp/avatar.jpg',
    avatarAnimationPath: overrides?.avatarAnimationPath ?? '/tmp/avatar.tgs',
    avatarFileId: overrides?.avatarFileId ?? 77,
    isMutualContact: overrides?.isMutualContact ?? true,
    statusKind: overrides?.statusKind,
    lastSeenAt: overrides?.lastSeenAt,
    accentColorId: overrides?.accentColorId
  };
}

export default function contactsPageViewModelTest() {
  describe('ContactsPageViewModelTest', () => {
    it('shouldCreateIdleInitialState', 0, () => {
      const viewModel = new ContactsPageViewModel();
      const state = viewModel.createInitialState();

      expect(state.contacts.length).assertEqual(0);
      expect(state.pageMode).assertEqual(ContactsPageMode.Idle);
      expect(state.isLoading).assertFalse();
      expect(state.isPullRefreshing).assertFalse();
    });

    it('shouldPlanRefreshIntoLoadingState', 0, () => {
      const viewModel = new ContactsPageViewModel();
      const currentState: ContactsPageState = {
        contacts: [buildContact()],
        pageMode: ContactsPageMode.Ready,
        isLoading: false,
        isPullRefreshing: false
      };

      const refreshPlan = viewModel.planRefresh(currentState);

      expect(refreshPlan.shouldRequestContacts).assertTrue();
      expect(refreshPlan.nextPageState.pageMode).assertEqual(ContactsPageMode.Ready);
      expect(refreshPlan.nextPageState.isLoading).assertTrue();
      expect(refreshPlan.nextPageState.isPullRefreshing).assertFalse();
      expect(refreshPlan.nextPageState.contacts.length).assertEqual(1);
    });

    it('shouldSkipPullRefreshWhenAlreadyLoading', 0, () => {
      const viewModel = new ContactsPageViewModel();
      const currentState: ContactsPageState = {
        contacts: [buildContact()],
        pageMode: ContactsPageMode.Ready,
        isLoading: true,
        isPullRefreshing: false
      };

      const refreshPlan = viewModel.planPullRefresh(currentState);

      expect(refreshPlan.shouldRequestContacts).assertFalse();
      expect(refreshPlan.nextPageState.pageMode).assertEqual(ContactsPageMode.Ready);
      expect(refreshPlan.nextPageState.isLoading).assertTrue();
      expect(refreshPlan.nextPageState.isPullRefreshing).assertFalse();
    });

    it('shouldApplyContactsIntoReadyStateWithClonedItems', 0, () => {
      const viewModel = new ContactsPageViewModel();
      const contacts: TdContactListItem[] = [buildContact()];

      const nextState = viewModel.applyContacts(contacts);
      contacts[0].firstName = 'Changed';

      expect(nextState.pageMode).assertEqual(ContactsPageMode.Ready);
      expect(nextState.isLoading).assertFalse();
      expect(nextState.isPullRefreshing).assertFalse();
      expect(nextState.contacts.length).assertEqual(1);
      expect(nextState.contacts[0].firstName).assertEqual('Ada');
      expect(viewModel.contactStatusKind(nextState.contacts[0])).assertEqual('empty');
    });

    it('shouldResolveDisplayLinesAndRenderKey', 0, () => {
      const viewModel = new ContactsPageViewModel();
      const usernameOnly = buildContact({
        firstName: '',
        lastName: '',
        username: 'user42',
        phoneNumber: ''
      });
      const phoneOnly = buildContact({
        firstName: '',
        lastName: '',
        username: '',
        phoneNumber: '48000111000'
      });
      phoneOnly.avatarFileId = undefined;

      expect(viewModel.contactDisplayName(usernameOnly)).assertEqual('@user42');
      expect(viewModel.contactSecondaryLine(usernameOnly)).assertEqual('@user42');
      expect(viewModel.contactDisplayName(phoneOnly)).assertEqual('48000111000');
      expect(viewModel.contactSecondaryLine(phoneOnly)).assertEqual('48000111000');
      expect(viewModel.contactRenderKey(phoneOnly)).assertEqual('42:0:');
    });

    it('shouldResolveStatusAndGradientMetadata', 0, () => {
      const viewModel = new ContactsPageViewModel();
      const contact = buildContact({
        statusKind: 'offline',
        lastSeenAt: 1710001000,
        accentColorId: 5
      });

      expect(viewModel.contactStatusKind(contact)).assertEqual('offline');
      expect(viewModel.contactLastSeenAt(contact)).assertEqual(1710001000);
      expect(viewModel.contactAvatarPaletteIndex(contact)).assertEqual(5);
    });

    it('shouldPlanAuthRedirectOnlyForUnauthorizedStates', 0, () => {
      const viewModel = new ContactsPageViewModel();
      const readyPlan = viewModel.planAuthStateChange('authorizationStateReady');
      const closedPlan = viewModel.planAuthStateChange('authorizationStateClosed');

      expect(readyPlan.shouldNavigateToIndex).assertFalse();
      expect(readyPlan.resetIndexNavigation).assertTrue();
      expect(closedPlan.shouldNavigateToIndex).assertTrue();
      expect(closedPlan.resetIndexNavigation).assertFalse();
    });

    it('shouldPrependSyntheticMeContactWithoutDuplicates', 0, () => {
      const viewModel = new ContactsPageViewModel();
      const me: TdMeInfo = {
        id: 7,
        firstName: 'Pawel',
        lastName: 'Mandes',
        username: 'pmandes',
        phoneNumber: '48123456789',
        avatarPath: '/tmp/me.jpg',
        avatarAnimationPath: '/tmp/me.tgs'
      };
      const meContact = viewModel.mapMeToContact(me);
      const visible = viewModel.visibleContacts(meContact, [
        buildContact({ id: '7', firstName: 'Duplicate' }),
        buildContact({ id: '8', firstName: 'Ada' })
      ]);

      expect(visible.length).assertEqual(2);
      expect(visible[0].id).assertEqual('7');
      expect(visible[0].firstName).assertEqual('Pawel');
      expect(visible[0].avatarAnimationPath).assertEqual('/tmp/me.tgs');
      expect(visible[1].id).assertEqual('8');
    });

    it('shouldCreateUserProfileRouteParamsFromContact', 0, () => {
      const viewModel = new ContactsPageViewModel();
      const contact = buildContact({
        id: '84',
        firstName: 'Linus',
        lastName: 'Torvalds',
        username: 'torvalds',
        phoneNumber: '48111000111',
        avatarPath: '/tmp/linus.jpg',
        avatarAnimationPath: '/tmp/linus.tgs'
      });

      const params = viewModel.createUserProfileRouteParams(contact);

      expect(params.id).assertEqual('84');
      expect(params.firstName).assertEqual('Linus');
      expect(params.lastName).assertEqual('Torvalds');
      expect(params.username).assertEqual('torvalds');
      expect(params.phoneNumber).assertEqual('48111000111');
      expect(params.avatarPath).assertEqual('/tmp/linus.jpg');
      expect(params.avatarAnimationPath).assertEqual('/tmp/linus.tgs');
    });
  });
}
