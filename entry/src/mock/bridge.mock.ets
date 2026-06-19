export type ContactsMockScenario = 'filled' | 'empty' | 'loadingThenFilled';

export interface TdNativeBridge {
  createClientId(): number;
  send(clientId: number, requestJson: string): void;
  receive(timeoutSeconds?: number): string;
  execute(requestJson: string): string;
  setLogVerbosityLevel(level: number): string;
}

interface TdMockRequest {
  readonly requestType: string;
  readonly extra: string;
  readonly name: string;
  readonly userId: string;
}

interface MockUserShape {
  readonly id: number;
  readonly firstName: string;
  readonly lastName: string;
  readonly username: string;
  readonly phoneNumber: string;
  readonly isContact: boolean;
  readonly isMutualContact: boolean;
  readonly accentColorId: number;
  readonly wasOnline: number;
  readonly isOnline: boolean;
}

interface TdMockStatusOnlinePayload {
  '@type': string;
}

interface TdMockStatusOfflinePayload {
  '@type': string;
  'was_online': number;
}

type TdMockStatusPayload = TdMockStatusOnlinePayload | TdMockStatusOfflinePayload;

interface TdMockUserPayload {
  '@type': string;
  '@extra'?: string;
  'id': number;
  'first_name': string;
  'last_name': string;
  'username': string;
  'phone_number': string;
  'is_contact': boolean;
  'is_mutual_contact': boolean;
  'accent_color_id': number;
  'status': TdMockStatusPayload;
}

interface TdMockAuthorizationStatePayload {
  '@type': string;
}

interface TdMockOptionIntegerValuePayload {
  '@type': string;
  'value': string;
}

interface TdMockUpdateOptionPayload {
  '@type': string;
  'name': string;
  'value': TdMockOptionIntegerValuePayload;
}

interface TdMockUsersPayload {
  '@type': string;
  '@extra': string;
  'user_ids': number[];
}

interface TdMockUpdateUserPayload {
  '@type': string;
  'user': TdMockUserPayload;
}

interface TdMockUserFullInfoPayload {
  '@type': string;
  '@extra': string;
}

interface TdMockOkPayload {
  '@type': string;
  '@extra'?: string;
}

interface TdMockOptionValueStringPayload {
  '@type': string;
  'value': string;
}

type TdMockResponsePayload =
  TdMockUserPayload |
  TdMockAuthorizationStatePayload |
  TdMockUpdateOptionPayload |
  TdMockUsersPayload |
  TdMockUpdateUserPayload |
  TdMockUserFullInfoPayload |
  TdMockOkPayload |
  TdMockOptionValueStringPayload;

const MOCK_ME_ID: number = 9001;
const DEFAULT_SCENARIO: ContactsMockScenario = 'filled';
const CONTACT_RESPONSE_DELAY_MS: number = 900;

const MOCK_ME: MockUserShape = {
  id: MOCK_ME_ID,
  firstName: 'Test',
  lastName: 'Account',
  username: 'testaccount',
  phoneNumber: '+48123456789',
  isContact: false,
  isMutualContact: false,
  accentColorId: 0,
  wasOnline: 0,
  isOnline: true
};

const BASE_FILLED_CONTACT_USERS: MockUserShape[] = [
  {
    id: 1001,
    firstName: 'Alice',
    lastName: 'Example',
    username: 'alice',
    phoneNumber: '+48111111111',
    isContact: true,
    isMutualContact: true,
    accentColorId: 1,
    wasOnline: 0,
    isOnline: true
  },
  {
    id: 1002,
    firstName: 'Bob',
    lastName: 'Example',
    username: 'bob',
    phoneNumber: '+48222222222',
    isContact: true,
    isMutualContact: false,
    accentColorId: 2,
    wasOnline: 1710000000,
    isOnline: false
  }
];

let contactsScenario: ContactsMockScenario = DEFAULT_SCENARIO;
let filledContactUsers: MockUserShape[] = cloneMockUsers(BASE_FILLED_CONTACT_USERS);

function extractStringField(payload: string, fieldName: string): string {
  const match = payload.match(new RegExp(`\"${fieldName}\"\\s*:\\s*\"([^\"]*)\"`));
  if (!match || match.length < 2) {
    return '';
  }
  return match[1];
}

function extractIntOrStringField(payload: string, fieldName: string): string {
  const stringMatch = payload.match(new RegExp(`\"${fieldName}\"\\s*:\\s*\"([^\"]+)\"`));
  if (stringMatch && stringMatch.length >= 2) {
    return stringMatch[1];
  }

  const numberMatch = payload.match(new RegExp(`\"${fieldName}\"\\s*:\\s*(-?\\d+)`));
  if (!numberMatch || numberMatch.length < 2) {
    return '';
  }
  return numberMatch[1];
}

function parseRequest(requestJson: string): TdMockRequest {
  return {
    requestType: extractStringField(requestJson, '@type'),
    extra: extractStringField(requestJson, '@extra'),
    name: extractStringField(requestJson, 'name'),
    userId: extractIntOrStringField(requestJson, 'user_id')
  };
}

