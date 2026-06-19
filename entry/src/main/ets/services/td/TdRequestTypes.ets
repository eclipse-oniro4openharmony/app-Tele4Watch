/**
 * TDLib request: asks for current authorization state.
 */
export interface TdGetAuthorizationStateRequest {
  '@type': 'getAuthorizationState';
}

/**
 * TDLib payload used by `setAuthenticationPhoneNumber`.
 */
export interface TdPhoneNumberAuthenticationSettings {
  '@type': 'phoneNumberAuthenticationSettings';
  'allow_flash_call': boolean;
  'allow_missed_call': boolean;
  'is_current_phone_number': boolean;
  'allow_sms_retriever_api': boolean;
}

/**
 * TDLib request: starts phone-number authentication flow.
 */
export interface TdSetAuthenticationPhoneNumberRequest {
  '@type': 'setAuthenticationPhoneNumber';
  '@extra': string;
  'phone_number': string;
  'settings': TdPhoneNumberAuthenticationSettings;
}

/**
 * TDLib request: submits login code received by the user.
 */
export interface TdCheckAuthenticationCodeRequest {
  '@type': 'checkAuthenticationCode';
  '@extra': string;
  'code': string;
}

/**
 * TDLib request: asks for QR authentication token/link.
 */
export interface TdRequestQrCodeAuthenticationRequest {
  '@type': 'requestQrCodeAuthentication';
  '@extra': string;
  'other_user_ids': string[];
}

/**
 * TDLib request: returns current account user object.
 */
export interface TdGetMeRequest {
  '@type': 'getMe';
  '@extra': string;
}

/**
 * TDLib request: returns one user object by id.
 */
export interface TdGetUserRequest {
  '@type': 'getUser';
  '@extra': string;
  'user_id': string;
}

/**
 * TDLib request: returns extended profile for selected user.
 */
export interface TdGetUserFullInfoRequest {
  '@type': 'getUserFullInfo';
  '@extra': string;
  'user_id': string;
}

/**
 * TDLib request: logs out currently authorized account.
 */
export interface TdLogOutRequest {
  '@type': 'logOut';
  '@extra': string;
}

/**
 * TDLib request: sends core TDLib runtime parameters.
 */
export interface TdSetTdlibParametersRequest {
  '@type': 'setTdlibParameters';
  '@extra': string;
  'use_test_dc': boolean;
  'database_directory': string;
  'files_directory': string;
  'database_encryption_key': string;
  'use_file_database': boolean;
  'use_chat_info_database': boolean;
  'use_message_database': boolean;
  'use_secret_chats': boolean;
  'api_id': number;
  'api_hash': string;
  'system_language_code': string;
  'device_model': string;
  'system_version': string;
  'application_version': string;
}

/**
 * TDLib request: reads runtime option by name.
 */
export interface TdGetOptionRequest {
  '@type': 'getOption';
  'name': string;
}

/**
 * TDLib chat-list selector for the main list.
 */
export interface TdChatListMain {
  '@type': 'chatListMain';
}

/**
 * TDLib chat-list selector for archived chats.
 */
export interface TdChatListArchive {
  '@type': 'chatListArchive';
}

/**
 * TDLib chat-list selector for custom chat folder.
 */
export interface TdChatListFolder {
  '@type': 'chatListFolder';
  'chat_folder_id': number;
}

/**
 * TDLib chat-list selector used by `getChats` / `loadChats`.
 */
export type TdChatList = TdChatListMain | TdChatListArchive | TdChatListFolder;

/**
 * TDLib request: returns Telegram contacts linked to current account.
 */
export interface TdGetContactsRequest {
  '@type': 'getContacts';
  '@extra': string;
}

/**
 * TDLib request: searches Telegram contacts by query.
 */
export interface TdSearchContactsRequest {
  '@type': 'searchContacts';
  '@extra': string;
  'query': string;
  'limit': number;
}

/**
 * TDLib request: fetches available custom chat folders.
 */
export interface TdGetChatFoldersRequest {
  '@type': 'getChatFolders';
  '@extra': string;
}

/**
 * TDLib request: preloads chat descriptors for selected list.
 */
