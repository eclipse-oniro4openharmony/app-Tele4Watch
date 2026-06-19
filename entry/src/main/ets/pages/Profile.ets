import { hilog } from '@kit.PerformanceAnalysisKit';
import { TdMeInfo } from '../models/td/TdViewTypes';
import {
  ArcList,
  ArcScrollBar
} from '@kit.ArkUI';
import { ProfileCard } from '../ui/ProfileCard';
import { ActionButtonListItem } from '../ui/ActionButtonListItem';
import { ProfileRouteParams } from '../models/profile/ProfileRouteParams';
import { ProfilePageState } from '../models/profile/ProfilePageState';
import { CallScreenMockMode } from '../models/voip/CallScreenTypes';
import { isDevelDebugEnabled } from '../config/TelegramSecrets.local';
import { notificationRuntimeService } from '../services/notifications/NotificationRuntimeService';
import { ProfilePageViewModel } from '../viewmodel/ProfilePageViewModel';

const DOMAIN = 0x2026;
const TAG = 'ProfilePage';

@Entry
@Component
struct Profile {
  private readonly viewModel: ProfilePageViewModel = new ProfilePageViewModel();
  private readonly initialPageState: ProfilePageState = this.viewModel.createInitialState();
  @State userId: string = this.initialPageState.userId;
  @State fullName: string = this.initialPageState.fullName;
  @State username: string = this.initialPageState.username;
  @State phoneNumber: string = this.initialPageState.phoneNumber;
  @State avatarPath: string = this.initialPageState.avatarPath;
  @State avatarAnimationPath: string = this.initialPageState.avatarAnimationPath;
  // TODO(task-4.6 cleanup): remove with the debug action builders + mock entries.
  private readonly develDebug: boolean = isDevelDebugEnabled();

  private scroller: Scroller = new Scroller();
  private hasNavigatedToIndex: boolean = false;

  /**
   * Redirects to Index when current session is no longer authorized.
   *
   * @param state Current authorization state.
   */
  private redirectToIndexIfUnauthorized(state: string): void {
    if (state === 'authorizationStateReady') {
      return;
    }
    if (this.hasNavigatedToIndex) {
      return;
    }

    hilog.info(DOMAIN, TAG, 'Session is no longer authorized (state=%{public}s). Redirecting to Index.', state);
    try {
      this.hasNavigatedToIndex = true;
      this.getUIContext().getRouter().replaceUrl({
        url: 'pages/Index'
      });
    } catch (error) {
      this.hasNavigatedToIndex = false;
      hilog.error(DOMAIN, TAG, 'Failed to redirect Profile to Index: %{public}s', String(error));
    }
  }

  /**
   * Reads route params and maps them to Profile UI state.
   */
  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle enter: Profile');
    this.hasNavigatedToIndex = false;
    const params = this.getUIContext().getRouter().getParams() as ProfileRouteParams;
    this.applyPageState(this.viewModel.createStateFromRoute(
      params.id ?? '-',
      params.firstName ?? '',
      params.lastName ?? '',
      params.username ?? '',
      params.phoneNumber ?? '-',
      typeof params.avatarPath === 'string' ? params.avatarPath : '',
      typeof params.avatarAnimationPath === 'string' ? params.avatarAnimationPath : ''
    ));

    this.viewModel.setMeListener((me: TdMeInfo): void => {
      this.applyPageState(this.viewModel.applyMeInfo(me));
    });

    this.viewModel.setAuthStateListener((state: string): void => {
      this.redirectToIndexIfUnauthorized(state);
      if (state === 'authorizationStateReady') {
        notificationRuntimeService.ensureStarted(TAG);
      }
    });

