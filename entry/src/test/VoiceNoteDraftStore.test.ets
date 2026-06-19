import { describe, expect, it } from '@ohos/hypium';
import { VoiceNoteDraftStore, VoiceNoteDraftStorageIO } from '../main/ets/services/media/VoiceNoteDraftStore';
import { VoiceNoteRecordingResult } from '../main/ets/services/media/VoiceNoteRecorderController';

class FakeVoiceNoteDraftStorageIO extends VoiceNoteDraftStorageIO {
  ensureDirectoryCalls: string[] = [];
  deleteFileCalls: string[] = [];
  ensureDirectoryResult: boolean = true;

  ensureDirectory(directoryPath: string): boolean {
    this.ensureDirectoryCalls.push(directoryPath);
    return this.ensureDirectoryResult;
  }

  deleteFileIfPresent(filePath: string): void {
    this.deleteFileCalls.push(filePath);
  }
}

class FakeVoiceNoteRecordingResult implements VoiceNoteRecordingResult {
  filePath: string;
  durationSec: number;
  waveform: ArrayBuffer;

  constructor(filePath: string, durationSec: number, waveform: ArrayBuffer) {
    this.filePath = filePath;
    this.durationSec = durationSec;
    this.waveform = waveform;
  }
}

function createRecordingResult(filePath: string, durationSec: number, waveformBytes: number[]): FakeVoiceNoteRecordingResult {
  const waveform = new ArrayBuffer(waveformBytes.length);
  const waveformBuffer = new Uint8Array(waveform);
  for (let index = 0; index < waveformBytes.length; index += 1) {
    waveformBuffer[index] = waveformBytes[index];
  }
  return new FakeVoiceNoteRecordingResult(filePath, durationSec, waveform);
}

