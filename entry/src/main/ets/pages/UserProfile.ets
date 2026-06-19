import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ArcList,
  ArcScrollBar
} from '@kit.ArkUI';
import { ProfilePageState } from '../models/profile/ProfilePageState';
import { ProfileRouteParams } from '../models/profile/ProfileRouteParams';
import { ChatRouteParams } from '../models/chat/ChatRouteParams';
import { ProfileCard } from '../ui/ProfileCard';
import { ActionButtonListItem } from '../ui/ActionButtonListItem';
import { ProfilePageViewModel } from '../viewmodel/ProfilePageViewModel';

const DOMAIN = 0x2026;
const TAG = 'UserProfilePage';

@Entry
@Component
struct UserProfile {
  private readonly viewModel: ProfilePageViewModel = new ProfilePageViewModel();
  private readonly initialPageState: ProfilePageState = this.viewModel.createInitialState();
  @State userId: string = this.initialPageState.userId;
  @State fullName: string = this.initialPageState.fullName;
  @State username: string = this.initialPageState.username;
  @State phoneNumber: string = this.initialPageState.phoneNumber;
  @State avatarPath: string = this.initialPageState.avatarPath;
  @State avatarAnimationPath: string = this.initialPageState.avatarAnimationPath;
  @State isOpeningChat: boolean = false;

  private scroller: Scroller = new Scroller();
  private hasNavigatedToIndex: boolean = false;
  private chatOpenRequestToken: number = 0;

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
      hilog.error(DOMAIN, TAG, 'Failed to redirect UserProfile to Index: %{public}s', String(error));
    }
  }

  /**
   * Reads route params and maps them to one read-only profile-card state.
   */
  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle enter: UserProfile');
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

    this.viewModel.setAuthStateListener((state: string): void => {
      this.redirectToIndexIfUnauthorized(state);
    });
    this.redirectToIndexIfUnauthorized(this.viewModel.getAuthorizationStateName());
  }

  /**
   * Applies one mapped user-profile state to ArkUI-owned fields.
   *
   * @param nextPageState The mapped page state.
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
   * Emits lifecycle log when leaving UserProfile screen.
   */
  aboutToDisappear(): void {
    this.chatOpenRequestToken = this.chatOpenRequestToken + 1;
    this.isOpeningChat = false;
    hilog.info(DOMAIN, TAG, 'Lifecycle leave: UserProfile');
  }

  build() {
    Stack() {
      Image($r('app.media.watch_wallpaper_466'))
        .width('100%')
        .align(Alignment.Center)

      RelativeContainer() {
        ArcList({
          scroller: this.scroller
        }) {
          ProfileCard({
            userId: this.userId,
            fullName: this.fullName,
            username: this.username,
            phoneNumber: this.phoneNumber,
            avatarPath: this.avatarPath,
            avatarAnimationPath: this.avatarAnimationPath
          })
          this.buildChatAction();
          this.buildCallAction();
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)

        ArcScrollBar({ scroller: this.scroller, state: BarState.Auto })

        Text($r('app.string.profile_title'))
          .id('user-profile-header')
          .width('100%')
          .height(40)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .backgroundColor('#D9151A21')
          .alignRules({
            top: { anchor: '__container__', align: VerticalAlign.Top },
            left: { anchor: '__container__', align: HorizontalAlign.Start }
          })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  /**
   * Renders action list item that opens chat with the displayed user.
   */
  @Builder
  private buildChatAction(): void {
    ActionButtonListItem({
      label: $r('app.string.user_profile_action_chat'),
      hasIcon: true,
      iconResource: $r('app.media.profile_chats_icon'),
      buttonColor: $r('app.color.surface_profile_chats_fill'),
      gradientStartColor: $r('app.color.surface_profile_chats_gradient_start'),
      gradientMiddleColor: $r('app.color.surface_profile_chats_gradient_middle'),
      gradientEndColor: $r('app.color.surface_profile_chats_gradient_end'),
      isEnabled: this.viewModel.canOpenUserChat(this.userId) && !this.isOpeningChat,
      onButtonClick: (): void => {
        this.openUserChat();
      }
    });
  }

  /**
   * Renders action list item that starts an outgoing voice call to the displayed user.
   */
  @Builder
  private buildCallAction(): void {
    ActionButtonListItem({
      label: $r('app.string.user_profile_action_call'),
      hasIcon: true,
      iconResource: $r('app.media.profile_call_icon'),
      buttonColor: $r('app.color.surface_profile_call_fill'),
      gradientStartColor: $r('app.color.surface_profile_call_gradient_start'),
      gradientMiddleColor: $r('app.color.surface_profile_call_gradient_middle'),
      gradientEndColor: $r('app.color.surface_profile_call_gradient_end'),
      isEnabled: this.viewModel.canCallUser(this.userId),
      onButtonClick: (): void => {
        this.startOutgoingCall();
      }
    });
  }

  /**
   * Navigates to the outgoing-call screen, which places the call to the displayed user.
   */
  private startOutgoingCall(): void {
    if (!this.viewModel.canCallUser(this.userId)) {
      hilog.warn(DOMAIN, TAG, 'startOutgoingCall ignored: user id not callable (userId=%{public}s)', this.userId);
      return;
    }

    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/CallScreen',
        params: {
          direction: 'outgoing',
          userId: this.userId,
          peerName: this.fullName
        }
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'startOutgoingCall failed: %{public}s', String(error));
    }
  }

  /**
   * Opens chat details for the displayed user.
   */
  private openUserChat(): void {
    if (this.isOpeningChat) {
      return;
    }

    this.isOpeningChat = true;
    this.chatOpenRequestToken = this.chatOpenRequestToken + 1;
    const requestToken = this.chatOpenRequestToken;
    const requestStarted = this.viewModel.requestUserChatRouteParams(
      this.userId,
      this.fullName,
      this.username,
      (routeParams, errorMessage): void => {
        if (requestToken !== this.chatOpenRequestToken) {
          return;
        }
        this.isOpeningChat = false;
        if (!routeParams) {
          hilog.warn(DOMAIN, TAG, 'openUserChat failed: %{public}s', errorMessage);
          return;
        }

        this.openChatDetails(routeParams);
      }
    );
    if (!requestStarted) {
      this.isOpeningChat = false;
    }
  }

  /**
   * Opens ChatDetails with route params returned by TDLib.
   *
   * @param routeParams Real chat route params.
   */
  private openChatDetails(routeParams: ChatRouteParams): void {
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/ChatDetails',
        params: routeParams
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'openChatDetails failed: %{public}s', String(error));
    }
  }
}
