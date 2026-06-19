import { describe, it, expect } from '@ohos/hypium';
import { createResourceUiText } from '../main/ets/models/ui/UiTextValue';
import { buildChatListMessagePreview } from '../main/ets/services/td/TdChatPreviewMapper';
import { TdCallEventStatus, TdChatMessageItem, TdChatMessageKind } from '../main/ets/services/td/TdPayloadTypes';

function buildMessage(
  kind: TdChatMessageKind | undefined,
  isOutgoing: boolean,
  text: string = '',
  caption: string | undefined = undefined,
  status: TdCallEventStatus | undefined = undefined,
  durationSec: number | undefined = undefined
): TdChatMessageItem {
  return {
    id: '1001',
    chatId: '55',
    kind: kind,
    text: text,
    textValue: undefined,
    caption: caption,
    callEventStatus: status,
    callEventDurationSec: durationSec,
    isOutgoing: isOutgoing,
    date: 1710000000
  };
}

export default function tdChatPreviewMapperTest() {
  describe('TdChatPreviewMapperTest', () => {
    it('shouldPreferCaptionOverMediaPlaceholder', 0, () => {
      const preview = buildChatListMessagePreview(buildMessage('photo', true, '[photo]', 'Trip'));
      expect(preview.text).assertEqual('Trip');
      expect(preview.textValue === undefined).assertTrue();
      expect(preview.isOutgoing).assertTrue();
    });

    it('shouldMapMediaPlaceholdersToDirectionAwareResources', 0, () => {
      const incomingVoice = buildMessage('voiceNote', false, '', undefined);
      incomingVoice.textValue = createResourceUiText('chat_message_voice_note_fallback');
      const incomingVoicePreview = buildChatListMessagePreview(incomingVoice);
      if (incomingVoicePreview.textValue) {
        expect(incomingVoicePreview.textValue.resourceName).assertEqual('chat_preview_incoming_voice_note');
      } else {
        expect(false).assertTrue();
      }
      expect(incomingVoicePreview.text).assertEqual('You received a voice message');

      const outgoingStickerPreview = buildChatListMessagePreview(buildMessage('sticker', true, '[sticker]'));
      if (outgoingStickerPreview.textValue) {
        expect(outgoingStickerPreview.textValue.resourceName).assertEqual('chat_preview_outgoing_sticker');
      } else {
        expect(false).assertTrue();
      }
      expect(outgoingStickerPreview.text).assertEqual('You sent a sticker');

      const stickerWithEmojiMetadata = buildChatListMessagePreview(buildMessage('sticker', false, '[sticker]', ':)'));
      if (stickerWithEmojiMetadata.textValue) {
        expect(stickerWithEmojiMetadata.textValue.resourceName).assertEqual('chat_preview_incoming_sticker');
      } else {
        expect(false).assertTrue();
      }
      expect(stickerWithEmojiMetadata.text).assertEqual('You received a sticker');
    });

    it('shouldMapAnsweredCallPreviewWithDirectionAndDuration', 0, () => {
      const outgoing = buildChatListMessagePreview(buildMessage('callEvent', true, '', undefined, 'answered', 83));
      expect(outgoing.text).assertEqual('Outgoing Call (1 min 23 s)');
      expect(outgoing.callEventStatus).assertEqual('answered');
      expect(outgoing.isOutgoing).assertTrue();
      if (outgoing.textValue) {
        expect(outgoing.textValue.resourceName).assertEqual('chat_preview_call_outgoing_minutes_seconds_format');
        expect(outgoing.textValue.args[0]).assertEqual(1);
        expect(outgoing.textValue.args[1]).assertEqual(23);
      } else {
        expect(false).assertTrue();
      }

      const incoming = buildChatListMessagePreview(buildMessage('callEvent', false, '', undefined, 'answered', 49));
      expect(incoming.text).assertEqual('Incoming Call (49 s)');
      if (incoming.textValue) {
        expect(incoming.textValue.resourceName).assertEqual('chat_preview_call_incoming_seconds_format');
        expect(incoming.textValue.args[0]).assertEqual(49);
      } else {
        expect(false).assertTrue();
      }
    });

    it('shouldMapCallFailurePreviewWithoutChangingStatusSemantics', 0, () => {
      const cancelled = buildChatListMessagePreview(buildMessage('callEvent', true, '', undefined, 'cancelled', 0));
      expect(cancelled.text).assertEqual('Cancelled Call');
      expect(cancelled.isOutgoing).assertTrue();
      expect(cancelled.callEventStatus).assertEqual('cancelled');
      if (cancelled.textValue) {
        expect(cancelled.textValue.resourceName).assertEqual('chat_preview_call_cancelled');
      } else {
        expect(false).assertTrue();
      }

      const missed = buildChatListMessagePreview(buildMessage('callEvent', false, '', undefined, 'missed', 0));
      expect(missed.text).assertEqual('Missed Call');
      expect(missed.callEventStatus).assertEqual('missed');
      if (missed.textValue) {
        expect(missed.textValue.resourceName).assertEqual('chat_preview_call_missed');
      } else {
        expect(false).assertTrue();
      }
    });
  });
}