export interface TdLoadChatsRequest {
  '@type': 'loadChats';
  '@extra': string;
  'chat_list': TdChatList;
  'limit': number;
}

/**
 * TDLib request: fetches ordered chat ids for selected list.
 */
export interface TdGetChatsRequest {
  '@type': 'getChats';
  '@extra': string;
  'chat_list': TdChatList;
  'limit': number;
  'offset_order': string;
  'offset_chat_id': string;
}

/**
 * TDLib request: fetches one chat object by id.
 */
export interface TdGetChatRequest {
  '@type': 'getChat';
  '@extra': string;
  'chat_id': string;
}

/**
 * TDLib request: creates or opens a private chat with selected user.
 */
export interface TdCreatePrivateChatRequest {
  '@type': 'createPrivateChat';
  '@extra': string;
  'user_id': string;
  'force': boolean;
}

/**
 * TDLib request: fetches message history page for one chat.
 */
export interface TdGetChatHistoryRequest {
  '@type': 'getChatHistory';
  '@extra': string;
  'chat_id': string;
  'from_message_id': string;
  'offset': number;
  'limit': number;
  'only_local': boolean;
}

/**
 * TDLib source marker for messages viewed in chat history.
 */
export interface TdMessageSourceChatHistory {
  '@type': 'messageSourceChatHistory';
}

/**
 * TDLib request: marks visible messages as viewed/read.
 */
export interface TdViewMessagesRequest {
  '@type': 'viewMessages';
  '@extra': string;
  'chat_id': string;
  'message_ids': string[];
  'source': TdMessageSourceChatHistory;
  'force_read': boolean;
}

/**
 * TDLib formatted-text payload used by input message content.
 */
export interface TdFormattedTextInput {
  '@type': 'formattedText';
  'text': string;
}

/**
 * TDLib input message content for plain text messages.
 */
export interface TdInputMessageTextContent {
  '@type': 'inputMessageText';
  'text': TdFormattedTextInput;
  'clear_draft': boolean;
}

/**
 * TDLib local-file descriptor used for media upload requests.
 */
export interface TdInputFileLocal {
  '@type': 'inputFileLocal';
  'path': string;
}

/**
 * TDLib input message content for voice-note messages.
 */
export interface TdInputMessageVoiceNoteContent {
  '@type': 'inputMessageVoiceNote';
  'voice_note': TdInputFileLocal;
  'duration': number;
  'waveform': string;
  'caption': TdFormattedTextInput;
}

/**
 * TDLib input message content variants supported by this repository.
 */
export type TdInputMessageContent =
  TdInputMessageTextContent |
  TdInputMessageVoiceNoteContent;

/**
 * TDLib request: sends text message to chat.
 */
export interface TdSendMessageRequest {
  '@type': 'sendMessage';
  '@extra': string;
  'chat_id': string;
  'input_message_content': TdInputMessageContent;
}

const TD_BASE64_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/**
 * Encodes waveform bytes into TDLib-compatible Base64 string.
 *
 * @param waveform Raw 63-byte waveform bitstream.
 * @returns Base64 representation accepted by TDLib JSON bridge.
 */
export function encodeTdVoiceNoteWaveform(waveform: Uint8Array): string {
  if (waveform.length === 0) {
    return '';
  }

  let result: string = '';
  let index: number = 0;
  while (index < waveform.length) {
    const firstByte: number = waveform[index] & 0xFF;
    const secondBytePresent: boolean = index + 1 < waveform.length;
    const thirdBytePresent: boolean = index + 2 < waveform.length;
    const secondByte: number = secondBytePresent ? (waveform[index + 1] & 0xFF) : 0;
    const thirdByte: number = thirdBytePresent ? (waveform[index + 2] & 0xFF) : 0;
    const combined: number = (firstByte << 16) | (secondByte << 8) | thirdByte;

    result += TD_BASE64_ALPHABET.charAt((combined >> 18) & 0x3F);
    result += TD_BASE64_ALPHABET.charAt((combined >> 12) & 0x3F);
    result += secondBytePresent ? TD_BASE64_ALPHABET.charAt((combined >> 6) & 0x3F) : '=';
    result += thirdBytePresent ? TD_BASE64_ALPHABET.charAt(combined & 0x3F) : '=';
    index += 3;
  }
  return result;
}

