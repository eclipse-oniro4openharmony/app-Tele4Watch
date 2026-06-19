import { describe, it, expect } from '@ohos/hypium';
import { TdChatMessageItem, TdChatMessageKind } from '../main/ets/services/td/TdPayloadTypes';
import {
  formatChatMessagePreviewText,
  parseMessagePayload,
  parseUpdateMessageSendSucceededPayload,
  parseUpdateNewMessagePayload
} from '../main/ets/services/td/TdMessageParser';

function buildUpdateMessagePayload(
  contentJson: string,
  senderJson: string = '{"@type":"messageSenderUser","user_id":"7"}',
  isOutgoing: boolean = false
): string {
  return `{"message":{"id":"1001","chat_id":"55","date":1710000000,"is_outgoing":${isOutgoing},"sender_id":${senderJson},"content":${contentJson}}}`;
}

function buildTopLevelSendMessageResponse(messageIdJson: string): string {
  return `{"id":${messageIdJson},"chat_id":"55","date":1710000000,"is_outgoing":true,`
    + '"sender_id":{"@type":"messageSenderUser","user_id":"7"},'
    + '"sending_state":{"@type":"messageSendingStatePending"},'
    + '"content":{"@type":"messageText","text":{"@type":"formattedText","text":"OK","entities":[]}}}';
}

function buildSendSucceededPayload(oldMessageIdJson: string): string {
  return '{"message":{"id":"2002","chat_id":"55","date":1710000003,"is_outgoing":true,'
    + '"sender_id":{"@type":"messageSenderUser","user_id":"7"},'
    + '"content":{"@type":"messageText","text":{"@type":"formattedText","text":"Delivered"}}},'
    + `"old_message_id":${oldMessageIdJson}}`;
}

function buildPreviewMessage(
  kind: TdChatMessageKind | undefined,
  text: string = '',
  caption: string | undefined = undefined
): TdChatMessageItem {
  return {
    id: '1001',
    chatId: '55',
    kind: kind,
    text: text,
    caption: caption,
    isOutgoing: false,
    date: 1710000000
  };
}

