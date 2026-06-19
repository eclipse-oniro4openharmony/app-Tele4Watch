import { hilog } from '@kit.PerformanceAnalysisKit';
import resourceManager from '@ohos.resourceManager';
import { TdMeInfo } from '../models/td/TdViewTypes';
import {
  ArcList,
  ArcListItem,
  ArcScrollBar
} from '@kit.ArkUI';
import { IndexPageMode, IndexPageState } from '../models/auth/IndexPageState';
import { UiTextValue } from '../models/ui/UiTextValue';
import {
  PendingDeeplink,
  deeplinkInbox
} from '../app/DeeplinkInbox';
import { postAuthRouter } from '../app/PostAuthRouter';
import { notificationRuntimeService } from '../services/notifications/NotificationRuntimeService';
import { ActionButtonListItem } from '../ui/ActionButtonListItem';
import { IndexPageViewModel } from '../viewmodel/IndexPageViewModel';
import { resolveString } from '../utils/ResourceTextResolver';
import { resolveUiTextValue } from '../utils/UiTextValueResolver';

const DOMAIN = 0x2026;
const TAG = 'IndexPage';
const AUTH_STATE_READY = 'authorizationStateReady';

@Entry
@Component
struct Index {
  private readonly viewModel: IndexPageViewModel = new IndexPageViewModel();
  private readonly initialPageState: IndexPageState = this.viewModel.createInitialState();
  @State tdlibVersion: string = this.initialPageState.tdlibVersion;
  @State infoText: UiTextValue = this.initialPageState.infoText;
  @State errorText: UiTextValue = this.initialPageState.errorText;
  @State currentAuthState: string = this.initialPageState.currentAuthState;
  @State pageMode: IndexPageMode = this.initialPageState.pageMode;
  @State canChooseQr: boolean = this.initialPageState.canChooseQr;
  @State canChoosePhone: boolean = this.initialPageState.canChoosePhone;

  private scroller: Scroller = new Scroller();
  private bootstrapStartedInUi: boolean = false;
  private hasNavigatedToProfile: boolean = false;
  private hasNavigatedToQrPage: boolean = false;
  private hasNavigatedToPhonePage: boolean = false;

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

  private resolvedTdlibSubtitle(): string {
    if (this.tdlibVersion.length > 0) {
      return this.getString('auth_tdlib_subtitle_format', this.tdlibVersion);
    }
    return this.getString('auth_tdlib_subtitle_unknown');
  }

  private resolvedInfoText(): string {
    const resolved = this.resolveUiText(this.infoText);
    if (resolved.length > 0) {
      return resolved;
    }
    return this.getString('index_info_preparing_telegram_authorization');
  }

  private resolvedErrorText(): string {
    return this.resolveUiText(this.errorText);
  }

  private applyAuthState(state: string): void {
    const authStatePlan = this.viewModel.planAuthStateChange(this.currentPageState(), state);
    this.applyPageState(authStatePlan.nextPageState);
    if (authStatePlan.resetProfileNavigation) {
      this.hasNavigatedToProfile = false;
    }
    if (state === AUTH_STATE_READY) {
      this.requestNotificationsOnce();
    }
    if (!authStatePlan.shouldRestartBootstrap) {
      return;
    }

    this.bootstrapStartedInUi = false;
    this.runAuthBootstrapOnce();
  }

  private runAuthBootstrapOnce(): void {
    if (this.bootstrapStartedInUi) {
      return;
    }

    this.bootstrapStartedInUi = true;
    this.applyPageState(this.viewModel.createBootstrapStartingState(this.currentPageState()));

    try {
      this.viewModel.startAuthorizationBootstrap();
      const version = this.viewModel.getVersion();
      this.applyPageState(this.viewModel.applyTdlibVersion(this.currentPageState(), version));
      this.applyAuthState(this.viewModel.getAuthorizationStateName());
    } catch (error) {
      const errorText = String(error);
      this.bootstrapStartedInUi = false;
      this.applyPageState(this.viewModel.createBootstrapErrorState(this.currentPageState(), errorText));
    }
  }

