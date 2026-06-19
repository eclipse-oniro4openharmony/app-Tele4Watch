import { hilog } from '@kit.PerformanceAnalysisKit';
import resourceManager from '@ohos.resourceManager';
import { TdContactListItem, TdMeInfo } from '../models/td/TdViewTypes';
import { ContactListItem } from '../ui/ContactListItem';
import {
  ArcList,
  ArcScrollBar
} from '@kit.ArkUI';
import { ContactsPageMode, ContactsPageState } from '../models/contact/ContactsPageState';
import { ContactsPageViewModel } from '../viewmodel/ContactsPageViewModel';
import { resolveString } from '../utils/ResourceTextResolver';

const DOMAIN = 0x2026;
const TAG = 'ContactsPage';
const CONTACTS_LOADING_ID = 'contacts-loading';
const CONTACTS_EMPTY_ID = 'contacts-empty';

@Entry
@Component
struct Contacts {
  private readonly viewModel: ContactsPageViewModel = new ContactsPageViewModel();
  private readonly initialPageState: ContactsPageState = this.viewModel.createInitialState();
  @State meContact?: TdContactListItem = undefined;
  @State contacts: TdContactListItem[] = this.initialPageState.contacts;
  @State pageMode: ContactsPageMode = this.initialPageState.pageMode;
  @State isLoading: boolean = this.initialPageState.isLoading;
  @State isPullRefreshing: boolean = this.initialPageState.isPullRefreshing;

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
      hilog.error(DOMAIN, TAG, 'Failed to redirect Contacts to Index: %{public}s', String(error));
    }
  }

  /**
   * Binds listeners and requests contacts refresh after the page becomes visible.
   */
  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle enter: Contacts');
    this.hasNavigatedToIndex = false;
    this.viewModel.setContactsListener((items: TdContactListItem[]): void => {
      const nextPageState = this.viewModel.applyContacts(items);
      this.applyPageState(nextPageState);
      hilog.info(DOMAIN, TAG, 'Contacts updated (count=%{public}d)', nextPageState.contacts.length);
    });
    this.viewModel.setMeListener((me: TdMeInfo): void => {
      this.meContact = this.viewModel.mapMeToContact(me);
    });
    this.viewModel.setAuthStateListener((state: string): void => {
      this.redirectToIndexIfUnauthorized(state);
    });
    this.redirectToIndexIfUnauthorized(this.viewModel.getAuthorizationStateName());
    this.refreshContacts();
  }

  /**
   * Emits lifecycle log when leaving Contacts screen.
   */
  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'Lifecycle leave: Contacts');
  }

  /**
   * Requests contacts refresh and updates transient loading state.
   */
  private refreshContacts(): void {
    const refreshPlan = this.viewModel.planRefresh(this.currentPageState());
    this.applyPageState(refreshPlan.nextPageState);
    if (refreshPlan.shouldRequestContacts) {
      this.viewModel.requestContacts();
    }
  }

  /**
   * Opens the read-only profile page for one selected contact.
   *
   * @param contact The selected contact row.
   */
  private openUserProfile(contact: TdContactListItem): void {
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/UserProfile',
        params: this.viewModel.createUserProfileRouteParams(contact)
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to open UserProfile: %{public}s', String(error));
    }
  }

  /**
   * Returns the current mapped contacts-page state snapshot.
   *
   * @returns The current contacts-page state.
   */
  private currentPageState(): ContactsPageState {
    return {
      contacts: this.contacts,
      pageMode: this.pageMode,
      isLoading: this.isLoading,
      isPullRefreshing: this.isPullRefreshing
    };
  }

  /**
   * Applies one mapped contacts-page state to ArkUI-owned fields.
   *
   * @param nextPageState The mapped contacts-page state.
   */
  private applyPageState(nextPageState: ContactsPageState): void {
    this.contacts = nextPageState.contacts;
    this.pageMode = nextPageState.pageMode;
    this.isLoading = nextPageState.isLoading;
    this.isPullRefreshing = nextPageState.isPullRefreshing;
  }

  /**
   * Returns rendered contact rows, including synthetic current-account row when available.
   *
   * @returns Ordered rows rendered by the page.
   */
  private visibleContacts(): TdContactListItem[] {
    return this.viewModel.visibleContacts(this.meContact, this.contacts);
  }

  /**
   * Returns whether Telegram contacts payload already contains at least one row.
   *
   * The synthetic "current account" row must not hide loading/empty overlays.
   *
   * @returns `true` when Telegram contacts list is non-empty.
   */
  private hasTelegramContacts(): boolean {
    return this.contacts.length > 0;
  }

  /**
   * Returns whether the transient loading overlay should be visible.
   *
   * @returns `true` when the page is waiting for the first contacts payload.
   */
  private shouldShowLoadingState(): boolean {
    return this.isLoading && !this.hasTelegramContacts();
  }

  /**
   * Returns whether the empty-state overlay should be visible.
   *
   * @returns `true` when loading has finished and Telegram returned no contacts.
   */
  private shouldShowEmptyState(): boolean {
    return !this.isLoading && !this.isPullRefreshing && !this.hasTelegramContacts();
  }

  /**
   * Returns localized subtitle for one contact row.
   *
   * @param contact The contact item.
   * @returns Status label or fallback metadata line.
   */
  private contactSubtitle(contact: TdContactListItem): string {
    const statusKind = this.viewModel.contactStatusKind(contact);
    if (statusKind === 'online') {
      return this.getString('contacts_status_online');
    }
    if (statusKind === 'recently') {
      return this.getString('contacts_status_recently');
    }
    if (statusKind === 'lastWeek') {
      return this.getString('contacts_status_last_week');
    }
    if (statusKind === 'lastMonth') {
      return this.getString('contacts_status_last_month');
    }
    if (statusKind === 'offline') {
      const lastSeenAt = this.viewModel.contactLastSeenAt(contact);
      const formattedLastSeen = this.formatLastSeenAt(lastSeenAt);
      if (formattedLastSeen.length > 0) {
        return this.getString('contacts_status_last_seen', formattedLastSeen);
      }
    }
    return this.viewModel.contactSecondaryLine(contact);
  }

  /**
   * Returns subtitle color for one contact row.
   *
   * @param contact The contact item.
   * @returns Highlight color for online status, otherwise muted text color.
   */
  private contactSubtitleColor(contact: TdContactListItem): ResourceColor {
    if (this.viewModel.contactStatusKind(contact) === 'online') {
      return $r('app.color.contact_status_online');
    }
    return '#B0B0B0';
  }

  /**
   * Formats offline timestamp for one contact subtitle.
   *
   * @param unixSeconds Unix timestamp in seconds.
   * @returns Formatted local date-time label or empty string.
   */
  private formatLastSeenAt(unixSeconds: number): string {
    if (unixSeconds <= 0) {
      return '';
    }

    const date = new Date(unixSeconds * 1000);
    const hours = date.getHours();
    const minutes = date.getMinutes();
    const hoursText = hours < 10 ? `0${hours}` : `${hours}`;
    const minutesText = minutes < 10 ? `0${minutes}` : `${minutes}`;

    const now = new Date();
    const sameDay = date.getFullYear() === now.getFullYear() &&
      date.getMonth() === now.getMonth() &&
      date.getDate() === now.getDate();
    if (sameDay) {
      return `${hoursText}:${minutesText}`;
    }

    const day = date.getDate();
    const month = date.getMonth() + 1;
    const dayText = day < 10 ? `0${day}` : `${day}`;
    const monthText = month < 10 ? `0${month}` : `${month}`;
    return `${dayText}.${monthText} ${hoursText}:${minutesText}`;
  }

  build() {
    Stack() {
      Image($r('app.media.watch_wallpaper_466'))
        .width('100%')
        .align(Alignment.Center)

      RelativeContainer() {
        Refresh({ refreshing: $$this.isPullRefreshing }) {
          ArcList({
            scroller: this.scroller,
            initialIndex: 0
          }) {
            ForEach(this.visibleContacts(), (contact: TdContactListItem) => {
              ContactListItem({
                title: this.viewModel.contactDisplayName(contact),
                subtitle: this.contactSubtitle(contact),
                subtitleColor: this.contactSubtitleColor(contact),
                avatarPath: this.viewModel.contactAvatarPath(contact),
                avatarPaletteIndex: this.viewModel.contactAvatarPaletteIndex(contact),
                onItemClick: (): void => {
                  this.openUserProfile(contact);
                }
              });
            }, (contact: TdContactListItem) => this.viewModel.contactRenderKey(contact))
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
        }
        .width('100%')
        .height('100%')
        .onRefreshing(() => {
          const refreshPlan = this.viewModel.planPullRefresh(this.currentPageState());
          this.applyPageState(refreshPlan.nextPageState);
          if (refreshPlan.shouldRequestContacts) {
            this.viewModel.requestContacts();
          }
        })

        ArcScrollBar({ scroller: this.scroller, state: BarState.Auto })

        Text($r('app.string.contacts_title'))
          .id('contacts-header')
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

        if (this.shouldShowLoadingState()) {
          Column() {
            Text($r('app.string.contacts_loading'))
              .id(CONTACTS_LOADING_ID)
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
        } else if (this.shouldShowEmptyState()) {
          Column() {
            Text($r('app.string.contacts_empty'))
              .id(CONTACTS_EMPTY_ID)
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
