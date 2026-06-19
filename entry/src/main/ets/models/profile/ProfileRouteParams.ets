import { TdMeInfo } from '../td/TdViewTypes';

/**
 * Router params accepted by the Profile page.
 */
export interface ProfileRouteParams {
  id?: string;
  firstName?: string;
  lastName?: string;
  username?: string;
  phoneNumber?: string;
  avatarPath?: string;
  avatarAnimationPath?: string;
}

/**
 * Maps the current-user model to Profile page router params.
 *
 * @param me The current user model emitted by TD client.
 * @returns Profile page router params.
 */
export function createProfileRouteParams(me: TdMeInfo): ProfileRouteParams {
  return {
    id: String(me.id),
    firstName: me.firstName,
    lastName: me.lastName,
    username: me.username,
    phoneNumber: me.phoneNumber,
    avatarPath: typeof me.avatarPath === 'string' ? me.avatarPath : '',
    avatarAnimationPath: typeof me.avatarAnimationPath === 'string' ? me.avatarAnimationPath : ''
  };
}
