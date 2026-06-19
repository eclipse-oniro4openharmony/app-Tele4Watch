import {
  TdChatListItem as ServiceTdChatListItem,
  TdChatMessageItem as ServiceTdChatMessageItem,
  TdContactListItem as ServiceTdContactListItem,
  TdMeInfo as ServiceTdMeInfo
} from '../../services/td/TdPayloadTypes';

export type TdMeInfo = ServiceTdMeInfo;
export type TdChatListItem = ServiceTdChatListItem;
export type TdContactListItem = ServiceTdContactListItem;
export type TdChatMessageItem = ServiceTdChatMessageItem;