  private openProfilePage(me: TdMeInfo): void {
    if (this.hasNavigatedToProfile) {
      return;
    }
    this.hasNavigatedToProfile = true;
    void this.openProfilePageAsync(me);
  }

  private async openProfilePageAsync(me: TdMeInfo): Promise<void> {
    try {
      const opened = await postAuthRouter.openProfileRoot(this.getUIContext().getRouter(), me);
      if (opened) {
        return;
      }
      this.hasNavigatedToProfile = false;
      hilog.error(DOMAIN, TAG, 'Failed to open Profile page from Index.');
    } catch (error) {
      this.hasNavigatedToProfile = false;
      hilog.error(DOMAIN, TAG, 'Failed to open Profile page from Index: %{public}s', String(error));
    }
  }

  private openPendingDeeplink(me: TdMeInfo): boolean {
    if (this.hasNavigatedToProfile) {
      return false;
    }
    if (!deeplinkInbox.peek()) {
      return false;
    }

    const deeplink = deeplinkInbox.consume();
    if (!deeplink) {
      return false;
    }

    this.hasNavigatedToProfile = true;
    void this.openPendingDeeplinkAsync(deeplink, me);
    return true;
  }

  private async openPendingDeeplinkAsync(deeplink: PendingDeeplink, me: TdMeInfo): Promise<void> {
    try {
      const opened = await postAuthRouter.openDeeplinkStack(this.getUIContext().getRouter(), me, deeplink);
      if (opened) {
        hilog.info(DOMAIN, TAG, 'Opened cold-start %{public}s deeplink stack for chat %{public}s',
          deeplink.kind,
          deeplink.chatId);
        return;
      }
      this.hasNavigatedToProfile = false;
      deeplinkInbox.put(deeplink);
      hilog.error(DOMAIN, TAG, 'Failed to open cold-start deeplink stack.');
    } catch (error) {
      this.hasNavigatedToProfile = false;
      deeplinkInbox.put(deeplink);
      hilog.error(DOMAIN, TAG, 'Failed to open cold-start deeplink stack: %{public}s', String(error));
    }
  }

  private requestNotificationsOnce(): void {
    notificationRuntimeService.ensureStarted(TAG);
  }

