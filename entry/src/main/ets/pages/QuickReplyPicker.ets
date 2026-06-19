import { promptAction, ArcList, ArcScrollBar } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import resourceManager from '@ohos.resourceManager';
import {
  QuickReplyPickerPageMode,
  QuickReplyPickerPageState
} from '../models/quickreply/QuickReplyPickerPageState';
import {
  QuickReplyPickerSource,
  QuickReplyTemplate
} from '../models/quickreply/QuickReplyTemplate';
import { UiTextValue, createEmptyUiTextValue } from '../models/ui/UiTextValue';
import { QuickReplyListItem } from '../ui/QuickReplyListItem';
import { QuickReplyPickerViewModel } from '../viewmodel/QuickReplyPickerViewModel';
import { resolveUiTextValue } from '../utils/UiTextValueResolver';

const DOMAIN = 0x2026;
const TAG = 'QuickReplyPickerPage';

interface QuickReplyPickerParams {
  chatId?: string;
  notificationId?: number;
  source?: string;
}

@Entry
@Component
struct QuickReplyPicker {
  @State chatId: string = '';
  @State notificationId?: number = undefined;
  @State source: QuickReplyPickerSource = 'notification';
  @State templates: QuickReplyTemplate[] = [];
  @State pageMode: QuickReplyPickerPageMode = QuickReplyPickerPageMode.Idle;
  @State isLoading: boolean = false;
  @State isSending: boolean = false;
  @State selectedTemplateId: string = '';
  @State statusText: UiTextValue = createEmptyUiTextValue();
  @State errorText: UiTextValue = createEmptyUiTextValue();
  @State canPickTemplate: boolean = false;
  @State shouldClose: boolean = false;
  @State notificationCancelled: boolean = false;

  private viewModel?: QuickReplyPickerViewModel = undefined;
  private templateScroller: Scroller = new Scroller();

