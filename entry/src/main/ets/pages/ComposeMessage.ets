import { hilog } from '@kit.PerformanceAnalysisKit';
import resourceManager from '@ohos.resourceManager';
import { ComposeMessagePageState } from '../models/chat/ComposeMessagePageState';
import { UiTextValue, createEmptyUiTextValue, createResourceUiText } from '../models/ui/UiTextValue';
import { MessageComposer } from '../ui/MessageComposer';
import { ComposeMessagePageViewModel } from '../viewmodel/ComposeMessagePageViewModel';
import { resolveUiTextValue } from '../utils/UiTextValueResolver';

const DOMAIN = 0x2026;
const TAG = 'ComposeMessagePage';

interface ComposeMessageParams {
  chatId?: string;
  chatTitle?: string;
  chatUsername?: string;
}

@Entry
@Component
struct ComposeMessage {
  private readonly viewModel: ComposeMessagePageViewModel = new ComposeMessagePageViewModel();
  private readonly initialPageState: ComposeMessagePageState = this.viewModel.createInitialState();
  @State chatId: string = this.initialPageState.chatId;
  @State chatTitle: string = this.initialPageState.chatTitle;
  @State chatUsername: string = this.initialPageState.chatUsername;
  @State draftMessage: string = this.initialPageState.draftMessage;
  @State isSendingMessage: boolean = this.initialPageState.isSendingMessage;
  @State sendErrorText: UiTextValue = this.initialPageState.sendErrorText;
  private hasNavigatedToIndex: boolean = false;

  private getResourceManager(): resourceManager.ResourceManager {
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      throw new Error('Host context unavailable.');
    }
    return hostContext.resourceManager;
  }

  private resolvedSendErrorText(): string {
    return resolveUiTextValue(this.getResourceManager(), this.sendErrorText);
  }

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
      hilog.error(DOMAIN, TAG, 'Failed to redirect ComposeMessage to Index: %{public}s', String(error));
    }
  }

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle enter: ComposeMessage');
    this.hasNavigatedToIndex = false;
    const params = this.getUIContext().getRouter().getParams() as ComposeMessageParams;
    this.applyPageState(this.viewModel.applyRoute(
      this.currentPageState(),
      typeof params.chatId === 'string' ? params.chatId : '',
      typeof params.chatTitle === 'string' ? params.chatTitle : '',
      typeof params.chatUsername === 'string' ? params.chatUsername : ''
    ));

    this.viewModel.setMessageSendResultListener((chatId: string, ok: boolean, errorMessage: string): void => {
      if (chatId !== this.chatId) {
        return;
      }

      if (ok) {
        this.applyPageState(this.viewModel.createSendSuccessState(this.currentPageState()));
        this.returnToChatDetails();
        return;
      }
      this.applyPageState(this.viewModel.createSendErrorState(this.currentPageState(), errorMessage));
    });

    this.viewModel.setAuthStateListener((state: string): void => {
      this.redirectToIndexIfUnauthorized(state);
    });
    this.redirectToIndexIfUnauthorized(this.viewModel.getAuthorizationStateName());
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle leave: ComposeMessage');
    this.viewModel.clearMessageSendResultListener();
  }

  private submitMessage(): void {
    const sendPlan = this.viewModel.planMessageSend(this.currentPageState());
    this.applyPageState(sendPlan.nextPageState);
    if (!sendPlan.shouldSend) {
      return;
    }

    const started = this.viewModel.sendChatTextMessage(sendPlan.chatId, sendPlan.messageText);
    if (!started) {
      this.applyPageState(this.viewModel.createValidationErrorState(
        this.currentPageState(),
        createResourceUiText('compose_error_send_unavailable')
      ));
    }
  }

  private currentPageState(): ComposeMessagePageState {
    return {
      chatId: this.chatId,
      chatTitle: this.chatTitle,
      chatUsername: this.chatUsername,
      draftMessage: this.draftMessage,
      isSendingMessage: this.isSendingMessage,
      sendErrorText: this.sendErrorText,
      sendEnabled: !this.isSendingMessage && this.draftMessage.trim().length > 0
    };
  }

  private applyPageState(nextPageState: ComposeMessagePageState): void {
    this.chatId = nextPageState.chatId;
    this.chatTitle = nextPageState.chatTitle;
    this.chatUsername = nextPageState.chatUsername;
    this.draftMessage = nextPageState.draftMessage;
    this.isSendingMessage = nextPageState.isSendingMessage;
    this.sendErrorText = nextPageState.sendErrorText;
  }

  private returnToChatDetails(): void {
    const safeChatId = this.chatId.trim();
    if (safeChatId.length > 0) {
      this.viewModel.requestChatHistory(safeChatId, 50);
    }

    try {
      this.getUIContext().getRouter().back();
      return;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'router.back failed, fallback push: %{public}s', String(error));
    }

    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/ChatDetails',
        params: {
          chatId: this.chatId,
          chatTitle: this.chatTitle,
          chatUsername: this.chatUsername
        }
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'returnToChatDetails failed: %{public}s', String(error));
    }
  }

  build() {
    Stack() {
      Image($r('app.media.watch_wallpaper_466'))
        .width('100%')
        .align(Alignment.Center)

      RelativeContainer() {
        Column({ space: 1 }) {
          Text($r('app.string.compose_title'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .width('100%')

          Text(this.chatTitle)
            .fontSize(9)
            .fontColor('#CCD8E6')
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .width('100%')
        }
        .id('compose-message-header')
        .width('100%')
        .height(36)
        .padding({ left: 12, right: 12, top: 2, bottom: 2 })
        .backgroundColor('#D9151A21')
        .alignRules({
          top: { anchor: '__container__', align: VerticalAlign.Top },
          left: { anchor: '__container__', align: HorizontalAlign.Start }
        })

        Column() {
          MessageComposer({
            draftMessage: this.draftMessage,
            isSendingMessage: this.isSendingMessage,
            sendErrorText: this.resolvedSendErrorText(),
            canSendMessage: this.currentPageState().sendEnabled,
            placeholderText: $r('app.string.message_composer_placeholder'),
            onDraftChange: (value: string): void => {
              this.applyPageState(this.viewModel.updateDraftMessage(this.currentPageState(), value));
            },
            onClearError: (): void => {
              this.applyPageState(this.viewModel.createValidationErrorState(
                this.currentPageState(),
                createEmptyUiTextValue()
              ));
            },
            onSendClick: (): void => {
              this.submitMessage();
            }
          })
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .padding({ top: 40, bottom: 8 })
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
