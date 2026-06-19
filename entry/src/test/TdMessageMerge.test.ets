import { describe, expect, it } from '@ohos/hypium';
import { copyMissingMediaFieldsFromPendingMessage } from '../main/ets/services/td/TdMessageMerge';
import { TdChatMessageItem } from '../main/ets/services/td/TdPayloadTypes';

function createVoiceNoteMessage(
  id: string,
  mediaLocalPath: string | undefined,
  mediaDurationSec: number,
  waveform: number[] | undefined
): TdChatMessageItem {
  return {
    'id': id,
    'chatId': 'chat-1',
    'kind': 'voiceNote',
    'text': '',
    'mediaFileId': 1277,
    'mediaLocalPath': mediaLocalPath,
    'mediaMimeType': 'audio/ogg',
    'mediaDurationSec': mediaDurationSec,
    'voiceNoteWaveform': waveform,
    'isOutgoing': true,
    'date': 1710000000
  };
}

function createPhotoMessage(
  id: string,
  mediaFileId: number | undefined,
  mediaThumbFileId: number | undefined,
  mediaLocalPath: string | undefined,
  mediaThumbPath: string | undefined,
  mediaMimeType: string | undefined
): TdChatMessageItem {
  return {
    'id': id,
    'chatId': 'chat-1',
    'kind': 'photo',
    'text': '',
    'mediaFileId': mediaFileId,
    'mediaThumbFileId': mediaThumbFileId,
    'mediaLocalPath': mediaLocalPath,
    'mediaThumbPath': mediaThumbPath,
    'mediaMimeType': mediaMimeType,
    'isOutgoing': true,
    'date': 1710000000
  };
}

export default function tdMessageMergeTest() {
  describe('TdMessageMergeTest', () => {
    it('shouldCopyMissingVoiceNoteMediaFieldsFromPendingMessage', 0, (): void => {
      const confirmedMessage = createVoiceNoteMessage('final-1', undefined, 0, undefined);
      const pendingMessage = createVoiceNoteMessage(
        'pending-1',
        '/cache/voice-note-local.oga',
        32,
        [2, 5, 9]
      );

      copyMissingMediaFieldsFromPendingMessage(confirmedMessage, pendingMessage);

      expect(confirmedMessage.mediaLocalPath ?? '').assertEqual('/cache/voice-note-local.oga');
      expect(confirmedMessage.mediaDurationSec ?? 0).assertEqual(32);
      expect((confirmedMessage.voiceNoteWaveform ?? []).join(',')).assertEqual('2,5,9');
    });

    it('shouldCopyMissingFileIdsMimeAndThumbPathFromPendingMessage', 0, (): void => {
      const confirmedMessage = createPhotoMessage('final-3', undefined, 0, undefined, '', '');
      const pendingMessage = createPhotoMessage(
        'pending-3',
        9001,
        9002,
        '/cache/photo.jpg',
        '/cache/photo-thumb.jpg',
        'image/jpeg'
      );

      copyMissingMediaFieldsFromPendingMessage(confirmedMessage, pendingMessage);

      expect(confirmedMessage.mediaFileId ?? 0).assertEqual(9001);
      expect(confirmedMessage.mediaThumbFileId ?? 0).assertEqual(9002);
      expect(confirmedMessage.mediaLocalPath ?? '').assertEqual('/cache/photo.jpg');
      expect(confirmedMessage.mediaThumbPath ?? '').assertEqual('/cache/photo-thumb.jpg');
      expect(confirmedMessage.mediaMimeType ?? '').assertEqual('image/jpeg');
    });

    it('shouldNotOverwriteConfirmedFileIdsMimeAndThumbPathWhenAlreadyPresent', 0, (): void => {
      const confirmedMessage = createPhotoMessage(
        'final-4',
        1001,
        1002,
        '/cache/confirmed.jpg',
        '/cache/confirmed-thumb.jpg',
        'image/png'
      );
      const pendingMessage = createPhotoMessage(
        'pending-4',
        9001,
        9002,
        '/cache/pending.jpg',
        '/cache/pending-thumb.jpg',
        'image/jpeg'
      );

      copyMissingMediaFieldsFromPendingMessage(confirmedMessage, pendingMessage);

      expect(confirmedMessage.mediaFileId ?? 0).assertEqual(1001);
      expect(confirmedMessage.mediaThumbFileId ?? 0).assertEqual(1002);
      expect(confirmedMessage.mediaLocalPath ?? '').assertEqual('/cache/confirmed.jpg');
      expect(confirmedMessage.mediaThumbPath ?? '').assertEqual('/cache/confirmed-thumb.jpg');
      expect(confirmedMessage.mediaMimeType ?? '').assertEqual('image/png');
    });

    it('shouldNotOverwriteConfirmedVoiceNoteMediaFieldsWhenAlreadyPresent', 0, (): void => {
      const confirmedMessage = createVoiceNoteMessage(
        'final-2',
        '/cache/confirmed.oga',
        18,
        [7, 8, 9]
      );
      const pendingMessage = createVoiceNoteMessage(
        'pending-2',
        '/cache/pending.oga',
        32,
        [2, 5, 9]
      );

      copyMissingMediaFieldsFromPendingMessage(confirmedMessage, pendingMessage);

      expect(confirmedMessage.mediaLocalPath ?? '').assertEqual('/cache/confirmed.oga');
      expect(confirmedMessage.mediaDurationSec ?? 0).assertEqual(18);
      expect((confirmedMessage.voiceNoteWaveform ?? []).join(',')).assertEqual('7,8,9');
    });
  });
}
