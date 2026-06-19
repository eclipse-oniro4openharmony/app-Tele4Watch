import { common, Want } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import {
  QuickReplyPickerRouteParams,
  QuickReplyPickerSource,
  createQuickReplyPickerRouteParams
} from '../models/quickreply/QuickReplyTemplate';

export const CHAT_DEEPLINK_KIND: 'chat' = 'chat';
export const QUICK_REPLY_DEEPLINK_KIND: 'quickReply' = 'quickReply';
export const CALL_REJECT_DEEPLINK_KIND: 'rejectCall' = 'rejectCall';
export const CALL_ANSWER_DEEPLINK_KIND: 'answerCall' = 'answerCall';
export const CALL_ANSWER_ON_PHONE_DEEPLINK_KIND: 'answerCallOnPhone' = 'answerCallOnPhone';
export const CALL_RESUME_DEEPLINK_KIND: 'resumeCall' = 'resumeCall';
const DEEPLINK_PARAMETER_KEY = 'deeplink';
const CHAT_ID_PARAMETER_KEY = 'chatId';
const MESSAGE_ID_PARAMETER_KEY = 'messageId';
const NOTIFICATION_ID_PARAMETER_KEY = 'notificationId';
const SOURCE_PARAMETER_KEY = 'source';
const CALL_ID_PARAMETER_KEY = 'callId';
const PEER_NAME_PARAMETER_KEY = 'peerName';
const DEEPLINK_PREFERENCES_NAME = 'tele4watch.deeplink';
const PENDING_DEEPLINK_KEY = 'pendingChatDeeplink';

/**
 * Chat deeplink carried from notification tap to UI routing.
 */
export interface ChatDeeplink {
  kind: 'chat';
  chatId: string;
  messageId?: string;
}

/**
 * Quick-reply deeplink carried from notification action button to picker routing.
 */
export interface QuickReplyDeeplink {
  kind: 'quickReply';
  chatId: string;
  notificationId?: number;
  source: QuickReplyPickerSource;
}

export type PendingDeeplink = ChatDeeplink | QuickReplyDeeplink;

/**
 * Call action deeplink carried from notification action button or the
 * ongoing-call notification body tap.
 */
export interface CallActionDeeplink {
  kind: 'rejectCall' | 'answerCall' | 'answerCallOnPhone' | 'resumeCall';
  callId: number;
  /** Peer display name, only carried by the `resumeCall` deeplink. */
  peerName?: string;
}

/**
 * Router params accepted by ChatDetails when opened from a notification.
 */
export interface ChatDeeplinkRouteParams {
  chatId: string;
  initialMessageId?: string;
}

/**
 * Compact diagnostics for call-action Want payloads.
 *
 * @param want Ability launch want.
 * @returns Stable diagnostic text for call-action routing logs.
 */
export function describeCallActionWant(want: Want): string {
  const parameters = want.parameters;
  if (!parameters) {
    return 'parameters=missing';
  }

  const serializedParameters = JSON.stringify(parameters);
  const kind = readStringParameter(serializedParameters, DEEPLINK_PARAMETER_KEY);
  const callIdText = readStringParameter(serializedParameters, CALL_ID_PARAMETER_KEY);
  return 'parametersLen=' + serializedParameters.length +
    ' kind=' + (kind.length > 0 ? kind : 'missing') +
    ' callId=' + (callIdText.length > 0 ? callIdText : 'missing');
}

interface StoredDeeplinkPayload {
  deeplink: string;
  chatId: string;
  messageId: string;
  notificationId: string;
  source: string;
}

/**
 * Maps chat deeplink to ChatDetails route params.
 *
 * @param deeplink Parsed chat deeplink.
 * @returns Route params consumed by ChatDetails.
 */
export function createChatDeeplinkRouteParams(deeplink: ChatDeeplink): ChatDeeplinkRouteParams {
  return {
    chatId: deeplink.chatId,
    initialMessageId: deeplink.messageId
  };
}

/**
 * Maps quick-reply deeplink to QuickReplyPicker route params.
 *
 * @param deeplink Parsed quick-reply deeplink.
 * @returns Route params consumed by QuickReplyPicker.
 */
export function createQuickReplyDeeplinkRouteParams(
  deeplink: QuickReplyDeeplink
): QuickReplyPickerRouteParams {
  return createQuickReplyPickerRouteParams(deeplink.chatId, deeplink.source, deeplink.notificationId);
}

/**
 * Parses notification deeplink data from Ability Want parameters.
 *
 * @param want Ability launch want.
 * @returns Chat deeplink or `undefined` when parameters are not a T4W chat deeplink.
 */
