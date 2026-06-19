import { hilog } from '@kit.PerformanceAnalysisKit';
import resourceManager from '@ohos.resourceManager';
import { TdMeInfo } from '../models/td/TdViewTypes';
import {
  ArcList,
  ArcListItem,
  ArcScrollBar
} from '@kit.ArkUI';
import { CodeLoginPageMode, CodeLoginPageState } from '../models/auth/CodeLoginPageState';
import { UiTextValue } from '../models/ui/UiTextValue';
import {
  PendingDeeplink,
  deeplinkInbox
} from '../app/DeeplinkInbox';
import { postAuthRouter } from '../app/PostAuthRouter';
import { notificationRuntimeService } from '../services/notifications/NotificationRuntimeService';
import { ArcSubmitButton } from '../ui/ArcSubmitButton';
import { CodeLoginPageViewModel, CodeLoginRouteTarget } from '../viewmodel/CodeLoginPageViewModel';
import { resolveString } from '../utils/ResourceTextResolver';
import { resolveUiTextValue } from '../utils/UiTextValueResolver';

const DOMAIN = 0x2026;
const TAG = 'CodeLoginPage';

@Entry
@Component
struct CodeLogin {
  private readonly viewModel: CodeLoginPageViewModel = new CodeLoginPageViewModel();
  private readonly initialPageState: CodeLoginPageState = this.viewModel.createInitialState();
  @State currentAuthState: string = this.initialPageState.currentAuthState;
  @State loginCode: string = this.initialPageState.loginCodeInput;
  @State pageMode: CodeLoginPageMode = this.initialPageState.pageMode;
  @State infoText: UiTextValue = this.initialPageState.infoText;
  @State errorText: UiTextValue = this.initialPageState.errorText;
  @State expectedCodeLength: number = this.initialPageState.expectedCodeLength;
  @State submitEnabled: boolean = this.initialPageState.submitEnabled;
  @State hasNavigatedToProfile: boolean = false;
  @State hasNavigatedToPhonePage: boolean = false;

