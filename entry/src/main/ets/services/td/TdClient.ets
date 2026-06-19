import { hilog } from '@kit.PerformanceAnalysisKit';
import { tdNativeBridge } from 'bridge';
import { getActiveTelegramCredentials, telegramSecrets } from '../../config/TelegramSecrets.local';
import { computeTdAuthTransition, TdAuthAction } from './TdAuthReducer';
import { UiTextValue, cloneUiTextValue } from '../../models/ui/UiTextValue';
import { TgCallDiagnosticResult, tgCallDiagnostics } from '../calls/TgCallDiagnostics';
import {
  extractAuthorizationStateCodeLength,
  extractAuthorizationStateQrLink,
  extractAuthorizationStateType,
  extractConnectionStateType,
  extractErrorCode,
  extractErrorMessage,
  extractExtra,
  extractOptionIntegerValue,
  extractTopLevelType,
  extractUpdateOptionName
} from './TdPayloadParsers';
import {
  TdMessageMediaBindingType,
  TdMessagesExtraInfo,
  TdParsedMessageBindingInfo,
  TdSendMessageExtraInfo,
  TdUpdateDeleteMessagesPayload,
  TdUserFullInfoExtraInfo
} from './TdClientTypes';
import {
  TdAnimatedChatPhotoPayload,
  TdCallEvent,
  TdChatKind,
  TdChatListItem,
  TdChatPhotoPayload,
  TdMessageDeliveryState,
  TdChatMessageItem,
  TdCallEventStatus,
  TdChatMessageKind,
  TdContactListItem,
  TdGetOptionResponse,
  TdMeInfo,
  TdNotificationContentKind,
  TdNotificationEvent,
  TdNotificationGroupPayload,
  TdNotificationItem,
  TdParsedCallPayload,
  TdParsedCallProtocolPayload,
  TdParsedCallServerPayload,
  TdParsedCallStatePayload,
  TdUserProfileItem,
  TdUserFullInfoPayload,
  TdUserPayload
} from './TdPayloadTypes';
import {
  buildTdSendVoiceNoteMessageRequest,
  encodeTdVoiceNoteWaveform,
  TdAcceptCallRequest,
  TdCallProtocolRequest,
  TdCheckAuthenticationCodeRequest,
  TdCancelDownloadFileRequest,
  TdCreateCallRequest,
  TdDiscardCallRequest,
  TdDownloadFileRequest,
  TdGetAuthorizationStateRequest,
  TdGetChatRequest,
  TdGetChatsRequest,
  TdGetChatHistoryRequest,
  TdGetContactsRequest,
  TdGetMeRequest,
  TdGetOptionRequest,
  TdGetUserRequest,
  TdGetUserFullInfoRequest,
  TdLogOutRequest,
  TdLoadChatsRequest,
  TdCreatePrivateChatRequest,
  TdRequest,
  TdRequestQrCodeAuthenticationRequest,
  TdSendCallSignalingDataRequest,
  TdSendMessageRequest,
  TdSetAuthenticationPhoneNumberRequest,
  TdSetTdlibParametersRequest,
  TdViewMessagesRequest
} from './TdRequestTypes';
import {
  parseCallId,
  parseUpdateCall,
  parseUpdateNewCallSignalingData
} from './TdCallParser';
import { copyMissingMediaFieldsFromPendingMessage } from './TdMessageMerge';
import {
  parseChatListMembershipPayload,
  parseChatPayload,
  parseChatFoldersPayload,
  parseChatsPayload,
  parseUpdateChatLastMessagePayload,
  parseUpdateChatNotificationSettingsPayload,
  parseUpdateChatPhotoPayload,
  parseUpdateChatPositionPayload,
  parseUpdateChatReadInboxPayload,
  parseUpdateChatReadOutboxPayload,
  parseUpdateChatTitlePayload,
  parseUpdateFilePayload,
  parseUpdateNewChatPayload
} from './TdChatParser';
import {
  formatChatMessagePreviewText,
  parseMessagePayload,
  parseMessagesPayload,
  parseUpdateMessageSendSucceededPayload,
  parseUpdateNewMessagePayload
} from './TdMessageParser';
import { buildChatListMessagePreview } from './TdChatPreviewMapper';
import { SubscriptionHub } from '../../utils/SubscriptionHub';
import {
  parseUpdateActiveNotifications,
  parseUpdateNotification,
  parseUpdateNotificationGroup
} from './TdNotificationParser';
import { buildFallbackNotificationId } from './TdNotificationId';
import {
  parseUsersPayload,
  parseUpdateUserFullInfoPayload,
  parseUpdateUserPayload,
  parseUserFullInfoPayload,
  parseUserPayload,
  resolveUsername
} from './TdUserParser';
import { TdContactsCoordinator } from './TdContactsCoordinator';

const DOMAIN = 0x2026;
const TAG = 'TdClient';
const TDLIB_DIR = '/data/storage/el2/base/files/tdlib';

/**
 * High-level TDLib client wrapper used by the UI layer.
 *
 * Responsibilities:
 * - initialize native TDLib JSON bridge
 * - drive authorization bootstrap and state transitions
 * - expose simple UI-facing methods (submit phone/code, get version)
 * - map selected TDLib payloads to typed UI callbacks (`authState`, `me`)
 *
 * This class intentionally stays stateful, because TDLib authorization is
 * stateful and event-driven.
 */
class TdClient {

  /**
   * Only these option updates are logged as `info` to keep logs readable.
   * Other option updates are still processed when needed, but not highlighted.
   */
  private static readonly IMPORTANT_OPTION_NAMES: Set<string> = new Set<string>([
    'version',
    'commit_hash',
    'test_mode'
  ]);
  /** Polling interval used to drain TDLib async updates. */
  private static readonly AUTH_POLL_INTERVAL_MS: number = 24;
  /** Upper bound of TDLib payloads processed in single polling tick. */
  private static readonly AUTH_POLL_MAX_UPDATES_PER_TICK: number = 80;
  /** Enables verbose polling diagnostics (`receive` + unhandled payload previews). */
  private static readonly VERBOSE_TD_POLL_LOGS: boolean = false;
  /** Session label shown in Telegram "Active sessions" app details. */
  private static readonly SESSION_APP_LABEL: string = 'Tele4Watch 1.0.0';
  /** Device model shown in Telegram "Active sessions". */
  private static readonly SESSION_DEVICE_MODEL: string = 'Huawei Watch 5';
  /** System version shown in Telegram "Active sessions". */
  private static readonly SESSION_SYSTEM_VERSION: string = 'HarmonyOS Next 6';
  /** Canonical TDLib auth state used for fully authorized requests. */
  private static readonly AUTH_READY_STATE: string = 'authorizationStateReady';
  /** Canonical TDLib auth state used when session must be re-established. */
  private static readonly AUTH_WAIT_PHONE_STATE: string = 'authorizationStateWaitPhoneNumber';
  /** Fallback code length used only when TDLib doesn't expose `code_info.type.length`. */
  private static readonly AUTH_CODE_LENGTH_FALLBACK: number = 5;
  /** Minimal distance between consecutive `getMe` requests. */
  private static readonly ME_REQUEST_MIN_INTERVAL_MS: number = 1200;
  /** Time budget after which stale in-flight `getMe` guard is released. */
  private static readonly ME_REQUEST_IN_FLIGHT_TIMEOUT_MS: number = 4000;
  /** Reasons that should bypass `getMe` cooldown to refresh profile media immediately. */
  private static readonly ME_REQUEST_COOLDOWN_BYPASS_REASONS: Set<string> = new Set<string>([
    'avatar-small-ready',
    'avatar-animated-ready',
    'animated-avatar-removed',
    'animated-avatar-ready',
    'animated-avatar-cleared'
  ]);
  /** `@extra` tag used for main-list `loadChats` request. */
  private static readonly CHATS_EXTRA_LOAD_MAIN: string = 'chats:load';
  /** `@extra` tag used for main-list `getChats` request. */
  private static readonly CHATS_EXTRA_GET_MAIN: string = 'chats:get';
  /** `@extra` tag used for archive-list `loadChats` diagnostics. */
  private static readonly CHATS_EXTRA_LOAD_ARCHIVE: string = 'chats:load:archive';
  /** `@extra` tag used for archive-list `getChats` diagnostics. */
  private static readonly CHATS_EXTRA_GET_ARCHIVE: string = 'chats:get:archive';
  /** `@extra` tag used for `getChatFolders` diagnostics. */
  private static readonly CHATS_EXTRA_GET_FOLDERS: string = 'chats:get:folders';
  /** Prefix of `@extra` used for folder-list `loadChats` diagnostics. */
  private static readonly CHATS_EXTRA_LOAD_FOLDER_PREFIX: string = 'chats:load:folder:';
  /** Prefix of `@extra` used for folder-list `getChats` diagnostics. */
  private static readonly CHATS_EXTRA_GET_FOLDER_PREFIX: string = 'chats:get:folder:';
  /** `@extra` tag used for account Telegram contacts request. */
  private static readonly CONTACTS_EXTRA_GET: string = 'contacts:get';
  /** Prefix of `@extra` used for per-contact `getUser` requests. */
  private static readonly CONTACTS_EXTRA_GET_USER_PREFIX: string = 'contacts:user:';
  /** Prefix of `@extra` used for `createPrivateChat` requests. */
  private static readonly PRIVATE_CHAT_EXTRA_CREATE_PREFIX: string = 'private-chat:create:';
  /** Prefix of `@extra` used for `createCall` requests. */
  private static readonly CALL_EXTRA_CREATE_PREFIX: string = 'call:create:';
  /** Enables additional archive-list probe when requesting main chats. */
  private static readonly ENABLE_ARCHIVE_CHAT_LIST_PROBE: boolean = true;
  /** Enables additional custom-folder probe when requesting main chats. */
  private static readonly ENABLE_FOLDER_CHAT_LIST_PROBE: boolean = true;
  /** Small startup buffer for notification updates emitted before the publisher is ready. */
  private static readonly MAX_PENDING_NOTIFICATION_EVENTS: number = 32;
  private static readonly MAX_PENDING_CHAT_READ_EVENTS: number = 32;
  private static readonly MAX_PENDING_CALL_EVENTS: number = 16;
  /** Delay used for TDLib history retries while chat/message caches warm up. */
  private static readonly HISTORY_RETRY_DELAY_MS: number = 1200;
  /** Time budget for one-shot `sendMessage` confirmation callbacks. */
  private static readonly SEND_CONFIRM_TIMEOUT_MS: number = 10000;

  /** Native TDLib client id; `-1` means not initialized yet. */
  private clientId: number = -1;

  /** Polling timer id; `-1` means polling is currently disabled. */
  private authPollerId: number = -1;
  /** Guards bootstrap sequence against repeated start calls. */
  private isAuthorizationBootstrapRunning: boolean = false;

  /** Last known authorization state from TDLib. */
  private authState: string = 'unknown';
  /** Expected authentication-code length extracted from latest TDLib wait-code state. */
  private authCodeLength: number = TdClient.AUTH_CODE_LENGTH_FALLBACK;
  /** Guard to avoid sending `setTdlibParameters` more than once per lifecycle. */
  private tdlibParametersSent: boolean = false;

  /** Guard to avoid requesting `getMe` repeatedly after authorization is ready. */
  private meRequested: boolean = false;
  /** Guard indicating that `getMe` request was sent and response is still pending. */
  private meRequestInFlight: boolean = false;
  /** Unix time in milliseconds when latest `getMe` request was sent. */
  private meRequestLastSentAtMs: number = 0;

  /** Current account id from `updateOption(my_id)` used to filter `updateUser`. */
  private myUserId: number = 0;

  /** Optional UI callback invoked whenever auth state changes. */
  private authStateListener?: (state: string) => void;
  /** Optional UI callback invoked when QR login link changes. */
  private qrAuthLinkListener?: (link: string, updatedAtMs: number) => void;

  /** Optional UI callback invoked when current user profile is available. */
  private meListener?: (me: TdMeInfo) => void;
  /** Last emitted current-account model cached for newly attached listeners. */
  private currentMe?: TdMeInfo = undefined;
  /** Optional UI callback invoked when contacts list is refreshed. */
  private contactsListener?: (contacts: TdContactListItem[]) => void;

  /** Optional UI callback invoked when chat list is refreshed. */
  private chatsListener?: (chats: TdChatListItem[]) => void;

  /** Registered subscribers for per-chat timeline emits. Multiple pages (e.g. ChatDetails and
   *  MediaViewer pushed on top) can observe the same stream without stealing each other's slot —
   *  the `SubscriptionHub` issues stable per-subscriber tokens. */
  private chatMessagesSubscriptions: SubscriptionHub<(chatId: string, messages: TdChatMessageItem[]) => void> =
    new SubscriptionHub<(chatId: string, messages: TdChatMessageItem[]) => void>('chatMessages');
  /** Map of chats with a user-initiated older-history pull still awaiting a TDLib response.
   *  Keyed by `chatId`, value is the unique `pullToken` that was embedded into the dispatched
   *  request's `@extra`. Latest-wins: if the user pulls again before the previous response
   *  arrives, the older token is overwritten and the stale response will mismatch.
   *
   *  Lets `historyPageResolved` fire ONLY for the SPECIFIC response that closes the pending
   *  pull cycle — not for unrelated `getChatHistory` responses that share the same `chatId`
   *  (initial load, deeplink center-load, internal probe / sparse / sparse-deeplink retries,
   *  refresh-from-zero retries). */
  private pullTokenByChatId: Map<string, number> = new Map();
  private nextPullToken: number = 1;
  /** Subscribers for "your older-history pull just resolved" events. Decouples pull-cycle close
   *  from the generic `chatMessages` fan-out so live updates mid-pull cannot accidentally flip
   *  `isLoadingOlder=false` ahead of the actual page response. Replaces the previous
   *  `historyExhaustedListener` (which fired on every `true`→`false` transition and required
   *  view-side `pullInFlight` filtering). */
  private historyPageResolvedSubscriptions: SubscriptionHub<(chatId: string, outcome: 'page-loaded' | 'no-more' | 'rejected') => void> =
    new SubscriptionHub<(chatId: string, outcome: 'page-loaded' | 'no-more' | 'rejected') => void>('historyPageResolved');
  /** Optional UI callback invoked when `sendMessage` request is confirmed or rejected. */
  private messageSendResultListener?: (chatId: string, ok: boolean, errorMessage: string) => void;
  /** One-shot callbacks waiting for concrete send confirmation keyed by request `@extra`. */
  private messageSendConfirmationListeners: Map<string, (ok: boolean, errorMessage: string) => void> =
    new Map<string, (ok: boolean, errorMessage: string) => void>();
  /** Maps TDLib pending message ids to original request `@extra` tokens. */
  private sendExtraByPendingMessageId: Map<string, string> = new Map<string, string>();
  /** Timeout ids for one-shot send confirmations keyed by request `@extra`. */
  private sendConfirmationTimeoutIdsByExtra: Map<string, number> = new Map<string, number>();
  /** Optional service callback invoked for TDLib notification updates. */
  private notificationsListener?: (event: TdNotificationEvent) => void;
  /** Guards notification buffering after the listener is intentionally released. */
  private notificationBufferingEnabled: boolean = true;
  /** Startup queue for notification updates that arrive before NotificationKit bootstrap finishes. */
  private pendingNotificationEvents: TdNotificationEvent[] = [];
  /** Optional service callback invoked when TDLib moves a chat inbox read cursor. */
  private chatReadListener?: (chatId: string) => void;
  /** Guards chat-read buffering after the listener is intentionally released. */
  private chatReadBufferingEnabled: boolean = true;
  /** Startup queue for read updates that arrive before NotificationKit bootstrap finishes. */
  private pendingChatReadChatIds: string[] = [];
  /** Optional service callback invoked for TDLib call updates. */
  private callListener?: (event: TdCallEvent) => void;
  /** Guards call buffering after the listener is intentionally released. */
  private callBufferingEnabled: boolean = true;
  /** Startup queue for call updates that arrive before the call publisher is ready. */
  private pendingCallEvents: TdCallEvent[] = [];
  /** Chat ids refreshed to reconcile already-visible system notifications. */
  private notificationRefreshChatIds: Set<string> = new Set<string>();
  /** One-shot callbacks waiting for `createPrivateChat` responses keyed by `@extra`. */
  private privateChatRequestListeners: Map<string, (chat: TdChatListItem | undefined, errorMessage: string) => void> =
    new Map<string, (chat: TdChatListItem | undefined, errorMessage: string) => void>();
  /** One-shot callbacks waiting for `createCall` responses keyed by `@extra`. */
  private callCreationListeners: Map<string, (callId: number, errorMessage: string) => void> =
    new Map<string, (callId: number, errorMessage: string) => void>();
  /** Optional UI callback invoked for authorization-related TDLib errors. */
  private authErrorListener?: (extra: string, code: number, message: string) => void;

  /** Last QR login link received from TDLib (`tg://login?token=...`). */
  private qrAuthLink: string = '';
  /** Unix time in milliseconds when `qrAuthLink` was last updated. */
  private qrAuthLinkUpdatedAtMs: number = 0;

  /** Last received chat order from `getChats` result. */
  private chatOrder: string[] = [];
  /** TDLib main-list position order indexed by chat id for live list updates. */
  private chatPositionOrderByChatId: Map<string, string> = new Map<string, string>();

  /** Chat titles indexed by chat id; filled from `getChat` payloads. */
  private chatTitleById: Map<string, string> = new Map<string, string>();
  /** Normalized chat kinds indexed by chat id. */
  private chatKindByChatId: Map<string, TdChatKind> = new Map<string, TdChatKind>();
  /** Chat avatar local file path indexed by chat id. */
  private chatAvatarPathByChatId: Map<string, string> = new Map<string, string>();
  /** Last message unix timestamp indexed by chat id. */
  private chatLastMessageDateByChatId: Map<string, number> = new Map<string, number>();
  /** Last message text preview indexed by chat id. */
  private chatLastMessageTextByChatId: Map<string, string> = new Map<string, string>();
  /** Last message resource-backed text preview indexed by chat id. */
  private chatLastMessageTextValueByChatId: Map<string, UiTextValue> = new Map<string, UiTextValue>();
  /** Last message normalized kind indexed by chat id. */
  private chatLastMessageKindByChatId: Map<string, TdChatMessageKind> = new Map<string, TdChatMessageKind>();
  /** Whether the last message in the chat was sent by the local user. Used by the chat-list preview row to pick the direction-aware call icon. */
  private chatLastMessageIsOutgoingByChatId: Map<string, boolean> = new Map<string, boolean>();
  /** Call-event outcome carried by the last message when it is a `callEvent`, so the preview icon can swap between answered / missed / cancelled variants. */
  private chatLastMessageCallEventStatusByChatId: Map<string, TdCallEventStatus> = new Map<string, TdCallEventStatus>();
  /** Last read incoming message id indexed by chat id. */
  private chatLastReadInboxMessageIdByChatId: Map<string, string> = new Map<string, string>();
  /** Last read outgoing message id indexed by chat id. */
  private chatLastReadOutboxMessageIdByChatId: Map<string, string> = new Map<string, string>();
  /** Unread counter indexed by chat id. */
  private chatUnreadCountByChatId: Map<string, number> = new Map<string, number>();
  /** Remaining mute duration from TDLib notification settings indexed by chat id. */
  private chatNotificationMuteForByChatId: Map<string, number> = new Map<string, number>();
  /** Default silent-send flag indexed by chat id. */
  private chatDefaultDisableNotificationByChatId: Map<string, boolean> = new Map<string, boolean>();
  /** Private chat peer user id indexed by chat id. */
  private chatPeerUserIdByChatId: Map<string, string> = new Map<string, string>();
  /** Known usernames indexed by user id. */
  private usernameByUserId: Map<string, string> = new Map<string, string>();
  /** Known first names indexed by user id. */
  private firstNameByUserId: Map<string, string> = new Map<string, string>();
  /** Known last names indexed by user id. */
  private lastNameByUserId: Map<string, string> = new Map<string, string>();
  /** Known phone numbers indexed by user id. */
  private phoneNumberByUserId: Map<string, string> = new Map<string, string>();
  /** User avatar local file path indexed by user id. */
  private userAvatarPathByUserId: Map<string, string> = new Map<string, string>();
  /** User animated-avatar local file path indexed by user id. */
  private userAnimatedAvatarPathByUserId: Map<string, string> = new Map<string, string>();
  /** Pure contacts orchestration state used by contact-list flow. */
  private readonly contactsCoordinator: TdContactsCoordinator = new TdContactsCoordinator();
  /** Reverse mapping from avatar file id to chat id. */
  private avatarFileIdToChatId: Map<number, string> = new Map<number, string>();
  /** Reverse mapping from avatar file id to user id. */
  private avatarFileIdToUserId: Map<number, string> = new Map<number, string>();
  /** Reverse mapping from animated-avatar file id to user id. */
  private animatedAvatarFileIdToUserId: Map<number, string> = new Map<number, string>();

  /** Last fetched message list indexed by chat id. */
  private messagesByChatId: Map<string, TdChatMessageItem[]> = new Map<string, TdChatMessageItem[]>();
  /** Tracks requested chat-history pages to avoid duplicate fetches. */
  private historyRequestedFromByChatId: Map<string, Set<string>> = new Map<string, Set<string>>();
  /** Stores per-chat history limit to keep pagination consistent. */
  private historyLimitByChatId: Map<string, number> = new Map<string, number>();
  /** Stores cursor (`from_message_id`) for loading next older page per chat. */
  private historyNextFromByChatId: Map<string, string> = new Map<string, string>();
  /** Indicates whether more history pages may still be available for chat. */
  private historyHasMoreByChatId: Map<string, boolean> = new Map<string, boolean>();
  /** User pull retry budget for reloading short first page (`from=0`) when needed. */
  private historyRetryBudgetByChatId: Map<string, number> = new Map<string, number>();
  /** Retry budget for deeplink history requests issued before TDLib warms chat cache. */
  private historyChatNotFoundRetryBudgetByChatId: Map<string, number> = new Map<string, number>();
  /** Latest message id already submitted to `viewMessages` per chat. */
  private viewedTailMessageIdByChatId: Map<string, string> = new Map<string, string>();

  /** Guard set to avoid requesting the same chat details repeatedly. */
  private requestedChatIds: Set<string> = new Set<string>();
  /** Guard set to avoid requesting the same avatar file repeatedly. */
  private requestedAvatarDownloads: Set<number> = new Set<number>();
  /** Guard set to avoid requesting the same contact user repeatedly during one contacts refresh. */
  private requestedContactUserIds: Set<string> = new Set<string>();
  /** Guard set to avoid requesting the same `getUserFullInfo` repeatedly. */
  private requestedUserFullInfoIds: Set<string> = new Set<string>();
  /** Guard set to avoid requesting the same message-media file repeatedly. */
  private requestedMessageMediaDownloads: Set<number> = new Set<number>();
  /** Message media-binding key -> media file id index used to keep `updateFile` bindings in sync. */
  private messageMediaFileIdByBindingKey: Map<string, number> = new Map<string, number>();
  /** Media file id -> message media-binding keys index used by `updateFile` to patch messages in-place. */
  private messageBindingKeysByMediaFileId: Map<number, Set<string>> = new Map<number, Set<string>>();

  /**
   * Authorization action dispatch table.
   * Keeps `handleAuthAction` tiny and makes future extension straightforward.
   */
  private readonly authActionHandlers: Record<TdAuthAction, () => void> = {
    'sendTdlibParameters': (): void => {
      hilog.info(DOMAIN, TAG, 'Action: sending setTdlibParameters');
      this.sendTdlibParameters();
    },
    'requestMe': (): void => {
      this.requestMe('auth-ready');
    },
    'waitPhoneNumber': (): void => {
      hilog.info(DOMAIN, TAG, 'Action required: waiting for phone number input');
    },
    'waitOtherDeviceConfirmation': (): void => {
      hilog.info(DOMAIN, TAG, 'Action required: waiting for QR confirmation on another device');
    },
    'waitNetwork': (): void => {
      hilog.info(DOMAIN, TAG, 'Action required: waiting for network connection');
    },
    'waitCode': (): void => {
      hilog.info(DOMAIN, TAG, 'Action required: waiting for login code input');
    },
    'waitPassword': (): void => {
      hilog.info(DOMAIN, TAG, 'Action required: waiting for 2FA password input');
    },
    'ready': (): void => {
      hilog.info(DOMAIN, TAG, 'Authorization ready - user is logged in');
    },
    'lifecycleReset': (): void => {
      hilog.info(DOMAIN, TAG, 'Authorization lifecycle state reset');
    }
  };
  
  /**
   * Top-level TDLib payload dispatcher.
   * Each entry handles one `@type` branch and delegates to dedicated methods.
   */
  private readonly payloadHandlers: Record<string, (payload: string, source: string) => void> = {
    'updateAuthorizationState': (payload: string, source: string): void => {
      const state = extractAuthorizationStateType(payload);
      const codeLength = extractAuthorizationStateCodeLength(payload);
      const qrAuthLink = extractAuthorizationStateQrLink(payload);
      this.handleAuthorizationState(state, source, qrAuthLink, codeLength);
    },
    'updateConnectionState': (payload: string, source: string): void => {
      this.handleConnectionState(payload, source);
    },
    'updateOption': (payload: string, source: string): void => {
      this.handleUpdateOption(payload, source);
    },
    'user': (payload: string, source: string): void => {
      this.handleUser(payload, source);
    },
    'users': (payload: string, source: string): void => {
      this.handleUsers(payload, source);
    },
    'updateUser': (payload: string, source: string): void => {
      this.handleUpdateUser(payload, source);
    },
    'userFullInfo': (payload: string, source: string): void => {
      this.handleUserFullInfo(payload, source);
    },
    'updateUserFullInfo': (payload: string, source: string): void => {
      this.handleUpdateUserFullInfo(payload, source);
    },
    'chats': (payload: string, source: string): void => {
      this.handleChats(payload, source);
    },
    'chatFolders': (payload: string, source: string): void => {
      this.handleChatFolders(payload, source);
    },
    'updateChatFolders': (payload: string, source: string): void => {
      this.handleChatFolders(payload, source);
    },
    'messages': (payload: string, source: string): void => {
      this.handleMessages(payload, source);
    },
    'message': (payload: string, source: string): void => {
      this.handleMessage(payload, source);
    },
    'chat': (payload: string, source: string): void => {
      this.handleChat(payload, source);
    },
    'updateNewChat': (payload: string, source: string): void => {
      this.handleUpdateNewChat(payload, source);
    },
    'updateChatLastMessage': (payload: string, source: string): void => {
      this.handleUpdateChatLastMessage(payload, source);
    },
    'updateChatTitle': (payload: string, source: string): void => {
      this.handleUpdateChatTitle(payload, source);
    },
    'updateChatPhoto': (payload: string, source: string): void => {
      this.handleUpdateChatPhoto(payload, source);
    },
    'updateChatPosition': (payload: string, source: string): void => {
      this.handleUpdateChatPosition(payload, source);
    },
    'updateChatAddedToList': (payload: string, source: string): void => {
      this.handleUpdateChatAddedToList(payload, source);
    },
    'updateChatRemovedFromList': (payload: string, source: string): void => {
      this.handleUpdateChatRemovedFromList(payload, source);
    },
    'updateNewMessage': (payload: string, source: string): void => {
      this.handleUpdateNewMessage(payload, source);
    },
    'updateNotification': (payload: string, source: string): void => {
      this.handleUpdateNotification(payload, source);
    },
    'updateNotificationGroup': (payload: string, source: string): void => {
      this.handleUpdateNotificationGroup(payload, source);
    },
    'updateActiveNotifications': (payload: string, source: string): void => {
      this.handleUpdateActiveNotifications(payload, source);
    },
    'updateCall': (payload: string, source: string): void => {
      this.handleUpdateCall(payload, source);
    },
    'callId': (payload: string, source: string): void => {
      this.handleCallId(payload, source);
    },
    'updateNewCallSignalingData': (payload: string, source: string): void => {
      this.handleUpdateNewCallSignalingData(payload, source);
    },
    'updateMessageSendSucceeded': (payload: string, source: string): void => {
      this.handleUpdateMessageSendSucceeded(payload, source);
    },
    'updateDeleteMessages': (payload: string, source: string): void => {
      this.handleUpdateDeleteMessages(payload, source);
    },
    'updateUserStatus': (payload: string, source: string): void => {
      this.ignorePassiveUpdate(payload, source);
    },
    'updateUnreadMessageCount': (payload: string, source: string): void => {
      this.ignorePassiveUpdate(payload, source);
    },
    'updateSavedMessagesTopic': (payload: string, source: string): void => {
      this.ignorePassiveUpdate(payload, source);
    },
    'updateChatReadInbox': (payload: string, source: string): void => {
      this.handleUpdateChatReadInbox(payload, source);
    },
    'updateChatReadOutbox': (payload: string, source: string): void => {
      this.handleUpdateChatReadOutbox(payload, source);
    },
    'updateChatNotificationSettings': (payload: string, source: string): void => {
      this.handleUpdateChatNotificationSettings(payload, source);
    },
    'updateFile': (payload: string, source: string): void => {
      this.handleUpdateFile(payload, source);
    },
    'file': (payload: string, source: string): void => {
      this.handleUpdateFile(payload, source);
    },
    'ok': (payload: string, source: string): void => {
      this.handleOk(payload, source);
    },
    'error': (payload: string, source: string): void => {
      this.handleError(payload, source);
    }
  };