  private getResourceManager(): resourceManager.ResourceManager {
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      throw new Error('Host context unavailable.');
    }
    return hostContext.resourceManager;
  }

  private getViewModel(): QuickReplyPickerViewModel {
    if (!this.viewModel) {
      this.viewModel = QuickReplyPickerViewModel.createDefault(this.getResourceManager());
    }
    return this.viewModel;
  }

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle enter: QuickReplyPicker');
    const viewModel = this.getViewModel();
    const params = this.getUIContext().getRouter().getParams() as QuickReplyPickerParams;
    const nextPageState = viewModel.applyRoute(
      this.currentPageState(),
      typeof params.chatId === 'string' ? params.chatId : '',
      typeof params.source === 'string' ? params.source : 'notification',
      typeof params.notificationId === 'number' ? params.notificationId : undefined
    );
    this.applyPageState(viewModel.createLoadingState(nextPageState));
    void this.loadTemplatesAsync();
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle leave: QuickReplyPicker');
  }

  private async loadTemplatesAsync(): Promise<void> {
    const viewModel = this.getViewModel();
    const result = await viewModel.loadTemplates();
    this.applyPageState(viewModel.applyTemplateLoadResult(this.currentPageState(), result));
  }

  private onTemplateClick(template: QuickReplyTemplate): void {
    void this.dispatchTemplateAsync(template);
  }

  private async dispatchTemplateAsync(template: QuickReplyTemplate): Promise<void> {
    const viewModel = this.getViewModel();
    const dispatchPlan = viewModel.planTemplateDispatch(this.currentPageState(), template.id);
    this.applyPageState(dispatchPlan.nextPageState);
    if (!dispatchPlan.shouldDispatch) {
      this.showErrorToastIfNeeded();
      return;
    }

    try {
      const result = await viewModel.dispatchTemplate(
        dispatchPlan.chatId,
        dispatchPlan.templateId,
        dispatchPlan.notificationId
      );
      const nextPageState = viewModel.applyDispatchResult(this.currentPageState(), result);
      this.applyPageState(nextPageState);
      if (nextPageState.shouldClose) {
        this.showToast(this.resolveUiText(nextPageState.statusText));
        this.closePicker();
        return;
      }
      this.showErrorToastIfNeeded();
    } catch (error) {
      this.applyPageState(viewModel.applyDispatchResult(this.currentPageState(), {
        kind: 'error',
        reason: 'other',
        errorMessage: String(error)
      }));
      this.showErrorToastIfNeeded();
    }
  }

  private closePicker(): void {
    try {
      this.getUIContext().getRouter().back();
      return;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'router.back failed after quick reply: %{public}s', String(error));
    }

    try {
      this.getUIContext().getRouter().replaceUrl({
        url: 'pages/Chats'
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'QuickReplyPicker fallback navigation failed: %{public}s', String(error));
    }
  }

  private showErrorToastIfNeeded(): void {
    const resolved = this.resolveUiText(this.errorText);
    if (resolved.length > 0) {
      this.showToast(resolved);
    }
  }

  private showToast(message: string): void {
    if (message.length === 0) {
      return;
    }
    try {
      promptAction.showToast({
        message: message,
        duration: 1500
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'showToast failed: %{public}s', String(error));
    }
  }

  private resolveUiText(textValue: UiTextValue): string {
    return resolveUiTextValue(this.getResourceManager(), textValue);
  }

  private currentPageState(): QuickReplyPickerPageState {
    return {
      chatId: this.chatId,
      notificationId: this.notificationId,
      source: this.source,
      templates: this.templates,
      pageMode: this.pageMode,
      isLoading: this.isLoading,
      isSending: this.isSending,
      selectedTemplateId: this.selectedTemplateId,
      statusText: this.statusText,
      errorText: this.errorText,
      canPickTemplate: this.canPickTemplate,
      shouldClose: this.shouldClose,
      notificationCancelled: this.notificationCancelled
    };
  }

  private applyPageState(nextPageState: QuickReplyPickerPageState): void {
    this.chatId = nextPageState.chatId;
    this.notificationId = nextPageState.notificationId;
    this.source = nextPageState.source;
    this.templates = nextPageState.templates;
    this.pageMode = nextPageState.pageMode;
    this.isLoading = nextPageState.isLoading;
    this.isSending = nextPageState.isSending;
    this.selectedTemplateId = nextPageState.selectedTemplateId;
    this.statusText = nextPageState.statusText;
    this.errorText = nextPageState.errorText;
    this.canPickTemplate = nextPageState.canPickTemplate;
    this.shouldClose = nextPageState.shouldClose;
    this.notificationCancelled = nextPageState.notificationCancelled;
  }

  private templateRenderKey(template: QuickReplyTemplate): string {
    return `${template.id}:${template.text}:${template.userDefined ? 'u' : 'd'}`;
  }

  private canSelectTemplate(templateId: string): boolean {
    return this.canPickTemplate || this.selectedTemplateId === templateId;
  }

  @Builder
  private buildTemplateList(): void {
    ArcList({ scroller: this.templateScroller, initialIndex: 0 }) {
      ForEach(this.templates, (template: QuickReplyTemplate) => {
        QuickReplyListItem({
          label: template.text,
          isEnabled: this.canSelectTemplate(template.id),
          onItemClick: (): void => {
            if (this.canSelectTemplate(template.id)) {
              this.onTemplateClick(template);
            }
          }
        })
      }, (template: QuickReplyTemplate) => this.templateRenderKey(template))
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildStateOverlay(message: ResourceStr): void {
    Column() {
      Text(message)
        .fontSize(11)
        .fontColor('#B0B0B0')
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .backgroundColor('#66000000')
        .borderRadius(14)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 48 })
    .alignRules({
      top: { anchor: '__container__', align: VerticalAlign.Top },
      left: { anchor: '__container__', align: HorizontalAlign.Start }
    })
  }

  build() {
    Stack() {
      Image($r('app.media.watch_wallpaper_466'))
        .width('100%')
        .align(Alignment.Center)

      RelativeContainer() {
        this.buildTemplateList()

        if (this.templates.length > 0) {
          ArcScrollBar({ scroller: this.templateScroller, state: BarState.Auto })
        }

        Text($r('app.string.quick_reply_title'))
          .width('100%')
          .height(40)
          .padding({ top: 8, bottom: 8 })
          .backgroundColor('#D9151A21')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .alignRules({
            top: { anchor: '__container__', align: VerticalAlign.Top },
            left: { anchor: '__container__', align: HorizontalAlign.Start }
          })

        if (this.pageMode === QuickReplyPickerPageMode.Loading) {
          this.buildStateOverlay($r('app.string.quick_reply_loading'))
        } else if (this.pageMode === QuickReplyPickerPageMode.Empty) {
          this.buildStateOverlay($r('app.string.quick_reply_empty'))
        } else if (this.pageMode === QuickReplyPickerPageMode.Sending) {
          this.buildStateOverlay(this.resolveUiText(this.statusText))
        } else if (this.pageMode === QuickReplyPickerPageMode.Error) {
          this.buildStateOverlay(this.resolveUiText(this.errorText))
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