  private scroller: Scroller = new Scroller();

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
    return this.getString('code_login_info_preparing');
  }

  private resolvedErrorText(): string {
    return this.resolveUiText(this.errorText);
  }

  private submitCode(): void {
    const submitPlan = this.viewModel.planCodeSubmit(this.currentPageState());
    this.applyPageState(submitPlan.nextPageState);
    if (!submitPlan.shouldSubmit) {
      return;
    }
    this.viewModel.submitCode(submitPlan.loginCodeInput);
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
      hilog.error(DOMAIN, TAG, 'Failed to open Profile page from CodeLogin.');
    } catch (error) {
      this.hasNavigatedToProfile = false;
      hilog.error(DOMAIN, TAG, 'Failed to open Profile page from CodeLogin: %{public}s', String(error));
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
        hilog.info(DOMAIN, TAG, 'Opened pending %{public}s deeplink stack after code login for chat %{public}s',
          deeplink.kind,
          deeplink.chatId);
        return;
      }
      this.hasNavigatedToProfile = false;
      deeplinkInbox.put(deeplink);
      hilog.error(DOMAIN, TAG, 'Failed to open pending deeplink stack after code login.');
    } catch (error) {
      this.hasNavigatedToProfile = false;
      deeplinkInbox.put(deeplink);
      hilog.error(DOMAIN, TAG, 'Failed to open pending deeplink stack after code login: %{public}s',
        String(error));
    }
  }

  private openPhoneLoginPage(): void {
    if (this.hasNavigatedToPhonePage) {
      return;
    }
    try {
      this.hasNavigatedToPhonePage = true;
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/PhoneLogin'
      });
    } catch (error) {
      this.hasNavigatedToPhonePage = false;
      hilog.error(DOMAIN, TAG, 'Failed to open PhoneLogin page from CodeLogin: %{public}s', String(error));
    }
  }

  private applyAuthState(state: string): void {
    const authStatePlan = this.viewModel.planAuthStateChange(this.currentPageState(), state);
    this.applyPageState(authStatePlan.nextPageState);
    if (authStatePlan.resetProfileNavigation) {
      this.hasNavigatedToProfile = false;
    }
    if (authStatePlan.resetPhoneNavigation) {
      this.hasNavigatedToPhonePage = false;
    }
    if (authStatePlan.nextRoute === CodeLoginRouteTarget.PhoneLogin) {
      this.openPhoneLoginPage();
    }
    if (state === 'authorizationStateReady') {
      notificationRuntimeService.ensureStarted(TAG);
    }
  }

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle enter: CodeLogin');
    this.hasNavigatedToProfile = false;
    this.hasNavigatedToPhonePage = false;

    this.viewModel.setAuthStateListener((state: string): void => {
      this.applyAuthState(state);
    });

    this.viewModel.setMeListener((me: TdMeInfo): void => {
      if (this.viewModel.getAuthorizationStateName() !== 'authorizationStateReady') {
        return;
      }
      if (this.openPendingDeeplink(me)) {
        return;
      }
      this.openProfilePage(me);
    });

    this.viewModel.setAuthErrorListener((extra: string, code: number, message: string): void => {
      if (extra !== 'auth:code') {
        return;
      }
      if (this.currentAuthState !== 'authorizationStateWaitCode') {
        return;
      }
      this.applyPageState(this.viewModel.createAuthErrorState(this.currentPageState(), code, message));
    });

    this.applyAuthState(this.viewModel.getAuthorizationStateName());
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle leave: CodeLogin');
  }

  private currentPageState(): CodeLoginPageState {
    return {
      currentAuthState: this.currentAuthState,
      loginCodeInput: this.loginCode,
      pageMode: this.pageMode,
      infoText: this.infoText,
      errorText: this.errorText,
      expectedCodeLength: this.expectedCodeLength,
      submitEnabled: this.submitEnabled
    };
  }

  private applyPageState(nextPageState: CodeLoginPageState): void {
    this.currentAuthState = nextPageState.currentAuthState;
    this.loginCode = nextPageState.loginCodeInput;
    this.pageMode = nextPageState.pageMode;
    this.infoText = nextPageState.infoText;
    this.errorText = nextPageState.errorText;
    this.expectedCodeLength = nextPageState.expectedCodeLength;
    this.submitEnabled = nextPageState.submitEnabled;
  }

  @Builder
  private buildCodeCard(): void {
    ArcListItem() {
      Column({ space: 8 }) {
        Row() {
          TextInput({ text: this.loginCode, placeholder: $r('app.string.code_login_placeholder') })
            .onChange((value: string) => {
              this.applyPageState(this.viewModel.updateCodeInput(this.currentPageState(), value));
              if (this.currentAuthState === 'authorizationStateWaitCode') {
                this.applyPageState(this.viewModel.applyAuthState(this.currentPageState(), this.currentAuthState));
              }
            })
            .width('100%')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_secondary'))
            .placeholderFont({ size: 9, weight: FontWeight.Regular })
        }
        .width('100%')

        if (this.pageMode === CodeLoginPageMode.Loading) {
          Row() {
            LoadingProgress()
              .width(18)
              .height(18)
            Text(this.resolvedInfoText())
              .fontSize(10)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
          }
          .height(26)
        } else if (this.pageMode === CodeLoginPageMode.Error) {
          Column({ space: 6 }) {
            Text($r('app.string.code_login_error_title'))
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
      }
      .width('85%')
      .padding({ left: 12, right: 12, top: 12, bottom: 16 })
      .opacity(0.85)
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

  @Builder
  private buildSubmitButton(): void {
    ArcSubmitButton({
      label: $r('app.string.code_login_submit'),
      isEnabled: this.submitEnabled,
      enabledId: 'submitCodeButtonEnabled',
      disabledId: 'submitCodeButtonDisabled',
      onSubmitButtonClick: (): void => {
        this.submitCode();
      }
    })
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
          this.buildCodeCard();
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)

        ArcScrollBar({ scroller: this.scroller, state: BarState.Auto })

        Text($r('app.string.code_login_title'))
          .id('code-login-header')
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

        this.buildSubmitButton()
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
