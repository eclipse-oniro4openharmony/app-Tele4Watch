import { hilog } from '@kit.PerformanceAnalysisKit';
import resourceManager from '@ohos.resourceManager';
import {
  ArcList,
  ArcListItem,
  ArcScrollBar
} from '@kit.ArkUI';
import { LogoutPageMode, LogoutPageState } from '../models/auth/LogoutPageState';
import { UiTextValue } from '../models/ui/UiTextValue';
import { notificationRuntimeService } from '../services/notifications/NotificationRuntimeService';
import { ConfirmActionDialog } from '../ui/ConfirmActionDialog';
import { GradientActionButton } from '../ui/GradientActionButton';
import { LogoutPageViewModel } from '../viewmodel/LogoutPageViewModel';
import { resolveString } from '../utils/ResourceTextResolver';
import { resolveUiTextValue } from '../utils/UiTextValueResolver';

const DOMAIN = 0x2026;
const TAG = 'LogoutPage';

@Entry
@Component
struct Logout {
  private readonly viewModel: LogoutPageViewModel = new LogoutPageViewModel();
  private readonly initialPageState: LogoutPageState = this.viewModel.createInitialState();
  @State currentAuthState: string = this.initialPageState.currentAuthState;
  @State pageMode: LogoutPageMode = this.initialPageState.pageMode;
  @State infoText: UiTextValue = this.initialPageState.infoText;
  @State errorText: UiTextValue = this.initialPageState.errorText;
  @State showLogoutConfirm: boolean = this.initialPageState.confirmVisible;

  private scroller: Scroller = new Scroller();
  private hasNavigatedToIndex: boolean = false;

