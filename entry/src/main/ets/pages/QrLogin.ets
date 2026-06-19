import { hilog } from '@kit.PerformanceAnalysisKit';
import resourceManager from '@ohos.resourceManager';
import { TdMeInfo } from '../models/td/TdViewTypes';
import {
  ArcList,
  ArcListItem,
  ArcScrollBar
} from '@kit.ArkUI';
import { QrLoginPageMode, QrLoginPageState } from '../models/auth/QrLoginPageState';
import { UiTextValue } from '../models/ui/UiTextValue';
import {
  PendingDeeplink,
  deeplinkInbox
} from '../app/DeeplinkInbox';
import { postAuthRouter } from '../app/PostAuthRouter';
import { notificationRuntimeService } from '../services/notifications/NotificationRuntimeService';
import { QrLoginPageViewModel } from '../viewmodel/QrLoginPageViewModel';
import { resolveUiTextValue } from '../utils/UiTextValueResolver';

const DOMAIN = 0x2026;
const TAG = 'QrLoginPage';

@Entry
@Component
struct QrLogin {
  private readonly viewModel: QrLoginPageViewModel = new QrLoginPageViewModel();
  private readonly initialPageState: QrLoginPageState = this.viewModel.createInitialState();
  @State currentAuthState: string = this.initialPageState.currentAuthState;
  @State qrAuthLink: string = this.initialPageState.qrAuthLink;
  @State lastNonEmptyQrAuthLink: string = this.initialPageState.lastNonEmptyQrAuthLink;
  @State qrAuthLinkUpdatedAtMs: number = this.initialPageState.qrAuthLinkUpdatedAtMs;
  @State qrUiNowMs: number = this.initialPageState.qrUiNowMs;
  @State pageMode: QrLoginPageMode = this.initialPageState.pageMode;
  @State infoText: UiTextValue = this.initialPageState.infoText;
  @State errorText: UiTextValue = this.initialPageState.errorText;
  @State hasNavigatedToProfile: boolean = false;

  private qrScroller: Scroller = new Scroller();
  private qrUiTickerId: number = -1;
  private qrPreferenceRequested: boolean = false;