function buildStatusPayload(user: MockUserShape): TdMockStatusPayload {
  if (user.isOnline) {
    const statusPayload: TdMockStatusOnlinePayload = {
      '@type': 'userStatusOnline'
    };
    return statusPayload;
  }

  const statusPayload: TdMockStatusOfflinePayload = {
    '@type': 'userStatusOffline',
    'was_online': user.wasOnline
  };
  return statusPayload;
}

function buildUserPayload(user: MockUserShape, extra: string): TdMockUserPayload {
  return {
    '@type': 'user',
    '@extra': extra,
    'id': user.id,
    'first_name': user.firstName,
    'last_name': user.lastName,
    'username': user.username,
    'phone_number': user.phoneNumber,
    'is_contact': user.isContact,
    'is_mutual_contact': user.isMutualContact,
    'accent_color_id': user.accentColorId,
    'status': buildStatusPayload(user)
  };
}

function buildContactsUserIds(): number[] {
  if (contactsScenario === 'empty') {
    return [];
  }

  const userIds: number[] = [];
  for (let index = 0; index < filledContactUsers.length; index += 1) {
    userIds.push(filledContactUsers[index].id);
  }
  return userIds;
}

function findContactUser(userId: string): MockUserShape | undefined {
  for (let index = 0; index < filledContactUsers.length; index += 1) {
    const contactUser = filledContactUsers[index];
    if (String(contactUser.id) === userId) {
      return contactUser;
    }
  }
  return undefined;
}

function cloneMockUser(user: MockUserShape): MockUserShape {
  return {
    id: user.id,
    firstName: user.firstName,
    lastName: user.lastName,
    username: user.username,
    phoneNumber: user.phoneNumber,
    isContact: user.isContact,
    isMutualContact: user.isMutualContact,
    accentColorId: user.accentColorId,
    wasOnline: user.wasOnline,
    isOnline: user.isOnline
  };
}

function cloneMockUsers(users: MockUserShape[]): MockUserShape[] {
  const clonedUsers: MockUserShape[] = [];
  for (let index = 0; index < users.length; index += 1) {
    clonedUsers.push(cloneMockUser(users[index]));
  }
  return clonedUsers;
}

function replaceContactUser(nextUser: MockUserShape): void {
  const nextUsers: MockUserShape[] = [];
  let replaced = false;
  for (let index = 0; index < filledContactUsers.length; index += 1) {
    const currentUser = filledContactUsers[index];
    if (currentUser.id === nextUser.id) {
      nextUsers.push(cloneMockUser(nextUser));
      replaced = true;
      continue;
    }
    nextUsers.push(cloneMockUser(currentUser));
  }
  if (!replaced) {
    nextUsers.push(cloneMockUser(nextUser));
  }
  filledContactUsers = nextUsers;
}

class MockTdNativeBridge implements TdNativeBridge {
  private clientId: number = 0;
  private queuedResponses: string[] = [];
  private scheduledTimerIds: number[] = [];

  createClientId(): number {
    this.clientId += 1;
    return this.clientId;
  }

  send(_clientId: number, requestJson: string): void {
    const request = parseRequest(requestJson);
    if (request.requestType.length === 0) {
      return;
    }

    if (request.requestType === 'getAuthorizationState') {
      const authStatePayload: TdMockAuthorizationStatePayload = {
        '@type': 'authorizationStateWaitTdlibParameters'
      };
      this.enqueueResponse(authStatePayload);
      return;
    }

    if (request.requestType === 'setTdlibParameters') {
      const optionValuePayload: TdMockOptionIntegerValuePayload = {
        '@type': 'optionValueInteger',
        'value': String(MOCK_ME_ID)
      };
      const updateOptionPayload: TdMockUpdateOptionPayload = {
        '@type': 'updateOption',
        'name': 'my_id',
        'value': optionValuePayload
      };
      const readyPayload: TdMockAuthorizationStatePayload = {
        '@type': 'authorizationStateReady'
      };
      this.enqueueResponse(updateOptionPayload);
      this.enqueueResponse(readyPayload);
      return;
    }

    if (request.requestType === 'getMe') {
      this.enqueueResponse(buildUserPayload(MOCK_ME, 'auth:getMe'));
      return;
    }

    if (request.requestType === 'getContacts') {
      const usersPayload: TdMockUsersPayload = {
        '@type': 'users',
        '@extra': 'contacts:get',
        'user_ids': buildContactsUserIds()
      };
      this.enqueueResponse(usersPayload);
      return;
    }

    if (request.requestType === 'getUser') {
      const contactUser = findContactUser(request.userId);
      if (!contactUser) {
        return;
      }
      const resolvedExtra = request.extra.length > 0 ? request.extra : `contacts:user:${request.userId}`;
      if (contactsScenario === 'loadingThenFilled') {
        this.enqueueResponseAfterDelay(buildUserPayload(contactUser, resolvedExtra), CONTACT_RESPONSE_DELAY_MS);
        return;
      }
      this.enqueueResponse(buildUserPayload(contactUser, resolvedExtra));
      return;
    }

    if (request.requestType === 'getUserFullInfo') {
      const userFullInfoPayload: TdMockUserFullInfoPayload = {
        '@type': 'userFullInfo',
        '@extra': request.extra
      };
      this.enqueueResponse(userFullInfoPayload);
      return;
    }

    if (request.requestType === 'downloadFile') {
      const okPayload: TdMockOkPayload = {
        '@type': 'ok',
        '@extra': request.extra
      };
      this.enqueueResponse(okPayload);
      return;
    }
  }