  /**
   * Returns log-friendly short representation of long payloads.
   *
   * @param value Full payload string.
   * @param maxLength Max string length kept in logs.
   * @returns Original string when short enough, otherwise truncated preview.
   */
  private preview(value: string, maxLength: number = 200): string {
    if (value.length <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength) + '...(truncated)';
  }

  /**
   * Initializes native TDLib client if needed.
   *
   * Safe to call repeatedly; initialization is performed only once.
   */
  init(): void {
    if (this.clientId >= 0) {
      hilog.debug(DOMAIN, TAG, 'init skipped, existing clientId=%{public}d', this.clientId);
      return;
    }
    const credentials = getActiveTelegramCredentials();
    hilog.info(DOMAIN, TAG, 'Telegram env=%{public}s apiId=%{public}d useTestDc=%{public}d',
      telegramSecrets.environment,
      credentials.apiId,
      credentials.useTestDc ? 1 : 0
    );
    this.clientId = tdNativeBridge.createClientId();
    this.tdlibParametersSent = false;
    this.meRequestInFlight = false;
    this.meRequestLastSentAtMs = 0;
    hilog.info(DOMAIN, TAG, 'TD client created: %{public}d', this.clientId);
    this.logTgCallDiagnostics();
  }

  private logTgCallDiagnostics(): void {
    const result: TgCallDiagnosticResult = tgCallDiagnostics.runRawSignalingCryptoProbe();
    if (result.status === 'passed') {
      hilog.info(DOMAIN, TAG, 'TgCall diagnostics: %{public}s', result.message);
    } else {
      hilog.warn(DOMAIN, TAG, 'TgCall diagnostics: %{public}s', result.message);
    }

    const factoryResult: TgCallDiagnosticResult = tgCallDiagnostics.runFactoryRegistryProbe();
    if (factoryResult.status === 'passed') {
      hilog.info(DOMAIN, TAG, 'TgCall diagnostics: %{public}s', factoryResult.message);
    } else {
      hilog.warn(DOMAIN, TAG, 'TgCall diagnostics: %{public}s', factoryResult.message);
    }

    const webKSignalingResult: TgCallDiagnosticResult = tgCallDiagnostics.runWebKSignalingProbe();
    if (webKSignalingResult.status === 'passed') {
      hilog.info(DOMAIN, TAG, 'TgCall diagnostics: %{public}s', webKSignalingResult.message);
    } else {
      hilog.warn(DOMAIN, TAG, 'TgCall diagnostics: %{public}s', webKSignalingResult.message);
    }

    const webKMediaPathResult: TgCallDiagnosticResult = tgCallDiagnostics.runWebKMediaPathProbe();
    if (webKMediaPathResult.status === 'passed') {
      hilog.info(DOMAIN, TAG, 'TgCall diagnostics: %{public}s', webKMediaPathResult.message);
    } else {
      hilog.warn(DOMAIN, TAG, 'TgCall diagnostics: %{public}s', webKMediaPathResult.message);
    }

    const sessionResult: TgCallDiagnosticResult = tgCallDiagnostics.runSessionLifecycleProbe();
    if (sessionResult.status === 'passed') {
      hilog.info(DOMAIN, TAG, 'TgCall diagnostics: %{public}s', sessionResult.message);
      return;
    }

    hilog.warn(DOMAIN, TAG, 'TgCall diagnostics: %{public}s', sessionResult.message);
  }

  /**
   * Starts full authorization bootstrap:
   * 1) configure TDLib internal log verbosity
   * 2) start polling for async updates
   * 3) request initial authorization state
   */
  startAuthorizationBootstrap(): void {
    if (this.isAuthorizationBootstrapRunning) {
      hilog.info(DOMAIN, TAG, 'startAuthorizationBootstrap ignored: bootstrap already running');
      return;
    }
    this.isAuthorizationBootstrapRunning = true;
    this.init();
    try {
      hilog.info(DOMAIN, TAG, 'STEP 1/3: set TDLib log verbosity');
      this.setLogVerbosityLevel(1);

      hilog.info(DOMAIN, TAG, 'STEP 2/3: start authorization update polling');
      this.startAuthPolling();

      hilog.info(DOMAIN, TAG, 'STEP 3/3: request initial authorization state (async)');
      const request: TdGetAuthorizationStateRequest = { '@type': 'getAuthorizationState' };
      this.send(request);
    } catch (error) {
      this.isAuthorizationBootstrapRunning = false;
      throw new Error(String(error));
    }
  }

  /**
   * Stops authorization polling loop.
   *
   * Does not close TDLib client itself - only stops local polling timer.
   */
  stopAuthorizationBootstrap(): void {
    this.isAuthorizationBootstrapRunning = false;
    if (this.authPollerId < 0) {
      this.stopQrRefreshLoop();
      return;
    }
    clearInterval(this.authPollerId);
    this.authPollerId = -1;
    this.stopQrRefreshLoop();
    hilog.info(DOMAIN, TAG, 'Authorization polling stopped');
  }

  /**
   * Resets singleton runtime state used by mock-driven `ohosTest` cases.
   *
   * The production app does not call this method. It exists to isolate test
   * cases because `tdClient` is a process-wide singleton reused across the
   * whole `entry_test` session.
   */
  resetRuntimeStateForTesting(): void {
    this.stopAuthorizationBootstrap();
    this.clientId = -1;
    this.authState = 'unknown';
    this.tdlibParametersSent = false;
    this.meRequested = false;
    this.meRequestInFlight = false;
    this.meRequestLastSentAtMs = 0;
    this.myUserId = 0;
    this.currentMe = undefined;
    this.authStateListener = undefined;
    this.qrAuthLinkListener = undefined;
    this.meListener = undefined;
    this.contactsListener = undefined;
    this.chatsListener = undefined;
    this.chatMessagesSubscriptions.clear();
    this.pullTokenByChatId.clear();
    this.nextPullToken = 1;
    this.historyPageResolvedSubscriptions.clear();
    this.messageSendResultListener = undefined;
    this.clearPendingSendConfirmationTimeouts();
    this.messageSendConfirmationListeners.clear();
    this.sendExtraByPendingMessageId.clear();
    this.notificationsListener = undefined;
    this.chatReadListener = undefined;
    this.callListener = undefined;
    this.pendingCallEvents = [];
    this.privateChatRequestListeners.clear();
    this.callCreationListeners.clear();
    this.authErrorListener = undefined;
    this.clearQrAuthLink();
    this.resetSessionCaches();
  }

  /**
   * Returns current authorization state known by this wrapper.
   */
  getAuthorizationStateName(): string {
    return this.authState;
  }

  /**
   * Returns expected authentication-code length reported by TDLib.
   *
   * @returns Positive code length, or fallback length when TDLib didn't expose one.
   */
  getExpectedAuthenticationCodeLength(): number {
    return this.authCodeLength;
  }

  /**
   * Registers auth-state listener used by UI.
   *
   * @param listener Callback called on state change.
   */
  setAuthStateListener(listener: (state: string) => void): void {
    this.authStateListener = listener;
  }

  /**
   * Registers QR-link listener used by login UI.
   *
   * @param listener Callback called when QR link value changes.
   */
  setQrAuthLinkListener(listener: (link: string, updatedAtMs: number) => void): void {
    this.qrAuthLinkListener = listener;
  }

  /**
   * Returns current QR login link.
   *
   * @returns QR link received from TDLib or empty string when unavailable.
   */
  getQrAuthLink(): string {
    return this.qrAuthLink;
  }

  /**
   * Returns unix timestamp of the last QR-link update.
   *
   * @returns Milliseconds since epoch, or `0` if link is unknown.
   */
  getQrAuthLinkUpdatedAtMs(): number {
    return this.qrAuthLinkUpdatedAtMs;
  }

  /**
   * Requests manual QR-link refresh in QR authorization state.
   *
   * @returns `true` when refresh request was sent; otherwise `false`.
   */
  refreshQrAuthLink(): boolean {
    if (this.authState !== 'authorizationStateWaitOtherDeviceConfirmation') {
      hilog.info(DOMAIN, TAG, 'refreshQrAuthLink ignored in state=%{public}s', this.authState);
      return false;
    }
    this.sendRequestQrCodeAuthentication('manual');
    return true;
  }

  /**
   * Requests QR-first login flow.
   *
   * Allowed states:
   * - `authorizationStateWaitPhoneNumber` (switch from phone prompt to QR flow)
   * - `authorizationStateWaitOtherDeviceConfirmation` (refresh QR link)
   *
   * @returns `true` when request was sent, otherwise `false`.
   */
  requestQrLoginPreference(): boolean {
    if (this.authState !== 'authorizationStateWaitPhoneNumber'
      && this.authState !== 'authorizationStateWaitOtherDeviceConfirmation') {
      hilog.info(DOMAIN, TAG, 'requestQrLoginPreference ignored in state=%{public}s', this.authState);
      return false;
    }

    const reason = this.authState === 'authorizationStateWaitPhoneNumber'
      ? 'prefer-from-phone-state'
      : 'prefer-refresh';
    this.sendRequestQrCodeAuthentication(reason);
    return true;
  }

  /**
   * Registers current-user listener used by UI.
   *
   * @param listener Callback called when user profile is available.
   */
  setMeListener(listener: (me: TdMeInfo) => void): void {
    this.meListener = listener;
    if (this.currentMe) {
      this.meListener(this.currentMe);
    }
  }

  /**
   * Registers contacts-list listener used by UI.
   *
   * @param listener Callback called whenever contacts list state is updated.
   */
  setContactsListener(listener: (contacts: TdContactListItem[]) => void): void {
    this.contactsListener = listener;
  }

  /**
   * Registers chats-list listener used by UI.
   *
   * @param listener Callback called whenever chat list state is updated.
   */
  setChatsListener(listener: (chats: TdChatListItem[]) => void): void {
    this.chatsListener = listener;
  }

  /**
   * Subscribes a chat-messages listener. Multiple subscribers receive the same fan-out emit, so
   * a page pushed on top of ChatDetails (e.g. MediaViewer) does not steal the ChatDetails slot.
   * The returned token must be passed to `unsubscribeChatMessages` to detach the listener; treat
   * `0` as the "not subscribed" sentinel since the first issued token is `1`.
   *
   * @param listener Callback called with chat id and parsed message list.
   * @returns Subscription token used to unsubscribe.
   */
  subscribeChatMessages(listener: (chatId: string, messages: TdChatMessageItem[]) => void): number {
    return this.chatMessagesSubscriptions.subscribe(listener);
  }

  /**
   * Removes a previously-registered chat-messages listener. Idempotent on unknown tokens
   * (including the `0` sentinel), so views can safely call this from `aboutToDisappear` without
   * tracking whether `subscribeChatMessages` actually ran.
   *
   * @param token Subscription token returned by `subscribeChatMessages`.
   */
  unsubscribeChatMessages(token: number): void {
    this.chatMessagesSubscriptions.unsubscribe(token);
  }

  /**
   * Subscribes to "your older-history pull just resolved" events. Fires ONLY for responses to a
   * pull request that was previously dispatched via `requestOlderChatHistory` (and returned
   * `'started'`); live updates, read-outbox events, and internal probe retries do not trigger it.
   *
   * Outcomes:
   * - `'page-loaded'` — TDLib returned a page and there may still be more older history.
   * - `'no-more'`     — the response exhausted older history (toast trigger for the view).
   * - `'rejected'`    — reserved for future async-error correlation; not emitted today.
   *
   * @param listener Callback invoked once per resolved pull cycle.
   * @returns Subscription token used to unsubscribe.
   */
  subscribeHistoryPageResolved(
    listener: (chatId: string, outcome: 'page-loaded' | 'no-more' | 'rejected') => void
  ): number {
    return this.historyPageResolvedSubscriptions.subscribe(listener);
  }

  /**
   * Removes a previously-registered history-page-resolved listener. Idempotent on the `0`
   * sentinel and on unknown tokens.
   *
   * @param token Subscription token returned by `subscribeHistoryPageResolved`.
   */
  unsubscribeHistoryPageResolved(token: number): void {
    this.historyPageResolvedSubscriptions.unsubscribe(token);
  }

  /**
   * Fans out a history-page-resolved event to all subscribers. Each callback is isolated by
   * try/catch so a throwing subscriber cannot block the rest.
   */
  private emitHistoryPageResolved(chatId: string, outcome: 'page-loaded' | 'no-more' | 'rejected'): void {
    this.historyPageResolvedSubscriptions.forEach(
      (listener: (chatId: string, outcome: 'page-loaded' | 'no-more' | 'rejected') => void): void => {
        listener(chatId, outcome);
      }
    );
  }

  /**
   * Fires `historyPageResolved` if (and only if) the response's `pullToken` matches the latest
   * token registered for `chatId` in `pullTokenByChatId`. Mismatch (or zero token) silently
   * skips — that's how non-pull responses (initial load, deeplink, internal probe/sparse
   * retries) and STALE pull responses (a later user pull already overwrote the token) avoid
   * spuriously closing a pull cycle they didn't initiate.
   */
  private resolvePendingPullIfAny(chatId: string, pullToken: number, outcome: 'page-loaded' | 'no-more'): void {
    if (pullToken <= 0) {
      return;
    }
    const expected = this.pullTokenByChatId.get(chatId);
    if (expected !== pullToken) {
      return;
    }
    this.pullTokenByChatId.delete(chatId);
    this.emitHistoryPageResolved(chatId, outcome);
  }