  private openQrLoginPage(): void {
    if (this.hasNavigatedToQrPage) {
      return;
    }
    try {
      this.hasNavigatedToQrPage = true;
      this.hasNavigatedToPhonePage = false;
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/QrLogin'
      });
    } catch (error) {
      this.hasNavigatedToQrPage = false;
      hilog.error(DOMAIN, TAG, 'Failed to open QrLogin page: %{public}s', String(error));
    }
  }

  private openPhoneLoginPage(): void {
    if (this.hasNavigatedToPhonePage) {
      return;
    }
    try {
      this.hasNavigatedToPhonePage = true;
      this.hasNavigatedToQrPage = false;
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/PhoneLogin'
      });
    } catch (error) {
      this.hasNavigatedToPhonePage = false;
      hilog.error(DOMAIN, TAG, 'Failed to open PhoneLogin page: %{public}s', String(error));
    }
  }

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle enter: Index');

    this.bootstrapStartedInUi = false;
    this.hasNavigatedToProfile = false;
    this.hasNavigatedToQrPage = false;
    this.hasNavigatedToPhonePage = false;

    const version = this.viewModel.getVersion();
    this.applyPageState(this.viewModel.applyTdlibVersion(this.currentPageState(), version));

    this.viewModel.setMeListener((me: TdMeInfo): void => {
      if (this.viewModel.getAuthorizationStateName() !== AUTH_STATE_READY) {
        return;
      }
      if (this.hasNavigatedToProfile) {
        return;
      }
      this.requestNotificationsOnce();
      if (this.openPendingDeeplink(me)) {
        return;
      }
      if (deeplinkInbox.peek()) {
        // Profile navigation is already in flight; do not fall through to Profile twice.
        return;
      }
      this.openProfilePage(me);
    });

    this.viewModel.setAuthStateListener((state: string): void => {
      this.applyAuthState(state);
    });

    this.applyAuthState(this.viewModel.getAuthorizationStateName());
    this.runAuthBootstrapOnce();
  }

  private currentPageState(): IndexPageState {
    return {
      tdlibVersion: this.tdlibVersion,
      currentAuthState: this.currentAuthState,
      infoText: this.infoText,
      errorText: this.errorText,
      pageMode: this.pageMode,
      canChooseQr: this.canChooseQr,
      canChoosePhone: this.canChoosePhone
    };
  }

  private applyPageState(nextPageState: IndexPageState): void {
    this.tdlibVersion = nextPageState.tdlibVersion;
    this.currentAuthState = nextPageState.currentAuthState;
    this.infoText = nextPageState.infoText;
    this.errorText = nextPageState.errorText;
    this.pageMode = nextPageState.pageMode;
    this.canChooseQr = nextPageState.canChooseQr;
    this.canChoosePhone = nextPageState.canChoosePhone;
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle leave: Index');
  }

  @Builder
  private buildStatusCard(): void {
    ArcListItem() {
      Column({ space: 10 }) {
        Column({ space: 2 }) {
          Text($r('app.string.index_app_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .width('100%')

          Text(this.resolvedTdlibSubtitle())
            .fontSize(11)
            .fontColor('#B0B0B0')
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .width('100%')
        }
        .width('100%')

        if (this.pageMode === IndexPageMode.Loading) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(18)
              .height(18)
            Text(this.resolvedInfoText())
              .fontSize(9)
              .fontColor('#fbfbfb')
              .maxLines(2)
          }
          .height(26)
        } else if (this.pageMode === IndexPageMode.Error) {
          Column({ space: 6 }) {
            Text($r('app.string.common_error_label'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Text(this.resolvedErrorText())
              .fontSize(9)
              .fontColor('#F5B7B7')
              .textAlign(TextAlign.Center)
              .maxLines(3)
              .width('100%')
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor('#4A2323')
          .borderRadius(14)
        } else {
          Text(this.resolvedInfoText())
            .fontSize(9)
            .fontColor('#fbfbfb')
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .width('100%')
        }
      }
      .width('85%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .margin({ top: 4, bottom: 4 })
      .backgroundColor('#00000000')
      .opacity(0.8)
      .linearGradient({
        direction: GradientDirection.LeftTop,
        colors: [['#ff0c0b0b', 0.0], ['#ff4c4c4c', 1.0]]
      })
      .borderRadius(32)
    }
  }

  @Builder
  private buildQrChoiceItem(): void {
    ActionButtonListItem({
      label: $r('app.string.index_action_qr_login'),
      buttonColor: $r('app.color.surface_auth_qr_fill'),
      gradientStartColor: $r('app.color.surface_auth_qr_gradient_start'),
      gradientMiddleColor: $r('app.color.surface_auth_qr_gradient_middle'),
      gradientEndColor: $r('app.color.surface_auth_qr_gradient_end'),
      isEnabled: this.canChooseQr,
      onButtonClick: (): void => {
        if (!this.canChooseQr) {
          return;
        }
        this.openQrLoginPage();
      }
    });
  }

  @Builder
  private buildPhoneChoiceItem(): void {
    ActionButtonListItem({
      label: $r('app.string.index_action_phone_login'),
      buttonColor: $r('app.color.surface_auth_phone_fill'),
      gradientStartColor: $r('app.color.surface_auth_phone_gradient_start'),
      gradientMiddleColor: $r('app.color.surface_auth_phone_gradient_middle'),
      gradientEndColor: $r('app.color.surface_auth_phone_gradient_end'),
      isEnabled: this.canChoosePhone,
      onButtonClick: (): void => {
        if (!this.canChoosePhone) {
          return;
        }
        this.openPhoneLoginPage();
      }
    });
  }

  build() {
    Stack() {
      Image($r('app.media.watch_wallpaper_466'))
        .width('100%')
        .align(Alignment.Center)

      ArcList({
        scroller: this.scroller
      }) {
        this.buildStatusCard();

        if (this.viewModel.shouldShowAuthChoices(this.currentPageState())) {
          this.buildQrChoiceItem();
          this.buildPhoneChoiceItem();
        }
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)

      ArcScrollBar({ scroller: this.scroller, state: BarState.Auto })
    }
    .width('100%')
    .height('100%')
  }
}