  private getResourceManager(): resourceManager.ResourceManager {
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      throw new Error('Host context unavailable.');
    }
    return hostContext.resourceManager;
  }

  private getString(resourceName: string, ...args: Array<string | number>): string {
    return resolveString(this.getResourceManager(), resourceName, ...args);
  }

  private resolveUiText(textValue: UiTextValue): string {
    return resolveUiTextValue(this.getResourceManager(), textValue);
  }

  private resolvedInfoText(): string {
    const resolved = this.resolveUiText(this.infoText);
    if (resolved.length > 0) {
      return resolved;
    }
    return this.getString('logout_info_isolated');
  }

  private resolvedErrorText(): string {
    return this.resolveUiText(this.errorText);
  }

  private applyAuthState(state: string): void {
    const authStatePlan = this.viewModel.planAuthStateChange(this.currentPageState(), state);
    this.applyPageState(authStatePlan.nextPageState);
    if (authStatePlan.shouldHideConfirm) {
      this.showLogoutConfirm = false;
    }
    if (authStatePlan.shouldNavigateToIndex) {
      this.navigateToIndexAfterLogout();
    }
  }

  private openLogoutConfirm(): void {
    if (this.currentAuthState !== 'authorizationStateReady') {
      return;
    }
    this.applyPageState(this.viewModel.showConfirmDialog(this.currentPageState()));
  }

  private cancelLogoutConfirm(): void {
    this.applyPageState(this.viewModel.hideConfirmDialog(this.currentPageState()));
  }

  private confirmLogout(): void {
    if (this.currentAuthState !== 'authorizationStateReady') {
      this.applyPageState(this.viewModel.hideConfirmDialog(this.currentPageState()));
      return;
    }
    this.applyPageState(this.viewModel.hideConfirmDialog(this.currentPageState()));
    notificationRuntimeService.releaseForLogout();
    this.viewModel.logout();
    this.applyPageState(this.viewModel.createLogoutRequestedState(this.currentPageState()));
  }

  private navigateToIndexAfterLogout(): void {
    if (this.hasNavigatedToIndex) {
      return;
    }
    try {
      this.hasNavigatedToIndex = true;
      this.getUIContext().getRouter().replaceUrl({
        url: 'pages/Index'
      });
    } catch (error) {
      this.hasNavigatedToIndex = false;
      hilog.error(DOMAIN, TAG, 'Failed to navigate to Index after logout: %{public}s', String(error));
    }
  }

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle enter: Logout');
    this.hasNavigatedToIndex = false;

    this.viewModel.setAuthStateListener((state: string): void => {
      this.applyAuthState(state);
    });

    this.applyAuthState(this.viewModel.getAuthorizationStateName());
  }

  private currentPageState(): LogoutPageState {
    return {
      currentAuthState: this.currentAuthState,
      pageMode: this.pageMode,
      infoText: this.infoText,
      errorText: this.errorText,
      confirmVisible: this.showLogoutConfirm,
      actionEnabled: this.currentAuthState === 'authorizationStateReady'
    };
  }

  private applyPageState(nextPageState: LogoutPageState): void {
    this.currentAuthState = nextPageState.currentAuthState;
    this.pageMode = nextPageState.pageMode;
    this.infoText = nextPageState.infoText;
    this.errorText = nextPageState.errorText;
    this.showLogoutConfirm = nextPageState.confirmVisible;
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle leave: Logout');
  }

  @Builder
  private buildLogoutCard(): void {
    ArcListItem() {
      Column({ space: 10 }) {
        if (this.pageMode === LogoutPageMode.Loading) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(18)
              .height(18)
            Text(this.resolvedInfoText())
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(2)
          }
          .height(26)
        } else if (this.pageMode === LogoutPageMode.Error) {
          Column({ space: 6 }) {
            Text($r('app.string.logout_error_title'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(this.resolvedErrorText())
              .fontSize(9)
              .fontColor($r('app.color.text_error_secondary'))
              .textAlign(TextAlign.Center)
              .maxLines(3)
              .width('100%')
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.surface_error_panel_background'))
          .borderRadius(14)
        } else {
          Text(this.resolvedInfoText())
            .fontSize(9)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .width('100%')
        }

        GradientActionButton({
          label: $r('app.string.logout_request'),
          buttonColor: $r('app.color.surface_profile_logout_fill'),
          gradientStartColor: $r('app.color.surface_profile_logout_gradient_start'),
          gradientMiddleColor: $r('app.color.surface_profile_logout_gradient_middle'),
          gradientEndColor: $r('app.color.surface_profile_logout_gradient_end'),
          isEnabled: this.currentPageState().actionEnabled,
          buttonHeight: 36,
          onButtonClick: (): void => {
            this.openLogoutConfirm();
          }
        })
      }
      .width('85%')
      .padding({ left: 10, right: 10, top: 10, bottom: 10 })
      .linearGradient({
        direction: GradientDirection.LeftTop,
        colors: [
          [$r('app.color.surface_list_card_gradient_start'), 0.0],
          [$r('app.color.surface_list_card_gradient_end'), 1.0]
        ]
      })
      .shadow({
        color: $r('app.color.surface_card_shadow'),
        radius: 10,
        offsetX: 0,
        offsetY: 3
      })
      .borderRadius(32)
    }
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
          this.buildLogoutCard();
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)

        ArcScrollBar({ scroller: this.scroller, state: BarState.Auto })

        Text($r('app.string.logout_title'))
          .id('logout-header')
          .width('100%')
          .height(40)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.surface_page_header_background'))
          .alignRules({
            top: { anchor: '__container__', align: VerticalAlign.Top },
            left: { anchor: '__container__', align: HorizontalAlign.Start }
          })
      }
      .width('100%')
      .height('100%')

      if (this.showLogoutConfirm) {
        ConfirmActionDialog({
          titleText: $r('app.string.logout_confirm_title'),
          messageText: $r('app.string.logout_confirm_message'),
          cancelLabel: $r('app.string.logout_confirm_cancel'),
          confirmLabel: $r('app.string.logout_confirm_confirm'),
          cancelButtonColor: $r('app.color.bg_action_enabled'),
          confirmButtonColor: $r('app.color.surface_profile_logout_fill'),
          confirmGradientStartColor: $r('app.color.surface_profile_logout_gradient_start'),
          confirmGradientMiddleColor: $r('app.color.surface_profile_logout_gradient_middle'),
          confirmGradientEndColor: $r('app.color.surface_profile_logout_gradient_end'),
          onCancelButtonClick: (): void => {
            this.cancelLogoutConfirm();
          },
          onConfirmButtonClick: (): void => {
            this.confirmLogout();
          }
        });
      }
    }
    .width('100%')
    .height('100%')
  }
}