export default function tdMessageParserTest() {
  describe('TdMessageParserTest', () => {
    it('shouldFormatChatMessagePreviewText', 0, () => {
      // Text / caption pass-through stays unchanged regardless of direction.
      expect(formatChatMessagePreviewText(buildPreviewMessage('photo', 'Hello', 'caption'))).assertEqual('Hello');
      expect(formatChatMessagePreviewText(buildPreviewMessage('photo', '', 'caption'))).assertEqual('caption');

      // Placeholder kinds now produce direction-aware fallback strings (used
      // by the notification path that has no resourceManager handy; chat-list
      // rows read the resource-backed textValue instead).
      expect(formatChatMessagePreviewText(buildPreviewMessage('photo'))).assertEqual('You received a photo');
      expect(formatChatMessagePreviewText(buildPreviewMessage('animation'))).assertEqual('You received a GIF');
      expect(formatChatMessagePreviewText(buildPreviewMessage('video'))).assertEqual('You received a video');
      expect(formatChatMessagePreviewText(buildPreviewMessage('videoNote'))).assertEqual('You received a video message');
      expect(formatChatMessagePreviewText(buildPreviewMessage('voiceNote'))).assertEqual('You received a voice message');
      expect(formatChatMessagePreviewText(buildPreviewMessage('sticker'))).assertEqual('You received a sticker');
      expect(formatChatMessagePreviewText(buildPreviewMessage('animatedEmoji'))).assertEqual('You received an emoji');

      // Outgoing branch uses the "You sent ..." variant.
      const outgoingPhoto: TdChatMessageItem = buildPreviewMessage('photo');
      outgoingPhoto.isOutgoing = true;
      expect(formatChatMessagePreviewText(outgoingPhoto)).assertEqual('You sent a photo');

      const outgoingVoice: TdChatMessageItem = buildPreviewMessage('voiceNote');
      outgoingVoice.isOutgoing = true;
      expect(formatChatMessagePreviewText(outgoingVoice)).assertEqual('You sent a voice message');

      // Service / call event preview untouched here (callEvent carries its
      // own resource-backed textValue covered in dedicated cases below).
      expect(formatChatMessagePreviewText(buildPreviewMessage('serviceEvent'))).assertEqual('[service message]');
      expect(formatChatMessagePreviewText(buildPreviewMessage(undefined))).assertEqual('New message');
    });

    it('shouldParseBasicGroupCreateServiceEvent', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload('{"@type":"messageBasicGroupChatCreate","title":"Builders","member_user_ids":["1","2"]}')
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.message.kind).assertEqual('serviceEvent');
        expect(result.message.text).assertEqual('');
        if (result.message.textValue) {
          expect(result.message.textValue.resourceName).assertEqual('chat_service_basic_group_created_format');
          expect(result.message.textValue.args.length).assertEqual(1);
          expect(result.message.textValue.args[0]).assertEqual('Builders');
        } else {
          expect(false).assertTrue();
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseTopLevelSendMessageResponse', 0, () => {
      const result = parseMessagePayload(
        '{"id":"-9001","chat_id":"55","date":1710000000,"is_outgoing":true,'
          + '"sender_id":{"@type":"messageSenderUser","user_id":"7"},'
          + '"sending_state":{"@type":"messageSendingStatePending"},'
          + '"content":{"@type":"messageText","text":{"@type":"formattedText","text":"OK","entities":[]}}}',
        ''
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.chatId).assertEqual('55');
        expect(result.message.id).assertEqual('-9001');
        expect(result.message.text).assertEqual('OK');
        expect(result.message.sendingState).assertEqual('pending');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldNormalizePendingAndSucceededSendIdsConsistently', 0, () => {
      const stringPendingResult = parseMessagePayload(buildTopLevelSendMessageResponse('"-9001"'), '');
      const stringSucceededResult = parseUpdateMessageSendSucceededPayload(buildSendSucceededPayload('"-9001"'));
      const numberPendingResult = parseMessagePayload(buildTopLevelSendMessageResponse('-9002'), '');
      const numberSucceededResult = parseUpdateMessageSendSucceededPayload(buildSendSucceededPayload('-9002'));

      expect(stringPendingResult.ok).assertTrue();
      expect(stringSucceededResult.ok).assertTrue();
      expect(numberPendingResult.ok).assertTrue();
      expect(numberSucceededResult.ok).assertTrue();
      if (
        stringPendingResult.message &&
        numberPendingResult.message
      ) {
        expect(stringPendingResult.message.id).assertEqual(stringSucceededResult.oldMessageId);
        expect(numberPendingResult.message.id).assertEqual(numberSucceededResult.oldMessageId);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseSupergroupCreateServiceEvent', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload('{"@type":"messageSupergroupChatCreate","title":"Telegram News"}')
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.message.kind).assertEqual('serviceEvent');
        if (result.message.textValue) {
          expect(result.message.textValue.resourceName).assertEqual('chat_service_supergroup_created_format');
          expect(result.message.textValue.args.length).assertEqual(1);
          expect(result.message.textValue.args[0]).assertEqual('Telegram News');
        } else {
          expect(false).assertTrue();
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseChatChangeTitleServiceEvent', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload('{"@type":"messageChatChangeTitle","title":"Nowy Tytul"}')
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        if (result.message.textValue) {
          expect(result.message.textValue.resourceName).assertEqual('chat_service_title_changed_format');
          expect(result.message.textValue.args.length).assertEqual(1);
          expect(result.message.textValue.args[0]).assertEqual('Nowy Tytul');
        } else {
          expect(false).assertTrue();
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseChatChangePhotoServiceEvent', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload(
          '{"@type":"messageChatChangePhoto","photo":{"sizes":['
          + '{"type":"s","width":40,"height":40,"photo":{"id":82,"local":{"path":"/tmp/chat-thumb.jpg","is_downloading_completed":true}}},'
          + '{"type":"x","width":160,"height":160,"photo":{"id":81,"local":{"path":"/tmp/chat-photo.jpg","is_downloading_completed":true}}}'
          + ']}}'
        )
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.message.kind).assertEqual('serviceEvent');
        expect(result.message.mediaFileId).assertEqual(81);
        expect(result.message.mediaLocalPath).assertEqual('/tmp/chat-photo.jpg');
        expect(result.message.mediaThumbPath).assertEqual('/tmp/chat-thumb.jpg');
        expect(result.message.mediaWidth).assertEqual(160);
        expect(result.message.mediaHeight).assertEqual(160);
        if (result.message.textValue) {
          expect(result.message.textValue.resourceName).assertEqual('chat_service_photo_changed');
          expect(result.message.textValue.args.length).assertEqual(0);
        } else {
          expect(false).assertTrue();
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseChatAddMembersServiceEvent', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload('{"@type":"messageChatAddMembers","member_user_ids":["11","12"]}')
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        if (result.message.textValue) {
          expect(result.message.textValue.resourceName).assertEqual('chat_service_members_added_multiple');
        } else {
          expect(false).assertTrue();
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseChatJoinByLinkServiceEvent', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload('{"@type":"messageChatJoinByLink"}')
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        if (result.message.textValue) {
          expect(result.message.textValue.resourceName).assertEqual('chat_service_joined_by_link');
        } else {
          expect(false).assertTrue();
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseChatDeleteMemberAsSelfLeave', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload(
          '{"@type":"messageChatDeleteMember","user_id":"77"}',
          '{"@type":"messageSenderUser","user_id":"77"}'
        )
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        if (result.message.textValue) {
          expect(result.message.textValue.resourceName).assertEqual('chat_service_user_left');
        } else {
          expect(false).assertTrue();
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseChatDeleteMemberAsRemoval', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload(
          '{"@type":"messageChatDeleteMember","user_id":"77"}',
          '{"@type":"messageSenderUser","user_id":"13"}'
        )
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        if (result.message.textValue) {
          expect(result.message.textValue.resourceName).assertEqual('chat_service_user_removed');
        } else {
          expect(false).assertTrue();
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseUpgradeEventsAndPinMessage', 0, () => {
      const upgradeToResult = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload('{"@type":"messageChatUpgradeTo","supergroup_id":"9"}')
      );
      const upgradeFromResult = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload('{"@type":"messageChatUpgradeFrom","title":"Old Group","basic_group_id":"4"}')
      );
      const pinResult = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload('{"@type":"messagePinMessage","message_id":"333"}')
      );

      expect(upgradeToResult.ok).assertTrue();
      expect(upgradeFromResult.ok).assertTrue();
      expect(pinResult.ok).assertTrue();
      if (upgradeToResult.message && upgradeFromResult.message && pinResult.message) {
        if (upgradeToResult.message.textValue && upgradeFromResult.message.textValue && pinResult.message.textValue) {
          expect(upgradeToResult.message.textValue.resourceName).assertEqual('chat_service_upgraded_to_supergroup');
          expect(upgradeFromResult.message.textValue.resourceName).assertEqual('chat_service_upgraded_from_group_format');
          expect(upgradeFromResult.message.textValue.args.length).assertEqual(1);
          expect(upgradeFromResult.message.textValue.args[0]).assertEqual('Old Group');
          expect(pinResult.message.textValue.resourceName).assertEqual('chat_service_message_pinned');
        } else {
          expect(false).assertTrue();
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseScreenshotAndContactRegisteredEvents', 0, () => {
      const screenshotResult = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload('{"@type":"messageScreenshotTaken"}')
      );
      const contactRegisteredResult = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload('{"@type":"messageContactRegistered"}')
      );

      expect(screenshotResult.ok).assertTrue();
      expect(contactRegisteredResult.ok).assertTrue();
      if (screenshotResult.message && contactRegisteredResult.message) {
        if (screenshotResult.message.textValue && contactRegisteredResult.message.textValue) {
          expect(screenshotResult.message.textValue.resourceName).assertEqual('chat_service_screenshot_taken');
          expect(contactRegisteredResult.message.textValue.resourceName).assertEqual('chat_service_contact_registered');
        } else {
          expect(false).assertTrue();
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseMissedVoiceCallAsCallEvent', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload(
          '{"@type":"messageCall","is_video":false,"duration":0,'
          + '"discard_reason":{"@type":"callDiscardReasonMissed"}}'
        )
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.message.kind).assertEqual('callEvent');
        expect(result.message.callEventStatus).assertEqual('missed');
        expect(result.message.callEventDurationSec).assertEqual(0);
        expect(result.message.callEventIsVideo).assertEqual(false);
        // Chat-list preview text fallback stays localised (used by ChatListItem).
        expect(result.message.text).assertEqual('Missed voice call');
        if (result.message.textValue) {
          expect(result.message.textValue.resourceName).assertEqual('chat_service_voice_call_missed');
        } else {
          expect(false).assertTrue();
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldMapOutgoingMissedCallToCancelledStatus', 0, () => {
      // TDLib emits `callDiscardReasonMissed` on both ends of an unanswered
      // call. From the caller's perspective the local user gave up before
      // pickup, so the bubble shows "Cancelled Call".
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload(
          '{"@type":"messageCall","is_video":false,"duration":0,'
          + '"discard_reason":{"@type":"callDiscardReasonMissed"}}',
          '{"@type":"messageSenderUser","user_id":"7"}',
          true
        )
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.message.kind).assertEqual('callEvent');
        expect(result.message.callEventStatus).assertEqual('cancelled');
        expect(result.message.callEventDurationSec).assertEqual(0);
        expect(result.message.isOutgoing).assertTrue();
        // Preview text must use the cancelled resource, not the legacy
        // declined fallback (review #2210 P2).
        if (result.message.textValue) {
          expect(result.message.textValue.resourceName).assertEqual('chat_service_voice_call_cancelled');
        } else {
          expect(false).assertTrue();
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldMapHungUpWithZeroDurationToAnsweredStatus', 0, () => {
      // TDLib reserves `HungUp` for calls that were answered and then ended.
      // `duration=0` is a timing edge case (immediate hangup after pickup),
      // Telegram-Android still surfaces it as a regular Outgoing/Incoming
      // Call without any cancellation flag.
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload(
          '{"@type":"messageCall","is_video":false,"duration":0,'
          + '"discard_reason":{"@type":"callDiscardReasonHungUp"}}'
        )
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.message.kind).assertEqual('callEvent');
        expect(result.message.callEventStatus).assertEqual('answered');
        expect(result.message.callEventDurationSec).assertEqual(0);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldMapEmptyDiscardReasonWithZeroDurationToCancelledStatus', 0, () => {
      // `Disconnected` / `Empty` without a duration means the call never
      // carried audio — stays `cancelled` and emits the cancelled preview
      // resource so the chat-list row does not say "Declined ..." (review
      // #2210 P2).
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload(
          '{"@type":"messageCall","is_video":false,"duration":0,'
          + '"discard_reason":{"@type":"callDiscardReasonEmpty"}}'
        )
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.message.kind).assertEqual('callEvent');
        expect(result.message.callEventStatus).assertEqual('cancelled');
        if (result.message.textValue) {
          expect(result.message.textValue.resourceName).assertEqual('chat_service_voice_call_cancelled');
        } else {
          expect(false).assertTrue();
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseVideoCallDurationAsAnsweredCallEvent', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload(
          '{"@type":"messageCall","is_video":true,"duration":83,'
          + '"discard_reason":{"@type":"callDiscardReasonHungUp"}}'
        )
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.message.kind).assertEqual('callEvent');
        expect(result.message.callEventStatus).assertEqual('answered');
        expect(result.message.callEventDurationSec).assertEqual(83);
        expect(result.message.callEventIsVideo).assertEqual(true);
        expect(result.message.text).assertEqual('Video call (1:23)');
        if (result.message.textValue) {
          expect(result.message.textValue.resourceName).assertEqual('chat_service_video_call_duration_format');
          expect(result.message.textValue.args[0]).assertEqual('1:23');
        } else {
          expect(false).assertTrue();
        }
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseSenderChatIdForChatSenders', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload(
          '{"@type":"messageText","text":{"@type":"formattedText","text":"Channel post"}}',
          '{"@type":"messageSenderChat","chat_id":"999001"}'
        )
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.message.senderUserId).assertEqual(undefined);
        expect(result.message.senderChatId).assertEqual('999001');
        expect(result.message.text).assertEqual('Channel post');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseNegativeChannelChatIdsInLiveUpdates', 0, () => {
      const result = parseUpdateNewMessagePayload(
        '{"message":{"id":"1004","chat_id":-1003559072152,"date":1710000004,"is_outgoing":true,"sender_id":{"@type":"messageSenderChat","chat_id":-1003559072152},"content":{"@type":"messageText","text":{"@type":"formattedText","text":"Channel update"}}}}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('-1003559072152');
      if (result.message) {
        expect(result.message.chatId).assertEqual('-1003559072152');
        expect(result.message.senderChatId).assertEqual('-1003559072152');
        expect(result.message.text).assertEqual('Channel update');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParsePendingAndFailedSendingState', 0, () => {
      const pendingResult = parseUpdateNewMessagePayload(
        '{"message":{"id":"1002","chat_id":"55","date":1710000001,"is_outgoing":true,"sender_id":{"@type":"messageSenderUser","user_id":"7"},"sending_state":{"@type":"messageSendingStatePending","sending_id":77},"content":{"@type":"messageText","text":{"@type":"formattedText","text":"Pending"}}}}'
      );
      const failedResult = parseUpdateNewMessagePayload(
        '{"message":{"id":"1003","chat_id":"55","date":1710000002,"is_outgoing":true,"sender_id":{"@type":"messageSenderUser","user_id":"7"},"sending_state":{"@type":"messageSendingStateFailed","can_retry":true},"content":{"@type":"messageText","text":{"@type":"formattedText","text":"Failed"}}}}'
      );

      expect(pendingResult.ok).assertTrue();
      expect(failedResult.ok).assertTrue();
      if (pendingResult.message && failedResult.message) {
        expect(pendingResult.message.sendingState).assertEqual('pending');
        expect(failedResult.message.sendingState).assertEqual('failed');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseVoiceNoteWithDownloadedLocalFile', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload(
          '{"@type":"messageVoiceNote","caption":{"@type":"formattedText","text":"Voice caption"},'
          + '"is_listened":false,"voice_note":{"duration":17,"mime_type":"audio/ogg","waveform":"AA==",'
          + '"voice":{"id":901,"local":{"path":"/data/storage/el2/base/files/tdlib/files/voice_notes/test.oga",'
          + '"is_downloading_completed":true}}}}'
        )
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.message.kind).assertEqual('voiceNote');
        expect(result.message.text).assertEqual('Voice caption');
        expect(result.message.caption).assertEqual('Voice caption');
        expect(result.message.mediaFileId).assertEqual(901);
        expect(result.message.mediaLocalPath)
          .assertEqual('/data/storage/el2/base/files/tdlib/files/voice_notes/test.oga');
        expect(result.message.mediaMimeType).assertEqual('audio/ogg');
        expect(result.message.mediaDurationSec).assertEqual(17);
        expect(result.message.voiceNoteIsListened).assertFalse();
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseVoiceNoteWithoutLocalPathWhenDownloadIsIncomplete', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload(
          '{"@type":"messageVoiceNote","voice_note":{"duration":"9","mime_type":"audio/ogg",'
          + '"voice":{"id":902,"local":{"path":"/tmp/pending.oga","is_downloading_completed":false}}}}'
        )
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.message.kind).assertEqual('voiceNote');
        expect(result.message.text).assertEqual('');
        if (result.message.textValue) {
          expect(result.message.textValue.resourceName).assertEqual('chat_message_voice_note_fallback');
        } else {
          expect(false).assertTrue();
        }
        expect(result.message.mediaFileId).assertEqual(902);
        expect(result.message.mediaLocalPath).assertUndefined();
        expect(result.message.mediaMimeType).assertEqual('audio/ogg');
        expect(result.message.mediaDurationSec).assertEqual(9);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseVideoNoteWithThumbnailAndMinithumbnail', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload(
          '{"@type":"messageVideoNote","video_note":{"duration":12,"length":384,'
          + '"minithumbnail":{"width":32,"height":32,"data":"bWluaS1qcGVn"},'
          + '"thumbnail":{"width":240,"height":240,"file":{"id":903,'
          + '"local":{"path":"/tmp/video-note-thumb.jpg","is_downloading_completed":true}}},'
          + '"video":{"id":904,"local":{"path":"/tmp/video-note.mp4","is_downloading_completed":true}}}}'
        )
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.message.kind).assertEqual('videoNote');
        expect(result.message.text).assertEqual('[video note]');
        expect(result.message.mediaFileId).assertEqual(904);
        expect(result.message.mediaThumbFileId).assertEqual(903);
        expect(result.message.mediaLocalPath).assertEqual('/tmp/video-note.mp4');
        expect(result.message.mediaThumbPath).assertEqual('/tmp/video-note-thumb.jpg');
        expect(result.message.mediaMinithumbnailData).assertEqual('bWluaS1qcGVn');
        expect(result.message.mediaWidth).assertEqual(384);
        expect(result.message.mediaHeight).assertEqual(384);
        expect(result.message.mediaMimeType).assertEqual('video/mp4');
        expect(result.message.mediaDurationSec).assertEqual(12);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseVideoNoteWithoutLocalPathsWhenDownloadsAreIncomplete', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload(
          '{"@type":"messageVideoNote","video_note":{"duration":"7","length":"240",'
          + '"thumbnail":{"width":90,"height":90,"file":{"id":905,'
          + '"local":{"path":"/tmp/video-note-thumb-pending.jpg","is_downloading_completed":false}}},'
          + '"video":{"id":906,"local":{"path":"/tmp/video-note-pending.mp4","is_downloading_completed":false}}}}'
        )
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.message.kind).assertEqual('videoNote');
        expect(result.message.mediaFileId).assertEqual(906);
        expect(result.message.mediaThumbFileId).assertEqual(905);
        expect(result.message.mediaLocalPath).assertUndefined();
        expect(result.message.mediaThumbPath).assertUndefined();
        expect(result.message.mediaMinithumbnailData).assertUndefined();
        expect(result.message.mediaWidth).assertEqual(240);
        expect(result.message.mediaHeight).assertEqual(240);
        expect(result.message.mediaMimeType).assertEqual('video/mp4');
        expect(result.message.mediaDurationSec).assertEqual(7);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseVideoNoteWithoutThumbnailData', 0, () => {
      const result = parseUpdateNewMessagePayload(
        buildUpdateMessagePayload(
          '{"@type":"messageVideoNote","video_note":{"duration":3,"length":0,"video":{"id":907,"local":{"path":"","is_downloading_completed":false}}}}'
        )
      );

      expect(result.ok).assertTrue();
      if (result.message) {
        expect(result.message.kind).assertEqual('videoNote');
        expect(result.message.mediaFileId).assertEqual(907);
        expect(result.message.mediaThumbFileId).assertUndefined();
        expect(result.message.mediaThumbPath).assertUndefined();
        expect(result.message.mediaMinithumbnailData).assertUndefined();
        expect(result.message.mediaWidth).assertUndefined();
        expect(result.message.mediaHeight).assertUndefined();
        expect(result.message.mediaDurationSec).assertEqual(3);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseUpdateMessageSendSucceededPayload', 0, () => {
      const result = parseUpdateMessageSendSucceededPayload(
        '{"message":{"id":"2002","chat_id":"55","date":1710000003,"is_outgoing":true,"sender_id":{"@type":"messageSenderUser","user_id":"7"},"content":{"@type":"messageText","text":{"@type":"formattedText","text":"Delivered"}}},"old_message_id":"2001"}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('55');
      expect(result.oldMessageId).assertEqual('2001');
      if (result.message) {
        expect(result.message.id).assertEqual('2002');
        expect(result.message.sendingState).assertEqual(undefined);
        expect(result.message.text).assertEqual('Delivered');
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldParseUpdateMessageSendSucceededForNegativeChannelChatId', 0, () => {
      const result = parseUpdateMessageSendSucceededPayload(
        '{"message":{"id":"2003","chat_id":-1003559072152,"date":1710000005,"is_outgoing":true,"sender_id":{"@type":"messageSenderChat","chat_id":-1003559072152},"content":{"@type":"messageText","text":{"@type":"formattedText","text":"Delivered channel"}}},"old_message_id":"2002"}'
      );

      expect(result.ok).assertTrue();
      expect(result.chatId).assertEqual('-1003559072152');
      expect(result.oldMessageId).assertEqual('2002');
      if (result.message) {
        expect(result.message.chatId).assertEqual('-1003559072152');
        expect(result.message.senderChatId).assertEqual('-1003559072152');
      } else {
        expect(false).assertTrue();
      }
    });
  });
}
