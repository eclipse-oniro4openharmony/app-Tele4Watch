import { hilog } from '@kit.PerformanceAnalysisKit';
import { TdChatListItem } from '../models/td/TdViewTypes';
import { ChatListItem } from '../ui/ChatListItem';
import {
  ArcList,
  ArcScrollBar
} from '@kit.ArkUI';
import { ChatsPageMode, ChatsPageState } from '../models/chat/ChatsPageState';
import { ChatsPageViewModel } from '../viewmodel/ChatsPageViewModel';

const DOMAIN = 0x2026;
const TAG = 'ChatsPage';

@Entry
@Component
struct Chats {
  private readonly viewModel: ChatsPageViewModel = new ChatsPageViewModel();
  private readonly initialPageState: ChatsPageState = this.viewModel.createInitialState();
  @State chats: TdChatListItem[] = this.initialPageState.chats;
  @State pageMode: ChatsPageMode = this.initialPageState.pageMode;
  @State isLoading: boolean = this.initialPageState.isLoading;
  @State isPullRefreshing: boolean = this.initialPageState.isPullRefreshing;

  private chatScroller: Scroller = new Scroller();
  private hasNavigatedToIndex: boolean = false;

  private logChatDates(items: TdChatListItem[]): void {
    for (const chat of items) {
      const rawDate = typeof chat.lastMessageDate === 'number' ? `${chat.lastMessageDate}` : 'none';
      const label = this.viewModel.chatTimeLabel(chat);
      const unreadCount = this.viewModel.chatUnreadCount(chat);
      hilog.info(
        DOMAIN,
        TAG,
        'chat=%{public}s rawDate=%{public}s label=%{public}s unread=%{public}d',
        chat.id,
        rawDate,
        label,
        unreadCount
      );
    }
  }

  private openChat(chat: TdChatListItem): void {
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/ChatDetails',
        params: this.viewModel.createChatRouteParams(chat)
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'openChat failed: %{public}s', String(error));
    }
  }

  private openUserProfile(chat: TdChatListItem): void {
    const routeParams = this.viewModel.createUserProfileRouteParams(chat);
    if (!routeParams) {
      return;
    }
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/UserProfile',
        params: routeParams
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'openUserProfile failed: %{public}s', String(error));
    }
  }

  /**
   * Redirects to Index when current session is no longer authorized.
   *
   * @param state Current authorization state.
   */
  private redirectToIndexIfUnauthorized(state: string): void {
    const authStatePlan = this.viewModel.planAuthStateChange(state);
    if (authStatePlan.resetIndexNavigation) {
      this.hasNavigatedToIndex = false;
    }
    if (!authStatePlan.shouldNavigateToIndex) {
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
      hilog.error(DOMAIN, TAG, 'Failed to redirect Chats to Index: %{public}s', String(error));
    }
  }

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle enter: Chats');
    this.hasNavigatedToIndex = false;
    this.viewModel.setChatsListener((items: TdChatListItem[]): void => {
      const nextPageState = this.viewModel.applyChats(items);
      this.applyPageState(nextPageState);
      this.logChatDates(nextPageState.chats);
    });
    this.viewModel.setAuthStateListener((state: string): void => {
      this.redirectToIndexIfUnauthorized(state);
    });
    this.redirectToIndexIfUnauthorized(this.viewModel.getAuthorizationStateName());
    this.refreshChats();
  }

  /**
   * Emits lifecycle log when leaving Chats screen.
   */
  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle leave: Chats');
  }

  private refreshChats(): void {
    const refreshPlan = this.viewModel.planRefresh(this.currentPageState(), 40);
    this.applyPageState(refreshPlan.nextPageState);
    if (refreshPlan.shouldRequestChats) {
      this.viewModel.requestChats(refreshPlan.requestLimit);
    }
  }

  /**
   * Returns the current mapped chats-page state snapshot.
   *
   * @returns The current chats-page state.
   */
  private currentPageState(): ChatsPageState {
    return {
      chats: this.chats,
      pageMode: this.pageMode,
      isLoading: this.isLoading,
      isPullRefreshing: this.isPullRefreshing
    };
  }

  /**
   * Applies one mapped chats-page state to ArkUI-owned fields.
   *
   * @param nextPageState The mapped chats-page state.
   */
  private applyPageState(nextPageState: ChatsPageState): void {
    this.chats = nextPageState.chats;
    this.pageMode = nextPageState.pageMode;
    this.isLoading = nextPageState.isLoading;
    this.isPullRefreshing = nextPageState.isPullRefreshing;
  }

  build() {
    Stack() {
      Image($r('app.media.watch_wallpaper_466'))
        .width('100%')
        .align(Alignment.Center)

      RelativeContainer() {
        Refresh({ refreshing: $$this.isPullRefreshing }) {
          ArcList({ scroller: this.chatScroller, initialIndex: 0 }) {
            ForEach(this.chats, (chat: TdChatListItem) => {
              ChatListItem({
                title: chat.title,
                lastMessageText: this.viewModel.chatLastMessageText(chat),
                lastMessageTextValue: chat.lastMessageTextValue,
                lastMessageKind: chat.lastMessageKind,
                lastMessageIsOutgoing: chat.lastMessageIsOutgoing === true,
                lastMessageCallEventStatus: chat.lastMessageCallEventStatus,
                avatarPath: this.viewModel.chatAvatarPath(chat),
                avatarPaletteIndex: this.viewModel.chatAvatarPaletteIndex(chat),
                chatKind: chat.chatKind,
                timeLabel: this.viewModel.chatTimeLabel(chat),
                unreadCount: this.viewModel.chatUnreadCount(chat),
                isMuted: this.viewModel.chatIsMuted(chat),
                onAvatarClick: (): void => {
                  this.openUserProfile(chat);
                },
                onItemClick: () => {
                  this.openChat(chat);
                }
              });
            }, (chat: TdChatListItem) => this.viewModel.chatRenderKey(chat))
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
        }
        .width('100%')
        .height('100%')
        .onRefreshing(() => {
          const refreshPlan = this.viewModel.planPullRefresh(this.currentPageState(), 40);
          this.applyPageState(refreshPlan.nextPageState);
          if (refreshPlan.shouldRequestChats) {
            this.viewModel.requestChats(refreshPlan.requestLimit);
          }
        })

        ArcScrollBar({ scroller: this.chatScroller, state: BarState.Auto })

        Text($r('app.string.chats_title'))
          .id('chats-header')
          .width('100%')
          .height(40)
          .padding({ top: 8, bottom: 8 })
          .backgroundColor('#D9151A21')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .backgroundColor('#D9151A21')
          .alignRules({
            top: { anchor: '__container__', align: VerticalAlign.Top },
            left: { anchor: '__container__', align: HorizontalAlign.Start }
          })

        if (this.isLoading && this.chats.length === 0) {
          Column() {
            Text($r('app.string.chats_loading'))
              .fontSize(11)
              .fontColor('#B0B0B0')
              .textAlign(TextAlign.Center)
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
        } else if (!this.isLoading && this.chats.length === 0) {
          Column() {
            Text($r('app.string.chats_empty'))
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
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