    const currentAuthState = this.viewModel.getAuthorizationStateName();
    this.redirectToIndexIfUnauthorized(currentAuthState);
    if (currentAuthState === 'authorizationStateReady') {
      notificationRuntimeService.ensureStarted(TAG);
    }
  }

  /**
   * Applies one mapped profile-page state to ArkUI-owned fields.
   *
   * @param nextPageState The mapped profile-page state.
   */
  private applyPageState(nextPageState: ProfilePageState): void {
    this.userId = nextPageState.userId;
    this.fullName = nextPageState.fullName;
    this.username = nextPageState.username;
    this.phoneNumber = nextPageState.phoneNumber;
    this.avatarPath = nextPageState.avatarPath;
    this.avatarAnimationPath = nextPageState.avatarAnimationPath;
  }

  /**
   * Emits lifecycle log when leaving Profile screen.
   */
  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle leave: Profile');
  }

  /**
   * Blocks system back from returning an authorized user to the login screen.
   *
   * @returns true when the back event is consumed by Profile.
   */
  onBackPress(): boolean {
    hilog.info(DOMAIN, TAG, 'System back ignored on Profile.');
    return true;
  }

  build() {
    Stack() {
      Image($r('app.media.watch_wallpaper_466'))
        .width('100%')
        .align(Alignment.Center)

      RelativeContainer() {
        ArcList({
          scroller: this.scroller,
        }) {
          this.buildProfile();
          this.buildContactsAction();
          this.buildChatsAction();
          this.buildLogoutAction();
          // TODO(task-4.6 cleanup): remove the three debug entries below
          // (and their builders / strings) once the CallScreen UI polish
          // iteration is done. Gated on `develDebug` so production builds
          // (template `TelegramSecrets.develDebug=false`) never expose them.
          if (this.develDebug) {
            this.buildDebugMockIncomingAction();
            this.buildDebugMockConnectedAction();
            this.buildDebugMockOutgoingAction();
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off);

        ArcScrollBar({ scroller: this.scroller, state: BarState.Auto })

        Text($r('app.string.profile_title'))
          .id('profile-header')
          .width('100%')
          .height(40)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .backgroundColor('#D9151A21')
          .alignRules({
            top: { anchor: "__container__", align: VerticalAlign.Top },
            left: { anchor: "__container__", align: HorizontalAlign.Start }
          })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  /**
   * Renders the profile data card.
   */
  @Builder
  buildProfile() {
    ProfileCard({
      userId: this.userId,
      fullName: this.fullName,
      username: this.username,
      phoneNumber: this.phoneNumber,
      avatarPath: this.avatarPath,
      avatarAnimationPath: this.avatarAnimationPath
    })
  }

  /**
   * Renders action list item that opens contacts screen.
   */
  @Builder
  private buildContactsAction(): void {
    ActionButtonListItem({
      label: $r('app.string.profile_action_contacts'),
      hasIcon: true,
      iconResource: $r('app.media.profile_contacts_icon'),
      buttonColor: $r('app.color.surface_profile_contacts_fill'),
      gradientStartColor: $r('app.color.surface_profile_contacts_gradient_start'),
      gradientMiddleColor: $r('app.color.surface_profile_contacts_gradient_middle'),
      gradientEndColor: $r('app.color.surface_profile_contacts_gradient_end'),
      isEnabled: true,
      onButtonClick: (): void => {
        this.openContactsPage();
      }
    });
  }

  /**
   * Renders action list item that opens chats screen.
   */
  @Builder
  private buildChatsAction(): void {
    ActionButtonListItem({
      label: $r('app.string.profile_action_chats'),
      hasIcon: true,
      iconResource: $r('app.media.profile_chats_icon'),
      buttonColor: $r('app.color.surface_profile_chats_fill'),
      gradientStartColor: $r('app.color.surface_profile_chats_gradient_start'),
      gradientMiddleColor: $r('app.color.surface_profile_chats_gradient_middle'),
      gradientEndColor: $r('app.color.surface_profile_chats_gradient_end'),
      isEnabled: true,
      onButtonClick: (): void => {
        this.openChatsPage();
      }
    });
  }

  /**
   * Renders action list item that opens logout screen.
   */
  @Builder
  private buildLogoutAction(): void {
    ActionButtonListItem({
      label: $r('app.string.profile_action_logout'),
      hasIcon: true,
      iconResource: $r('app.media.profile_logout_icon'),
      buttonColor: $r('app.color.surface_profile_logout_fill'),
      gradientStartColor: $r('app.color.surface_profile_logout_gradient_start'),
      gradientMiddleColor: $r('app.color.surface_profile_logout_gradient_middle'),
      gradientEndColor: $r('app.color.surface_profile_logout_gradient_end'),
      isEnabled: true,
      onButtonClick: (): void => {
        this.openLogoutPage();
      }
    });
  }

  /**
   * Opens contacts page.
   */
  private openContactsPage(): void {
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/Contacts'
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to open Contacts page: %{public}s', String(error));
    }
  }

  /**
   * Opens chats list page.
   */
  private openChatsPage(): void {
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/Chats'
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to open Chats page: %{public}s', String(error));
    }
  }

  /**
   * Opens logout flow page.
   */
  private openLogoutPage(): void {
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/Logout'
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to open Logout page: %{public}s', String(error));
    }
  }

  // TODO(task-4.6 cleanup): remove the three debug builders + the openDebug...
  // helper once CallScreen layout polish is finished.

  @Builder
  private buildDebugMockIncomingAction(): void {
    ActionButtonListItem({
      label: $r('app.string.profile_action_debug_mock_incoming'),
      hasIcon: true,
      iconResource: $r('app.media.profile_call_icon'),
      buttonColor: $r('app.color.surface_profile_chats_fill'),
      gradientStartColor: $r('app.color.surface_profile_chats_gradient_start'),
      gradientMiddleColor: $r('app.color.surface_profile_chats_gradient_middle'),
      gradientEndColor: $r('app.color.surface_profile_chats_gradient_end'),
      isEnabled: true,
      onButtonClick: (): void => {
        this.openDebugMockCallScreen('incomingRinging');
      }
    });
  }

  @Builder
  private buildDebugMockConnectedAction(): void {
    ActionButtonListItem({
      label: $r('app.string.profile_action_debug_mock_connected'),
      hasIcon: true,
      iconResource: $r('app.media.profile_call_icon'),
      buttonColor: $r('app.color.surface_profile_chats_fill'),
      gradientStartColor: $r('app.color.surface_profile_chats_gradient_start'),
      gradientMiddleColor: $r('app.color.surface_profile_chats_gradient_middle'),
      gradientEndColor: $r('app.color.surface_profile_chats_gradient_end'),
      isEnabled: true,
      onButtonClick: (): void => {
        this.openDebugMockCallScreen('connected');
      }
    });
  }

  @Builder
  private buildDebugMockOutgoingAction(): void {
    ActionButtonListItem({
      label: $r('app.string.profile_action_debug_mock_outgoing'),
      hasIcon: true,
      iconResource: $r('app.media.profile_call_icon'),
      buttonColor: $r('app.color.surface_profile_chats_fill'),
      gradientStartColor: $r('app.color.surface_profile_chats_gradient_start'),
      gradientMiddleColor: $r('app.color.surface_profile_chats_gradient_middle'),
      gradientEndColor: $r('app.color.surface_profile_chats_gradient_end'),
      isEnabled: true,
      onButtonClick: (): void => {
        this.openDebugMockCallScreen('outgoing');
      }
    });
  }

  /**
   * TODO(task-4.6 cleanup): remove with the debug action builders.
   */
  private openDebugMockCallScreen(mockMode: CallScreenMockMode): void {
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/CallScreen',
        params: {
          direction: mockMode === 'outgoing' ? 'outgoing' : 'incoming',
          mockMode: mockMode,
          callId: 999999,
          userId: this.userId,
          peerName: this.fullName.length > 0 ? this.fullName : 'Test Caller'
        }
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to open debug CallScreen: %{public}s', String(error));
    }
  }
}