/**
 * Builds one `sendMessage(inputMessageVoiceNote)` TDLib request payload.
 *
 * @param extra TDLib `@extra` token used for correlation.
 * @param chatId Target chat id.
 * @param filePath Local encoded `.oga` file path.
 * @param durationSec Voice-note duration in seconds.
 * @param waveformBase64 Base64 encoded waveform bitstream.
 * @returns Fully typed TDLib request payload.
 */
export function buildTdSendVoiceNoteMessageRequest(
  extra: string,
  chatId: string,
  filePath: string,
  durationSec: number,
  waveformBase64: string
): TdSendMessageRequest {
  const safeDurationSec = durationSec > 0 ? Math.round(durationSec) : 0;
  return {
    '@type': 'sendMessage',
    '@extra': extra,
    'chat_id': chatId,
    'input_message_content': {
      '@type': 'inputMessageVoiceNote',
      'voice_note': {
        '@type': 'inputFileLocal',
        'path': filePath
      },
      'duration': safeDurationSec,
      'waveform': waveformBase64,
      'caption': {
        '@type': 'formattedText',
        'text': ''
      }
    }
  };
}

/**
 * TDLib request: schedules/starts file download.
 */
export interface TdDownloadFileRequest {
  '@type': 'downloadFile';
  'file_id': number;
  'priority': number;
  'offset': number;
  'limit': number;
  'synchronous': boolean;
}

/**
 * TDLib request: cancels file download.
 */
export interface TdCancelDownloadFileRequest {
  '@type': 'cancelDownloadFile';
  'file_id': number;
  'only_if_pending': boolean;
}

/**
 * TDLib call protocol payload used by `acceptCall`.
 */
export interface TdCallProtocolRequest {
  '@type': 'callProtocol';
  'udp_p2p': boolean;
  'udp_reflector': boolean;
  'min_layer': number;
  'max_layer': number;
  'library_versions': string[];
}

/**
 * TDLib request: creates a new outgoing call to a user.
 */
export interface TdCreateCallRequest {
  '@type': 'createCall';
  '@extra': string;
  'user_id': number;
  'protocol': TdCallProtocolRequest;
  'is_video': boolean;
}

/**
 * TDLib request: accepts an incoming call.
 */
export interface TdAcceptCallRequest {
  '@type': 'acceptCall';
  '@extra': string;
  'call_id': number;
  'protocol': TdCallProtocolRequest;
}

/**
 * TDLib request: discards or ends a call.
 */
export interface TdDiscardCallRequest {
  '@type': 'discardCall';
  '@extra': string;
  'call_id': number;
  'is_disconnected': boolean;
  'invite_link': string;
  'duration': number;
  'is_video': boolean;
  'connection_id': string;
}

/**
 * TDLib request: sends opaque call signaling data.
 */
export interface TdSendCallSignalingDataRequest {
  '@type': 'sendCallSignalingData';
  '@extra': string;
  'call_id': number;
  'data': string;
}

/**
 * Union of TDLib request payloads supported by `TdClient`.
 */
export type TdRequest =
  TdGetAuthorizationStateRequest |
  TdSetAuthenticationPhoneNumberRequest |
  TdCheckAuthenticationCodeRequest |
  TdRequestQrCodeAuthenticationRequest |
  TdGetMeRequest |
  TdGetUserRequest |
  TdGetUserFullInfoRequest |
  TdLogOutRequest |
  TdSetTdlibParametersRequest |
  TdGetOptionRequest |
  TdGetContactsRequest |
  TdSearchContactsRequest |
  TdGetChatFoldersRequest |
  TdLoadChatsRequest |
  TdGetChatsRequest |
  TdGetChatRequest |
  TdCreatePrivateChatRequest |
  TdGetChatHistoryRequest |
  TdViewMessagesRequest |
  TdSendMessageRequest |
  TdDownloadFileRequest |
  TdCancelDownloadFileRequest |
  TdCreateCallRequest |
  TdAcceptCallRequest |
  TdDiscardCallRequest |
  TdSendCallSignalingDataRequest;