export default function voiceNoteDraftStoreTest() {
  describe('VoiceNoteDraftStoreTest', () => {
    it('shouldCreateOutputPathInsideVoiceNotesDirectory', 0, () => {
      const storageIO = new FakeVoiceNoteDraftStorageIO();
      const store = new VoiceNoteDraftStore(storageIO);

      const outputPath = store.createOutputPath('/cache/runtime');

      expect(storageIO.ensureDirectoryCalls.length).assertEqual(1);
      expect(storageIO.ensureDirectoryCalls[0]).assertEqual('/cache/runtime/voice_notes');
      expect(outputPath.startsWith('/cache/runtime/voice_notes/voice-note-')).assertTrue();
      expect(outputPath.endsWith('.oga')).assertTrue();
    });

    it('shouldExposeStoredPendingPayload', 0, () => {
      const storageIO = new FakeVoiceNoteDraftStorageIO();
      const store = new VoiceNoteDraftStore(storageIO);
      store.storePending(createRecordingResult('/cache/runtime/voice_notes/pending.oga', 12, [1, 2, 3, 4]));

      const payload = store.getPendingPayload();

      expect(payload !== undefined).assertTrue();
      expect(payload?.filePath ?? '').assertEqual('/cache/runtime/voice_notes/pending.oga');
      expect(payload?.durationSec ?? 0).assertEqual(12);
      expect(new Uint8Array(payload?.waveform ?? new ArrayBuffer(0)).length).assertEqual(4);
    });

    it('shouldDeletePendingFileWhenClearingDraft', 0, () => {
      const storageIO = new FakeVoiceNoteDraftStorageIO();
      const store = new VoiceNoteDraftStore(storageIO);
      store.storePending(createRecordingResult('/cache/runtime/voice_notes/to-delete.oga', 7, [9]));

      store.clearPending(true);

      expect(storageIO.deleteFileCalls.length).assertEqual(1);
      expect(storageIO.deleteFileCalls[0]).assertEqual('/cache/runtime/voice_notes/to-delete.oga');
      expect(store.getPendingPayload() === undefined).assertTrue();
    });

    it('shouldThrowWhenCreatingOutputPathWithBlankCacheDir', 0, () => {
      const storageIO = new FakeVoiceNoteDraftStorageIO();
      const store = new VoiceNoteDraftStore(storageIO);

      let thrownMessage: string = '';
      try {
        store.createOutputPath('   ');
      } catch (error) {
        thrownMessage = (error as Error).message;
      }

      expect(thrownMessage).assertEqual('Cache directory is unavailable.');
      expect(storageIO.ensureDirectoryCalls.length).assertEqual(0);
    });

    it('shouldThrowWhenEnsureDirectoryFails', 0, () => {
      const storageIO = new FakeVoiceNoteDraftStorageIO();
      storageIO.ensureDirectoryResult = false;
      const store = new VoiceNoteDraftStore(storageIO);

      let thrownMessage: string = '';
      try {
        store.createOutputPath('/cache/runtime');
      } catch (error) {
        thrownMessage = (error as Error).message;
      }

      expect(thrownMessage).assertEqual('Voice note cache directory could not be created.');
      expect(storageIO.ensureDirectoryCalls.length).assertEqual(1);
      expect(storageIO.ensureDirectoryCalls[0]).assertEqual('/cache/runtime/voice_notes');
    });

    it('shouldResetPendingStateWithoutDeletingWhenClearingSoftly', 0, () => {
      const storageIO = new FakeVoiceNoteDraftStorageIO();
      const store = new VoiceNoteDraftStore(storageIO);
      store.storePending(createRecordingResult('/cache/runtime/voice_notes/keep.oga', 5, [1, 2]));

      store.clearPending(false);

      expect(storageIO.deleteFileCalls.length).assertEqual(0);
      expect(store.getPendingPayload() === undefined).assertTrue();
    });

    it('shouldReturnUndefinedPayloadWhenDurationIsNonPositive', 0, () => {
      const storageIO = new FakeVoiceNoteDraftStorageIO();
      const store = new VoiceNoteDraftStore(storageIO);
      store.storePending(createRecordingResult('/cache/runtime/voice_notes/zero.oga', 0, [1, 2, 3]));

      const payload = store.getPendingPayload();

      expect(payload === undefined).assertTrue();
    });

    it('shouldReturnUndefinedPayloadWhenWaveformIsEmpty', 0, () => {
      const storageIO = new FakeVoiceNoteDraftStorageIO();
      const store = new VoiceNoteDraftStore(storageIO);
      store.storePending(createRecordingResult('/cache/runtime/voice_notes/no-wave.oga', 8, []));

      const payload = store.getPendingPayload();

      expect(payload === undefined).assertTrue();
    });

    it('shouldCloneWaveformOnStoreSoSourceMutationsDoNotLeakIntoPayload', 0, () => {
      const storageIO = new FakeVoiceNoteDraftStorageIO();
      const store = new VoiceNoteDraftStore(storageIO);
      const recording = createRecordingResult('/cache/runtime/voice_notes/mutable.oga', 6, [10, 20, 30]);
      store.storePending(recording);

      new Uint8Array(recording.waveform)[0] = 99;
      const payload = store.getPendingPayload();

      expect(payload !== undefined).assertTrue();
      const payloadBytes = new Uint8Array(payload?.waveform ?? new ArrayBuffer(0));
      expect(payloadBytes[0]).assertEqual(10);
      expect(payloadBytes[1]).assertEqual(20);
      expect(payloadBytes[2]).assertEqual(30);
    });

    it('shouldIsolatePayloadsBetweenRepeatedGetPendingPayloadCalls', 0, () => {
      const storageIO = new FakeVoiceNoteDraftStorageIO();
      const store = new VoiceNoteDraftStore(storageIO);
      store.storePending(createRecordingResult('/cache/runtime/voice_notes/isolated.oga', 4, [7, 8, 9]));

      const firstPayload = store.getPendingPayload();
      new Uint8Array(firstPayload?.waveform ?? new ArrayBuffer(0))[0] = 42;
      const secondPayload = store.getPendingPayload();

      expect(new Uint8Array(secondPayload?.waveform ?? new ArrayBuffer(0))[0]).assertEqual(7);
    });
  });
}
