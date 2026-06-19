import { describe, expect, it } from '@ohos/hypium';
import {
  VoiceNoteAudioCapturer,
  VoiceNoteAudioCapturerFactory,
  VoiceNoteReadDataListener,
  VoiceNoteRecorderBridge,
  VoiceNoteRecorderController,
  VoiceNoteNativeRecordResult,
  VoiceNoteRecorderSnapshot
} from '../main/ets/services/media/VoiceNoteRecorderController';

class FakeVoiceNoteCapturer implements VoiceNoteAudioCapturer {
  private readDataListener: VoiceNoteReadDataListener | undefined = undefined;
  readonly calls: string[] = [];
  failStart: boolean = false;
  failStop: boolean = false;
  failRelease: boolean = false;

  setReadDataListener(listener: VoiceNoteReadDataListener | undefined): void {
    this.readDataListener = listener;
    this.calls.push(listener ? 'set-listener' : 'clear-listener');
  }

  async start(): Promise<void> {
    this.calls.push('start');
    if (this.failStart) {
      throw new Error('capturer start failed');
    }
  }

  async stop(): Promise<void> {
    this.calls.push('stop');
    if (this.failStop) {
      throw new Error('capturer stop failed');
    }
  }

  async release(): Promise<void> {
    this.calls.push('release');
    if (this.failRelease) {
      throw new Error('capturer release failed');
    }
  }

  emitReadData(byteLength: number): void {
    if (!this.readDataListener) {
      return;
    }
    this.readDataListener(new ArrayBuffer(byteLength));
  }
}

class FakeVoiceNoteCapturerFactory implements VoiceNoteAudioCapturerFactory {
  readonly capturer: FakeVoiceNoteCapturer = new FakeVoiceNoteCapturer();

  async createCapturer(): Promise<VoiceNoteAudioCapturer> {
    return this.capturer;
  }
}

class FakeVoiceNoteRecorderBridge implements VoiceNoteRecorderBridge {
  readonly calls: string[] = [];
  startResult: boolean = true;
  writeResult: boolean = true;
  stopThrows: boolean = false;
  stopResult: VoiceNoteNativeRecordResult = new FakeVoiceNoteRecordResult(4, [7, 8, 9]);

  startVoiceRecord(outputPath: string, sampleRate: number): boolean {
    this.calls.push(`start:${outputPath}:${sampleRate}`);
    return this.startResult;
  }

  writeVoiceFrame(pcm: ArrayBuffer, length: number): boolean {
    this.calls.push(`write:${pcm.byteLength}:${length}`);
    return this.writeResult;
  }

  stopVoiceRecord(): VoiceNoteNativeRecordResult {
    this.calls.push('stop');
    if (this.stopThrows) {
      throw new Error('native stop failed');
    }
    return this.stopResult;
  }
}

class FakeVoiceNoteRecordResult implements VoiceNoteNativeRecordResult {
  durationSec: number;
  waveform: ArrayBuffer;

  constructor(durationSec: number, waveformBytes: number[]) {
    this.durationSec = durationSec;
    const rawBuffer = new ArrayBuffer(waveformBytes.length);
    const buffer = new Uint8Array(rawBuffer);
    for (let index = 0; index < waveformBytes.length; index += 1) {
      buffer[index] = waveformBytes[index];
    }
    this.waveform = rawBuffer;
  }
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}