  receive(_timeoutSeconds?: number): string {
    if (this.queuedResponses.length <= 0) {
      return '';
    }

    const nextResponse = this.queuedResponses.shift();
    if (typeof nextResponse !== 'string') {
      return '';
    }
    return nextResponse;
  }

  execute(requestJson: string): string {
    const request = parseRequest(requestJson);
    if (request.requestType === 'getOption' && request.name === 'version') {
      const versionPayload: TdMockOptionValueStringPayload = {
        '@type': 'optionValueString',
        'value': '1.0.0-mock'
      };
      return JSON.stringify(versionPayload);
    }

    const okPayload: TdMockOkPayload = {
      '@type': 'ok'
    };
    return JSON.stringify(okPayload);
  }

  setLogVerbosityLevel(_level: number): string {
    const okPayload: TdMockOkPayload = {
      '@type': 'ok'
    };
    return JSON.stringify(okPayload);
  }

  reset(): void {
    this.clientId = 0;
    this.queuedResponses = [];
    this.clearScheduledResponses();
    contactsScenario = DEFAULT_SCENARIO;
    filledContactUsers = cloneMockUsers(BASE_FILLED_CONTACT_USERS);
  }

  /**
   * Queues one `updateUser` payload for an already known mock contact.
   *
   * @param nextUser Updated mock contact definition.
   */
  queueContactUpdate(nextUser: MockUserShape): void {
    const updateUserPayload: TdMockUpdateUserPayload = {
      '@type': 'updateUser',
      'user': buildUserPayload(nextUser, '')
    };
    this.enqueueResponse(updateUserPayload);
  }

  private enqueueResponse(payload: TdMockResponsePayload): void {
    this.queuedResponses.push(JSON.stringify(payload));
  }

  /**
   * Enqueues one mock TDLib payload after a short delay.
   *
   * @param payload Mock TDLib payload.
   * @param delayMs Delay in milliseconds.
   */
  private enqueueResponseAfterDelay(payload: TdMockResponsePayload, delayMs: number): void {
    const timerId = setTimeout((): void => {
      this.enqueueResponse(payload);
      this.removeScheduledTimer(timerId as number);
    }, delayMs) as number;
    this.scheduledTimerIds.push(timerId);
  }

  /**
   * Removes one scheduled timer id from local bookkeeping.
   *
   * @param timerId Timer id returned by `setTimeout`.
   */
  private removeScheduledTimer(timerId: number): void {
    const nextTimerIds: number[] = [];
    for (let index = 0; index < this.scheduledTimerIds.length; index += 1) {
      const currentTimerId = this.scheduledTimerIds[index];
      if (currentTimerId !== timerId) {
        nextTimerIds.push(currentTimerId);
      }
    }
    this.scheduledTimerIds = nextTimerIds;
  }

  /**
   * Cancels all delayed mock responses.
   */
  private clearScheduledResponses(): void {
    for (let index = 0; index < this.scheduledTimerIds.length; index += 1) {
      clearTimeout(this.scheduledTimerIds[index]);
    }
    this.scheduledTimerIds = [];
  }
}

export const tdNativeBridge: MockTdNativeBridge = new MockTdNativeBridge();
export default tdNativeBridge;

/**
 * Selects the contacts-response scenario used by subsequent requests.
 *
 * @param nextScenario Contacts mock scenario.
 */
export function setMockContactsScenario(nextScenario: ContactsMockScenario): void {
  contactsScenario = nextScenario;
}

/**
 * Queues `updateUser` for one known mock contact and updates future `getUser` replies.
 *
 * @param userId TDLib user id of the mocked contact.
 * @param firstName Updated first name rendered by the contacts page.
 * @param lastName Updated last name rendered by the contacts page.
 * @param username Updated username rendered by the contacts page.
 */
export function queueMockContactNameUpdate(
  userId: number,
  firstName: string,
  lastName: string,
  username: string
): void {
  const currentUser = findContactUser(String(userId));
  if (!currentUser) {
    return;
  }

  const nextUser: MockUserShape = {
    id: currentUser.id,
    firstName: firstName,
    lastName: lastName,
    username: username,
    phoneNumber: currentUser.phoneNumber,
    isContact: currentUser.isContact,
    isMutualContact: currentUser.isMutualContact,
    accentColorId: currentUser.accentColorId,
    wasOnline: currentUser.wasOnline,
    isOnline: currentUser.isOnline
  };
  replaceContactUser(nextUser);
  tdNativeBridge.queueContactUpdate(nextUser);
}

/**
 * Resets mock bridge state between UI-test cases.
 */
export function resetMockBridge(): void {
  tdNativeBridge.reset();
}