export function parseChatDeeplinkFromWant(want: Want): ChatDeeplink | undefined {
  const parameters = want.parameters;
  if (!parameters) {
    return undefined;
  }
  return parseChatDeeplinkFromSerialized(JSON.stringify(parameters));
}

/**
 * Parses quick-reply deeplink data from Ability Want parameters.
 *
 * @param want Ability launch want.
 * @returns Quick-reply deeplink or `undefined` when parameters are not a T4W quick-reply deeplink.
 */
export function parseQuickReplyDeeplinkFromWant(want: Want): QuickReplyDeeplink | undefined {
  const parameters = want.parameters;
  if (!parameters) {
    return undefined;
  }
  return parseQuickReplyDeeplinkFromSerialized(JSON.stringify(parameters));
}

function parseChatDeeplinkFromSerialized(serializedParameters: string): ChatDeeplink | undefined {
  const kind = readStringParameter(serializedParameters, DEEPLINK_PARAMETER_KEY);
  if (kind !== CHAT_DEEPLINK_KIND) {
    return undefined;
  }

  const chatId = readStringParameter(serializedParameters, CHAT_ID_PARAMETER_KEY);
  if (chatId.length === 0) {
    return undefined;
  }

  const messageId = readStringParameter(serializedParameters, MESSAGE_ID_PARAMETER_KEY);
  return {
    kind: CHAT_DEEPLINK_KIND,
    chatId: chatId,
    messageId: messageId.length > 0 ? messageId : undefined
  };
}

/**
 * Parses call-action deeplink data from Ability Want parameters.
 *
 * @param want Ability launch want.
 * @returns Call action deeplink or `undefined` when parameters are not a T4W call action.
 */
export function parseCallActionDeeplinkFromWant(want: Want): CallActionDeeplink | undefined {
  const parameters = want.parameters;
  if (!parameters) {
    return undefined;
  }
  const serializedParameters = JSON.stringify(parameters);

  const kind = readStringParameter(serializedParameters, DEEPLINK_PARAMETER_KEY);
  if (
    kind !== CALL_REJECT_DEEPLINK_KIND &&
    kind !== CALL_ANSWER_DEEPLINK_KIND &&
    kind !== CALL_ANSWER_ON_PHONE_DEEPLINK_KIND &&
    kind !== CALL_RESUME_DEEPLINK_KIND
  ) {
    return undefined;
  }

  const callIdText = readStringParameter(serializedParameters, CALL_ID_PARAMETER_KEY);
  const callId = Number.parseInt(callIdText, 10);
  if (Number.isNaN(callId) || callId <= 0) {
    return undefined;
  }

  const peerName = readStringParameter(serializedParameters, PEER_NAME_PARAMETER_KEY);
  return {
    kind: kind,
    callId: callId,
    peerName: peerName.length > 0 ? peerName : undefined
  };
}

function serializeChatDeeplink(deeplink: ChatDeeplink): string {
  const payload: StoredDeeplinkPayload = {
    deeplink: deeplink.kind,
    chatId: deeplink.chatId,
    messageId: deeplink.messageId ? deeplink.messageId : '',
    notificationId: '',
    source: ''
  };
  return JSON.stringify(payload);
}

function serializeQuickReplyDeeplink(deeplink: QuickReplyDeeplink): string {
  const payload: StoredDeeplinkPayload = {
    deeplink: deeplink.kind,
    chatId: deeplink.chatId,
    messageId: '',
    notificationId: deeplink.notificationId !== undefined ? String(deeplink.notificationId) : '',
    source: deeplink.source
  };
  return JSON.stringify(payload);
}

function serializePendingDeeplink(deeplink: PendingDeeplink): string {
  if (deeplink.kind === CHAT_DEEPLINK_KIND) {
    return serializeChatDeeplink(deeplink);
  }
  return serializeQuickReplyDeeplink(deeplink);
}

function parseQuickReplyDeeplinkFromSerialized(serializedParameters: string): QuickReplyDeeplink | undefined {
  const kind = readStringParameter(serializedParameters, DEEPLINK_PARAMETER_KEY);
  if (kind !== QUICK_REPLY_DEEPLINK_KIND) {
    return undefined;
  }

  const chatId = readStringParameter(serializedParameters, CHAT_ID_PARAMETER_KEY);
  if (chatId.length === 0) {
    return undefined;
  }

  const notificationIdText = readStringParameter(serializedParameters, NOTIFICATION_ID_PARAMETER_KEY);
  const notificationId = Number.parseInt(notificationIdText, 10);
  const source = readStringParameter(serializedParameters, SOURCE_PARAMETER_KEY);
  return {
    kind: QUICK_REPLY_DEEPLINK_KIND,
    chatId: chatId,
    notificationId: Number.isNaN(notificationId) || notificationId < 0 ? undefined : notificationId,
    source: normalizeQuickReplySource(source)
  };
}