  /**
   * Drops any pending pull-token registration for `chatId`. Intended for view-side cleanup when
   * the defensive timeout fires or the page is leaving while a pull is still in flight — keeps
   * `pullTokenByChatId` from holding a stale entry that a late TDLib response could then
   * accidentally match.
   */
  abandonPendingPull(chatId: string): void {
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      return;
    }
    this.pullTokenByChatId.delete(safeChatId);
  }

  /**
   * Centralized mutator for `historyHasMoreByChatId`. Single-point-of-write discipline so the
   * exhausted/has-more semantic is greppable from one place; the actual pull-close signal
   * (toast trigger included) is emitted separately via `resolvePendingPullIfAny` so live
   * updates and probe retries cannot fire spurious events.
   */
  private setHistoryHasMore(chatId: string, value: boolean): void {
    this.historyHasMoreByChatId.set(chatId, value);
  }

  /**
   * Registers `sendMessage` result listener used by chat composer UI.
   *
   * @param listener Callback called when TDLib confirms or rejects message send request.
   */
  setMessageSendResultListener(listener: (chatId: string, ok: boolean, errorMessage: string) => void): void {
    this.messageSendResultListener = listener;
  }

  /**
   * Sends text message and reports the final TDLib send outcome for this concrete request.
   *
   * The callback is keyed by request `@extra` and is fired only after TDLib confirms
   * `updateMessageSendSucceeded` or rejects the original `sendMessage` request.
   *
   * @param chatId Target chat id as TDLib int64 string.
   * @param text Message text to send.
   * @param listener One-shot callback for final send outcome.
   * @returns `true` when request was sent and callback registered, otherwise `false`.
   */
  sendChatTextMessageWithConfirm(
    chatId: string,
    text: string,
    listener: (ok: boolean, errorMessage: string) => void
  ): boolean {
    if (!this.canRunAuthorizedRequest('sendChatTextMessageWithConfirm')) {
      return false;
    }

    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      hilog.error(DOMAIN, TAG, 'sendChatTextMessageWithConfirm rejected: empty chat id');
      return false;
    }

    const safeText = text.trim();
    if (safeText.length === 0) {
      hilog.error(DOMAIN, TAG, 'sendChatTextMessageWithConfirm rejected: empty text');
      return false;
    }

    const extra = `message:send:${safeChatId}:confirm:${Date.now()}`;
    this.messageSendConfirmationListeners.set(extra, listener);
    this.armSendConfirmationTimeout(extra, safeChatId);
    if (!this.sendChatTextMessageInternal(safeChatId, safeText, extra, 'sendChatTextMessageWithConfirm')) {
      this.clearSendConfirmationRegistration(extra);
      return false;
    }

    return true;
  }

  /**
   * Registers TDLib notification update listener used by notification services.
   *
   * @param listener Callback called for parsed TDLib notification events.
   */
  setNotificationsListener(listener: ((event: TdNotificationEvent) => void) | undefined): void {
    this.notificationsListener = listener;
    if (!listener) {
      this.notificationBufferingEnabled = false;
      this.pendingNotificationEvents = [];
      return;
    }

    this.notificationBufferingEnabled = true;
    if (this.pendingNotificationEvents.length === 0) {
      return;
    }

    const pendingEvents = this.pendingNotificationEvents;
    this.pendingNotificationEvents = [];
    hilog.info(DOMAIN, TAG, 'Flushing pending notification events: %{public}d', pendingEvents.length);
    for (const event of pendingEvents) {
      listener(this.cloneNotificationEvent(event));
    }
  }

  /**
   * Registers chat-read listener used by notification services.
   *
   * @param listener Callback called when TDLib moves a chat inbox read cursor.
   */
  setChatReadListener(listener: ((chatId: string) => void) | undefined): void {
    this.chatReadListener = listener;
    if (!listener) {
      this.chatReadBufferingEnabled = false;
      this.pendingChatReadChatIds = [];
      return;
    }

    this.chatReadBufferingEnabled = true;
    if (this.pendingChatReadChatIds.length === 0) {
      return;
    }

    const pendingChatIds = this.pendingChatReadChatIds;
    this.pendingChatReadChatIds = [];
    hilog.info(DOMAIN, TAG, 'Flushing pending chat-read events: %{public}d', pendingChatIds.length);
    for (const chatId of pendingChatIds) {
      listener(chatId);
    }
  }

  /**
   * Registers TDLib call update listener used by notification/call services.
   *
   * @param listener Callback called for parsed TDLib call events.
   */
  setCallListener(listener: ((event: TdCallEvent) => void) | undefined): void {
    this.callListener = listener;
    if (!listener) {
      this.callBufferingEnabled = false;
      this.pendingCallEvents = [];
      return;
    }

    this.callBufferingEnabled = true;
    if (this.pendingCallEvents.length === 0) {
      return;
    }

    const pendingEvents = this.pendingCallEvents;
    this.pendingCallEvents = [];
    hilog.info(DOMAIN, TAG, 'Flushing pending call events: %{public}d', pendingEvents.length);
    for (const event of pendingEvents) {
      listener(this.cloneCallEvent(event));
    }
  }

  /**
   * Refreshes chat descriptors needed to reconcile hydrated notification requests.
   *
   * @param chatIds TDLib chat ids resolved from active system notifications.
   */
  refreshNotificationChats(chatIds: string[]): void {
    if (!this.canRunAuthorizedRequest('refreshNotificationChats')) {
      return;
    }

    let requestedCount = 0;
    for (const chatId of chatIds) {
      const safeChatId = chatId.trim();
      if (safeChatId.length === 0) {
        continue;
      }
      this.notificationRefreshChatIds.add(safeChatId);
      this.requestChatDetails(safeChatId, true);
      requestedCount += 1;
    }

    if (requestedCount > 0) {
      hilog.info(DOMAIN, TAG, 'Requested notification chat refresh: %{public}d', requestedCount);
    }
  }

  /**
   * Returns best-known chat title from the local TDLib chat cache.
   *
   * @param chatId TDLib chat id.
   * @returns Cached title or empty string when unavailable.
   */
  getCachedChatTitle(chatId: string): string {
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      return '';
    }

    const title = this.chatTitleById.get(safeChatId);
    if (title !== undefined && title.length > 0 && title !== 'Unknown chat') {
      return title;
    }
    return '';
  }

  /**
   * Returns best-known avatar path for one chat from the local TDLib chat cache.
   *
   * @param chatId TDLib chat id.
   * @returns Cached avatar path or empty string when unavailable.
   */
  getCachedChatAvatarPath(chatId: string): string {
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      return '';
    }
    const path = this.chatAvatarPathByChatId.get(safeChatId);
    if (path !== undefined && path.length > 0) {
      return path;
    }
    return '';
  }

  /**
   * Returns best-known avatar path for one user from the local TDLib user cache.
   *
   * @param userId TDLib user id.
   * @returns Cached avatar path or empty string when unavailable.
   */
  getCachedUserAvatarPath(userId: string): string {
    const safeUserId = userId.trim();
    if (safeUserId.length === 0) {
      return '';
    }
    const path = this.userAvatarPathByUserId.get(safeUserId);
    if (path !== undefined && path.length > 0) {
      return path;
    }
    return '';
  }

  /**
   * Returns cached user-profile snapshot for one TDLib user id.
   *
   * @param userId User id as TDLib int64 string.
   * @returns Cached user-profile snapshot or `undefined` when the id is unknown.
   */
  getUserProfile(userId: string): TdUserProfileItem | undefined {
    const safeUserId = userId.trim();
    if (safeUserId.length === 0) {
      return undefined;
    }

    let firstName = this.firstNameByUserId.get(safeUserId);
    let lastName = this.lastNameByUserId.get(safeUserId);
    let username = this.usernameByUserId.get(safeUserId);
    let phoneNumber = this.phoneNumberByUserId.get(safeUserId);
    let avatarPath = this.userAvatarPathByUserId.get(safeUserId);
    let avatarAnimationPath = this.userAnimatedAvatarPathByUserId.get(safeUserId);

    if (this.currentMe && String(this.currentMe.id) === safeUserId) {
      if ((firstName === undefined || firstName.length === 0) && this.currentMe.firstName.length > 0) {
        firstName = this.currentMe.firstName;
      }
      if ((lastName === undefined || lastName.length === 0) && this.currentMe.lastName.length > 0) {
        lastName = this.currentMe.lastName;
      }
      if ((username === undefined || username.length === 0) && this.currentMe.username.length > 0) {
        username = this.currentMe.username;
      }
      if ((phoneNumber === undefined || phoneNumber.length === 0) && this.currentMe.phoneNumber.length > 0) {
        phoneNumber = this.currentMe.phoneNumber;
      }
      if ((avatarPath === undefined || avatarPath.length === 0)
        && typeof this.currentMe.avatarPath === 'string'
        && this.currentMe.avatarPath.length > 0) {
        avatarPath = this.currentMe.avatarPath;
      }
      if ((avatarAnimationPath === undefined || avatarAnimationPath.length === 0)
        && typeof this.currentMe.avatarAnimationPath === 'string'
        && this.currentMe.avatarAnimationPath.length > 0) {
        avatarAnimationPath = this.currentMe.avatarAnimationPath;
      }
    }

    const hasProfileData = (firstName !== undefined && firstName.length > 0) ||
      (lastName !== undefined && lastName.length > 0) ||
      (username !== undefined && username.length > 0) ||
      (phoneNumber !== undefined && phoneNumber.length > 0) ||
      (avatarPath !== undefined && avatarPath.length > 0) ||
      (avatarAnimationPath !== undefined && avatarAnimationPath.length > 0);
    if (!hasProfileData) {
      return undefined;
    }

    return {
      'id': safeUserId,
      'firstName': firstName !== undefined ? firstName : '',
      'lastName': lastName !== undefined ? lastName : '',
      'username': username !== undefined ? username : '',
      'phoneNumber': phoneNumber !== undefined ? phoneNumber : '',
      'avatarPath': avatarPath,
      'avatarAnimationPath': avatarAnimationPath
    };
  }

  /**
   * Registers authorization-error listener used by login UI.
   *
   * @param listener Callback called for TDLib errors tagged with `auth:*` extra.
   */
  setAuthErrorListener(listener: (extra: string, code: number, message: string) => void): void {
    this.authErrorListener = listener;
  }

  /**
   * Requests Telegram contacts linked to current account.
   */
  requestContacts(): void {
    if (!this.canRunAuthorizedRequest('requestContacts')) {
      return;
    }
    this.requestedContactUserIds.clear();
    const request: TdGetContactsRequest = {
      '@type': 'getContacts',
      '@extra': TdClient.CONTACTS_EXTRA_GET
    };
    this.send(request);
    hilog.info(DOMAIN, TAG, 'Requested contacts list');
  }

  /**
   * Requests main chat list from TDLib.
   *
   * This method sends:
   * 1) `loadChats` to make sure list cache is warmed up
   * 2) `getChats` to fetch current ordered chat ids
   * 3) `getChat` for every returned chat id to resolve chat title
   *
   * @param limit Max number of chats requested from main chat list.
   */
  requestChats(limit: number = 30): void {
    if (!this.canRunAuthorizedRequest('requestChats')) {
      return;
    }
    const safeLimit = limit > 0 ? limit : 30;
    this.requestedChatIds.clear();

    const loadRequest: TdLoadChatsRequest = {
      '@type': 'loadChats',
      '@extra': TdClient.CHATS_EXTRA_LOAD_MAIN,
      'chat_list': { '@type': 'chatListMain' },
      'limit': safeLimit
    };
    const getRequest: TdGetChatsRequest = {
      '@type': 'getChats',
      '@extra': TdClient.CHATS_EXTRA_GET_MAIN,
      'chat_list': { '@type': 'chatListMain' },
      'limit': safeLimit,
      'offset_order': '9223372036854775807',
      'offset_chat_id': '0'
    };

    this.send(loadRequest);
    this.send(getRequest);
    hilog.info(DOMAIN, TAG, 'Requested chat list (limit=%{public}d)', safeLimit);
    if (TdClient.ENABLE_ARCHIVE_CHAT_LIST_PROBE) {
      this.requestArchiveChatsProbe(safeLimit);
    }
  }

  /**
   * Creates or opens a private chat for selected user and reports the real TDLib chat id.
   *
   * @param userId Target user id as TDLib int64 string.
   * @param listener Callback invoked with opened chat or error message.
   * @returns `true` when cached chat exists or request was sent.
   */
  requestPrivateChat(
    userId: string,
    listener: (chat: TdChatListItem | undefined, errorMessage: string) => void
  ): boolean {
    if (!this.canRunAuthorizedRequest('requestPrivateChat')) {
      listener(undefined, 'Not authorized.');
      return false;
    }

    const safeUserId = userId.trim();
    if (safeUserId.length === 0 || safeUserId === '-') {
      listener(undefined, 'Missing user id.');
      return false;
    }

    const cachedChat = this.findPrivateChatByUserId(safeUserId);
    if (cachedChat) {
      listener(cachedChat, '');
      return true;
    }

    const extra = `${TdClient.PRIVATE_CHAT_EXTRA_CREATE_PREFIX}${safeUserId}:${Date.now()}`;
    this.privateChatRequestListeners.set(extra, listener);
    const request: TdCreatePrivateChatRequest = {
      '@type': 'createPrivateChat',
      '@extra': extra,
      'user_id': safeUserId,
      'force': false
    };
    this.send(request);
    hilog.info(DOMAIN, TAG, 'Requested private chat (userId=%{public}s)', safeUserId);
    return true;
  }

  /**
   * Sends archive-list probe requests used to diagnose missing chats in main list.
   *
   * @param limit Max number of chats requested from archive list.
   */
  private requestArchiveChatsProbe(limit: number): void {
    const safeLimit = limit > 0 ? limit : 30;
    const getArchiveRequest: TdGetChatsRequest = {
      '@type': 'getChats',
      '@extra': TdClient.CHATS_EXTRA_GET_ARCHIVE,
      'chat_list': { '@type': 'chatListArchive' },
      'limit': safeLimit,
      'offset_order': '9223372036854775807',
      'offset_chat_id': '0'
    };
    this.send(getArchiveRequest);
    hilog.info(DOMAIN, TAG, 'Requested archive chat probe via getChats (limit=%{public}d)', safeLimit);
  }

  /**
   * Sends `loadChats/getChats` probe for a single custom folder.
   *
   * @param folderId TDLib custom folder id.
   * @param limit Max number of chats requested from folder list.
   */
  private requestSingleFolderChatsProbe(folderId: number, limit: number): void {
    const safeLimit = limit > 0 ? limit : 30;
    const loadExtra = `${TdClient.CHATS_EXTRA_LOAD_FOLDER_PREFIX}${folderId}`;
    const getExtra = `${TdClient.CHATS_EXTRA_GET_FOLDER_PREFIX}${folderId}`;
    const loadFolderRequest: TdLoadChatsRequest = {
      '@type': 'loadChats',
      '@extra': loadExtra,
      'chat_list': { '@type': 'chatListFolder', 'chat_folder_id': folderId },
      'limit': safeLimit
    };
    const getFolderRequest: TdGetChatsRequest = {
      '@type': 'getChats',
      '@extra': getExtra,
      'chat_list': { '@type': 'chatListFolder', 'chat_folder_id': folderId },
      'limit': safeLimit,
      'offset_order': '9223372036854775807',
      'offset_chat_id': '0'
    };
    this.send(loadFolderRequest);
    this.send(getFolderRequest);
    hilog.info(DOMAIN, TAG, 'Requested folder chat probe (folderId=%{public}d, limit=%{public}d)', folderId, safeLimit);
  }

  /**
   * Requests message history for selected chat.
   *
   * @param chatId Chat id as TDLib int64 string.
   * @param limit Max number of messages requested from TDLib.
   */
  requestChatHistory(chatId: string, limit: number = 40): void {
    if (!this.canRunAuthorizedRequest('requestChatHistory')) {
      return;
    }
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      hilog.error(DOMAIN, TAG, 'requestChatHistory rejected: empty chat id');
      return;
    }

    const safeLimit = limit > 0 ? limit : 40;
    this.historyLimitByChatId.set(safeChatId, safeLimit);
    this.historyRequestedFromByChatId.set(safeChatId, new Set<string>());
    this.historyNextFromByChatId.set(safeChatId, '0');
    this.setHistoryHasMore(safeChatId, true);
    this.historyRetryBudgetByChatId.set(safeChatId, 1);
    this.historyChatNotFoundRetryBudgetByChatId.set(safeChatId, 0);
    this.requestChatHistoryPage(safeChatId, safeLimit, '0');
  }

  /**
   * Requests message history for selected chat, starting around a known message id.
   *
   * @param chatId Chat id as TDLib int64 string.
   * @param limit Max number of messages requested from TDLib.
   * @param fromMessageId Message id requested near the middle of the first page.
   */
  requestChatHistoryFromMessage(chatId: string, limit: number, fromMessageId: string): void {
    if (!this.canRunAuthorizedRequest('requestChatHistoryFromMessage')) {
      return;
    }
    const safeChatId = chatId.trim();
    const safeFromMessageId = fromMessageId.trim();
    if (safeChatId.length === 0 || safeFromMessageId.length === 0) {
      hilog.error(DOMAIN, TAG, 'requestChatHistoryFromMessage rejected: empty chat or message id');
      return;
    }

    const safeLimit = limit > 0 ? limit : 40;
    const centeredOffset = -Math.floor(safeLimit / 2);
    this.historyLimitByChatId.set(safeChatId, safeLimit);
    this.historyRequestedFromByChatId.set(safeChatId, new Set<string>());
    this.historyNextFromByChatId.set(safeChatId, safeFromMessageId);
    this.setHistoryHasMore(safeChatId, true);
    this.historyRetryBudgetByChatId.set(safeChatId, 1);
    this.historyChatNotFoundRetryBudgetByChatId.set(safeChatId, 1);
    this.requestChatHistoryPage(safeChatId, safeLimit, safeFromMessageId, false, centeredOffset);
  }

  /**
   * Requests next older chat-history page for already initialized chat timeline.
   *
   * Intended for pull-to-load gesture when user reaches top of message list.
   *
   * @param chatId Chat id as TDLib int64 string.
   * @returns `'started'` when the upstream request was issued (an emit will follow),
   * `'no-more-pages'` when the history was already exhausted upstream, `'rejected'`
   * when the request is malformed or unauthorized.
   */
  requestOlderChatHistory(chatId: string): 'started' | 'no-more-pages' | 'rejected' {
    if (!this.canRunAuthorizedRequest('requestOlderChatHistory')) {
      return 'rejected';
    }
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      hilog.debug(DOMAIN, TAG, 'requestOlderChatHistory ignored: empty chat id');
      return 'rejected';
    }

    const limit = this.historyLimitByChatId.get(safeChatId);
    if (typeof limit !== 'number' || limit <= 0) {
      hilog.debug(DOMAIN, TAG, 'requestOlderChatHistory ignored: no history limit (chatId=%{public}s)', safeChatId);
      return 'rejected';
    }

    const hasMore = this.historyHasMoreByChatId.get(safeChatId);
    const cachedMessages = this.messagesByChatId.get(safeChatId);
    const cachedCount = cachedMessages ? cachedMessages.length : 0;
    const retryBudget = this.historyRetryBudgetByChatId.get(safeChatId);
    const budget = typeof retryBudget === 'number' ? retryBudget : 0;
    // Reserve (but do not yet consume) a unique pull token. The token is consumed — i.e.
    // `nextPullToken` is bumped and `pullTokenByChatId` populated — ONLY at the moment a
    // dispatch actually succeeds, so rejected calls never burn a token. This also guarantees
    // that a failed `requestChatHistoryPage` leaves no stale entry that could match a future
    // response.
    const pullToken = this.nextPullToken;
    if (hasMore === false) {
      if (budget > 0 && cachedCount > 0 && cachedCount < limit) {
        // First response may be partial (locally cached only). Allow pull-to-refresh retry.
        this.historyRetryBudgetByChatId.set(safeChatId, budget - 1);
        hilog.info(DOMAIN, TAG,
          'requestOlderChatHistory retrying first page (chatId=%{public}s, cached=%{public}d, limit=%{public}d, budgetLeft=%{public}d)',
          safeChatId,
          cachedCount,
          limit,
          budget - 1
        );
        if (this.requestChatHistoryPage(safeChatId, limit, '0', true, 0, pullToken)) {
          this.pullTokenByChatId.set(safeChatId, pullToken);
          this.nextPullToken = pullToken + 1;
          return 'started';
        }
        return 'rejected';
      }
      hilog.info(DOMAIN, TAG,
        'requestOlderChatHistory no more pages (chatId=%{public}s, cached=%{public}d, limit=%{public}d)',
        safeChatId,
        cachedCount,
        limit
      );
      return 'no-more-pages';
    }

    let fromMessageId = this.historyNextFromByChatId.get(safeChatId);
    if (typeof fromMessageId !== 'string' || fromMessageId.length === 0) {
      const cachedMessages = this.messagesByChatId.get(safeChatId);
      if (cachedMessages && cachedMessages.length > 0) {
        fromMessageId = cachedMessages[0].id;
      } else {
        fromMessageId = '0';
      }
    }

    const started = this.requestChatHistoryPage(safeChatId, limit, fromMessageId, false, 0, pullToken);
    if (started) {
      this.pullTokenByChatId.set(safeChatId, pullToken);
      this.nextPullToken = pullToken + 1;
      return 'started';
    }
    // Allow user-initiated pull to retry even if the same cursor was already requested.
    const retryStarted = this.requestChatHistoryPage(safeChatId, limit, fromMessageId, true, 0, pullToken);
    hilog.info(DOMAIN, TAG,
      'requestOlderChatHistory duplicate cursor retry (chatId=%{public}s, from=%{public}s, started=%{public}d)',
      safeChatId,
      fromMessageId,
      retryStarted ? 1 : 0
    );
    if (retryStarted) {
      this.pullTokenByChatId.set(safeChatId, pullToken);
      this.nextPullToken = pullToken + 1;
      return 'started';
    }
    return 'rejected';
  }

  /**
   * Marks the currently visible chat messages as viewed/read in TDLib.
   *
   * @param chatId Chat id as TDLib int64 string.
   * @param messages Messages currently rendered in the timeline.
   */
  viewMessages(chatId: string, messages: TdChatMessageItem[]): void {
    if (!this.canRunAuthorizedRequest('viewMessages')) {
      return;
    }
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0 || messages.length === 0) {
      return;
    }

    const messageIds: string[] = [];
    for (const message of messages) {
      if (!message.isOutgoing && message.id.length > 0) {
        messageIds.push(message.id);
      }
    }
    if (messageIds.length === 0) {
      return;
    }

    const firstMessageId = messageIds[0];
    const tailMessageId = messageIds[messageIds.length - 1];
    const previousTailMessageId = this.viewedTailMessageIdByChatId.get(safeChatId);
    if (previousTailMessageId === tailMessageId) {
      hilog.debug(
        DOMAIN,
        TAG,
        'viewMessages skipped: tail already submitted (chatId=%{public}s, tail=%{public}s, count=%{public}d)',
        safeChatId,
        tailMessageId,
        messageIds.length
      );
      return;
    }
    this.viewedTailMessageIdByChatId.set(safeChatId, tailMessageId);

    const unreadBefore = this.chatUnreadCountByChatId.get(safeChatId);
    const request: TdViewMessagesRequest = {
      '@type': 'viewMessages',
      '@extra': `messages:view:${safeChatId}:${tailMessageId}`,
      'chat_id': safeChatId,
      'message_ids': messageIds,
      'source': { '@type': 'messageSourceChatHistory' },
      'force_read': true
    };
    this.send(request);
    hilog.info(
      DOMAIN,
      TAG,
      'Requested viewMessages for badge consume (chatId=%{public}s, count=%{public}d, first=%{public}s, tail=%{public}s, unreadBefore=%{public}d)',
      safeChatId,
      messageIds.length,
      firstMessageId,
      tailMessageId,
      typeof unreadBefore === 'number' ? unreadBefore : -1
    );
  }

  /**
   * Requests asynchronous download for selected TDLib file id.
   *
   * @param fileId TDLib file identifier.
   * @param priority Download priority in TDLib scheduler.
   * @returns `true` when request was sent.
   */
  downloadFile(fileId: number, priority: number = 1): boolean {
    if (fileId <= 0) {
      return false;
    }
    const request: TdDownloadFileRequest = {
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': priority > 0 ? priority : 1,
      'offset': 0,
      'limit': 0,
      'synchronous': false
    };
    this.send(request);
    return true;
  }

  /**
   * Cancels asynchronous download for selected TDLib file id.
   *
   * @param fileId TDLib file identifier.
   * @returns `true` when cancel request was sent.
   */
  cancelDownloadFile(fileId: number): boolean {
    if (fileId <= 0) {
      return false;
    }
    const request: TdCancelDownloadFileRequest = {
      '@type': 'cancelDownloadFile',
      'file_id': fileId,
      'only_if_pending': false
    };
    this.send(request);
    return true;
  }

  /**
   * Creates a new outgoing call to the given user.
   *
   * TDLib answers `createCall` with a synchronous `callId` payload correlated by
   * `@extra`; the call lifecycle then continues through `updateCall` events.
   *
   * @param userId Target user id as TDLib int64 string.
   * @param protocol Call protocol accepted by local VoIP implementation.
   * @param isVideo Whether to start a video call.
   * @param listener Callback invoked with the created call id or an error message.
   * @returns `true` when request was sent.
   */
  createCall(
    userId: string,
    protocol: TdCallProtocolRequest,
    isVideo: boolean,
    listener: (callId: number, errorMessage: string) => void
  ): boolean {
    if (!this.canRunAuthorizedRequest('createCall')) {
      listener(0, 'Not authorized.');
      return false;
    }

    const safeUserId = userId.trim();
    const numericUserId = Number.parseInt(safeUserId, 10);
    if (safeUserId.length === 0 || safeUserId === '-' || Number.isNaN(numericUserId) || numericUserId <= 0) {
      hilog.error(DOMAIN, TAG, 'createCall rejected: invalid user id=%{public}s', safeUserId);
      listener(0, 'Missing user id.');
      return false;
    }

    const extra = `${TdClient.CALL_EXTRA_CREATE_PREFIX}${safeUserId}:${Date.now()}`;
    this.callCreationListeners.set(extra, listener);
    const request: TdCreateCallRequest = {
      '@type': 'createCall',
      '@extra': extra,
      'user_id': numericUserId,
      'protocol': protocol,
      'is_video': isVideo
    };
    this.send(request);
    hilog.info(DOMAIN, TAG, 'Requested createCall (userId=%{public}s, video=%{public}d)', safeUserId, isVideo ? 1 : 0);
    return true;
  }

  /**
   * Accepts an incoming call using the provided TDLib call protocol.
   *
   * @param callId TDLib call id.
   * @param protocol Call protocol accepted by local VoIP implementation.
   * @returns `true` when request was sent.
   */
  acceptCall(callId: number, protocol: TdCallProtocolRequest): boolean {
    if (!this.canRunAuthorizedRequest('acceptCall')) {
      return false;
    }
    if (callId <= 0) {
      hilog.error(DOMAIN, TAG, 'acceptCall rejected: invalid call id=%{public}d', callId);
      return false;
    }
    const request: TdAcceptCallRequest = {
      '@type': 'acceptCall',
      '@extra': `call:accept:${callId}:${Date.now()}`,
      'call_id': Math.trunc(callId),
      'protocol': protocol
    };
    this.send(request);
    hilog.info(DOMAIN, TAG, 'Requested acceptCall (callId=%{public}d)', callId);
    return true;
  }

  /**
   * Discards or ends a TDLib call.
   *
   * @param callId TDLib call id.
   * @param isDisconnected Whether local network/audio connection was disconnected.
   * @param durationSec Call duration in seconds, if known.
   * @param isVideo Whether the call is a video call.
   * @param connectionId TDLib connection id, or `0` when not available.
   * @returns `true` when request was sent.
   */
  discardCall(
    callId: number,
    isDisconnected: boolean = false,
    durationSec: number = 0,
    isVideo: boolean = false,
    connectionId: string = '0'
  ): boolean {
    if (!this.canRunAuthorizedRequest('discardCall')) {
      return false;
    }
    if (callId <= 0) {
      hilog.error(DOMAIN, TAG, 'discardCall rejected: invalid call id=%{public}d', callId);
      return false;
    }
    const safeDuration = durationSec > 0 ? Math.trunc(durationSec) : 0;
    const trimmedConnectionId = connectionId.trim();
    const request: TdDiscardCallRequest = {
      '@type': 'discardCall',
      '@extra': `call:discard:${callId}:${Date.now()}`,
      'call_id': Math.trunc(callId),
      'is_disconnected': isDisconnected,
      'invite_link': '',
      'duration': safeDuration,
      'is_video': isVideo,
      'connection_id': trimmedConnectionId.length > 0 ? trimmedConnectionId : '0'
    };
    this.send(request);
    hilog.info(
      DOMAIN,
      TAG,
      'Requested discardCall (callId=%{public}d, duration=%{public}d)',
      callId,
      safeDuration
    );
    return true;
  }

  /**
   * Sends opaque TDLib call signaling data.
   *
   * @param callId TDLib call id.
   * @param data Signaling data received from local VoIP implementation.
   * @returns `true` when request was sent.
   */
  sendCallSignalingData(callId: number, data: string): boolean {
    if (!this.canRunAuthorizedRequest('sendCallSignalingData')) {
      return false;
    }
    if (callId <= 0) {
      hilog.error(DOMAIN, TAG, 'sendCallSignalingData rejected: invalid call id=%{public}d', callId);
      return false;
    }
    const safeData = data.trim();
    if (safeData.length === 0) {
      hilog.error(DOMAIN, TAG, 'sendCallSignalingData rejected: empty data');
      return false;
    }
    const request: TdSendCallSignalingDataRequest = {
      '@type': 'sendCallSignalingData',
      '@extra': `call:signal:${callId}:${Date.now()}`,
      'call_id': Math.trunc(callId),
      'data': safeData
    };
    this.send(request);
    hilog.debug(
      DOMAIN,
      TAG,
      'Requested sendCallSignalingData (callId=%{public}d, bytes=%{public}d)',
      callId,
      safeData.length
    );
    return true;
  }

  /**
   * Sends plain-text message to selected chat.
   *
   * @param chatId Target chat id as TDLib int64 string.
   * @param text Message text from compose input.
   * @returns `true` when request was sent, otherwise `false`.
   */
  sendChatTextMessage(chatId: string, text: string): boolean {
    if (!this.canRunAuthorizedRequest('sendChatTextMessage')) {
      return false;
    }
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      hilog.error(DOMAIN, TAG, 'sendChatTextMessage rejected: empty chat id');
      return false;
    }

    const safeText = text.trim();
    if (safeText.length === 0) {
      hilog.error(DOMAIN, TAG, 'sendChatTextMessage rejected: empty text');
      return false;
    }

    const extra = `message:send:${safeChatId}:${Date.now()}`;
    return this.sendChatTextMessageInternal(safeChatId, safeText, extra, 'sendChatTextMessage');
  }

  private sendChatTextMessageInternal(
    safeChatId: string,
    safeText: string,
    extra: string,
    sourceName: string
  ): boolean {
    const request: TdSendMessageRequest = {
      '@type': 'sendMessage',
      '@extra': extra,
      'chat_id': safeChatId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {
          '@type': 'formattedText',
          'text': safeText
        },
        'clear_draft': true
      }
    };
    this.send(request);
    hilog.info(DOMAIN, TAG, 'Requested sendMessage via %{public}s (chatId=%{public}s, extra=%{public}s, textLen=%{public}d)',
      sourceName,
      safeChatId,
      extra,
      safeText.length
    );
    return true;
  }

  /**
   * Sends voice-note message to selected chat.
   *
   * @param chatId Target chat id as TDLib int64 string.
   * @param filePath Local encoded `.oga` file path.
   * @param durationSec Voice-note duration in seconds.
   * @param waveform Raw 5-bit waveform bitstream returned by native recorder.
   * @returns `true` when request was sent, otherwise `false`.
   */
  sendChatVoiceNoteMessage(chatId: string, filePath: string, durationSec: number, waveform: ArrayBuffer): boolean {
    if (!this.canRunAuthorizedRequest('sendChatVoiceNoteMessage')) {
      return false;
    }

    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      hilog.error(DOMAIN, TAG, 'sendChatVoiceNoteMessage rejected: empty chat id');
      return false;
    }

    const safeFilePath = filePath.trim();
    if (safeFilePath.length === 0) {
      hilog.error(DOMAIN, TAG, 'sendChatVoiceNoteMessage rejected: empty file path');
      return false;
    }

    const safeDurationSec = Math.round(durationSec);
    if (safeDurationSec <= 0) {
      hilog.error(DOMAIN, TAG, 'sendChatVoiceNoteMessage rejected: invalid duration=%{public}d', safeDurationSec);
      return false;
    }

    const waveformBytes = new Uint8Array(waveform);
    if (waveformBytes.length === 0) {
      hilog.error(DOMAIN, TAG, 'sendChatVoiceNoteMessage rejected: empty waveform');
      return false;
    }

    const waveformBase64 = encodeTdVoiceNoteWaveform(waveformBytes);
    if (waveformBase64.length === 0) {
      hilog.error(DOMAIN, TAG, 'sendChatVoiceNoteMessage rejected: waveform encoding failed');
      return false;
    }

    const extra = `message:send:voice:${safeChatId}:${Date.now()}`;
    const request = buildTdSendVoiceNoteMessageRequest(
      extra,
      safeChatId,
      safeFilePath,
      safeDurationSec,
      waveformBase64
    );
    this.send(request);
    hilog.info(
      DOMAIN,
      TAG,
      'Requested voice-note sendMessage (chatId=%{public}s, extra=%{public}s, duration=%{public}d, waveformBytes=%{public}d)',
      safeChatId,
      extra,
      safeDurationSec,
      waveformBytes.length
    );
    return true;
  }

  /**
   * Requests a single page of chat history from TDLib.
   *
   * @param chatId Chat id as TDLib int64 string.
   * @param limit Max number of messages requested from TDLib.
   * @param fromMessageId Cursor id used by TDLib to page older messages.
   * @param forceRetry Allows repeating a request for the same cursor.
   * @param offset TDLib offset relative to `fromMessageId`.
   * @param pullToken Optional user-pull correlation token; embedded into `@extra` as
   * `:pull:<token>` suffix. Pass `0` for non-pull requests (initial load, deeplink, internal
   * probe / sparse retries). The matching response will only fire `historyPageResolved` when
   * the token in `@extra` matches the latest token stored in `pullTokenByChatId` for the same
   * chat — see `parseMessagesExtra` and `resolvePendingPullIfAny`.
   */
  private requestChatHistoryPage(
    chatId: string,
    limit: number,
    fromMessageId: string,
    forceRetry: boolean = false,
    offset: number = 0,
    pullToken: number = 0
  ): boolean {
    if (!this.canRunAuthorizedRequest('requestChatHistoryPage')) {
      return false;
    }
    const safeChatId = chatId.trim();
    const safeLimit = limit > 0 ? limit : 40;
    const safeFromId = fromMessageId.trim().length > 0 ? fromMessageId.trim() : '0';
    if (safeChatId.length === 0) {
      return false;
    }

    let requestedSet = this.historyRequestedFromByChatId.get(safeChatId);
    if (!requestedSet) {
      requestedSet = new Set<string>();
      this.historyRequestedFromByChatId.set(safeChatId, requestedSet);
    }
    if (!forceRetry && requestedSet.has(safeFromId)) {
      return false;
    }
    requestedSet.add(safeFromId);

    const extraToken = pullToken > 0
      ? `messages:get:${safeChatId}:${safeFromId}:pull:${pullToken}`
      : `messages:get:${safeChatId}:${safeFromId}`;
    const request: TdGetChatHistoryRequest = {
      '@type': 'getChatHistory',
      '@extra': extraToken,
      'chat_id': safeChatId,
      'from_message_id': safeFromId,
      'offset': offset,
      'limit': safeLimit,
      'only_local': false
    };
    this.send(request);
    hilog.info(DOMAIN, TAG,
      'Requested chat history page (chatId=%{public}s, from=%{public}s, offset=%{public}d, limit=%{public}d, force=%{public}d, pullToken=%{public}d)',
      safeChatId,
      safeFromId,
      offset,
      safeLimit,
      forceRetry ? 1 : 0,
      pullToken
    );
    return true;
  }

  /**
   * Submits user phone number for login flow.
   *
   * @param phoneNumber Raw phone number from UI input.
   */
  submitPhoneNumber(phoneNumber: string): void {
    const trimmed = phoneNumber.trim();
    if (trimmed.length === 0) {
      hilog.error(DOMAIN, TAG, 'submitPhoneNumber rejected: empty input');
      return;
    }
    if (this.authState !== 'authorizationStateWaitPhoneNumber') {
      hilog.info(DOMAIN, TAG, 'submitPhoneNumber called in state=%{public}s', this.authState);
      return;
    }
    const request: TdSetAuthenticationPhoneNumberRequest = {
      '@type': 'setAuthenticationPhoneNumber',
      '@extra': 'auth:phone',
      'phone_number': trimmed,
      'settings': {
        '@type': 'phoneNumberAuthenticationSettings',
        'allow_flash_call': false,
        'allow_missed_call': false,
        'is_current_phone_number': false,
        'allow_sms_retriever_api': false
      }
    };
    this.send(request);
    hilog.info(DOMAIN, TAG, 'Phone number submitted (len=%{public}d)', trimmed.length);
  }

  /**
   * Submits login code received by user (SMS/Telegram/other channel).
   *
   * @param code Raw confirmation code from UI input.
   */
  submitCode(code: string): void {
    const trimmed = code.trim();
    if (trimmed.length === 0) {
      hilog.error(DOMAIN, TAG, 'submitCode rejected: empty input');
      return;
    }
    if (this.authState !== 'authorizationStateWaitCode') {
      hilog.info(DOMAIN, TAG, 'submitCode called in state=%{public}s', this.authState);
      return;
    }
    const request: TdCheckAuthenticationCodeRequest = {
      '@type': 'checkAuthenticationCode',
      '@extra': 'auth:code',
      'code': trimmed
    };
    this.send(request);
    hilog.info(DOMAIN, TAG, 'Login code submitted (len=%{public}d)', trimmed.length);
  }

  /**
   * Sends TDLib request for a fresh QR login link.
   *
   * @param reason Source of refresh request used for diagnostics.
   */
  private sendRequestQrCodeAuthentication(reason: string): void {
    const request: TdRequestQrCodeAuthenticationRequest = {
      '@type': 'requestQrCodeAuthentication',
      '@extra': `auth:qr:${reason}:${Date.now()}`,
      'other_user_ids': []
    };
    this.send(request);
    hilog.info(DOMAIN, TAG, 'Requested QR authentication link refresh (reason=%{public}s)', reason);
  }

  /**
   * Starts account logout flow.
   *
   * TDLib will emit `authorizationStateLoggingOut` and then a fresh auth
   * lifecycle state (for example `authorizationStateWaitPhoneNumber`).
   */
  logout(): void {
    if (this.authState !== 'authorizationStateReady') {
      hilog.info(DOMAIN, TAG, 'logout called in state=%{public}s', this.authState);
    }
    const request: TdLogOutRequest = {
      '@type': 'logOut',
      '@extra': 'auth:logout'
    };
    this.send(request);
    hilog.info(DOMAIN, TAG, 'Logout requested');
  }

  /**
   * Sends asynchronous TDLib request.
   *
   * @param request Typed request object or raw JSON payload string.
   */
  send(request: TdRequest | string): void {
    this.init();
    if (typeof request === 'string') {
      hilog.debug(DOMAIN, TAG, 'send raw json: %{public}s', this.preview(request));
      tdNativeBridge.send(this.clientId, request);
      return;
    }
    const payload = JSON.stringify(request);
    hilog.debug(DOMAIN, TAG, 'send object json: %{public}s', this.preview(payload));
    tdNativeBridge.send(this.clientId, payload);
  }

  /**
   * Receives next asynchronous TDLib update.
   *
   * @param timeoutSeconds TDLib receive timeout in seconds.
   * @returns Raw payload or `null` when no payload is available.
   */
  receive(timeoutSeconds: number = 0): string | null {
    const response = tdNativeBridge.receive(timeoutSeconds);
    if (response.length === 0) {
      return null;
    }
    if (TdClient.VERBOSE_TD_POLL_LOGS) {
      hilog.debug(DOMAIN, TAG, 'receive timeout=%{public}s -> %{public}s', String(timeoutSeconds), this.preview(response));
    }
    return response;
  }

  /**
   * Executes synchronous TDLib request.
   *
   * Note: only methods allowed by TDLib for sync execution should be used.
   *
   * @param request Typed request object or raw JSON payload string.
   * @returns Raw JSON response from TDLib.
   */
  execute(request: TdRequest | string): string {
    if (typeof request === 'string') {
      hilog.debug(DOMAIN, TAG, 'execute raw json: %{public}s', this.preview(request));
      const response = tdNativeBridge.execute(request);
      hilog.debug(DOMAIN, TAG, 'execute response: %{public}s', this.preview(response));
      return response;
    }
    const payload = JSON.stringify(request);
    hilog.debug(DOMAIN, TAG, 'execute object json: %{public}s', this.preview(payload));
    const response = tdNativeBridge.execute(payload);
    hilog.debug(DOMAIN, TAG, 'execute response: %{public}s', this.preview(response));
    return response;
  }

  /**
   * Starts periodic update polling loop used by authorization flow.
   */
  private startAuthPolling(): void {
    if (this.authPollerId >= 0) {
      hilog.debug(DOMAIN, TAG, 'Authorization polling already running');
      return;
    }
    // Harmony returns timer id as number in this context.
    this.authPollerId = setInterval(() => {
      this.pollAuthorizationUpdates();
    }, TdClient.AUTH_POLL_INTERVAL_MS) as number;
    hilog.info(
      DOMAIN,
      TAG,
      'Authorization polling started (%{public}d ms, max %{public}d updates/tick)',
      TdClient.AUTH_POLL_INTERVAL_MS,
      TdClient.AUTH_POLL_MAX_UPDATES_PER_TICK
    );
  }

  /**
   * Polls TDLib queue and drains multiple payloads in one timer tick.
   *
   * This keeps startup bursts (`updateOption`, `update*`) from being processed
   * one-by-one every 120ms which noticeably delays auth transitions.
   */
  private pollAuthorizationUpdates(): void {
    let processedCount = 0;
    while (processedCount < TdClient.AUTH_POLL_MAX_UPDATES_PER_TICK) {
      if (this.authPollerId < 0) {
        return;
      }
      const update = this.receive(0);
      if (update === null) {
        return;
      }
      processedCount += 1;
      this.handleAuthorizationPayload(update, 'poll');
    }
    if (TdClient.VERBOSE_TD_POLL_LOGS) {
      hilog.debug(DOMAIN, TAG, 'Auth poll batch limit reached: %{public}d', processedCount);
    }
  }

  /**
   * Sends `setTdlibParameters` built from current app secrets/environment.
   */
  private sendTdlibParameters(): void {
    const credentials = getActiveTelegramCredentials();
    const tdlibVersion = this.getVersion();
    const sessionApplicationVersion = this.buildSessionApplicationVersion(tdlibVersion);
    const request: TdSetTdlibParametersRequest = {
      '@type': 'setTdlibParameters',
      '@extra': 'setTdlibParameters:init',
      'use_test_dc': credentials.useTestDc,
      'database_directory': `${TDLIB_DIR}/db`,
      'files_directory': `${TDLIB_DIR}/files`,
      'database_encryption_key': '',
      'use_file_database': true,
      'use_chat_info_database': true,
      'use_message_database': true,
      'use_secret_chats': true,
      'api_id': credentials.apiId,
      'api_hash': credentials.apiHash,
      'system_language_code': 'pl',
      'device_model': TdClient.SESSION_DEVICE_MODEL,
      'system_version': TdClient.SESSION_SYSTEM_VERSION,
      'application_version': sessionApplicationVersion
    };
    this.send(request);
    hilog.info(
      DOMAIN,
      TAG,
      'Sent setTdlibParameters (env=%{public}s, apiId=%{public}d, useTestDc=%{public}d, device=%{public}s, system=%{public}s, app=%{public}s)',
      telegramSecrets.environment,
      credentials.apiId,
      credentials.useTestDc ? 1 : 0,
      TdClient.SESSION_DEVICE_MODEL,
      TdClient.SESSION_SYSTEM_VERSION,
      sessionApplicationVersion
    );
  }

  /**
   * Builds app version label sent to Telegram session metadata.
   *
   * @param tdlibVersion Resolved TDLib version string.
   * @returns App label optionally extended with TDLib version marker.
   */
  private buildSessionApplicationVersion(tdlibVersion: string): string {
    if (tdlibVersion.length === 0) {
      return TdClient.SESSION_APP_LABEL;
    }
    return `${TdClient.SESSION_APP_LABEL} (TDLib ${tdlibVersion})`;
  }

  /**
   * Routes incoming TDLib payload to proper handler by top-level `@type`.
   *
   * @param payload Raw TDLib update/response payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleAuthorizationPayload(payload: string, source: string): void {
    const topType = extractTopLevelType(payload);
    if (topType.startsWith('authorizationState')) {
      const codeLength = extractAuthorizationStateCodeLength(payload);
      const qrAuthLink = extractAuthorizationStateQrLink(payload);
      this.handleAuthorizationState(topType, source, qrAuthLink, codeLength);
      return;
    }

    const handler = this.payloadHandlers[topType];
    if (handler) {
      handler(payload, source);
      return;
    }

    if (TdClient.VERBOSE_TD_POLL_LOGS) {
      hilog.debug(DOMAIN, TAG, 'Unhandled TD payload from %{public}s: %{public}s', source, this.preview(payload));
    }
  }

  /**
   * Handles `updateOption` payload.
   * - tracks `my_id` for current-account filtering
   * - emits selected important options to info logs
   *
   * @param payload Raw TDLib update payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateOption(payload: string, source: string): void {
    const name = extractUpdateOptionName(payload);
    if (name.length === 0) {
      return;
    }
    if (name === 'my_id') {
      const userId = extractOptionIntegerValue(payload);
      if (userId > 0) {
        this.myUserId = userId;
      }
    }
    if (TdClient.IMPORTANT_OPTION_NAMES.has(name)) {
      hilog.info(DOMAIN, TAG, 'updateOption %{public}s (source=%{public}s): %{public}s',
        name,
        source,
        this.preview(payload, 260)
      );
    }
  }

  /**
   * Converts raw TDLib user payload to UI-friendly user model.
   *
   * @param userObj Raw TDLib user object.
   * @returns Mapped user model used by UI.
   */
  private toMeInfo(userObj: TdUserPayload): TdMeInfo {
    const userId = typeof userObj.id === 'number' ? userObj.id : 0;
    let avatarPath: string | undefined = undefined;
    let avatarAnimationPath: string | undefined = undefined;
    const profilePhoto = userObj.profile_photo;
    if (profilePhoto && profilePhoto.small && profilePhoto.small.local
      && typeof profilePhoto.small.local.path === 'string'
      && profilePhoto.small.local.path.length > 0) {
      avatarPath = profilePhoto.small.local.path;
    } else if (userId > 0) {
      const cachedAvatarPath = this.userAvatarPathByUserId.get(String(userId));
      if (typeof cachedAvatarPath === 'string' && cachedAvatarPath.length > 0) {
        avatarPath = cachedAvatarPath;
      }
    }
    if (userId > 0) {
      const cachedAnimatedAvatarPath = this.userAnimatedAvatarPathByUserId.get(String(userId));
      if (typeof cachedAnimatedAvatarPath === 'string' && cachedAnimatedAvatarPath.length > 0) {
        avatarAnimationPath = cachedAnimatedAvatarPath;
      }
    }
    return {
      'id': userId,
      'firstName': typeof userObj.first_name === 'string' ? userObj.first_name : '',
      'lastName': typeof userObj.last_name === 'string' ? userObj.last_name : '',
      'username': resolveUsername(userObj),
      'phoneNumber': typeof userObj.phone_number === 'string' ? userObj.phone_number : '',
      'avatarPath': avatarPath,
      'avatarAnimationPath': avatarAnimationPath
    };
  }

  /**
   * Handles `user` payload (direct `getMe` response).
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUser(payload: string, source: string): void {
    const parsed = parseUserPayload(payload);
    if (!parsed.ok || !parsed.user) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse user payload: %{public}s', parsed.error);
      }
      return;
    }
    const contactUserId = this.parseContactUserExtra(extractExtra(payload));
    if (contactUserId.length > 0) {
      this.updateUserIdentityCache(parsed.user);
      this.updateUserAvatarCache(parsed.user);
      this.updateUsernameCache(parsed.user);
      this.applyContactUserUpdate(parsed.user);
      hilog.debug(DOMAIN, TAG, 'Received contact user details (source=%{public}s, userId=%{public}s)', source, contactUserId);
      return;
    }
    this.meRequestInFlight = false;
    this.updateUserIdentityCache(parsed.user);
    this.updateUserAvatarCache(parsed.user);
    this.updateUsernameCache(parsed.user);
    if (typeof parsed.user.id === 'number' && parsed.user.id > 0) {
      this.requestUserFullInfo(String(parsed.user.id));
    }
    const me = this.toMeInfo(parsed.user);
    this.currentMe = me;
    hilog.info(DOMAIN, TAG, 'Received getMe user (source=%{public}s): id=%{public}d, name=%{public}s %{public}s',
      source, me.id, me.firstName, me.lastName);
    if (this.meListener) {
      this.meListener(me);
    }
  }

  /**
   * Handles `updateUser` payload and forwards only current account updates.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateUser(payload: string, source: string): void {
    const parsed = parseUpdateUserPayload(payload);
    if (!parsed.ok || !parsed.user) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateUser payload: %{public}s', parsed.error);
      }
      return;
    }
    this.updateUserIdentityCache(parsed.user);
    this.updateUserAvatarCache(parsed.user);
    this.updateUsernameCache(parsed.user);
    this.applyContactUserUpdate(parsed.user);
    if (this.myUserId > 0 && parsed.user.id !== this.myUserId) {
      return;
    }
    if (typeof parsed.user.id === 'number' && parsed.user.id > 0) {
      this.requestUserFullInfo(String(parsed.user.id));
    }
    const me = this.toMeInfo(parsed.user);
    this.currentMe = me;
    hilog.info(DOMAIN, TAG, 'updateUser for current account (source=%{public}s): id=%{public}d', source, me.id);
    if (this.meListener) {
      this.meListener(me);
    }
  }

  /**
   * Handles `userFullInfo` payload (direct `getUserFullInfo` response).
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUserFullInfo(payload: string, source: string): void {
    const extraInfo = this.parseUserFullInfoExtra(extractExtra(payload));
    if (extraInfo.userId.length === 0) {
      hilog.debug(DOMAIN, TAG, 'Skipping userFullInfo without user id in @extra (source=%{public}s)', source);
      return;
    }
    const parsed = parseUserFullInfoPayload(payload);
    if (!parsed.ok || !parsed.userFullInfo) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse userFullInfo payload: %{public}s', parsed.error);
      }
      return;
    }
    this.updateUserAnimatedAvatarCache(extraInfo.userId, parsed.userFullInfo);
    hilog.debug(DOMAIN, TAG, 'userFullInfo processed (source=%{public}s, userId=%{public}s)', source, extraInfo.userId);
  }

  /**
   * Handles `updateUserFullInfo` payload and refreshes animated-avatar cache.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateUserFullInfo(payload: string, source: string): void {
    const parsed = parseUpdateUserFullInfoPayload(payload);
    if (!parsed.ok || !parsed.userFullInfo || typeof parsed.userId !== 'string' || parsed.userId.length === 0) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateUserFullInfo payload: %{public}s', parsed.error);
      }
      return;
    }
    this.updateUserAnimatedAvatarCache(parsed.userId, parsed.userFullInfo);
    hilog.debug(DOMAIN, TAG, 'updateUserFullInfo processed (source=%{public}s, userId=%{public}s)', source, parsed.userId);
  }

  /**
   * Handles `users` payload returned by `getContacts`.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUsers(payload: string, source: string): void {
    const extra = extractExtra(payload);
    if (extra !== TdClient.CONTACTS_EXTRA_GET) {
      hilog.debug(DOMAIN, TAG, 'Ignoring users payload outside contacts flow (source=%{public}s, extra=%{public}s)', source, extra);
      return;
    }

    const parsed = parseUsersPayload(payload);
    if (!parsed.ok || !parsed.userIds) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse users payload: %{public}s', parsed.error);
      }
      return;
    }

    this.contactsCoordinator.setContactUserIds(parsed.userIds);
    const contactUserIds = this.contactsCoordinator.getContactUserIds();
    for (let index = 0; index < contactUserIds.length; index += 1) {
      this.requestContactUser(contactUserIds[index]);
    }
    this.emitContacts();
    hilog.info(DOMAIN, TAG, 'Received contacts ids (source=%{public}s, count=%{public}d)', source, contactUserIds.length);
  }

  /**
   * Builds concise comma-separated preview of chat ids for diagnostics.
   *
   * @param chatIds Chat ids returned by TDLib.
   * @param maxShown Maximum number of ids included in preview.
   * @returns Comma-separated preview string.
   */
  private buildChatIdsPreview(chatIds: string[], maxShown: number = 6): string {
    let idsPreview = '';
    let shown = 0;
    for (const chatId of chatIds) {
      if (shown >= maxShown) {
        break;
      }
      if (idsPreview.length > 0) {
        idsPreview += ',';
      }
      idsPreview += chatId;
      shown += 1;
    }
    return idsPreview;
  }

  /**
   * Parses positive integer suffix from `@extra` token with `:<int>` tail.
   *
   * @param extra TDLib `@extra` value.
   * @param prefix Expected prefix without trailing `:`.
   * @returns Parsed positive integer, otherwise `0`.
   */
  private parsePositiveIntSuffix(extra: string, prefix: string): number {
    const marker = `${prefix}:`;
    if (!extra.startsWith(marker)) {
      return 0;
    }
    const rawValue = extra.substring(marker.length).trim();
    if (rawValue.length === 0) {
      return 0;
    }
    const parsed = Number.parseInt(rawValue, 10);
    if (Number.isNaN(parsed) || parsed <= 0) {
      return 0;
    }
    return parsed;
  }

  /**
   * Parses folder id from folder-probe `@extra` token.
   *
   * @param extra TDLib `@extra` value.
   * @returns Folder id, otherwise `0`.
   */
  private parseFolderProbeId(extra: string): number {
    if (!extra.startsWith(TdClient.CHATS_EXTRA_GET_FOLDER_PREFIX)) {
      return 0;
    }
    const rawFolderId = extra.substring(TdClient.CHATS_EXTRA_GET_FOLDER_PREFIX.length).trim();
    if (rawFolderId.length === 0) {
      return 0;
    }
    const folderId = Number.parseInt(rawFolderId, 10);
    if (Number.isNaN(folderId) || folderId <= 0) {
      return 0;
    }
    return folderId;
  }

  /**
   * Handles `chatFolders` payload and triggers per-folder chat-list probes.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleChatFolders(payload: string, source: string): void {
    const extra = extractExtra(payload);
    const parsed = parseChatFoldersPayload(payload);
    if (!parsed.ok || !parsed.folderIds) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse chatFolders payload: %{public}s', parsed.error);
      }
      return;
    }

    const folderIds = parsed.folderIds;
    const folderIdText: string[] = [];
    for (const folderId of folderIds) {
      folderIdText.push(String(folderId));
    }
    const idsPreview = this.buildChatIdsPreview(folderIdText, 8);
    hilog.info(
      DOMAIN,
      TAG,
      'Folder chat probe folders (source=%{public}s, count=%{public}d, ids=%{public}s)',
      source,
      folderIds.length,
      idsPreview
    );
    if (folderIds.length === 0) {
      return;
    }
    if (!TdClient.ENABLE_FOLDER_CHAT_LIST_PROBE) {
      hilog.debug(DOMAIN, TAG, 'Folder chat probe disabled; ignoring folders payload');
      return;
    }

    let folderProbeLimit = this.parsePositiveIntSuffix(extra, TdClient.CHATS_EXTRA_GET_FOLDERS);
    if (folderProbeLimit <= 0) {
      folderProbeLimit = 30;
    }
    for (const folderId of folderIds) {
      this.requestSingleFolderChatsProbe(folderId, folderProbeLimit);
    }
  }

  /**
   * Handles `chats` payload and requests details for each returned chat id.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleChats(payload: string, source: string): void {
    const extra = extractExtra(payload);
    const parsed = parseChatsPayload(payload);
    if (!parsed.ok || !parsed.chatIds) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse chats payload: %{public}s', parsed.error);
      }
      return;
    }

    if (extra === TdClient.CHATS_EXTRA_GET_ARCHIVE) {
      const archiveChatIds = parsed.chatIds;
      const idsPreview = this.buildChatIdsPreview(archiveChatIds);
      hilog.info(
        DOMAIN,
        TAG,
        'Archive chat probe result (source=%{public}s, count=%{public}d, ids=%{public}s)',
        source,
        archiveChatIds.length,
        idsPreview
      );
      return;
    }
    const folderId = this.parseFolderProbeId(extra);
    if (folderId > 0) {
      const folderChatIds = parsed.chatIds;
      const idsPreview = this.buildChatIdsPreview(folderChatIds);
      hilog.info(
        DOMAIN,
        TAG,
        'Folder chat probe result (source=%{public}s, folderId=%{public}d, count=%{public}d, ids=%{public}s)',
        source,
        folderId,
        folderChatIds.length,
        idsPreview
      );
      return;
    }

    this.chatOrder = parsed.chatIds;
    this.chatPositionOrderByChatId.clear();
    for (const chatId of this.chatOrder) {
      if (!this.chatTitleById.has(chatId)) {
        this.chatTitleById.set(chatId, 'Unknown chat');
      }
      this.requestChatDetails(chatId);
    }
    this.emitChats();
    hilog.info(DOMAIN, TAG, 'Received chats list (source=%{public}s, count=%{public}d)', source, this.chatOrder.length);
  }

  /**
   * Handles `messages` payload and updates selected chat history cache.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleMessages(payload: string, source: string): void {
    const extra = extractExtra(payload);
    const extraInfo = this.parseMessagesExtra(extra);
    const chatId = extraInfo.chatId;
    if (chatId.length === 0) {
      hilog.debug(DOMAIN, TAG, 'Skipping messages payload without chat extra (source=%{public}s)', source);
      return;
    }

    const parsed = parseMessagesPayload(payload, chatId);
    if (!parsed.ok || !parsed.messages) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse messages payload: %{public}s', parsed.error);
      }
      return;
    }

    const incomingMessages: TdChatMessageItem[] = [];
    for (const message of parsed.messages) {
      incomingMessages.push(this.cloneChatMessage(message));
    }
    this.requestMessageSenderChatDetails(incomingMessages);

    const fromMessageId = extraInfo.fromMessageId;
    const existingMessages = this.messagesByChatId.get(chatId);
    // Single merge path for every `getChatHistory` response (initial / older-pull / deeplink).
    // The previous deeplink/older-pull branch did a naïve `[incoming, ...existing dedupe]` concat
    // which only happens to land in the right order when `incoming` is strictly older than every
    // cached message. That assumption broke for deeplink loads where the targeted message sits
    // mid-history: the response window contains messages STRICTLY OLDER than messages already in
    // cache (e.g. an `updateNewMessage` that arrived seconds earlier), and the concat parked the
    // newer cached messages after the older deeplink window, scrambling the timeline.
    // `mergeRefreshedMessages` dedupes by id and sorts ascending, which is correct for every
    // `messages` response — TDLib's id is monotonic-per-chat, and ascending id matches the
    // oldest-first ordering the UI expects.
    const mergedMessages: TdChatMessageItem[] = (existingMessages && existingMessages.length > 0)
      ? this.mergeRefreshedMessages(existingMessages, incomingMessages)
      : incomingMessages;

    this.messagesByChatId.set(chatId, mergedMessages);
    this.historyChatNotFoundRetryBudgetByChatId.delete(chatId);
    this.reindexMessageMediaForChat(chatId, mergedMessages);
    this.emitChatMessages(chatId);
    const totalCount = typeof parsed.totalCount === 'number' ? parsed.totalCount : 0;
    hilog.info(DOMAIN, TAG, 'Received chat history (source=%{public}s, chatId=%{public}s, count=%{public}d)',
      source,
      chatId,
      mergedMessages.length
    );

    const limit = this.historyLimitByChatId.get(chatId);
    if (typeof limit !== 'number' || limit <= 0) {
      return;
    }
    if (mergedMessages.length === 0) {
      this.setHistoryHasMore(chatId, false);
      this.resolvePendingPullIfAny(chatId, extraInfo.pullToken, 'no-more');
      return;
    }

    const oldestId = mergedMessages[0].id;
    if (oldestId.length === 0) {
      this.setHistoryHasMore(chatId, false);
      this.resolvePendingPullIfAny(chatId, extraInfo.pullToken, 'no-more');
      return;
    }

    const hasMoreByTotalCount = totalCount > 0 && mergedMessages.length < totalCount;
    const hasMoreByPageSize = incomingMessages.length >= limit;
    const isInitialFromZeroLoad = fromMessageId === '0' && (!existingMessages || existingMessages.length === 0);
    const shouldProbeAfterFirstShortPage = fromMessageId === '0'
      && incomingMessages.length > 0
      && incomingMessages.length < limit
      && totalCount === 0;
    const shouldRetrySparseFirstPage = isInitialFromZeroLoad
      && incomingMessages.length === 1
      && totalCount <= 1;
    const shouldProbeSparseFirstPage = fromMessageId === '0'
      && incomingMessages.length === 1
      && totalCount <= 1;
    const shouldRefreshAfterSparseDeeplinkPage = fromMessageId !== '0'
      && incomingMessages.length === 1
      && mergedMessages.length === 1
      && totalCount <= 1;
    const retryBudget = this.historyRetryBudgetByChatId.get(chatId);
    const sparseLatestRetryBudget = typeof retryBudget === 'number' ? retryBudget : 0;
    const shouldRetrySparseLatestPage = fromMessageId === '0'
      && !isInitialFromZeroLoad
      && incomingMessages.length === 1
      && mergedMessages.length < limit
      && totalCount <= 1
      && sparseLatestRetryBudget > 0;
    const hasMore = incomingMessages.length > 0
      && (hasMoreByTotalCount || hasMoreByPageSize || shouldProbeAfterFirstShortPage);

    this.historyNextFromByChatId.set(chatId, oldestId);
    this.setHistoryHasMore(chatId, hasMore);
    this.resolvePendingPullIfAny(chatId, extraInfo.pullToken, hasMore ? 'page-loaded' : 'no-more');

    if (shouldProbeAfterFirstShortPage || shouldProbeSparseFirstPage) {
      this.requestChatHistoryPage(chatId, limit, oldestId);
    }
    if (shouldRetrySparseFirstPage) {
      hilog.info(
        DOMAIN,
        TAG,
        'Sparse first-page detected; retrying from=0 (chatId=%{public}s, count=%{public}d, total=%{public}d)',
        chatId,
        incomingMessages.length,
        totalCount
      );
      this.requestChatHistoryPage(chatId, limit, '0', true);
    }
    if (shouldRetrySparseLatestPage) {
      this.historyRetryBudgetByChatId.set(chatId, sparseLatestRetryBudget - 1);
      hilog.info(
        DOMAIN,
        TAG,
        'Sparse latest page detected; scheduling forced retry (chatId=%{public}s, count=%{public}d, total=%{public}d, budgetLeft=%{public}d)',
        chatId,
        incomingMessages.length,
        totalCount,
        sparseLatestRetryBudget - 1
      );
      setTimeout((): void => {
        this.requestChatHistoryPage(chatId, limit, '0', true);
      }, TdClient.HISTORY_RETRY_DELAY_MS);
    }
    if (shouldRefreshAfterSparseDeeplinkPage) {
      hilog.info(
        DOMAIN,
        TAG,
        'Sparse deeplink page detected; refreshing from latest page (chatId=%{public}s, anchor=%{public}s)',
        chatId,
        fromMessageId
      );
      this.requestChatHistoryPage(chatId, limit, '0');
    }
  }

  /**
   * Merges first-page refresh (`from=0`) with already loaded history pages.
   *
   * Keeps previously loaded older messages in cache and updates overlapping ids
   * from fresh payload while preserving canonical timeline order (oldest->newest).
   *
   * @param existingMessages Cached chat timeline (oldest -> newest).
   * @param incomingMessages Fresh first-page payload (oldest -> newest within page).
   * @returns Merged timeline with preserved older history.
   */
  private mergeRefreshedMessages(
    existingMessages: TdChatMessageItem[] | undefined,
    incomingMessages: TdChatMessageItem[]
  ): TdChatMessageItem[] {
    if ((!existingMessages || existingMessages.length === 0) && incomingMessages.length === 0) {
      return [];
    }

    const mergedById: Map<string, TdChatMessageItem> = new Map<string, TdChatMessageItem>();
    if (existingMessages && existingMessages.length > 0) {
      for (const existingMessage of existingMessages) {
        const normalizedExisting = this.cloneChatMessage(existingMessage);
        mergedById.set(normalizedExisting.id, normalizedExisting);
      }
    }

    for (const incomingMessage of incomingMessages) {
      const normalizedIncoming = this.cloneChatMessage(incomingMessage);
      mergedById.set(normalizedIncoming.id, normalizedIncoming);
    }

    const merged: TdChatMessageItem[] = [];
    for (const mergedMessage of mergedById.values()) {
      merged.push(mergedMessage);
    }
    merged.sort((left: TdChatMessageItem, right: TdChatMessageItem): number => {
      return this.compareTdInt64Ascending(left.id, right.id);
    });

    return merged;
  }

  /**
   * Compares TDLib int64 ids represented as strings in ascending numeric order.
   *
   * Falls back to lexicographic comparison when any operand isn't a decimal
   * number to keep ordering deterministic.
   */
  private compareTdInt64Ascending(leftRaw: string, rightRaw: string): number {
    const left = this.normalizeTdInt64String(leftRaw);
    const right = this.normalizeTdInt64String(rightRaw);
    const leftIsNumeric = this.isDecimalDigits(left);
    const rightIsNumeric = this.isDecimalDigits(right);
    if (leftIsNumeric && rightIsNumeric) {
      if (left.length !== right.length) {
        return left.length < right.length ? -1 : 1;
      }
      if (left === right) {
        return 0;
      }
      return left < right ? -1 : 1;
    }
    if (left === right) {
      return 0;
    }
    return left < right ? -1 : 1;
  }

  /**
   * Normalizes raw TDLib id string to comparable decimal representation.
   *
   * Trims whitespace and strips leading zeros while preserving single zero.
   */
  private normalizeTdInt64String(raw: string): string {
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      return '0';
    }
    let index = 0;
    while (index < trimmed.length - 1 && trimmed.charAt(index) === '0') {
      index += 1;
    }
    return trimmed.substring(index);
  }

  /**
   * Checks whether value consists only of ASCII decimal digits.
   */
  private isDecimalDigits(value: string): boolean {
    if (value.length === 0) {
      return false;
    }
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    return true;
  }

  /**
   * Ignores high-frequency passive updates that are not required by current UI.
   *
   * We intentionally keep these updates out of "Unhandled payload" logs to
   * reduce noise while preserving the ability to add dedicated handlers later.
   *
   * @param _payload Raw TDLib payload (unused).
   * @param _source Source label used in logs (unused).
   */
  private ignorePassiveUpdate(_payload: string, _source: string): void {
    // Intentionally ignored.
  }

  /**
   * Handles `updateChatReadInbox` payload and caches incoming read cursor.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateChatReadInbox(payload: string, source: string): void {
    const parsed = parseUpdateChatReadInboxPayload(payload);
    if (!parsed.ok || typeof parsed.chatId !== 'string') {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateChatReadInbox payload: %{public}s', parsed.error);
      }
      return;
    }

    this.chatLastReadInboxMessageIdByChatId.set(
      parsed.chatId,
      typeof parsed.lastReadInboxMessageId === 'string' ? parsed.lastReadInboxMessageId : '0'
    );
    const unreadBefore = this.chatUnreadCountByChatId.get(parsed.chatId);
    const unreadCount = typeof parsed.unreadCount === 'number' ? parsed.unreadCount : 0;
    this.chatUnreadCountByChatId.set(parsed.chatId, unreadCount);
    this.emitChats();
    if (unreadCount === 0) {
      this.emitChatReadEvent(parsed.chatId);
    }
    hilog.info(
      DOMAIN,
      TAG,
      'Chat read inbox updated for badge consume (source=%{public}s, chatId=%{public}s, lastRead=%{public}s, unreadBefore=%{public}d, unreadAfter=%{public}d)',
      source,
      parsed.chatId,
      typeof parsed.lastReadInboxMessageId === 'string' ? parsed.lastReadInboxMessageId : '0',
      typeof unreadBefore === 'number' ? unreadBefore : -1,
      unreadCount
    );
  }

  /**
   * Handles `updateChatReadOutbox` payload and refreshes outgoing delivery state.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateChatReadOutbox(payload: string, source: string): void {
    const parsed = parseUpdateChatReadOutboxPayload(payload);
    if (!parsed.ok || typeof parsed.chatId !== 'string') {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateChatReadOutbox payload: %{public}s', parsed.error);
      }
      return;
    }

    this.chatLastReadOutboxMessageIdByChatId.set(
      parsed.chatId,
      typeof parsed.lastReadOutboxMessageId === 'string' ? parsed.lastReadOutboxMessageId : '0'
    );
    this.emitChatMessages(parsed.chatId);
    hilog.debug(
      DOMAIN,
      TAG,
      'Chat read outbox updated (source=%{public}s, chatId=%{public}s, lastRead=%{public}s)',
      source,
      parsed.chatId,
      typeof parsed.lastReadOutboxMessageId === 'string' ? parsed.lastReadOutboxMessageId : '0'
    );
  }

  /**
   * Upserts single message into per-chat timeline cache.
   *
   * @param chatId Chat id that owns the message.
   * @param message Parsed message model from TDLib update.
   * @returns Updated timeline snapshot.
   */
  private upsertMessageInChatCache(chatId: string, message: TdChatMessageItem): TdChatMessageItem[] {
    const existingMessages = this.messagesByChatId.get(chatId);
    const normalizedMessage = this.cloneChatMessage(message);
    if (!existingMessages || existingMessages.length === 0) {
      return [normalizedMessage];
    }

    const updatedMessages: TdChatMessageItem[] = [];
    let replaced = false;
    for (const existingMessage of existingMessages) {
      if (existingMessage.id === normalizedMessage.id) {
        updatedMessages.push(normalizedMessage);
        replaced = true;
        continue;
      }
      updatedMessages.push(existingMessage);
    }
    if (!replaced) {
      updatedMessages.push(normalizedMessage);
    }
    return updatedMessages;
  }

  /**
   * Replaces stale pending message id with confirmed TDLib message payload.
   *
   * Removes both old pending entry and any already-cached final entry to keep
   * only one canonical message row after `updateMessageSendSucceeded`.
   *
   * @param chatId Chat id that owns the message.
   * @param oldMessageId Temporary/pending TDLib message id.
   * @param message Confirmed message payload.
   * @returns Updated timeline snapshot.
   */
  private replacePendingMessageInChatCache(
    chatId: string,
    oldMessageId: string,
    message: TdChatMessageItem
  ): TdChatMessageItem[] {
    const existingMessages = this.messagesByChatId.get(chatId);
    const normalizedMessage = this.cloneChatMessage(message);
    if (!existingMessages || existingMessages.length === 0) {
      return [normalizedMessage];
    }

    const updatedMessages: TdChatMessageItem[] = [];
    let inserted = false;
    for (const existingMessage of existingMessages) {
      if (existingMessage.id === oldMessageId || existingMessage.id === normalizedMessage.id) {
        copyMissingMediaFieldsFromPendingMessage(normalizedMessage, existingMessage);
        if (!inserted) {
          updatedMessages.push(normalizedMessage);
          inserted = true;
        }
        continue;
      }
      updatedMessages.push(existingMessage);
    }
    if (!inserted) {
      updatedMessages.push(normalizedMessage);
    }
    updatedMessages.sort((left: TdChatMessageItem, right: TdChatMessageItem): number => {
      return this.compareTdInt64Ascending(left.id, right.id);
    });
    return updatedMessages;
  }

  /**
   * Handles `updateNewMessage` payload and applies live timeline updates.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateNewMessage(payload: string, source: string): void {
    const parsed = parseUpdateNewMessagePayload(payload);
    if (!parsed.ok || !parsed.message || typeof parsed.chatId !== 'string' || parsed.chatId.length === 0) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateNewMessage payload: %{public}s', parsed.error);
      }
      return;
    }

    const chatId = parsed.chatId;
    this.requestMessageSenderChatDetails([parsed.message]);
    const updatedMessages = this.upsertMessageInChatCache(chatId, parsed.message);
    this.messagesByChatId.set(chatId, updatedMessages);
    this.reindexMessageMediaForChat(chatId, updatedMessages);
    this.emitChatMessages(chatId);

    if (updatedMessages.length > 0) {
      this.historyNextFromByChatId.set(chatId, updatedMessages[0].id);
      // Intentionally do NOT touch `historyHasMore`. A live HEAD update describes a brand-new
      // newest message, never anything between cached and "the beginning of time". If TDLib
      // previously told us `historyHasMore=false` (older-page space exhausted), that fact still
      // holds — the new message is at the head, not somewhere older we missed. Pull-to-refresh
      // will correctly surface the "no earlier messages" toast in that state, which is the
      // semantically correct outcome.
    }
    if (parsed.message.date > 0) {
      const chatListPreview = buildChatListMessagePreview(parsed.message);
      this.chatLastMessageDateByChatId.set(chatId, parsed.message.date);
      if (typeof chatListPreview.text === 'string') {
        this.chatLastMessageTextByChatId.set(chatId, chatListPreview.text);
      } else {
        this.chatLastMessageTextByChatId.delete(chatId);
      }
      if (chatListPreview.kind !== undefined) {
        this.chatLastMessageKindByChatId.set(chatId, chatListPreview.kind);
      } else {
        this.chatLastMessageKindByChatId.delete(chatId);
      }
      const lastMessageTextValue = cloneUiTextValue(chatListPreview.textValue);
      if (lastMessageTextValue) {
        this.chatLastMessageTextValueByChatId.set(chatId, lastMessageTextValue);
      } else {
        this.chatLastMessageTextValueByChatId.delete(chatId);
      }
      if (typeof chatListPreview.isOutgoing === 'boolean') {
        this.chatLastMessageIsOutgoingByChatId.set(chatId, chatListPreview.isOutgoing);
      } else {
        this.chatLastMessageIsOutgoingByChatId.delete(chatId);
      }
      if (chatListPreview.callEventStatus !== undefined) {
        this.chatLastMessageCallEventStatusByChatId.set(chatId, chatListPreview.callEventStatus);
      } else {
        this.chatLastMessageCallEventStatusByChatId.delete(chatId);
      }
      this.emitChats();
    }

    this.emitFallbackNotificationForNewMessage(parsed.message, source);

    hilog.info(
      DOMAIN,
      TAG,
      'Live message update applied (source=%{public}s, chatId=%{public}s, messageId=%{public}s, outgoing=%{public}d)',
      source,
      chatId,
      parsed.message.id,
      parsed.message.isOutgoing ? 1 : 0
    );
  }

  /**
   * Emits a notification event from `updateNewMessage` when TDLib notification
   * updates are not delivered by the wearable runtime.
   *
   * @param message Parsed incoming message.
   * @param source Source label used in logs.
   */
  private emitFallbackNotificationForNewMessage(message: TdChatMessageItem, source: string): void {
    const item = this.buildNotificationItemFromNewMessage(message);
    if (!item) {
      return;
    }

    this.emitNotificationEvent({
      'kind': 'notification',
      'groupId': item.groupId,
      'item': this.cloneNotificationItem(item)
    });
    hilog.info(
      DOMAIN,
      TAG,
      'Fallback notification emitted from updateNewMessage (source=%{public}s, chatId=%{public}s, messageId=%{public}s, notificationId=%{public}d)',
      source,
      item.chatId,
      item.messageId === undefined ? '' : item.messageId,
      item.id
    );
  }

  /**
   * Builds a notification item from a parsed incoming message.
   *
   * @param message Parsed incoming TDLib message.
   * @returns Notification item or `undefined` for messages that should not notify.
   */
  private buildNotificationItemFromNewMessage(message: TdChatMessageItem): TdNotificationItem | undefined {
    const chatId = message.chatId.trim();
    if (message.isOutgoing || chatId.length === 0 || message.id.length === 0) {
      return undefined;
    }

    const notificationId = this.stableNotificationId(chatId, message.id);
    return {
      'id': notificationId,
      'groupId': notificationId,
      'chatId': chatId,
      'messageId': message.id,
      'senderUserId': message.senderUserId,
      'senderChatId': message.senderChatId,
      'date': message.date > 0 ? message.date : 0,
      'isSilent': this.isChatMuted(chatId),
      'content': {
        'kind': this.toNotificationContentKind(message.kind),
        'text': formatChatMessagePreviewText(message),
        'showPreview': true
      }
    };
  }

  /**
   * Converts chat message kind to the notification content kind union.
   *
   * @param kind Parsed chat message kind.
   * @returns Notification content kind.
   */
  private toNotificationContentKind(kind: TdChatMessageKind | undefined): TdNotificationContentKind {
    if (kind === 'text') {
      return 'text';
    }
    if (kind === 'photo') {
      return 'photo';
    }
    if (kind === 'animation') {
      return 'animation';
    }
    if (kind === 'video') {
      return 'video';
    }
    if (kind === 'videoNote') {
      return 'videoNote';
    }
    if (kind === 'voiceNote') {
      return 'voiceNote';
    }
    if (kind === 'sticker') {
      return 'sticker';
    }
    if (kind === 'animatedEmoji') {
      return 'animatedEmoji';
    }
    if (kind === 'serviceEvent') {
      return 'serviceEvent';
    }
    if (kind === 'callEvent') {
      // Notification preview layer has no dedicated call kind; downgrade to
      // service-event so the "[call]" preview is rendered as an italic
      // service line (matches the previous behaviour for messageCall).
      return 'serviceEvent';
    }
    return 'unsupported';
  }

  /**
   * Creates a stable positive int32 notification id from fallback TDLib message identity.
   *
   * @param chatId TDLib chat id.
   * @param messageId TDLib message id.
   * @returns Positive int32 id.
   */
  private stableNotificationId(chatId: string, messageId: string): number {
    return buildFallbackNotificationId(chatId, messageId);
  }

  /**
   * Handles TDLib `updateNotification` and emits a typed notification item event.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateNotification(payload: string, source: string): void {
    const parsed = parseUpdateNotification(payload);
    if (!parsed.ok || !parsed.item || typeof parsed.groupId !== 'number') {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateNotification payload: %{public}s', parsed.error);
      }
      return;
    }

    this.emitNotificationEvent({
      'kind': 'notification',
      'groupId': parsed.groupId,
      'item': this.cloneNotificationItem(parsed.item)
    });
    hilog.info(
      DOMAIN,
      TAG,
      'Notification update parsed (source=%{public}s, groupId=%{public}d, chatId=%{public}s, notificationId=%{public}d)',
      source,
      parsed.groupId,
      parsed.item.chatId,
      parsed.item.id
    );
  }

  /**
   * Handles TDLib `updateNotificationGroup` and emits a typed group event.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateNotificationGroup(payload: string, source: string): void {
    const parsed = parseUpdateNotificationGroup(payload);
    if (!parsed.ok || !parsed.group) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateNotificationGroup payload: %{public}s', parsed.error);
      }
      return;
    }

    this.emitNotificationEvent({
      'kind': 'group',
      'groupId': parsed.group.groupId,
      'group': this.cloneNotificationGroup(parsed.group)
    });
    hilog.info(
      DOMAIN,
      TAG,
      'Notification group update parsed (source=%{public}s, groupId=%{public}d, chatId=%{public}s, added=%{public}d, removed=%{public}d)',
      source,
      parsed.group.groupId,
      parsed.group.chatId,
      parsed.group.items.length,
      parsed.group.removedNotificationIds.length
    );
  }

  /**
   * Handles TDLib `updateActiveNotifications` and emits a typed snapshot event.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateActiveNotifications(payload: string, source: string): void {
    const parsed = parseUpdateActiveNotifications(payload);
    if (!parsed.ok || !parsed.groups) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateActiveNotifications payload: %{public}s', parsed.error);
      }
      return;
    }

    const groups: TdNotificationGroupPayload[] = [];
    for (const group of parsed.groups) {
      groups.push(this.cloneNotificationGroup(group));
    }
    this.emitNotificationEvent({
      'kind': 'active',
      'groups': groups
    });
    hilog.info(
      DOMAIN,
      TAG,
      'Active notifications snapshot parsed (source=%{public}s, groups=%{public}d)',
      source,
      groups.length
    );
  }

  /**
   * Handles TDLib `updateCall` and emits a typed call event.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateCall(payload: string, source: string): void {
    const parsed = parseUpdateCall(payload);
    if (!parsed.ok || !parsed.call) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateCall payload: %{public}s', parsed.error);
      }
      return;
    }

    if (this.getUserProfile(parsed.call.userId) === undefined) {
      this.requestContactUser(parsed.call.userId);
    }
    this.emitCallEvent({
      'kind': 'call',
      'call': this.cloneCallPayload(parsed.call)
    });
    hilog.info(
      DOMAIN,
      TAG,
      'Call update parsed (source=%{public}s, callId=%{public}d, userId=%{public}s, state=%{public}s, outgoing=%{public}d)',
      source,
      parsed.call.id,
      parsed.call.userId,
      parsed.call.state.kind,
      parsed.call.isOutgoing ? 1 : 0
    );
    if (parsed.call.state.kind === 'error') {
      hilog.warn(
        DOMAIN,
        TAG,
        'Call error details (source=%{public}s, callId=%{public}d, errorCode=%{public}d, errorMessage=%{public}s)',
        source,
        parsed.call.id,
        parsed.call.state.errorCode === undefined ? 0 : parsed.call.state.errorCode,
        parsed.call.state.errorMessage === undefined ? '' : parsed.call.state.errorMessage
      );
    }
  }

  /**
   * Handles TDLib `callId` payload returned synchronously by `createCall`.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleCallId(payload: string, source: string): void {
    const parsed = parseCallId(payload);
    if (!parsed.ok || typeof parsed.callId !== 'number') {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse callId payload: %{public}s', parsed.error);
      }
      return;
    }

    const extra = parsed.extra === undefined ? '' : parsed.extra;
    const listener = this.callCreationListeners.get(extra);
    if (listener) {
      this.callCreationListeners.delete(extra);
      listener(parsed.callId, '');
    }
    hilog.info(
      DOMAIN,
      TAG,
      'Call created (source=%{public}s, callId=%{public}d, extra=%{public}s)',
      source,
      parsed.callId,
      extra
    );
  }

  /**
   * Completes a pending `createCall` request after TDLib returns an error payload.
   *
   * @param extra Request correlation token.
   * @param errorMessage TDLib error message.
   * @returns `true` when the error belongs to a `createCall` request.
   */
  private notifyCallCreationError(extra: string, errorMessage: string): boolean {
    if (!extra.startsWith(TdClient.CALL_EXTRA_CREATE_PREFIX)) {
      return false;
    }

    const listener = this.callCreationListeners.get(extra);
    this.callCreationListeners.delete(extra);
    if (listener) {
      listener(0, errorMessage);
    }
    return true;
  }

  /**
   * Handles TDLib `updateNewCallSignalingData` and emits a typed call event.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateNewCallSignalingData(payload: string, source: string): void {
    const parsed = parseUpdateNewCallSignalingData(payload);
    if (!parsed.ok || typeof parsed.callId !== 'number' || typeof parsed.data !== 'string') {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateNewCallSignalingData payload: %{public}s', parsed.error);
      }
      return;
    }

    this.emitCallEvent({
      'kind': 'signalingData',
      'callId': parsed.callId,
      'data': parsed.data
    });
    hilog.debug(
      DOMAIN,
      TAG,
      'Call signaling update parsed (source=%{public}s, callId=%{public}d, bytes=%{public}d)',
      source,
      parsed.callId,
      parsed.data.length
    );
  }

  /**
   * Handles `updateMessageSendSucceeded` and replaces stale pending cache row.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateMessageSendSucceeded(payload: string, source: string): void {
    const parsed = parseUpdateMessageSendSucceededPayload(payload);
    if (!parsed.ok || !parsed.message || typeof parsed.chatId !== 'string' || parsed.chatId.length === 0 ||
      typeof parsed.oldMessageId !== 'string' || parsed.oldMessageId.length === 0) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateMessageSendSucceeded payload: %{public}s', parsed.error);
      }
      return;
    }

    const chatId = parsed.chatId;
    this.requestMessageSenderChatDetails([parsed.message]);
    const updatedMessages = this.replacePendingMessageInChatCache(chatId, parsed.oldMessageId, parsed.message);
    this.messagesByChatId.set(chatId, updatedMessages);
    this.reindexMessageMediaForChat(chatId, updatedMessages);
    this.emitChatMessages(chatId);

    if (updatedMessages.length > 0) {
      this.historyNextFromByChatId.set(chatId, updatedMessages[0].id);
    }
    if (parsed.message.date > 0) {
      this.chatLastMessageDateByChatId.set(chatId, parsed.message.date);
      this.emitChats();
    }

    this.notifySendConfirmationSucceeded(parsed.oldMessageId);

    hilog.info(
      DOMAIN,
      TAG,
      'Send succeeded update applied (source=%{public}s, chatId=%{public}s, oldMessageId=%{public}s, messageId=%{public}s)',
      source,
      chatId,
      parsed.oldMessageId,
      parsed.message.id
    );
  }

  /**
   * Handles top-level `message` payloads used as `sendMessage` response.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleMessage(payload: string, source: string): void {
    const extra = extractExtra(payload);
    const extraInfo = this.parseSendMessageExtra(extra);
    const chatId = extraInfo.chatId;
    if (chatId.length === 0) {
      return;
    }

    this.trackPendingSendConfirmation(extra, payload, chatId, source);

    const historyLimit = this.historyLimitByChatId.get(chatId);
    const safeLimit = typeof historyLimit === 'number' && historyLimit > 0 ? historyLimit : 40;
    this.requestChatHistory(chatId, safeLimit);

    if (this.messageSendResultListener) {
      this.messageSendResultListener(chatId, true, '');
    }
    hilog.info(DOMAIN, TAG, 'sendMessage confirmed (source=%{public}s, chatId=%{public}s)', source, chatId);
  }

  private trackPendingSendConfirmation(extra: string, payload: string, chatId: string, source: string): void {
    if (!this.messageSendConfirmationListeners.has(extra)) {
      return;
    }

    const parsedMessage = parseMessagePayload(payload, chatId);
    if (!parsedMessage.ok || !parsedMessage.message || parsedMessage.message.id.length === 0) {
      this.notifySendConfirmationFailed(extra, 'Failed to parse pending send message.');
      if (parsedMessage.error !== undefined && parsedMessage.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse sendMessage response: %{public}s', parsedMessage.error);
      }
      return;
    }

    this.sendExtraByPendingMessageId.set(parsedMessage.message.id, extra);
    hilog.info(
      DOMAIN,
      TAG,
      'Tracked pending send confirmation (source=%{public}s, chatId=%{public}s, pendingMessageId=%{public}s)',
      source,
      chatId,
      parsedMessage.message.id
    );
  }

  private notifySendConfirmationSucceeded(pendingMessageId: string): void {
    const extra = this.sendExtraByPendingMessageId.get(pendingMessageId);
    if (!extra) {
      return;
    }

    this.sendExtraByPendingMessageId.delete(pendingMessageId);
    const listener = this.takeSendConfirmationListener(extra);
    if (!listener) {
      return;
    }

    listener(true, '');
  }

  private notifySendConfirmationFailed(extra: string, errorMessage: string): void {
    const listener = this.takeSendConfirmationListener(extra);
    if (!listener) {
      return;
    }

    listener(false, errorMessage);
  }

  private armSendConfirmationTimeout(extra: string, chatId: string): void {
    const timeoutId = setTimeout((): void => {
      hilog.warn(
        DOMAIN,
        TAG,
        'sendMessage confirmation timed out (chatId=%{public}s, extra=%{public}s)',
        chatId,
        extra
      );
      this.notifySendConfirmationFailed(extra, 'send confirmation timeout');
    }, TdClient.SEND_CONFIRM_TIMEOUT_MS);
    this.sendConfirmationTimeoutIdsByExtra.set(extra, timeoutId);
  }

  private takeSendConfirmationListener(
    extra: string
  ): ((ok: boolean, errorMessage: string) => void) | undefined {
    const listener = this.messageSendConfirmationListeners.get(extra);
    this.clearSendConfirmationRegistration(extra);
    return listener;
  }

  private clearSendConfirmationRegistration(extra: string): void {
    this.clearSendConfirmationTimeout(extra);
    this.messageSendConfirmationListeners.delete(extra);
    this.deletePendingSendMessageForExtra(extra);
  }

  private clearSendConfirmationTimeout(extra: string): void {
    const timeoutId = this.sendConfirmationTimeoutIdsByExtra.get(extra);
    if (timeoutId === undefined) {
      return;
    }
    clearTimeout(timeoutId);
    this.sendConfirmationTimeoutIdsByExtra.delete(extra);
  }

  private clearPendingSendConfirmationTimeouts(): void {
    this.sendConfirmationTimeoutIdsByExtra.forEach((timeoutId: number): void => {
      clearTimeout(timeoutId);
    });
    this.sendConfirmationTimeoutIdsByExtra.clear();
  }

  private deletePendingSendMessageForExtra(extra: string): void {
    let pendingMessageId = '';
    this.sendExtraByPendingMessageId.forEach((mappedExtra: string, mappedPendingMessageId: string): void => {
      if (mappedExtra === extra) {
        pendingMessageId = mappedPendingMessageId;
      }
    });

    if (pendingMessageId.length > 0) {
      this.sendExtraByPendingMessageId.delete(pendingMessageId);
    }
  }

  /**
   * Handles single `chat` payload and updates chat title cache.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleChat(payload: string, source: string): void {
    const extra = extractExtra(payload);
    const parsed = parseChatPayload(payload);
    if (!parsed.ok || !parsed.chat) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse chat payload: %{public}s', parsed.error);
      }
      return;
    }

    const chat = parsed.chat;
    this.upsertChatItem(chat);
    this.reconcileNotificationChatRefresh(chat);
    this.emitChats();
    this.emitChatMessages(chat.id);
    this.refreshMessagesForSenderChat(chat.id);
    this.notifyPrivateChatRequestSuccess(extra, chat);
    hilog.debug(DOMAIN, TAG, 'Chat details updated (source=%{public}s, id=%{public}s)', source, chat.id);
  }

  /**
   * Emits auto-dismiss signal for notification-driven chat refreshes.
   *
   * @param chat Refreshed chat list item.
   */
  private reconcileNotificationChatRefresh(chat: TdChatListItem): void {
    if (!this.notificationRefreshChatIds.has(chat.id)) {
      return;
    }

    this.notificationRefreshChatIds.delete(chat.id);
    if (chat.unreadCount === 0) {
      this.emitChatReadEvent(chat.id);
    }
  }

  /**
   * Completes pending private-chat request after TDLib returns a chat payload.
   *
   * @param extra Request correlation token.
   * @param chat Created or opened chat.
   */
  private notifyPrivateChatRequestSuccess(extra: string, chat: TdChatListItem): void {
    const listener = this.privateChatRequestListeners.get(extra);
    if (!listener) {
      return;
    }

    this.privateChatRequestListeners.delete(extra);
    listener(chat, '');
  }

  /**
   * Completes pending private-chat request after TDLib returns an error payload.
   *
   * @param extra Request correlation token.
   * @param errorMessage TDLib error message.
   * @returns `true` when the error belongs to a private-chat request.
   */
  private notifyPrivateChatRequestError(extra: string, errorMessage: string): boolean {
    if (!extra.startsWith(TdClient.PRIVATE_CHAT_EXTRA_CREATE_PREFIX)) {
      return false;
    }

    const listener = this.privateChatRequestListeners.get(extra);
    this.privateChatRequestListeners.delete(extra);
    if (listener) {
      listener(undefined, errorMessage);
    }
    return true;
  }

  /**
   * Parses the `@extra` token used for chat-history requests. Format:
   *   `messages:get:<chatId>:<fromMessageId>` for non-pull requests, or
   *   `messages:get:<chatId>:<fromMessageId>:pull:<token>` for user-initiated pulls.
   *
   * @param extra TDLib `@extra` value.
   * @returns Parsed info; `pullToken` is `0` when the `:pull:<token>` suffix is absent or
   * malformed.
   */
  private parseMessagesExtra(extra: string): TdMessagesExtraInfo {
    const prefix = 'messages:get:';
    if (!extra.startsWith(prefix)) {
      return {
        'chatId': '',
        'fromMessageId': '',
        'pullToken': 0
      };
    }

    const tail = extra.substring(prefix.length);
    const parts = tail.split(':');
    const chatId = parts.length > 0 ? parts[0].trim() : '';
    const fromMessageId = parts.length > 1 && parts[1].trim().length > 0 ? parts[1].trim() : '0';
    let pullToken = 0;
    if (parts.length >= 4 && parts[2].trim() === 'pull') {
      const parsed = Number.parseInt(parts[3].trim(), 10);
      if (Number.isFinite(parsed) && parsed > 0) {
        pullToken = parsed;
      }
    } else if (parts.length > 2 && parts[2].trim().length > 0) {
      // Defensive log: the only documented suffix is `:pull:<token>`. Anything else points at an
      // internal regression where a new request kind started emitting an extra suffix without
      // updating this parser. `pullToken=0` is the safe fallback (treated as non-pull) so the
      // request still resolves correctly — the warn just makes the silent drop discoverable.
      hilog.warn(DOMAIN, TAG, 'parseMessagesExtra: unknown suffix dropped (extra=%{public}s, suffix=%{public}s)',
        extra,
        parts[2].trim()
      );
    }
    return {
      'chatId': chatId,
      'fromMessageId': fromMessageId,
      'pullToken': pullToken
    };
  }

  /**
   * Retries a deeplink history request when TDLib has not warmed the chat cache yet.
   *
   * @param extra TDLib `@extra` token from the failed request.
   * @param code TDLib error code.
   * @param message TDLib error message.
   * @returns `true` when the error was handled by scheduling a retry.
   */
  private handleChatHistoryNotFoundError(extra: string, code: number, message: string): boolean {
    if (code !== 400 || message !== 'Chat not found') {
      return false;
    }

    const extraInfo = this.parseMessagesExtra(extra);
    const chatId = extraInfo.chatId;
    const fromMessageId = extraInfo.fromMessageId;
    if (chatId.length === 0 || fromMessageId.length === 0 || fromMessageId === '0') {
      return false;
    }

    const retryBudget = this.historyChatNotFoundRetryBudgetByChatId.get(chatId);
    const budget = typeof retryBudget === 'number' ? retryBudget : 0;
    if (budget <= 0) {
      return false;
    }

    this.historyChatNotFoundRetryBudgetByChatId.set(chatId, budget - 1);
    this.requestChats(30);
    const limit = this.historyLimitByChatId.get(chatId);
    const safeLimit = typeof limit === 'number' && limit > 0 ? limit : 50;
    const centeredOffset = -Math.floor(safeLimit / 2);
    setTimeout((): void => {
      this.requestChatHistoryPage(chatId, safeLimit, fromMessageId, true, centeredOffset);
    }, TdClient.HISTORY_RETRY_DELAY_MS);
    hilog.warn(
      DOMAIN,
      TAG,
      'Retrying deeplink chat history after Chat not found (chatId=%{public}s, messageId=%{public}s, budgetLeft=%{public}d)',
      chatId,
      fromMessageId,
      budget - 1
    );
    return true;
  }

  /**
   * Reads user id from `@extra` token used for `getUserFullInfo` requests.
   *
   * @param extra TDLib `@extra` value.
   * @returns User id extracted from `user:full:<userId>` token, otherwise empty string.
   */
  private parseUserFullInfoExtra(extra: string): TdUserFullInfoExtraInfo {
    const prefix = 'user:full:';
    if (!extra.startsWith(prefix)) {
      return {
        'userId': ''
      };
    }
    const userId = extra.substring(prefix.length).trim();
    return {
      'userId': userId
    };
  }

  /**
   * Reads contact user id from `@extra` token used for per-contact `getUser` requests.
   *
   * @param extra TDLib `@extra` value.
   * @returns User id extracted from `contacts:user:<userId>` token, otherwise empty string.
   */
  private parseContactUserExtra(extra: string): string {
    if (!extra.startsWith(TdClient.CONTACTS_EXTRA_GET_USER_PREFIX)) {
      return '';
    }
    return extra.substring(TdClient.CONTACTS_EXTRA_GET_USER_PREFIX.length).trim();
  }

  /**
   * Reads chat id from `@extra` token used for `sendMessage` requests.
   *
   * @param extra TDLib `@extra` value.
   * @returns Chat id extracted from `message:send:<chatId>:...` or `message:send:voice:<chatId>:...`, otherwise empty string.
   */
  private parseSendMessageExtra(extra: string): TdSendMessageExtraInfo {
    const prefix = 'message:send:';
    if (!extra.startsWith(prefix)) {
      return {
        'chatId': ''
      };
    }

    const tail = extra.substring(prefix.length);
    const parts = tail.split(':');
    const chatId = parts.length > 1 && parts[0] === 'voice'
      ? parts[1].trim()
      : (parts.length > 0 ? parts[0].trim() : '');
    return {
      'chatId': chatId
    };
  }

  /**
   * Handles `updateNewChat` payload and updates local chat cache immediately.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateNewChat(payload: string, source: string): void {
    const parsed = parseUpdateNewChatPayload(payload);
    if (!parsed.ok || !parsed.chat) {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateNewChat payload: %{public}s', parsed.error);
      }
      return;
    }

    const chat = parsed.chat;
    this.upsertChatItem(chat);
    this.emitChats();
    this.emitChatMessages(chat.id);
    hilog.debug(DOMAIN, TAG, 'New chat cached (source=%{public}s, id=%{public}s)', source, chat.id);
  }

  /**
   * Handles `updateChatLastMessage` payload and refreshes cached chat timestamp.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateChatLastMessage(payload: string, source: string): void {
    const parsed = parseUpdateChatLastMessagePayload(payload);
    if (!parsed.ok || typeof parsed.chatId !== 'string' || typeof parsed.lastMessageDate !== 'number') {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateChatLastMessage payload: %{public}s', parsed.error);
      }
      return;
    }

    this.chatLastMessageDateByChatId.set(parsed.chatId, parsed.lastMessageDate);
    if (typeof parsed.lastMessageText === 'string') {
      this.chatLastMessageTextByChatId.set(parsed.chatId, parsed.lastMessageText);
    }
    if (parsed.lastMessageKind !== undefined) {
      this.chatLastMessageKindByChatId.set(parsed.chatId, parsed.lastMessageKind);
    } else {
      this.chatLastMessageKindByChatId.delete(parsed.chatId);
    }
    const lastMessageTextValue = cloneUiTextValue(parsed.lastMessageTextValue);
    if (lastMessageTextValue) {
      this.chatLastMessageTextValueByChatId.set(parsed.chatId, lastMessageTextValue);
    } else {
      this.chatLastMessageTextValueByChatId.delete(parsed.chatId);
    }
    if (typeof parsed.lastMessageIsOutgoing === 'boolean') {
      this.chatLastMessageIsOutgoingByChatId.set(parsed.chatId, parsed.lastMessageIsOutgoing);
    } else {
      this.chatLastMessageIsOutgoingByChatId.delete(parsed.chatId);
    }
    if (parsed.lastMessageCallEventStatus !== undefined) {
      this.chatLastMessageCallEventStatusByChatId.set(parsed.chatId, parsed.lastMessageCallEventStatus);
    } else {
      this.chatLastMessageCallEventStatusByChatId.delete(parsed.chatId);
    }
    this.emitChats();
    hilog.debug(DOMAIN, TAG, 'Chat last message updated (source=%{public}s, id=%{public}s)', source, parsed.chatId);
  }

  /**
   * Handles `updateChatTitle` and refreshes the chat-list row title live.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateChatTitle(payload: string, source: string): void {
    const parsed = parseUpdateChatTitlePayload(payload);
    if (!parsed.ok || typeof parsed.chatId !== 'string' || typeof parsed.title !== 'string') {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateChatTitle payload: %{public}s', parsed.error);
      }
      return;
    }

    this.chatTitleById.set(parsed.chatId, parsed.title);
    this.emitChats();
    hilog.info(
      DOMAIN,
      TAG,
      'Chat title updated (source=%{public}s, chatId=%{public}s, titleLength=%{public}d)',
      source,
      parsed.chatId,
      parsed.title.length
    );
  }

  /**
   * Handles `updateChatPhoto` and refreshes chat-list avatar bindings live.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateChatPhoto(payload: string, source: string): void {
    const parsed = parseUpdateChatPhotoPayload(payload);
    if (!parsed.ok || typeof parsed.chatId !== 'string' || typeof parsed.hasPhoto !== 'boolean') {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateChatPhoto payload: %{public}s', parsed.error);
      }
      return;
    }

    this.removeAvatarFileBindingsForChat(parsed.chatId);
    if (!parsed.hasPhoto) {
      this.chatAvatarPathByChatId.delete(parsed.chatId);
      this.emitChats();
      this.refreshMessagesForSenderChat(parsed.chatId);
      hilog.info(DOMAIN, TAG, 'Chat photo removed (source=%{public}s, chatId=%{public}s)', source, parsed.chatId);
      return;
    }

    if (typeof parsed.avatarFileId === 'number' && parsed.avatarFileId > 0) {
      this.avatarFileIdToChatId.set(parsed.avatarFileId, parsed.chatId);
      this.requestAvatarDownload(parsed.avatarFileId);
    }
    if (typeof parsed.avatarPath === 'string' && parsed.avatarPath.length > 0) {
      this.chatAvatarPathByChatId.set(parsed.chatId, parsed.avatarPath);
    } else {
      this.chatAvatarPathByChatId.delete(parsed.chatId);
    }
    this.emitChats();
    this.refreshMessagesForSenderChat(parsed.chatId);
    hilog.info(
      DOMAIN,
      TAG,
      'Chat photo updated (source=%{public}s, chatId=%{public}s, fileId=%{public}d, pathReady=%{public}d)',
      source,
      parsed.chatId,
      typeof parsed.avatarFileId === 'number' ? parsed.avatarFileId : 0,
      typeof parsed.avatarPath === 'string' && parsed.avatarPath.length > 0 ? 1 : 0
    );
  }

  /**
   * Handles `updateChatPosition` and keeps the live main chat list ordered.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateChatPosition(payload: string, source: string): void {
    const parsed = parseUpdateChatPositionPayload(payload);
    if (!parsed.ok || typeof parsed.chatId !== 'string' || typeof parsed.order !== 'string') {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateChatPosition payload: %{public}s', parsed.error);
      }
      return;
    }

    if (parsed.isMainList !== true) {
      return;
    }

    if (parsed.order === '0') {
      const removed = this.removeChatFromMainOrder(parsed.chatId);
      this.chatPositionOrderByChatId.delete(parsed.chatId);
      if (removed) {
        this.emitChats();
      }
      hilog.info(
        DOMAIN,
        TAG,
        'Chat removed from main order by position (source=%{public}s, chatId=%{public}s)',
        source,
        parsed.chatId
      );
      return;
    }

    this.chatPositionOrderByChatId.set(parsed.chatId, parsed.order);
    this.ensureChatInMainOrder(parsed.chatId);
    this.sortMainChatOrderByKnownPositions();
    if (!this.chatTitleById.has(parsed.chatId)) {
      this.requestChatDetails(parsed.chatId);
    }
    this.emitChats();
    hilog.info(
      DOMAIN,
      TAG,
      'Chat position updated (source=%{public}s, chatId=%{public}s, order=%{public}s, pinned=%{public}d)',
      source,
      parsed.chatId,
      parsed.order,
      parsed.isPinned === true ? 1 : 0
    );
  }

  /**
   * Handles `updateChatAddedToList` for the main chat list.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateChatAddedToList(payload: string, source: string): void {
    const parsed = parseChatListMembershipPayload(payload);
    if (!parsed.ok || typeof parsed.chatId !== 'string') {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateChatAddedToList payload: %{public}s', parsed.error);
      }
      return;
    }

    if (parsed.isMainList !== true) {
      return;
    }

    const added = this.ensureChatInMainOrder(parsed.chatId);
    if (!this.chatTitleById.has(parsed.chatId)) {
      this.requestChatDetails(parsed.chatId);
    }
    if (added) {
      this.emitChats();
    }
    hilog.info(DOMAIN, TAG, 'Chat added to main list (source=%{public}s, chatId=%{public}s)', source, parsed.chatId);
  }

  /**
   * Handles `updateChatRemovedFromList` for the main chat list.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateChatRemovedFromList(payload: string, source: string): void {
    const parsed = parseChatListMembershipPayload(payload);
    if (!parsed.ok || typeof parsed.chatId !== 'string') {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateChatRemovedFromList payload: %{public}s', parsed.error);
      }
      return;
    }

    if (parsed.isMainList !== true) {
      return;
    }

    const removed = this.removeChatFromMainOrder(parsed.chatId);
    this.chatPositionOrderByChatId.delete(parsed.chatId);
    if (removed) {
      this.emitChats();
    }
    hilog.info(DOMAIN, TAG, 'Chat removed from main list (source=%{public}s, chatId=%{public}s)', source, parsed.chatId);
  }

  /**
   * Handles `updateChatNotificationSettings` and keeps fallback notification
   * slot routing aligned with TDLib chat mute state.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateChatNotificationSettings(payload: string, source: string): void {
    const parsed = parseUpdateChatNotificationSettingsPayload(payload);
    if (!parsed.ok || typeof parsed.chatId !== 'string' || typeof parsed.muteFor !== 'number') {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateChatNotificationSettings payload: %{public}s', parsed.error);
      }
      return;
    }

    this.chatNotificationMuteForByChatId.set(parsed.chatId, parsed.muteFor);
    this.emitChats();
    hilog.info(
      DOMAIN,
      TAG,
      'Chat notification settings updated (source=%{public}s, chatId=%{public}s, muteFor=%{public}d)',
      source,
      parsed.chatId,
      parsed.muteFor
    );
  }

  /**
   * Handles `updateDeleteMessages` payload for concise diagnostics.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateDeleteMessages(payload: string, source: string): void {
    try {
      const parsed = JSON.parse(payload) as TdUpdateDeleteMessagesPayload;
      const rawChatId = parsed.chat_id;
      const chatId = typeof rawChatId === 'number'
        ? String(rawChatId)
        : (typeof rawChatId === 'string' ? rawChatId : '');
      const messageIds = Array.isArray(parsed.message_ids) ? parsed.message_ids : [];
      const isPermanent = parsed.is_permanent === true;
      const fromCache = parsed.from_cache === true;
      if (fromCache) {
        hilog.info(
          DOMAIN,
          TAG,
          'Delete messages ignored (cache-only, source=%{public}s, chatId=%{public}s, count=%{public}d, permanent=%{public}d)',
          source,
          chatId,
          messageIds.length,
          isPermanent ? 1 : 0
        );
        return;
      }

      if (chatId.length > 0 && messageIds.length > 0) {
        const deletedIds: Set<string> = new Set<string>();
        for (const rawMessageId of messageIds) {
          if (typeof rawMessageId === 'string') {
            const trimmed = rawMessageId.trim();
            if (trimmed.length > 0) {
              deletedIds.add(trimmed);
            }
            continue;
          }
          if (typeof rawMessageId === 'number' && rawMessageId > 0) {
            deletedIds.add(String(rawMessageId));
          }
        }

        const sourceMessages = this.messagesByChatId.get(chatId);
        if (sourceMessages && sourceMessages.length > 0 && deletedIds.size > 0) {
          const filteredMessages: TdChatMessageItem[] = [];
          let removedCount = 0;
          for (const sourceMessage of sourceMessages) {
            if (deletedIds.has(sourceMessage.id)) {
              removedCount += 1;
              continue;
            }
            filteredMessages.push(sourceMessage);
          }
          if (removedCount > 0) {
            this.messagesByChatId.set(chatId, filteredMessages);
            this.reindexMessageMediaForChat(chatId, filteredMessages);
            this.emitChatMessages(chatId);
            if (filteredMessages.length > 0) {
              this.historyNextFromByChatId.set(chatId, filteredMessages[0].id);
            } else {
              this.historyNextFromByChatId.set(chatId, '0');
              // Intentionally leave historyHasMore at its previous value; only requestChatHistory(...) re-opens it.
            }
            hilog.info(
              DOMAIN,
              TAG,
              'Delete messages applied (source=%{public}s, chatId=%{public}s, removed=%{public}d, remaining=%{public}d)',
              source,
              chatId,
              removedCount,
              filteredMessages.length
            );
          }
        }
      }
      hilog.info(
        DOMAIN,
        TAG,
        'Delete messages update (source=%{public}s, chatId=%{public}s, count=%{public}d, permanent=%{public}d, fromCache=%{public}d)',
        source,
        chatId,
        messageIds.length,
        isPermanent ? 1 : 0,
        fromCache ? 1 : 0
      );
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to parse updateDeleteMessages payload: %{public}s', String(error));
    }
  }

  /**
   * Handles `updateFile` payload and refreshes cached local paths.
   *
   * Applies updates for:
   * - chat avatars
   * - user avatars
   * - media attachments used by chat messages
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleUpdateFile(payload: string, source: string): void {
    const parsed = parseUpdateFilePayload(payload);
    if (!parsed.ok || typeof parsed.fileId !== 'number') {
      if (parsed.error !== undefined && parsed.error.length > 0) {
        hilog.error(DOMAIN, TAG, 'Failed to parse updateFile payload: %{public}s', parsed.error);
      }
      return;
    }

    if (typeof parsed.localPath !== 'string' || parsed.localPath.length === 0) {
      return;
    }

    const chatId = this.avatarFileIdToChatId.get(parsed.fileId);
    if (typeof chatId === 'string' && chatId.length > 0) {
      this.chatAvatarPathByChatId.set(chatId, parsed.localPath);
      this.emitChats();
      this.refreshMessagesForSenderChat(chatId);
      hilog.debug(DOMAIN, TAG, 'Avatar file updated (source=%{public}s, chatId=%{public}s)', source, chatId);
    }

    const userId = this.avatarFileIdToUserId.get(parsed.fileId);
    if (typeof userId === 'string' && userId.length > 0) {
      this.avatarFileIdToUserId.delete(parsed.fileId);
      const current = this.userAvatarPathByUserId.get(userId);
      if (current !== parsed.localPath) {
        this.userAvatarPathByUserId.set(userId, parsed.localPath);
        if (this.shouldEmitContactsForUser(userId)) {
          this.emitContacts();
        }
        this.refreshMessagesForUser(userId);
        if (this.isCurrentUserId(userId)) {
          this.requestMe('avatar-small-ready');
        }
      }
    }

    const animatedUserId = this.animatedAvatarFileIdToUserId.get(parsed.fileId);
    if (typeof animatedUserId === 'string' && animatedUserId.length > 0) {
      this.animatedAvatarFileIdToUserId.delete(parsed.fileId);
      const currentAnimated = this.userAnimatedAvatarPathByUserId.get(animatedUserId);
      if (currentAnimated !== parsed.localPath) {
        this.userAnimatedAvatarPathByUserId.set(animatedUserId, parsed.localPath);
        if (this.isCurrentUserId(animatedUserId)) {
          this.requestMe('avatar-animated-ready');
        }
      }
    }

    const bindingKeys = this.messageBindingKeysByMediaFileId.get(parsed.fileId);
    if (!bindingKeys || bindingKeys.size === 0) {
      return;
    }

    const changedChatIds: Set<string> = new Set<string>();
    for (const bindingKey of bindingKeys) {
      const parsedBinding = this.parseMessageBindingKey(bindingKey);
      if (!parsedBinding) {
        continue;
      }
      const chatIdFromKey = parsedBinding.chatId;
      const messageIdFromKey = parsedBinding.messageId;
      const sourceMessages = this.messagesByChatId.get(chatIdFromKey);
      if (!sourceMessages || sourceMessages.length === 0) {
        continue;
      }

      let hasChanges: boolean = false;
      const updatedMessages: TdChatMessageItem[] = [];
      for (const sourceMessage of sourceMessages) {
        if (sourceMessage.id === messageIdFromKey) {
          if (parsedBinding.bindingType === 'main' && sourceMessage.mediaFileId === parsed.fileId) {
            if (sourceMessage.mediaLocalPath !== parsed.localPath) {
              const updatedMessage = this.cloneChatMessage(sourceMessage);
              updatedMessage.mediaLocalPath = parsed.localPath;
              updatedMessages.push(updatedMessage);
              hasChanges = true;
              continue;
            }
          } else if (parsedBinding.bindingType === 'thumb' && sourceMessage.mediaThumbFileId === parsed.fileId) {
            if (sourceMessage.mediaThumbPath !== parsed.localPath) {
              const updatedMessage = this.cloneChatMessage(sourceMessage);
              updatedMessage.mediaThumbPath = parsed.localPath;
              updatedMessages.push(updatedMessage);
              hasChanges = true;
              continue;
            }
          }
        }
        updatedMessages.push(sourceMessage);
      }

      if (hasChanges) {
        this.messagesByChatId.set(chatIdFromKey, updatedMessages);
        changedChatIds.add(chatIdFromKey);
      }
    }

    for (const changedChatId of changedChatIds) {
      this.emitChatMessages(changedChatId);
    }
    if (changedChatIds.size > 0) {
      hilog.debug(
        DOMAIN,
        TAG,
        'Media file path updated (source=%{public}s, fileId=%{public}d, changedChats=%{public}d)',
        source,
        parsed.fileId,
        changedChatIds.size
      );
    }
  }

  /**
   * Sends `getChat` request for specific chat id (only once per cycle).
   *
   * @param chatId Chat id as TDLib int64 string.
   * @param forceRefresh Whether to bypass the per-cycle duplicate guard.
   */
  private requestChatDetails(chatId: string, forceRefresh: boolean = false): void {
    if (!forceRefresh && this.requestedChatIds.has(chatId)) {
      return;
    }
    this.requestedChatIds.add(chatId);
    const request: TdGetChatRequest = {
      '@type': 'getChat',
      '@extra': `chat:get:${chatId}`,
      'chat_id': chatId
    };
    this.send(request);
  }

  /**
   * Ensures sender-chat details are requested for messages posted on behalf of chats/channels.
   *
   * @param messages Message batch that may contain `senderChatId`.
   */
  private requestMessageSenderChatDetails(messages: TdChatMessageItem[]): void {
    for (const message of messages) {
      const senderChatId = message.senderChatId;
      if (typeof senderChatId !== 'string' || senderChatId.length === 0) {
        continue;
      }
      if (this.chatAvatarPathByChatId.has(senderChatId)) {
        continue;
      }
      this.requestChatDetails(senderChatId);
    }
  }

  /**
   * Sends `getUser` request for specific contact user id (only once per refresh).
   *
   * @param userId User id as TDLib int64 string.
   */
  private requestContactUser(userId: string): void {
    const safeUserId = userId.trim();
    if (safeUserId.length === 0 || this.requestedContactUserIds.has(safeUserId)) {
      return;
    }
    this.requestedContactUserIds.add(safeUserId);
    const request: TdGetUserRequest = {
      '@type': 'getUser',
      '@extra': `${TdClient.CONTACTS_EXTRA_GET_USER_PREFIX}${safeUserId}`,
      'user_id': safeUserId
    };
    this.send(request);
  }

  /**
   * Requests asynchronous avatar file download for given TDLib file id.
   *
   * @param fileId TDLib file id for chat photo.
   */
  private requestAvatarDownload(fileId: number): void {
    if (fileId <= 0 || this.requestedAvatarDownloads.has(fileId)) {
      return;
    }
    this.requestedAvatarDownloads.add(fileId);
    const request: TdDownloadFileRequest = {
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': 1,
      'offset': 0,
      'limit': 0,
      'synchronous': false
    };
    this.send(request);
  }

  /**
   * Builds stable message media-binding key for media-file indexes.
   *
   * @param chatId Chat id as TDLib int64 string.
   * @param messageId Message id as TDLib int64 string.
   * @param bindingType Message media slot (`main` or `thumb`).
   * @returns Stable `<chatId>:<messageId>:<slot>` token.
   */
  private buildMessageBindingKey(chatId: string, messageId: string, bindingType: TdMessageMediaBindingType): string {
    return `${chatId}:${messageId}:${bindingType}`;
  }

  /**
   * Parses message media-binding key used by update-file index maps.
   *
   * @param bindingKey Message media-binding key.
   * @returns Parsed components or `undefined` when malformed.
   */
  private parseMessageBindingKey(
    bindingKey: string
  ): TdParsedMessageBindingInfo | undefined {
    const firstSeparator = bindingKey.indexOf(':');
    if (firstSeparator <= 0 || firstSeparator >= bindingKey.length - 1) {
      return undefined;
    }

    const secondSeparator = bindingKey.indexOf(':', firstSeparator + 1);
    if (secondSeparator <= firstSeparator + 1 || secondSeparator >= bindingKey.length - 1) {
      return undefined;
    }

    const chatId = bindingKey.substring(0, firstSeparator);
    const messageId = bindingKey.substring(firstSeparator + 1, secondSeparator);
    const slotValue = bindingKey.substring(secondSeparator + 1);

    let bindingType: TdMessageMediaBindingType | undefined = undefined;
    if (slotValue === 'main') {
      bindingType = 'main';
    } else if (slotValue === 'thumb') {
      bindingType = 'thumb';
    }
    if (bindingType === undefined) {
      return undefined;
    }

    const parsedBinding: TdParsedMessageBindingInfo = {
      'chatId': chatId,
      'messageId': messageId,
      'bindingType': bindingType
    };
    return parsedBinding;
  }

  /**
   * Clears cached media bindings that belong to selected chat timeline.
   *
   * @param chatId Chat id whose media bindings should be removed.
   */
  private clearMessageMediaBindingsForChat(chatId: string): void {
    const prefix = `${chatId}:`;
    const bindingKeysToDelete: string[] = [];

    for (const entry of this.messageMediaFileIdByBindingKey.entries()) {
      const bindingKey = entry[0];
      if (!bindingKey.startsWith(prefix)) {
        continue;
      }
      bindingKeysToDelete.push(bindingKey);
    }

    for (const bindingKey of bindingKeysToDelete) {
      const fileId = this.messageMediaFileIdByBindingKey.get(bindingKey);
      this.messageMediaFileIdByBindingKey.delete(bindingKey);
      if (typeof fileId !== 'number') {
        continue;
      }
      const boundBindingKeys = this.messageBindingKeysByMediaFileId.get(fileId);
      if (!boundBindingKeys) {
        continue;
      }
      boundBindingKeys.delete(bindingKey);
      if (boundBindingKeys.size === 0) {
        this.messageBindingKeysByMediaFileId.delete(fileId);
      }
    }
  }

  /**
   * Requests asynchronous download for message media file.
   *
   * @param fileId TDLib file id for media payload.
   */
  private requestMessageMediaDownload(fileId: number): void {
    if (fileId <= 0 || this.requestedMessageMediaDownloads.has(fileId)) {
      return;
    }
    this.requestedMessageMediaDownloads.add(fileId);

    const request: TdDownloadFileRequest = {
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': 8,
      'offset': 0,
      'limit': 0,
      'synchronous': false
    };
    this.send(request);
  }

  /**
   * Rebuilds media-file indexes for selected chat and starts pending downloads.
   *
   * @param chatId Chat id whose timeline was refreshed.
   * @param messages Full chat timeline snapshot (oldest-first).
   */
  private reindexMessageMediaForChat(chatId: string, messages: TdChatMessageItem[]): void {
    this.clearMessageMediaBindingsForChat(chatId);

    for (const message of messages) {
      const mainFileId = message.mediaFileId;
      if (typeof mainFileId === 'number' && mainFileId > 0) {
        const mainBindingKey = this.buildMessageBindingKey(chatId, message.id, 'main');
        this.messageMediaFileIdByBindingKey.set(mainBindingKey, mainFileId);

        let mainBindingKeys = this.messageBindingKeysByMediaFileId.get(mainFileId);
        if (!mainBindingKeys) {
          mainBindingKeys = new Set<string>();
          this.messageBindingKeysByMediaFileId.set(mainFileId, mainBindingKeys);
        }
        mainBindingKeys.add(mainBindingKey);

        const hasLocalMedia = typeof message.mediaLocalPath === 'string' && message.mediaLocalPath.length > 0;
        if (!hasLocalMedia) {
          hilog.debug(
            DOMAIN,
            TAG,
            'Media download requested (chatId=%{public}s, messageId=%{public}s, kind=%{public}s, slot=main, fileId=%{public}d)',
            chatId,
            message.id,
            typeof message.kind === 'string' ? message.kind : 'text',
            mainFileId
          );
          this.requestMessageMediaDownload(mainFileId);
        }
      }

      const thumbFileId = message.mediaThumbFileId;
      if (typeof thumbFileId === 'number' && thumbFileId > 0) {
        const thumbBindingKey = this.buildMessageBindingKey(chatId, message.id, 'thumb');
        this.messageMediaFileIdByBindingKey.set(thumbBindingKey, thumbFileId);

        let thumbBindingKeys = this.messageBindingKeysByMediaFileId.get(thumbFileId);
        if (!thumbBindingKeys) {
          thumbBindingKeys = new Set<string>();
          this.messageBindingKeysByMediaFileId.set(thumbFileId, thumbBindingKeys);
        }
        thumbBindingKeys.add(thumbBindingKey);

        const hasLocalThumb = typeof message.mediaThumbPath === 'string' && message.mediaThumbPath.length > 0;
        if (!hasLocalThumb) {
          hilog.debug(
            DOMAIN,
            TAG,
            'Media download requested (chatId=%{public}s, messageId=%{public}s, kind=%{public}s, slot=thumb, fileId=%{public}d)',
            chatId,
            message.id,
            typeof message.kind === 'string' ? message.kind : 'text',
            thumbFileId
          );
          this.requestMessageMediaDownload(thumbFileId);
        }
      }
    }
  }

  /**
   * Creates a detached copy of chat message item.
   *
   * @param source Source message model.
   * @returns Detached message copy.
   */
  private cloneChatMessage(source: TdChatMessageItem): TdChatMessageItem {
    return {
      'id': source.id,
      'chatId': source.chatId,
      'senderUserId': source.senderUserId,
      'senderChatId': source.senderChatId,
      'senderAvatarPath': source.senderAvatarPath,
      'sendingState': source.sendingState,
      'deliveryState': source.deliveryState,
      'kind': source.kind,
      'text': source.text,
      'textValue': source.textValue ? {
        resourceName: source.textValue.resourceName,
        rawText: source.textValue.rawText,
        args: [...source.textValue.args]
      } : undefined,
      'caption': source.caption,
      'mediaFileId': source.mediaFileId,
      'mediaThumbFileId': source.mediaThumbFileId,
      'mediaMinithumbnailData': source.mediaMinithumbnailData,
      'mediaLocalPath': source.mediaLocalPath,
      'mediaThumbPath': source.mediaThumbPath,
      'mediaWidth': source.mediaWidth,
      'mediaHeight': source.mediaHeight,
      'mediaMimeType': source.mediaMimeType,
      'mediaIsAnimated': source.mediaIsAnimated,
      'mediaDurationSec': source.mediaDurationSec,
      'voiceNoteWaveform': source.voiceNoteWaveform ? [...source.voiceNoteWaveform] : undefined,
      'voiceNoteIsListened': source.voiceNoteIsListened,
      'callEventStatus': source.callEventStatus,
      'callEventDurationSec': source.callEventDurationSec,
      'callEventIsVideo': source.callEventIsVideo,
      'isOutgoing': source.isOutgoing,
      'date': source.date
    };
  }

  /**
   * Upserts single chat item into local cache maps.
   *
   * @param chat Normalized chat list item.
   */
  private upsertChatItem(chat: TdChatListItem): void {
    if (this.chatOrder.indexOf(chat.id) < 0) {
      this.chatOrder.push(chat.id);
    }
    this.chatTitleById.set(chat.id, chat.title);
    this.chatKindByChatId.set(chat.id, chat.chatKind);
    if (typeof chat.peerUserId === 'string' && chat.peerUserId.length > 0) {
      this.chatPeerUserIdByChatId.set(chat.id, chat.peerUserId);
    }
    if (typeof chat.avatarPath === 'string' && chat.avatarPath.length > 0) {
      this.chatAvatarPathByChatId.set(chat.id, chat.avatarPath);
    }
    if (typeof chat.avatarFileId === 'number' && chat.avatarFileId > 0) {
      this.avatarFileIdToChatId.set(chat.avatarFileId, chat.id);
      if (!this.chatAvatarPathByChatId.has(chat.id)) {
        this.requestAvatarDownload(chat.avatarFileId);
      }
    }
    if (typeof chat.lastMessageDate === 'number' && chat.lastMessageDate > 0) {
      this.chatLastMessageDateByChatId.set(chat.id, chat.lastMessageDate);
    }
    if (typeof chat.lastMessageText === 'string' && chat.lastMessageText.length > 0) {
      this.chatLastMessageTextByChatId.set(chat.id, chat.lastMessageText);
    }
    if (chat.lastMessageKind !== undefined) {
      this.chatLastMessageKindByChatId.set(chat.id, chat.lastMessageKind);
    } else {
      this.chatLastMessageKindByChatId.delete(chat.id);
    }
    const lastMessageTextValue = cloneUiTextValue(chat.lastMessageTextValue);
    if (lastMessageTextValue) {
      this.chatLastMessageTextValueByChatId.set(chat.id, lastMessageTextValue);
    } else {
      this.chatLastMessageTextValueByChatId.delete(chat.id);
    }
    if (typeof chat.lastMessageIsOutgoing === 'boolean') {
      this.chatLastMessageIsOutgoingByChatId.set(chat.id, chat.lastMessageIsOutgoing);
    } else {
      this.chatLastMessageIsOutgoingByChatId.delete(chat.id);
    }
    if (chat.lastMessageCallEventStatus !== undefined) {
      this.chatLastMessageCallEventStatusByChatId.set(chat.id, chat.lastMessageCallEventStatus);
    } else {
      this.chatLastMessageCallEventStatusByChatId.delete(chat.id);
    }
    if (typeof chat.lastReadInboxMessageId === 'string') {
      this.chatLastReadInboxMessageIdByChatId.set(chat.id, chat.lastReadInboxMessageId);
    }
    if (typeof chat.lastReadOutboxMessageId === 'string') {
      this.chatLastReadOutboxMessageIdByChatId.set(chat.id, chat.lastReadOutboxMessageId);
    }
    if (typeof chat.unreadCount === 'number') {
      this.chatUnreadCountByChatId.set(chat.id, chat.unreadCount);
    }
    if (typeof chat.defaultDisableNotification === 'boolean') {
      this.chatDefaultDisableNotificationByChatId.set(chat.id, chat.defaultDisableNotification);
    }
    if (typeof chat.notificationMuteFor === 'number') {
      this.chatNotificationMuteForByChatId.set(chat.id, chat.notificationMuteFor);
    }
  }

  /**
   * Ensures a chat id exists in the local main-list order.
   *
   * @param chatId TDLib chat id.
   * @returns `true` when the order changed.
   */
  private ensureChatInMainOrder(chatId: string): boolean {
    if (this.chatOrder.indexOf(chatId) >= 0) {
      return false;
    }
    this.chatOrder.push(chatId);
    if (!this.chatTitleById.has(chatId)) {
      this.chatTitleById.set(chatId, 'Unknown chat');
    }
    return true;
  }

  /**
   * Removes a chat id from the local main-list order.
   *
   * @param chatId TDLib chat id.
   * @returns `true` when the order changed.
   */
  private removeChatFromMainOrder(chatId: string): boolean {
    const nextOrder: string[] = [];
    let removed = false;
    for (const currentChatId of this.chatOrder) {
      if (currentChatId === chatId) {
        removed = true;
      } else {
        nextOrder.push(currentChatId);
      }
    }
    if (removed) {
      this.chatOrder = nextOrder;
    }
    return removed;
  }

  /**
   * Removes stale avatar file bindings for one chat.
   *
   * @param chatId TDLib chat id.
   */
  private removeAvatarFileBindingsForChat(chatId: string): void {
    const staleFileIds: number[] = [];
    for (const entry of this.avatarFileIdToChatId.entries()) {
      const fileId = entry[0];
      const boundChatId = entry[1];
      if (boundChatId === chatId) {
        staleFileIds.push(fileId);
      }
    }
    for (const fileId of staleFileIds) {
      this.avatarFileIdToChatId.delete(fileId);
    }
  }

  /**
   * Sorts chats with known TDLib position orders before unknown-position rows.
   */
  private sortMainChatOrderByKnownPositions(): void {
    const positionedChatIds: string[] = [];
    const unpositionedChatIds: string[] = [];
    for (const chatId of this.chatOrder) {
      const order = this.chatPositionOrderByChatId.get(chatId);
      if (typeof order === 'string' && order.length > 0 && order !== '0') {
        positionedChatIds.push(chatId);
      } else {
        unpositionedChatIds.push(chatId);
      }
    }

    positionedChatIds.sort((leftChatId: string, rightChatId: string): number => {
      const leftOrder = this.chatPositionOrderByChatId.get(leftChatId);
      const rightOrder = this.chatPositionOrderByChatId.get(rightChatId);
      const leftText = typeof leftOrder === 'string' ? leftOrder : '0';
      const rightText = typeof rightOrder === 'string' ? rightOrder : '0';
      return this.compareChatPositionOrderDescending(leftText, rightText);
    });

    this.chatOrder = positionedChatIds.concat(unpositionedChatIds);
  }

  /**
   * Compares two positive TDLib order strings in descending order.
   *
   * @param leftOrder First order string.
   * @param rightOrder Second order string.
   * @returns Negative when left should be before right, positive for the opposite.
   */
  private compareChatPositionOrderDescending(leftOrder: string, rightOrder: string): number {
    const leftTrimmed = this.trimLeadingZeroes(leftOrder);
    const rightTrimmed = this.trimLeadingZeroes(rightOrder);
    if (leftTrimmed.length !== rightTrimmed.length) {
      return rightTrimmed.length - leftTrimmed.length;
    }
    if (leftTrimmed > rightTrimmed) {
      return -1;
    }
    if (leftTrimmed < rightTrimmed) {
      return 1;
    }
    return 0;
  }

  /**
   * Removes leading zeroes from numeric text while preserving a single zero.
   *
   * @param value Numeric text.
   * @returns Normalized numeric text.
   */
  private trimLeadingZeroes(value: string): string {
    let index = 0;
    while (index < value.length - 1 && value.charAt(index) === '0') {
      index += 1;
    }
    return value.substring(index);
  }

  /**
   * Resolves whether notifications for a chat should use a silent slot.
   *
   * @param chatId TDLib chat id.
   * @returns `true` when TDLib chat state says the chat is muted or silent by default.
   */
  private isChatMuted(chatId: string): boolean {
    const muteFor = this.chatNotificationMuteForByChatId.get(chatId);
    if (typeof muteFor === 'number' && muteFor > 0) {
      return true;
    }
    return this.chatDefaultDisableNotificationByChatId.get(chatId) === true;
  }

  /**
   * Finds cached private chat for selected user.
   *
   * @param userId TDLib user id.
   * @returns Cached chat row or `undefined` when chat is not known locally.
   */
  private findPrivateChatByUserId(userId: string): TdChatListItem | undefined {
    for (const chatId of this.chatOrder) {
      const peerUserId = this.chatPeerUserIdByChatId.get(chatId);
      const chatKind = this.chatKindByChatId.get(chatId);
      if (peerUserId === userId && chatKind === 'private') {
        return this.createChatListItemFromCache(chatId);
      }
    }
    return undefined;
  }

  /**
   * Creates one chat-list item from local chat cache maps.
   *
   * @param chatId Cached chat id.
   * @returns Chat list item with best-known cached fields.
   */
  private createChatListItemFromCache(chatId: string): TdChatListItem {
    const title = this.chatTitleById.get(chatId);
    const chatKind = this.chatKindByChatId.get(chatId);
    const peerUserId = this.chatPeerUserIdByChatId.get(chatId);
    const avatarPath = this.chatAvatarPathByChatId.get(chatId);
    const lastMessageDate = this.chatLastMessageDateByChatId.get(chatId);
    const lastMessageText = this.chatLastMessageTextByChatId.get(chatId);
    const lastMessageTextValue = cloneUiTextValue(this.chatLastMessageTextValueByChatId.get(chatId));
    const lastMessageKind = this.chatLastMessageKindByChatId.get(chatId);
    const lastMessageIsOutgoing = this.chatLastMessageIsOutgoingByChatId.get(chatId);
    const lastMessageCallEventStatus = this.chatLastMessageCallEventStatusByChatId.get(chatId);
    const lastReadInboxMessageId = this.chatLastReadInboxMessageIdByChatId.get(chatId);
    const lastReadOutboxMessageId = this.chatLastReadOutboxMessageIdByChatId.get(chatId);
    const unreadCount = this.chatUnreadCountByChatId.get(chatId);
    const defaultDisableNotification = this.chatDefaultDisableNotificationByChatId.get(chatId);
    const notificationMuteFor = this.chatNotificationMuteForByChatId.get(chatId);
    let username: string | undefined = undefined;
    if (typeof peerUserId === 'string' && peerUserId.length > 0) {
      const knownUsername = this.usernameByUserId.get(peerUserId);
      if (typeof knownUsername === 'string' && knownUsername.length > 0) {
        username = `@${knownUsername}`;
      }
    }

    return {
      'id': chatId,
      'title': title !== undefined ? title : 'Unknown chat',
      'chatKind': chatKind !== undefined ? chatKind : 'unknown',
      'username': username,
      'peerUserId': peerUserId,
      'avatarPath': avatarPath,
      'lastMessageDate': lastMessageDate,
      'lastMessageText': lastMessageText,
      'lastMessageTextValue': lastMessageTextValue,
      'lastMessageKind': lastMessageKind,
      'lastMessageIsOutgoing': lastMessageIsOutgoing,
      'lastMessageCallEventStatus': lastMessageCallEventStatus,
      'lastReadInboxMessageId': lastReadInboxMessageId,
      'lastReadOutboxMessageId': lastReadOutboxMessageId,
      'unreadCount': unreadCount,
      'defaultDisableNotification': defaultDisableNotification,
      'notificationMuteFor': notificationMuteFor
    };
  }

  /**
   * Emits current chat list snapshot to UI listener (if present).
   */
  private emitChats(): void {
    if (!this.chatsListener) {
      return;
    }
    const chats: TdChatListItem[] = [];
    for (const chatId of this.chatOrder) {
      chats.push(this.createChatListItemFromCache(chatId));
    }
    this.chatsListener(chats);
  }

  /**
   * Emits current contacts list snapshot to UI listener (if present).
   */
  private emitContacts(): void {
    if (!this.contactsListener) {
      return;
    }

    const baseContacts = this.contactsCoordinator.buildContactsSnapshot();
    if (!baseContacts) {
      return;
    }

    const contacts: TdContactListItem[] = [];
    for (let index = 0; index < baseContacts.length; index += 1) {
      const cachedContact = baseContacts[index];
      const userId = cachedContact.id;
      const cachedAvatarPath = this.userAvatarPathByUserId.get(userId);
      const cachedAvatarAnimationPath = this.userAnimatedAvatarPathByUserId.get(userId);
      const cachedUsername = this.usernameByUserId.get(userId);
      contacts.push({
        'id': cachedContact.id,
        'firstName': cachedContact.firstName,
        'lastName': cachedContact.lastName,
        'username': typeof cachedUsername === 'string' ? cachedUsername : cachedContact.username,
        'phoneNumber': cachedContact.phoneNumber,
        'avatarPath': typeof cachedAvatarPath === 'string' ? cachedAvatarPath : cachedContact.avatarPath,
        'avatarAnimationPath': typeof cachedAvatarAnimationPath === 'string'
          ? cachedAvatarAnimationPath
          : cachedContact.avatarAnimationPath,
        'avatarFileId': cachedContact.avatarFileId,
        'isMutualContact': cachedContact.isMutualContact,
        'statusKind': cachedContact.statusKind,
        'lastSeenAt': cachedContact.lastSeenAt,
        'accentColorId': cachedContact.accentColorId
      });
    }
    this.contactsListener(contacts);
  }

  /**
   * Emits cached messages for selected chat to UI listener.
   *
   * @param chatId Chat id whose messages should be emitted.
   */
  private emitChatMessages(chatId: string): void {
    if (this.chatMessagesSubscriptions.isEmpty()) {
      return;
    }

    const sourceMessages = this.messagesByChatId.get(chatId);
    const messages: TdChatMessageItem[] = [];
    if (sourceMessages) {
      for (const message of sourceMessages) {
        let avatarPath: string | undefined = message.senderAvatarPath;
        if (typeof message.senderUserId === 'string' && message.senderUserId.length > 0) {
          const storedPath = this.userAvatarPathByUserId.get(message.senderUserId);
          if (typeof storedPath === 'string' && storedPath.length > 0) {
            avatarPath = storedPath;
          }
        } else if (typeof message.senderChatId === 'string' && message.senderChatId.length > 0) {
          const storedChatPath = this.chatAvatarPathByChatId.get(message.senderChatId);
          if (typeof storedChatPath === 'string' && storedChatPath.length > 0) {
            avatarPath = storedChatPath;
          }
        }
        const emittedMessage = this.cloneChatMessage(message);
        emittedMessage.senderAvatarPath = avatarPath;
        emittedMessage.deliveryState = this.resolveMessageDeliveryState(chatId, emittedMessage);
        if (emittedMessage.isOutgoing) {
          const resolvedDeliveryState = typeof emittedMessage.deliveryState === 'string'
            ? emittedMessage.deliveryState
            : 'none';
          const resolvedSendingState = typeof emittedMessage.sendingState === 'string'
            ? emittedMessage.sendingState
            : 'none';
          hilog.debug(
            DOMAIN,
            TAG,
            'Emit message delivery state (chatId=%{public}s, messageId=%{public}s, kind=%{public}s, sending=%{public}s, delivery=%{public}s)',
            chatId,
            emittedMessage.id,
            emittedMessage.kind,
            resolvedSendingState,
            resolvedDeliveryState
          );
        }
        messages.push(emittedMessage);
      }
    }
    this.chatMessagesSubscriptions.forEach(
      (listener: (chatId: string, messages: TdChatMessageItem[]) => void): void => {
        listener(chatId, messages);
      }
    );
  }

  /**
   * Emits one TDLib notification event to the registered notification service.
   *
   * @param event Parsed TDLib notification event.
   */
  private emitNotificationEvent(event: TdNotificationEvent): void {
    const listener = this.notificationsListener;
    if (!listener) {
      if (!this.notificationBufferingEnabled) {
        return;
      }

      this.pendingNotificationEvents.push(this.cloneNotificationEvent(event));
      if (this.pendingNotificationEvents.length > TdClient.MAX_PENDING_NOTIFICATION_EVENTS) {
        this.pendingNotificationEvents.shift();
      }
      hilog.info(
        DOMAIN,
        TAG,
        'Queued notification event until publisher is ready (kind=%{public}s, pending=%{public}d)',
        event.kind,
        this.pendingNotificationEvents.length
      );
      return;
    }
    listener(this.cloneNotificationEvent(event));
  }

  /**
   * Emits or buffers one chat-read event for notification auto-dismiss.
   *
   * @param chatId TDLib chat id.
   */
  private emitChatReadEvent(chatId: string): void {
    const safeChatId = chatId.trim();
    if (safeChatId.length === 0) {
      return;
    }

    const listener = this.chatReadListener;
    if (!listener) {
      if (!this.chatReadBufferingEnabled) {
        return;
      }

      this.pendingChatReadChatIds.push(safeChatId);
      if (this.pendingChatReadChatIds.length > TdClient.MAX_PENDING_CHAT_READ_EVENTS) {
        this.pendingChatReadChatIds.shift();
      }
      hilog.info(
        DOMAIN,
        TAG,
        'Queued chat-read event until publisher is ready (chatId=%{public}s, pending=%{public}d)',
        safeChatId,
        this.pendingChatReadChatIds.length
      );
      return;
    }

    listener(safeChatId);
  }

  /**
   * Emits one TDLib call event to the registered call service.
   *
   * @param event Parsed TDLib call event.
   */
  private emitCallEvent(event: TdCallEvent): void {
    const listener = this.callListener;
    if (!listener) {
      if (!this.callBufferingEnabled) {
        return;
      }

      this.pendingCallEvents.push(this.cloneCallEvent(event));
      if (this.pendingCallEvents.length > TdClient.MAX_PENDING_CALL_EVENTS) {
        this.pendingCallEvents.shift();
      }
      hilog.info(
        DOMAIN,
        TAG,
        'Queued call event until listener is ready (kind=%{public}s, pending=%{public}d)',
        event.kind,
        this.pendingCallEvents.length
      );
      return;
    }

    listener(this.cloneCallEvent(event));
  }

  /**
   * Creates an isolated copy of one call event.
   *
   * @param event Source call event.
   * @returns Cloned call event.
   */
  private cloneCallEvent(event: TdCallEvent): TdCallEvent {
    if (event.kind === 'call') {
      return {
        'kind': 'call',
        'call': event.call === undefined ? undefined : this.cloneCallPayload(event.call)
      };
    }
    return {
      'kind': 'signalingData',
      'callId': event.callId,
      'data': event.data
    };
  }

  /**
   * Creates an isolated copy of one parsed call payload.
   *
   * @param call Source call payload.
   * @returns Cloned call payload.
   */
  private cloneCallPayload(call: TdParsedCallPayload): TdParsedCallPayload {
    return {
      'id': call.id,
      'uniqueId': call.uniqueId,
      'userId': call.userId,
      'isOutgoing': call.isOutgoing,
      'isVideo': call.isVideo,
      'state': this.cloneCallStatePayload(call.state)
    };
  }

  private cloneCallStatePayload(state: TdParsedCallStatePayload): TdParsedCallStatePayload {
    const clonedState: TdParsedCallStatePayload = {
      'kind': state.kind,
      'tdType': state.tdType
    };
    clonedState.isCreated = state.isCreated;
    clonedState.isReceived = state.isReceived;
    clonedState.protocol = state.protocol === undefined ? undefined : this.cloneCallProtocolPayload(state.protocol);
    clonedState.servers = state.servers === undefined ? undefined : this.cloneCallServers(state.servers);
    clonedState.config = state.config;
    clonedState.encryptionKey = state.encryptionKey;
    clonedState.emojis = state.emojis === undefined ? undefined : [...state.emojis];
    clonedState.allowP2p = state.allowP2p;
    clonedState.isGroupCallSupported = state.isGroupCallSupported;
    clonedState.customParameters = state.customParameters;
    clonedState.discardReason = state.discardReason;
    clonedState.needRating = state.needRating;
    clonedState.needDebugInformation = state.needDebugInformation;
    clonedState.needLog = state.needLog;
    clonedState.errorCode = state.errorCode;
    clonedState.errorMessage = state.errorMessage;
    return clonedState;
  }

  private cloneCallProtocolPayload(protocol: TdParsedCallProtocolPayload): TdParsedCallProtocolPayload {
    return {
      'udpP2p': protocol.udpP2p,
      'udpReflector': protocol.udpReflector,
      'minLayer': protocol.minLayer,
      'maxLayer': protocol.maxLayer,
      'libraryVersions': [...protocol.libraryVersions]
    };
  }

  private cloneCallServers(servers: TdParsedCallServerPayload[]): TdParsedCallServerPayload[] {
    const clonedServers: TdParsedCallServerPayload[] = [];
    for (const server of servers) {
      clonedServers.push({
        'id': server.id,
        'ipAddress': server.ipAddress,
        'ipv6Address': server.ipv6Address,
        'port': server.port,
        'type': server.type,
        'peerTag': server.peerTag
      });
    }
    return clonedServers;
  }

  /**
   * Creates an isolated copy of one notification event.
   *
   * @param event Source notification event.
   * @returns Cloned notification event.
   */
  private cloneNotificationEvent(event: TdNotificationEvent): TdNotificationEvent {
    if (event.kind === 'notification') {
      const item = event.item;
      return {
        'kind': 'notification',
        'groupId': event.groupId,
        'item': item === undefined ? undefined : this.cloneNotificationItem(item)
      };
    }
    if (event.kind === 'group') {
      const group = event.group;
      return {
        'kind': 'group',
        'groupId': event.groupId,
        'group': group === undefined ? undefined : this.cloneNotificationGroup(group)
      };
    }

    const groups: TdNotificationGroupPayload[] = [];
    const sourceGroups = event.groups;
    if (sourceGroups !== undefined) {
      for (const group of sourceGroups) {
        groups.push(this.cloneNotificationGroup(group));
      }
    }
    return {
      'kind': 'active',
      'groups': groups
    };
  }

  /**
   * Creates an isolated copy of one notification group payload.
   *
   * @param group Source notification group payload.
   * @returns Cloned notification group payload.
   */
  private cloneNotificationGroup(group: TdNotificationGroupPayload): TdNotificationGroupPayload {
    const items: TdNotificationItem[] = [];
    for (const item of group.items) {
      items.push(this.cloneNotificationItem(item));
    }

    return {
      'groupId': group.groupId,
      'chatId': group.chatId,
      'notificationSettingsChatId': group.notificationSettingsChatId,
      'totalCount': group.totalCount,
      'items': items,
      'removedNotificationIds': [...group.removedNotificationIds]
    };
  }

  /**
   * Creates an isolated copy of one notification item payload.
   *
   * @param item Source notification item payload.
   * @returns Cloned notification item payload.
   */
  private cloneNotificationItem(item: TdNotificationItem): TdNotificationItem {
    return {
      'id': item.id,
      'groupId': item.groupId,
      'chatId': item.chatId,
      'messageId': item.messageId,
      'senderUserId': item.senderUserId,
      'senderChatId': item.senderChatId,
      'date': item.date,
      'isSilent': item.isSilent,
      'content': {
        'kind': item.content.kind,
        'text': item.content.text,
        'showPreview': item.content.showPreview
      }
    };
  }

  /**
   * Resolves outgoing delivery state for one message using cached chat cursors.
   *
   * @param chatId Chat id that owns the message.
   * @param message Message item to evaluate.
   * @returns Delivery state for UI or `undefined` when not applicable.
   */
  private resolveMessageDeliveryState(chatId: string, message: TdChatMessageItem): TdMessageDeliveryState | undefined {
    if (!message.isOutgoing) {
      return undefined;
    }

    const chatKind = this.chatKindByChatId.get(chatId);
    if (chatKind === 'channel') {
      return undefined;
    }

    if (message.sendingState === 'pending') {
      return 'pending';
    }
    if (message.sendingState === 'failed') {
      return 'failed';
    }

    const lastReadOutboxMessageId = this.chatLastReadOutboxMessageIdByChatId.get(chatId);
    if (typeof lastReadOutboxMessageId === 'string' && lastReadOutboxMessageId.length > 0) {
      if (this.compareTdInt64Ascending(message.id, lastReadOutboxMessageId) <= 0) {
        return 'read';
      }
    }

    return 'sent';
  }

  /**
   * Requests current account profile data (`getMe`).
   */
  private requestMe(reason: string = 'unspecified'): void {
    if (!this.isAuthorizationReadyState(this.authState)) {
      hilog.debug(
        DOMAIN,
        TAG,
        'Skip getMe: authorization not ready (reason=%{public}s, state=%{public}s)',
        reason,
        this.authState
      );
      return;
    }

    const nowMs = Date.now();
    if (this.meRequestInFlight) {
      const inFlightAgeMs = nowMs - this.meRequestLastSentAtMs;
      if (inFlightAgeMs >= 0 && inFlightAgeMs < TdClient.ME_REQUEST_IN_FLIGHT_TIMEOUT_MS) {
        hilog.debug(
          DOMAIN,
          TAG,
          'Skip getMe: request already in-flight (reason=%{public}s, ageMs=%{public}d)',
          reason,
          inFlightAgeMs
        );
        return;
      }
      this.meRequestInFlight = false;
    }

    const elapsedMs = nowMs - this.meRequestLastSentAtMs;
    const bypassCooldown = TdClient.ME_REQUEST_COOLDOWN_BYPASS_REASONS.has(reason);
    if (!bypassCooldown && elapsedMs >= 0 && elapsedMs < TdClient.ME_REQUEST_MIN_INTERVAL_MS) {
      hilog.debug(
        DOMAIN,
        TAG,
        'Skip getMe: throttled (reason=%{public}s, elapsedMs=%{public}d)',
        reason,
        elapsedMs
      );
      return;
    }

    const request: TdGetMeRequest = {
      '@type': 'getMe',
      '@extra': 'auth:getMe'
    };
    this.send(request);
    this.meRequestInFlight = true;
    this.meRequestLastSentAtMs = nowMs;
    hilog.info(DOMAIN, TAG, 'Requested getMe (reason=%{public}s)', reason);
  }

  /**
   * Requests full user profile payload used for animated-avatar metadata.
   *
   * @param userId User id as TDLib int64 string.
   */
  private requestUserFullInfo(userId: string): void {
    if (!this.isAuthorizationReadyState(this.authState)) {
      return;
    }
    const safeUserId = userId.trim();
    if (safeUserId.length === 0) {
      return;
    }
    if (this.requestedUserFullInfoIds.has(safeUserId)) {
      return;
    }
    this.requestedUserFullInfoIds.add(safeUserId);
    const request: TdGetUserFullInfoRequest = {
      '@type': 'getUserFullInfo',
      '@extra': `user:full:${safeUserId}`,
      'user_id': safeUserId
    };
    this.send(request);
    hilog.debug(DOMAIN, TAG, 'Requested getUserFullInfo (userId=%{public}s)', safeUserId);
  }

  /**
   * Applies one TDLib user payload to contacts cache and emits updated list when relevant.
   *
   * @param userObj Raw TDLib user object.
   */
  private applyContactUserUpdate(userObj: TdUserPayload): void {
    const changed = this.contactsCoordinator.applyUserUpdate(userObj);
    if (!changed) {
      return;
    }
    this.emitContacts();
  }

  /**
   * Checks whether contact listeners should react to updates for specified user.
   *
   * @param userId User id as TDLib int64 string.
   * @returns `true` when the user already belongs to current contacts state.
   */
  private shouldEmitContactsForUser(userId: string): boolean {
    return this.contactsCoordinator.shouldIncludeUser(userId);
  }

  /**
   * Checks whether provided user id belongs to currently authenticated account.
   *
   * @param userId User id as TDLib int64 string.
   * @returns `true` when id matches current account id.
   */
  private isCurrentUserId(userId: string): boolean {
    if (this.myUserId <= 0) {
      return false;
    }
    return String(this.myUserId) === userId;
  }

  /**
   * Handles successful `ok` payloads and logs optional `@extra` context.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleOk(payload: string, source: string): void {
    const extra = extractExtra(payload);
    if (extra.length === 0) {
      hilog.debug(DOMAIN, TAG, 'TDLib ok (source=%{public}s)', source);
      return;
    }
    hilog.info(DOMAIN, TAG, 'TDLib ok (source=%{public}s, extra=%{public}s)', source, extra);
  }

  /**
   * Handles connection-state updates and emits network diagnostics.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleConnectionState(payload: string, source: string): void {
    const state = extractConnectionStateType(payload);
    if (state.length === 0) {
      hilog.debug(DOMAIN, TAG, 'Connection update without state (source=%{public}s)', source);
      return;
    }
    hilog.info(DOMAIN, TAG, 'Connection state: %{public}s (source=%{public}s)', state, source);
    if (state === 'connectionStateWaitingForNetwork') {
      hilog.info(DOMAIN, TAG, 'No network detected. Keep app open and reconnect internet/Wi-Fi.');
    }
  }

  /**
   * Returns whether current error is expected `loadChats` "no more chats" case.
   *
   * TDLib may answer `loadChats` with `404 Not Found` when chat list is already
   * fully loaded into local database. This isn't an application error.
   *
   * @param code TDLib error code.
   * @param message TDLib error message text.
   * @param extra TDLib `@extra` token of request that failed.
   * @returns `true` when error is expected and should be logged as info.
   */
  private isExpectedLoadChatsNotFound(code: number, message: string, extra: string): boolean {
    if (code !== 404) {
      return false;
    }
    if (message.indexOf('Not Found') < 0) {
      return false;
    }
    if (extra === TdClient.CHATS_EXTRA_LOAD_MAIN) {
      return true;
    }
    if (extra === TdClient.CHATS_EXTRA_LOAD_ARCHIVE) {
      return true;
    }
    if (extra.startsWith(TdClient.CHATS_EXTRA_LOAD_FOLDER_PREFIX)) {
      return true;
    }
    return false;
  }

  /**
   * Handles TDLib `error` payloads and forwards auth-related errors to UI.
   *
   * @param payload Raw TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleError(payload: string, source: string): void {
    const code = extractErrorCode(payload);
    const message = extractErrorMessage(payload);
    const extra = extractExtra(payload);
    if (extra === 'auth:getMe') {
      this.meRequestInFlight = false;
    }

    if (this.isExpectedLoadChatsNotFound(code, message, extra)) {
      hilog.info(
        DOMAIN,
        TAG,
        'TDLib loadChats finished (source=%{public}s, extra=%{public}s, code=%{public}d)',
        source,
        extra,
        code
      );
      return;
    }

    if (this.handleChatHistoryNotFoundError(extra, code, message)) {
      return;
    }

    if (extra.length > 0) {
      hilog.error(
        DOMAIN,
        TAG,
        'TDLib error (source=%{public}s, extra=%{public}s): code=%{public}d message=%{public}s',
        source,
        extra,
        code,
        message
      );
    } else {
      hilog.error(
        DOMAIN,
        TAG,
        'TDLib error (source=%{public}s): code=%{public}d message=%{public}s',
        source,
        code,
        message
      );
    }

    this.handleRemoteSessionRevoked(code, message, source);

    const sendExtraInfo = this.parseSendMessageExtra(extra);
    if (sendExtraInfo.chatId.length > 0) {
      this.notifySendConfirmationFailed(extra, message);
      if (this.messageSendResultListener) {
        this.messageSendResultListener(sendExtraInfo.chatId, false, message);
      }
      return;
    }

    if (this.notifyPrivateChatRequestError(extra, message)) {
      return;
    }

    if (this.notifyCallCreationError(extra, message)) {
      return;
    }

    if (!this.authErrorListener) {
      return;
    }
    if (!extra.startsWith('auth:')) {
      return;
    }
    this.authErrorListener(extra, code, message);
  }

  /**
   * Applies authorization state transition and executes side effects.
   *
   * Side effects are intentionally delegated to reducer actions to keep this
   * method deterministic and easy to reason about.
   *
   * @param stateType Authorization state extracted from TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   * @param qrAuthLinkFromPayload Optional QR login link extracted from payload.
   * @param codeLengthFromPayload Optional expected code length extracted from payload.
   */
  private handleAuthorizationState(
    stateType: string,
    source: string,
    qrAuthLinkFromPayload: string = '',
    codeLengthFromPayload: number = 0
  ): void {
    if (stateType.length === 0) {
      hilog.debug(DOMAIN, TAG, 'No authorization state in payload from %{public}s', source);
      return;
    }

    const previousState = this.authState;
    const transition = computeTdAuthTransition({
      currentState: this.authState,
      nextState: stateType,
      tdlibParametersSent: this.tdlibParametersSent,
      meRequested: this.meRequested
    });
    const next = transition.nextState;
    const leftReadyState = this.isAuthorizationReadyState(this.authState) && !this.isAuthorizationReadyState(next);

    // Log state transition before mutating local state for clarity in logs.
    if (transition.stateChanged) {
      hilog.info(DOMAIN, TAG, 'Authorization state changed: %{public}s -> %{public}s (source=%{public}s)',
        this.authState, next, source);
    } else {
      hilog.debug(DOMAIN, TAG, 'Authorization state unchanged: %{public}s (source=%{public}s)', next, source);
    }
    this.authState = next;
    this.tdlibParametersSent = transition.tdlibParametersSent;
    this.meRequested = transition.meRequested;
    this.applyAuthCodeLength(next, previousState, codeLengthFromPayload, source);
    this.applyQrAuthState(next, transition.stateChanged, qrAuthLinkFromPayload, source);

    const notifyAuthStateAfterCleanup = next === 'authorizationStateClosed';
    if (!notifyAuthStateAfterCleanup && this.authStateListener) {
      this.authStateListener(next);
    }

    // Execute reducer-driven side effects in declared order.
    for (const action of transition.actions) {
      this.handleAuthAction(action);
    }
    if (next === 'authorizationStateWaitTdlibParameters' && transition.actions.indexOf('sendTdlibParameters') < 0) {
      hilog.debug(DOMAIN, TAG, 'setTdlibParameters already sent; waiting for next state');
    }

    if (transition.shouldResetSession || leftReadyState) {
      this.stopQrRefreshLoop();
      this.clearQrAuthLink();
      this.myUserId = 0;
      this.currentMe = undefined;
      this.meRequested = false;
      this.meRequestInFlight = false;
      this.meRequestLastSentAtMs = 0;
      this.resetSessionCaches();
      this.emitContacts();
      this.emitChats();
    }

    if (next === 'authorizationStateClosed') {
      // Closed TDLib client can't be reused. Prepare wrapper for clean restart.
      this.stopAuthorizationBootstrap();
      this.clientId = -1;
      hilog.info(DOMAIN, TAG, 'TDLib client closed. Waiting for new bootstrap start.');
    }

    if (notifyAuthStateAfterCleanup && this.authStateListener) {
      this.authStateListener(next);
    }
  }

  /**
   * Tracks expected authentication-code length for code-login validation.
   *
   * @param stateType Current authorization state.
   * @param previousState Previous authorization state.
   * @param codeLengthFromPayload Positive length extracted from TDLib payload, or `0`.
   * @param source Source label used in logs.
   */
  private applyAuthCodeLength(
    stateType: string,
    previousState: string,
    codeLengthFromPayload: number,
    source: string
  ): void {
    if (stateType !== 'authorizationStateWaitCode') {
      this.authCodeLength = TdClient.AUTH_CODE_LENGTH_FALLBACK;
      return;
    }

    if (codeLengthFromPayload > 0) {
      this.authCodeLength = codeLengthFromPayload;
      hilog.info(DOMAIN, TAG, 'Auth code length=%{public}d (source=%{public}s)', this.authCodeLength, source);
      return;
    }

    if (previousState !== 'authorizationStateWaitCode') {
      this.authCodeLength = TdClient.AUTH_CODE_LENGTH_FALLBACK;
      hilog.info(DOMAIN, TAG, 'Auth code length unavailable; using fallback=%{public}d (source=%{public}s)',
        this.authCodeLength, source);
    }
  }

  /**
   * Applies QR-login specific state handling.
   *
   * @param stateType Current authorization state.
   * @param stateChanged Whether auth state changed in current transition.
   * @param qrAuthLinkFromPayload QR link extracted from current payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private applyQrAuthState(
    stateType: string,
    stateChanged: boolean,
    qrAuthLinkFromPayload: string,
    source: string
  ): void {
    if (stateType !== 'authorizationStateWaitOtherDeviceConfirmation') {
      this.stopQrRefreshLoop();
      this.clearQrAuthLink();
      return;
    }

    const safeQrLink = qrAuthLinkFromPayload.trim();
    if (safeQrLink.length > 0) {
      this.updateQrAuthLink(safeQrLink, source);
      return;
    }

    if (stateChanged) {
      hilog.info(DOMAIN, TAG, 'QR auth state entered without link payload; waiting for next update');
    }
  }

  /**
   * Stops QR-link refresh loop.
   *
   * QR auto-refresh requests are intentionally disabled because TDLib may
   * return `400 Call to requestQrCodeAuthentication unexpected` while
   * already waiting for another-device confirmation.
   */
  private stopQrRefreshLoop(): void {
    // Intentionally left as no-op to keep existing lifecycle calls stable.
  }

  /**
   * Stores latest QR-link and notifies UI listeners.
   *
   * @param link QR login link extracted from TDLib payload.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private updateQrAuthLink(link: string, source: string): void {
    const trimmedLink = link.trim();
    if (trimmedLink.length === 0) {
      return;
    }
    const changed = this.qrAuthLink !== trimmedLink;
    this.qrAuthLink = trimmedLink;
    this.qrAuthLinkUpdatedAtMs = Date.now();

    if (changed) {
      hilog.info(DOMAIN, TAG, 'QR auth link updated (source=%{public}s)', source);
    } else {
      hilog.debug(DOMAIN, TAG, 'QR auth link refreshed with same value (source=%{public}s)', source);
    }
    hilog.debug(DOMAIN, TAG, 'QR auth link value (source=%{public}s): %{public}s', source, trimmedLink);

    if (this.qrAuthLinkListener) {
      this.qrAuthLinkListener(this.qrAuthLink, this.qrAuthLinkUpdatedAtMs);
    }
  }

  /**
   * Clears stored QR-link and notifies UI listeners.
   */
  private clearQrAuthLink(): void {
    if (this.qrAuthLink.length === 0 && this.qrAuthLinkUpdatedAtMs === 0) {
      return;
    }

    this.qrAuthLink = '';
    this.qrAuthLinkUpdatedAtMs = 0;
    if (this.qrAuthLinkListener) {
      this.qrAuthLinkListener('', 0);
    }
  }

  /**
   * Dispatches single auth action using static handler map.
   *
   * @param action Reducer-produced authorization action to execute.
   */
  private handleAuthAction(action: TdAuthAction): void {
    this.authActionHandlers[action]();
  }

  /**
   * Returns whether provided state represents fully authorized TD session.
   *
   * @param state Authorization state value.
   * @returns `true` when state allows authenticated data requests.
   */
  private isAuthorizationReadyState(state: string): boolean {
    return state === TdClient.AUTH_READY_STATE;
  }

  /**
   * Checks whether authenticated request may be sent in current auth state.
   *
   * @param operation Log label of caller operation.
   * @returns `true` when request can be sent, otherwise `false`.
   */
  private canRunAuthorizedRequest(operation: string): boolean {
    if (this.isAuthorizationReadyState(this.authState)) {
      return true;
    }
    hilog.info(
      DOMAIN,
      TAG,
      '%{public}s skipped: authorization state=%{public}s',
      operation,
      this.authState
    );
    return false;
  }

  /**
   * Handles fatal auth errors that indicate remote session revocation.
   *
   * @param code TDLib error code.
   * @param message TDLib error message.
   * @param source Source label used in logs (e.g. `poll`).
   */
  private handleRemoteSessionRevoked(code: number, message: string, source: string): void {
    if (code !== 401) {
      return;
    }
    if (!this.isAuthorizationReadyState(this.authState)) {
      return;
    }

    hilog.warn(
      DOMAIN,
      TAG,
      'Detected revoked session from TDLib error (source=%{public}s, code=%{public}d, message=%{public}s). Switching to login state.',
      source,
      code,
      message
    );
    this.handleAuthorizationState(TdClient.AUTH_WAIT_PHONE_STATE, `${source}:remote-revoked`);
  }

  /**
   * Clears session-scoped caches that should not survive a fresh auth lifecycle.
   */
  private resetSessionCaches(): void {
    this.requestedChatIds.clear();
    this.requestedAvatarDownloads.clear();
    this.requestedContactUserIds.clear();
    this.requestedUserFullInfoIds.clear();
    this.requestedMessageMediaDownloads.clear();
    this.privateChatRequestListeners.clear();
    this.callCreationListeners.clear();
    this.chatOrder = [];
    this.contactsCoordinator.reset();
    this.chatTitleById.clear();
    this.chatKindByChatId.clear();
    this.chatAvatarPathByChatId.clear();
    this.chatLastMessageDateByChatId.clear();
    this.chatLastMessageTextByChatId.clear();
    this.chatLastMessageTextValueByChatId.clear();
    this.chatLastMessageKindByChatId.clear();
    this.chatLastReadInboxMessageIdByChatId.clear();
    this.chatLastReadOutboxMessageIdByChatId.clear();
    this.chatUnreadCountByChatId.clear();
    this.notificationRefreshChatIds.clear();
    this.chatPeerUserIdByChatId.clear();
    this.usernameByUserId.clear();
    this.firstNameByUserId.clear();
    this.lastNameByUserId.clear();
    this.phoneNumberByUserId.clear();
    this.userAvatarPathByUserId.clear();
    this.userAnimatedAvatarPathByUserId.clear();
    this.avatarFileIdToChatId.clear();
    this.avatarFileIdToUserId.clear();
    this.animatedAvatarFileIdToUserId.clear();
    this.messagesByChatId.clear();
    this.messageMediaFileIdByBindingKey.clear();
    this.messageBindingKeysByMediaFileId.clear();
    this.historyRequestedFromByChatId.clear();
    this.historyLimitByChatId.clear();
    this.historyNextFromByChatId.clear();
    this.historyHasMoreByChatId.clear();
    this.historyRetryBudgetByChatId.clear();
    this.historyChatNotFoundRetryBudgetByChatId.clear();
    this.viewedTailMessageIdByChatId.clear();
  }

  /**
   * Checks whether provided chat-photo payload contains animated variant.
   *
   * @param chatPhoto Chat photo payload from `userFullInfo`.
   * @returns `true` when animated or small-animated variant is present.
   */
  private hasAnimatedChatPhoto(chatPhoto: TdChatPhotoPayload | undefined): boolean {
    if (!chatPhoto) {
      return false;
    }
    return chatPhoto.small_animation !== undefined || chatPhoto.animation !== undefined;
  }

  /**
   * Selects best chat-photo source that can contain animated avatar variant.
   *
   * @param userFullInfo Raw `userFullInfo` payload.
   * @returns First photo payload that exposes animated variant.
   */
  private selectAnimatedAvatarPhoto(userFullInfo: TdUserFullInfoPayload): TdChatPhotoPayload | undefined {
    if (this.hasAnimatedChatPhoto(userFullInfo.personal_photo)) {
      return userFullInfo.personal_photo;
    }
    if (this.hasAnimatedChatPhoto(userFullInfo.photo)) {
      return userFullInfo.photo;
    }
    if (this.hasAnimatedChatPhoto(userFullInfo.public_photo)) {
      return userFullInfo.public_photo;
    }
    return undefined;
  }

  /**
   * Resolves local animated-avatar path from TDLib animated-photo payload.
   *
   * @param animatedPhoto Animated chat photo payload.
   * @returns Local file path, or empty string when unavailable.
   */
  private animatedPhotoLocalPath(animatedPhoto: TdAnimatedChatPhotoPayload | undefined): string {
    if (!animatedPhoto || !animatedPhoto.file || !animatedPhoto.file.local) {
      return '';
    }
    const localInfo = animatedPhoto.file.local;
    if (localInfo.is_downloading_completed === false) {
      return '';
    }
    const localPath = localInfo.path;
    if (typeof localPath === 'string' && localPath.length > 0) {
      return localPath;
    }
    return '';
  }

  /**
   * Resolves TDLib file id from animated chat-photo payload.
   *
   * @param animatedPhoto Animated chat photo payload.
   * @returns Positive file id, or `0` when unavailable.
   */
  private animatedPhotoFileId(animatedPhoto: TdAnimatedChatPhotoPayload | undefined): number {
    if (!animatedPhoto || !animatedPhoto.file) {
      return 0;
    }
    const fileId = animatedPhoto.file.id;
    if (typeof fileId === 'number' && fileId > 0) {
      return fileId;
    }
    return 0;
  }

  /**
   * Updates cached animated avatar path and triggers download when needed.
   *
   * @param userId User id as TDLib int64 string.
   * @param userFullInfo Raw TDLib `userFullInfo` payload.
   */
  private updateUserAnimatedAvatarCache(userId: string, userFullInfo: TdUserFullInfoPayload): void {
    const animatedPhoto = this.selectAnimatedAvatarPhoto(userFullInfo);
    if (!animatedPhoto) {
      hilog.debug(DOMAIN, TAG, 'Animated avatar unavailable in userFullInfo (userId=%{public}s)', userId);
      const removed = this.userAnimatedAvatarPathByUserId.delete(userId);
      if (removed && this.isCurrentUserId(userId)) {
        this.requestMe('animated-avatar-removed');
      }
      return;
    }

    const smallAnimationPath = this.animatedPhotoLocalPath(animatedPhoto.small_animation);
    const fullAnimationPath = this.animatedPhotoLocalPath(animatedPhoto.animation);
    const resolvedAnimationPath = smallAnimationPath.length > 0 ? smallAnimationPath : fullAnimationPath;
    if (resolvedAnimationPath.length > 0) {
      hilog.info(
        DOMAIN,
        TAG,
        'Animated avatar local path ready (userId=%{public}s, len=%{public}d)',
        userId,
        resolvedAnimationPath.length
      );
      const currentPath = this.userAnimatedAvatarPathByUserId.get(userId);
      if (currentPath !== resolvedAnimationPath) {
        this.userAnimatedAvatarPathByUserId.set(userId, resolvedAnimationPath);
        if (this.isCurrentUserId(userId)) {
          this.requestMe('animated-avatar-ready');
        }
      }
      return;
    }

    const smallAnimationFileId = this.animatedPhotoFileId(animatedPhoto.small_animation);
    const fullAnimationFileId = this.animatedPhotoFileId(animatedPhoto.animation);
    const animationFileId = smallAnimationFileId > 0 ? smallAnimationFileId : fullAnimationFileId;
    if (animationFileId > 0) {
      hilog.info(
        DOMAIN,
        TAG,
        'Animated avatar requires download (userId=%{public}s, fileId=%{public}d, smallLocalReady=%{public}d, fullLocalReady=%{public}d)',
        userId,
        animationFileId,
        smallAnimationPath.length > 0 ? 1 : 0,
        fullAnimationPath.length > 0 ? 1 : 0
      );
      this.animatedAvatarFileIdToUserId.set(animationFileId, userId);
      this.requestAvatarDownload(animationFileId);
    }
  }

  /**
   * Updates cached username for a TDLib user object.
   *
   * @param userObj Raw TDLib user object.
   */
  private updateUsernameCache(userObj: TdUserPayload): void {
    if (typeof userObj.id !== 'number' || userObj.id <= 0) {
      return;
    }
    const username = resolveUsername(userObj);
    if (username.length === 0) {
      return;
    }
    const userId = String(userObj.id);
    const current = this.usernameByUserId.get(userId);
    if (current === username) {
      return;
    }
    this.usernameByUserId.set(userId, username);
    if (this.shouldEmitContactsForUser(userId)) {
      this.emitContacts();
    }
    this.emitChats();
  }

  /**
   * Updates cached user identity fields used for routed profile snapshots.
   *
   * @param userObj Raw TDLib user object.
   */
  private updateUserIdentityCache(userObj: TdUserPayload): void {
    if (typeof userObj.id !== 'number' || userObj.id <= 0) {
      return;
    }
    const userId = String(userObj.id);
    this.firstNameByUserId.set(userId, typeof userObj.first_name === 'string' ? userObj.first_name : '');
    this.lastNameByUserId.set(userId, typeof userObj.last_name === 'string' ? userObj.last_name : '');
    this.phoneNumberByUserId.set(userId, typeof userObj.phone_number === 'string' ? userObj.phone_number : '');
  }

  /**
   * Updates cached user avatar path and triggers download when needed.
   *
   * @param userObj Raw TDLib user object.
   */
  private updateUserAvatarCache(userObj: TdUserPayload): void {
    if (typeof userObj.id !== 'number' || userObj.id <= 0) {
      return;
    }
    const userId = String(userObj.id);
    const profilePhoto = userObj.profile_photo;
    if (!profilePhoto || !profilePhoto.small) {
      return;
    }
    if (profilePhoto.has_animation === false) {
      const removed = this.userAnimatedAvatarPathByUserId.delete(userId);
      if (removed && this.isCurrentUserId(userId)) {
        this.requestMe('animated-avatar-cleared');
      }
    }

    const smallPhoto = profilePhoto.small;
    const localPhoto = smallPhoto.local;
    if (localPhoto && typeof localPhoto.path === 'string' && localPhoto.path.length > 0) {
      const current = this.userAvatarPathByUserId.get(userId);
      if (current !== localPhoto.path) {
        this.userAvatarPathByUserId.set(userId, localPhoto.path);
        if (this.shouldEmitContactsForUser(userId)) {
          this.emitContacts();
        }
        this.refreshMessagesForUser(userId);
      }
      return;
    }

    if (typeof smallPhoto.id === 'number' && smallPhoto.id > 0) {
      this.avatarFileIdToUserId.set(smallPhoto.id, userId);
      if (!this.userAvatarPathByUserId.has(userId)) {
        this.requestAvatarDownload(smallPhoto.id);
      }
    }
  }

  /**
   * Re-emits cached chat messages that belong to specified user.
   *
   * @param userId User id that owns the avatar.
   */
  private refreshMessagesForUser(userId: string): void {
    if (this.chatMessagesSubscriptions.isEmpty()) {
      return;
    }
    for (const entry of this.messagesByChatId.entries()) {
      const chatId = entry[0];
      const messages = entry[1];
      let shouldRefresh = false;
      for (const message of messages) {
        if (message.senderUserId === userId) {
          shouldRefresh = true;
          break;
        }
      }
      if (shouldRefresh) {
        this.emitChatMessages(chatId);
      }
    }
  }

  /**
   * Re-emits cached chat messages that were sent on behalf of specified chat.
   *
   * @param senderChatId Chat id that owns the sender avatar.
   */
  private refreshMessagesForSenderChat(senderChatId: string): void {
    if (this.chatMessagesSubscriptions.isEmpty()) {
      return;
    }
    for (const entry of this.messagesByChatId.entries()) {
      const chatId = entry[0];
      const messages = entry[1];
      let shouldRefresh = false;
      for (const message of messages) {
        if (message.senderChatId === senderChatId) {
          shouldRefresh = true;
          break;
        }
      }
      if (shouldRefresh) {
        this.emitChatMessages(chatId);
      }
    }
  }

  /**
   * Sets TDLib internal log verbosity.
   *
   * @param level TDLib verbosity level.
   * @returns Raw TDLib response payload.
   */
  setLogVerbosityLevel(level: number): string {
    hilog.info(DOMAIN, TAG, 'setLogVerbosityLevel=%{public}d', level);
    const response = tdNativeBridge.setLogVerbosityLevel(level);
    hilog.debug(DOMAIN, TAG, 'setLogVerbosityLevel response: %{public}s', this.preview(response));
    return response;
  }

  /**
   * Reads TDLib version via synchronous `getOption(version)` request.
   *
   * @returns Version string when available, otherwise raw/empty response.
   *
   */
  getVersion(): string {
    const request: TdGetOptionRequest = {
      '@type': 'getOption',
      'name': 'version'
    };
    const response = this.execute(request);
    if (response.length === 0) {
      return '';
    }

    try {
      const parsed = JSON.parse(response) as TdGetOptionResponse;
      if (typeof parsed.value === 'string') {
        hilog.info(DOMAIN, TAG, 'TDLib version=%{public}s', parsed.value);
        return parsed.value;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to parse TDLib version response: %{public}s', String(error));
    }
    return response;
  }
}

export const tdClient = new TdClient();