export default function voiceNoteRecorderControllerTest() {
  describe('VoiceNoteRecorderControllerTest', () => {
    it('shouldStartRecordingAndWriteIncomingPcmFrames', 0, async (): Promise<void> => {
      const capturerFactory = new FakeVoiceNoteCapturerFactory();
      const recorderBridge = new FakeVoiceNoteRecorderBridge();
      const controller = new VoiceNoteRecorderController(capturerFactory, recorderBridge);
      let snapshot: VoiceNoteRecorderSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNoteRecorderSnapshot): void => {
        snapshot = nextSnapshot;
      });

      const started = await controller.start('/cache/voice-note-1.oga');
      capturerFactory.capturer.emitReadData(960);
      await delay(0);

      expect(started).assertTrue();
      expect(snapshot.phase).assertEqual('recording');
      expect(snapshot.filePath).assertEqual('/cache/voice-note-1.oga');
      expect(capturerFactory.capturer.calls.join(',')).assertEqual('set-listener,start');
      expect(recorderBridge.calls.join(',')).assertEqual('start:/cache/voice-note-1.oga:48000,write:960:960');
    });

    it('shouldFlushQueuedPcmFramesBeforeStoppingNativeRecorder', 0, async (): Promise<void> => {
      const capturerFactory = new FakeVoiceNoteCapturerFactory();
      const recorderBridge = new FakeVoiceNoteRecorderBridge();
      const controller = new VoiceNoteRecorderController(capturerFactory, recorderBridge);

      const started = await controller.start('/cache/voice-note-flush.oga');
      capturerFactory.capturer.emitReadData(960);
      const result = await controller.stop();

      expect(started).assertTrue();
      expect(result !== undefined).assertTrue();
      expect(capturerFactory.capturer.calls.join(',')).assertEqual('set-listener,start,clear-listener,stop,release');
      expect(recorderBridge.calls.join(',')).assertEqual('start:/cache/voice-note-flush.oga:48000,write:960:960,stop');
    });

    it('shouldStopRecordingAndReturnVoiceNoteResult', 0, async (): Promise<void> => {
      const capturerFactory = new FakeVoiceNoteCapturerFactory();
      const recorderBridge = new FakeVoiceNoteRecorderBridge();
      const controller = new VoiceNoteRecorderController(capturerFactory, recorderBridge);
      let snapshot: VoiceNoteRecorderSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNoteRecorderSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.start('/cache/voice-note-2.oga');
      const result = await controller.stop();

      expect(snapshot.phase).assertEqual('idle');
      expect(result !== undefined).assertTrue();
      expect(result?.filePath ?? '').assertEqual('/cache/voice-note-2.oga');
      expect(result?.durationSec ?? 0).assertEqual(4);
      expect(new Uint8Array(result?.waveform ?? new ArrayBuffer(0)).length).assertEqual(3);
      expect(capturerFactory.capturer.calls.join(',')).assertEqual('set-listener,start,clear-listener,stop,release');
      expect(recorderBridge.calls.join(',')).assertEqual('start:/cache/voice-note-2.oga:48000,stop');
    });

    it('shouldCancelRecordingAndResetSnapshot', 0, async (): Promise<void> => {
      const capturerFactory = new FakeVoiceNoteCapturerFactory();
      const recorderBridge = new FakeVoiceNoteRecorderBridge();
      const controller = new VoiceNoteRecorderController(capturerFactory, recorderBridge);
      let snapshot: VoiceNoteRecorderSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNoteRecorderSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.start('/cache/voice-note-3.oga');
      await controller.cancel();

      expect(snapshot.phase).assertEqual('idle');
      expect(snapshot.filePath).assertEqual('');
      expect(capturerFactory.capturer.calls.join(',')).assertEqual('set-listener,start,clear-listener,stop,release');
      expect(recorderBridge.calls.join(',')).assertEqual('start:/cache/voice-note-3.oga:48000,stop');
    });

    it('shouldCleanupExactlyOnceWhenStopRacesWithFrameWriteFailure', 0, async (): Promise<void> => {
      // Regression: when writeVoiceFrame rejects a queued frame, handleReadFailure
      // schedules a late cancelInternal via the operation queue. If the user stop()
      // is already in flight at that moment the cancel must observe an empty
      // session and must not invoke capturer.stop/release or native stop twice.
      const capturerFactory = new FakeVoiceNoteCapturerFactory();
      const recorderBridge = new FakeVoiceNoteRecorderBridge();
      recorderBridge.writeResult = false;
      const controller = new VoiceNoteRecorderController(capturerFactory, recorderBridge);
      let snapshot: VoiceNoteRecorderSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNoteRecorderSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.start('/cache/voice-note-race.oga');
      capturerFactory.capturer.emitReadData(960);
      const result = await controller.stop();
      // Give the handleReadFailure-scheduled cancelInternal a chance to run.
      await delay(10);

      expect(result === undefined).assertTrue();
      expect(snapshot.phase).assertEqual('error');
      expect(snapshot.errorMessage).assertEqual('Voice note encoder rejected PCM frame.');
      expect(capturerFactory.capturer.calls.join(','))
        .assertEqual('set-listener,start,clear-listener,stop,release');
      expect(recorderBridge.calls.join(','))
        .assertEqual('start:/cache/voice-note-race.oga:48000,write:960:960,stop');
    });

    it('shouldExposeErrorWhenNativeFrameWriteFails', 0, async (): Promise<void> => {
      const capturerFactory = new FakeVoiceNoteCapturerFactory();
      const recorderBridge = new FakeVoiceNoteRecorderBridge();
      recorderBridge.writeResult = false;
      const controller = new VoiceNoteRecorderController(capturerFactory, recorderBridge);
      let snapshot: VoiceNoteRecorderSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNoteRecorderSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.start('/cache/voice-note-4.oga');
      capturerFactory.capturer.emitReadData(640);
      await delay(20);

      expect(snapshot.phase).assertEqual('error');
      expect(snapshot.errorMessage).assertEqual('Voice note encoder rejected PCM frame.');
      expect(capturerFactory.capturer.calls.join(',')).assertEqual('set-listener,start,clear-listener,stop,release');
      expect(recorderBridge.calls.join(',')).assertEqual('start:/cache/voice-note-4.oga:48000,write:640:640,stop');
    });

    it('shouldCallNativeStopExactlyOnceWhenCapturerReleaseThrowsAfterSuccessfulStop', 0, async (): Promise<void> => {
      const capturerFactory = new FakeVoiceNoteCapturerFactory();
      const recorderBridge = new FakeVoiceNoteRecorderBridge();
      capturerFactory.capturer.failRelease = true;
      const controller = new VoiceNoteRecorderController(capturerFactory, recorderBridge);
      let snapshot: VoiceNoteRecorderSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNoteRecorderSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.start('/cache/voice-note-7.oga');
      const result = await controller.stop();

      expect(result === undefined).assertTrue();
      expect(snapshot.phase).assertEqual('error');
      // Release error wins as the first failure even though native stop later succeeds.
      expect(snapshot.errorMessage).assertEqual('capturer release failed');
      // Capturer steps each run exactly once in the linear sequence.
      expect(capturerFactory.capturer.calls.join(',')).assertEqual('set-listener,start,clear-listener,stop,release');
      // Native stopVoiceRecord must be invoked exactly once despite the preceding release failure.
      expect(recorderBridge.calls.join(',')).assertEqual('start:/cache/voice-note-7.oga:48000,stop');
    });

    it('shouldCleanupExactlyOnceWhenNativeStopThrows', 0, async (): Promise<void> => {
      const capturerFactory = new FakeVoiceNoteCapturerFactory();
      const recorderBridge = new FakeVoiceNoteRecorderBridge();
      recorderBridge.stopThrows = true;
      const controller = new VoiceNoteRecorderController(capturerFactory, recorderBridge);
      let snapshot: VoiceNoteRecorderSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNoteRecorderSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.start('/cache/voice-note-6.oga');
      const result = await controller.stop();

      expect(result === undefined).assertTrue();
      expect(snapshot.phase).assertEqual('error');
      expect(snapshot.errorMessage).assertEqual('native stop failed');
      // Capturer stop + release must not be repeated on native failure path.
      expect(capturerFactory.capturer.calls.join(',')).assertEqual('set-listener,start,clear-listener,stop,release');
      // Native stopVoiceRecord called exactly once despite throwing.
      expect(recorderBridge.calls.join(',')).assertEqual('start:/cache/voice-note-6.oga:48000,stop');
    });

    it('shouldExposeErrorWhenNativeStopReturnsZeroDuration', 0, async (): Promise<void> => {
      const capturerFactory = new FakeVoiceNoteCapturerFactory();
      const recorderBridge = new FakeVoiceNoteRecorderBridge();
      recorderBridge.stopResult = new FakeVoiceNoteRecordResult(0, [1, 2, 3]);
      const controller = new VoiceNoteRecorderController(capturerFactory, recorderBridge);
      let snapshot: VoiceNoteRecorderSnapshot = controller.getSnapshot();
      controller.setListener((nextSnapshot: VoiceNoteRecorderSnapshot): void => {
        snapshot = nextSnapshot;
      });

      await controller.start('/cache/voice-note-5.oga');
      const result = await controller.stop();

      expect(result === undefined).assertTrue();
      expect(snapshot.phase).assertEqual('error');
      expect(snapshot.errorMessage).assertEqual('Voice note is too short to send.');
      expect(recorderBridge.calls.join(',')).assertEqual('start:/cache/voice-note-5.oga:48000,stop');
    });
  });
}
