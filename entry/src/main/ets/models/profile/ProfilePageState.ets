/**
 * Describes the presentation-safe state consumed by the routed profile page.
 */
export interface ProfilePageState {
  userId: string;
  fullName: string;
  username: string;
  phoneNumber: string;
  avatarPath: string;
  avatarAnimationPath: string;
}