function parsePendingDeeplinkFromSerialized(serializedParameters: string): PendingDeeplink | undefined {
  const chatDeeplink = parseChatDeeplinkFromSerialized(serializedParameters);
  if (chatDeeplink) {
    return chatDeeplink;
  }
  return parseQuickReplyDeeplinkFromSerialized(serializedParameters);
}

function normalizeQuickReplySource(source: string): QuickReplyPickerSource {
  if (source === 'chatDetails') {
    return 'chatDetails';
  }
  return 'notification';
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Single-slot hand-off for cold-start notification deeplinks.
 */
class DeeplinkInbox {
  private pendingDeeplink?: PendingDeeplink;
  private preferencesStore?: preferences.Preferences;

  /**
   * Connects the inbox to durable app storage and restores an unconsumed deeplink.
   *
   * @param context Ability context used for preferences access.
   */
  attachContext(context: common.UIAbilityContext): void {
    try {
      const options: preferences.Options = {
        name: DEEPLINK_PREFERENCES_NAME
      };
      this.preferencesStore = preferences.getPreferencesSync(context, options);
      const persistedDeeplink = this.readPersistedDeeplink();
      if (persistedDeeplink) {
        this.pendingDeeplink = persistedDeeplink;
      }
    } catch (error) {
      this.preferencesStore = undefined;
    }
  }

  /**
   * Stores latest deeplink until UI can consume it.
   *
   * @param deeplink Chat deeplink to store.
   */
  put(deeplink: PendingDeeplink): void {
    this.pendingDeeplink = deeplink;
    this.writePersistedDeeplink(deeplink);
  }

  /**
   * Reads and clears pending deeplink.
   *
   * @returns Pending deeplink or `undefined`.
   */
  consume(): PendingDeeplink | undefined {
    const deeplink = this.peek();
    this.pendingDeeplink = undefined;
    this.clearPersistedDeeplink();
    return deeplink;
  }

  /**
   * Reads pending deeplink without clearing it.
   *
   * @returns Pending deeplink or `undefined`.
   */
  peek(): PendingDeeplink | undefined {
    if (!this.pendingDeeplink) {
      const persistedDeeplink = this.readPersistedDeeplink();
      if (persistedDeeplink) {
        this.pendingDeeplink = persistedDeeplink;
      }
    }
    return this.pendingDeeplink;
  }

  private readPersistedDeeplink(): PendingDeeplink | undefined {
    if (!this.preferencesStore) {
      return undefined;
    }

    try {
      const value = this.preferencesStore.getSync(PENDING_DEEPLINK_KEY, '');
      if (typeof value !== 'string' || value.length === 0) {
        return undefined;
      }
      return parsePendingDeeplinkFromSerialized(value);
    } catch (error) {
      return undefined;
    }
  }

  private writePersistedDeeplink(deeplink: PendingDeeplink): void {
    if (!this.preferencesStore) {
      return;
    }

    try {
      this.preferencesStore.putSync(PENDING_DEEPLINK_KEY, serializePendingDeeplink(deeplink));
      this.preferencesStore.flushSync();
    } catch (error) {
      return;
    }
  }

  private clearPersistedDeeplink(): void {
    if (!this.preferencesStore) {
      return;
    }

    try {
      if (this.preferencesStore.hasSync(PENDING_DEEPLINK_KEY)) {
        this.preferencesStore.deleteSync(PENDING_DEEPLINK_KEY);
        this.preferencesStore.flushSync();
      }
    } catch (error) {
      return;
    }
  }
}

function readStringParameter(serializedParameters: string, key: string): string {
  const stringValue = readSerializedStringField(serializedParameters, key);
  if (stringValue.length > 0) {
    return stringValue;
  }
  return readSerializedNumberField(serializedParameters, key);
}

function readSerializedStringField(serializedParameters: string, key: string): string {
  const escapedKey = escapeRegex(key);
  const expression = new RegExp(`"${escapedKey}"\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"`);
  const match = serializedParameters.match(expression);
  if (!match || match.length < 2) {
    return '';
  }
  return decodeJsonString(match[1]).trim();
}

function readSerializedNumberField(serializedParameters: string, key: string): string {
  const escapedKey = escapeRegex(key);
  const expression = new RegExp(`"${escapedKey}"\\s*:\\s*(-?\\d+)`);
  const match = serializedParameters.match(expression);
  if (!match || match.length < 2) {
    return '';
  }
  return match[1];
}

function decodeJsonString(value: string): string {
  return value
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, '\\')
    .replace(/\\n/g, '\n')
    .replace(/\\r/g, '\r')
    .replace(/\\t/g, '\t');
}

export const deeplinkInbox: DeeplinkInbox = new DeeplinkInbox();