  private getResourceManager(): resourceManager.ResourceManager {
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      throw new Error('Host context unavailable.');
    }
    return hostContext.resourceManager;
  }

  private resolveUiText(textValue: UiTextValue): string {
    return resolveUiTextValue(this.getResourceManager(), textValue);
  }

  private resolvedInfoText(): string {
    const resolved = this.resolveUiText(this.infoText);
    if (resolved.length > 0) {
      return resolved;
    }
    return this.resolveUiText(this.viewModel.getQrFreshnessText(this.currentPageState()));
  }

  private resolvedErrorText(): string {
    return this.resolveUiText(this.errorText);
  }

  private startQrUiTicker(): void {
    if (this.qrUiTickerId >= 0) {
      return;
    }
    this.applyPageState(this.viewModel.updateQrUiNow(this.currentPageState(), Date.now()));
    this.qrUiTickerId = setInterval((): void => {
      this.applyPageState(this.viewModel.updateQrUiNow(this.currentPageState(), Date.now()));
    }, 1000) as number;
  }

  private stopQrUiTicker(): void {
    if (this.qrUiTickerId < 0) {
      return;
    }
    clearInterval(this.qrUiTickerId);
    this.qrUiTickerId = -1;
  }

  private openProfile(me: TdMeInfo): void {
    if (this.hasNavigatedToProfile) {
      return;
    }
    this.hasNavigatedToProfile = true;
    void this.openProfileAsync(me);
  }

  private async openProfileAsync(me: TdMeInfo): Promise<void> {
    try {
      const opened = await postAuthRouter.openProfileRoot(this.getUIContext().getRouter(), me);
      if (opened) {
        return;
      }
      this.hasNavigatedToProfile = false;
      hilog.error(DOMAIN, TAG, 'Failed to open Profile page from QrLogin.');
    } catch (error) {
      this.hasNavigatedToProfile = false;
      hilog.error(DOMAIN, TAG, 'Failed to open Profile page from QrLogin: %{public}s', String(error));
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
        hilog.info(DOMAIN, TAG, 'Opened pending %{public}s deeplink stack after QR login for chat %{public}s',
          deeplink.kind,
          deeplink.chatId);
        return;
      }
      this.hasNavigatedToProfile = false;
      deeplinkInbox.put(deeplink);
      hilog.error(DOMAIN, TAG, 'Failed to open pending deeplink stack after QR login.');
    } catch (error) {
      this.hasNavigatedToProfile = false;
      deeplinkInbox.put(deeplink);
      hilog.error(DOMAIN, TAG, 'Failed to open pending deeplink stack after QR login: %{public}s', String(error));
    }
  }

  private applyAuthState(state: string): void {
    const authStatePlan = this.viewModel.planAuthStateChange(
      this.currentPageState(),
      state,
      this.qrPreferenceRequested
    );
    if (authStatePlan.resetPreferenceRequest) {
      this.qrPreferenceRequested = false;
    }
    this.applyPageState(authStatePlan.nextPageState);
    if (authStatePlan.shouldRequestQrPreference) {
      this.qrPreferenceRequested = this.viewModel.requestQrLoginPreference();
      if (!this.qrPreferenceRequested) {
        this.applyPageState(this.viewModel.createQrPreferenceRequestErrorState(this.currentPageState()));
      }
    }
    if (state === 'authorizationStateReady') {
      notificationRuntimeService.ensureStarted(TAG);
    }
  }

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle enter: QrLogin');
    this.hasNavigatedToProfile = false;
    this.qrPreferenceRequested = false;
    this.startQrUiTicker();

    this.applyPageState(this.viewModel.applyQrLinkUpdate(
      this.currentPageState(),
      this.viewModel.getQrAuthLink(),
      this.viewModel.getQrAuthLinkUpdatedAtMs()
    ));

    this.viewModel.setAuthStateListener((state: string): void => {
      this.applyAuthState(state);
    });

    this.viewModel.setQrAuthLinkListener((link: string, updatedAtMs: number): void => {
      if (link.length === 0
        && this.currentAuthState === 'authorizationStateReady'
        && this.qrAuthLink.length > 0) {
        return;
      }

      this.applyPageState(this.viewModel.applyQrLinkUpdate(this.currentPageState(), link, updatedAtMs));
      if (this.currentAuthState === 'authorizationStateReady') {
        this.applyPageState(this.viewModel.applyAuthState(this.currentPageState(), this.currentAuthState));
      }
    });

    this.viewModel.setMeListener((me: TdMeInfo): void => {
      if (this.viewModel.getAuthorizationStateName() !== 'authorizationStateReady') {
        return;
      }
      if (this.openPendingDeeplink(me)) {
        return;
      }
      this.openProfile(me);
    });

    this.applyAuthState(this.viewModel.getAuthorizationStateName());
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle leave: QrLogin');
    this.stopQrUiTicker();
  }

  private currentPageState(): QrLoginPageState {
    return {
      currentAuthState: this.currentAuthState,
      qrAuthLink: this.qrAuthLink,
      lastNonEmptyQrAuthLink: this.lastNonEmptyQrAuthLink,
      qrAuthLinkUpdatedAtMs: this.qrAuthLinkUpdatedAtMs,
      qrUiNowMs: this.qrUiNowMs,
      pageMode: this.pageMode,
      infoText: this.infoText,
      errorText: this.errorText
    };
  }

  private applyPageState(nextPageState: QrLoginPageState): void {
    this.currentAuthState = nextPageState.currentAuthState;
    this.qrAuthLink = nextPageState.qrAuthLink;
    this.lastNonEmptyQrAuthLink = nextPageState.lastNonEmptyQrAuthLink;
    this.qrAuthLinkUpdatedAtMs = nextPageState.qrAuthLinkUpdatedAtMs;
    this.qrUiNowMs = nextPageState.qrUiNowMs;
    this.pageMode = nextPageState.pageMode;
    this.infoText = nextPageState.infoText;
    this.errorText = nextPageState.errorText;
  }

  @Builder
  private buildQrCard(): void {
    ArcListItem() {
      Column({ space: 10 }) {
        if (this.pageMode === QrLoginPageMode.Result
          && this.viewModel.getRenderableQrLink(this.currentPageState()).length > 0) {
          QRCode(this.viewModel.getRenderableQrLink(this.currentPageState()))
            .width(128)
            .height(128)
            .backgroundColor('#FFFFFF')
            .padding(8)
            .borderRadius(12)
        } else if (this.pageMode === QrLoginPageMode.Error) {
          Column({ space: 6 }) {
            Text($r('app.string.qr_login_error_title'))
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
          .width(128)
          .height(128)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 8, right: 8 })
          .backgroundColor('#4A2323')
          .borderRadius(12)
        } else {
          Column({ space: 6 }) {
            LoadingProgress()
              .width(24)
              .height(24)
            Text(this.resolvedInfoText())
              .fontSize(10)
              .fontColor('#7A7A7A')
          }
          .width(128)
          .height(128)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor('#F4F4F4')
          .borderRadius(12)
        }

        Text($r('app.string.qr_login_instruction'))
          .fontSize(8)
          .fontColor('#EEEEEE')
          .textAlign(TextAlign.Center)
          .maxLines(3)
          .width('100%')
      }
      .width('85%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .backgroundColor('#D9151A21')
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
          scroller: this.qrScroller
        }) {
          this.buildQrCard();
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)

        ArcScrollBar({ scroller: this.qrScroller, state: BarState.Auto })

        Text($r('app.string.qr_login_title'))
          .id('qr-login-header')
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
}
