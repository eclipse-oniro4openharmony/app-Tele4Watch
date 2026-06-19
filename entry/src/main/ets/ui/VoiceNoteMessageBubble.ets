import resourceManager from '@ohos.resourceManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TdChatMessageItem } from '../models/td/TdViewTypes';
import { createEmptyUiTextValue } from '../models/ui/UiTextValue';
import { resolveString } from '../utils/ResourceTextResolver';
import {
  VoiceNotePlaybackPhase,
  VoiceNotePlaybackSnapshot,
  VOICE_NOTE_ERROR_MISSING_FILE_PATH,
  VOICE_NOTE_ERROR_PLAYBACK_FAILED
} from '../services/media/VoiceNotePlaybackController';

const DOMAIN = 0x2026;
const TAG = 'VoiceNoteMessageBubble';
const VOICE_NOTE_WAVEFORM_BAR_COUNT = 32;
const VOICE_NOTE_WAVEFORM_BAR_WIDTH = 1.5;
const VOICE_NOTE_WAVEFORM_BAR_SPACING = 1;
const VOICE_NOTE_WAVEFORM_MIN_BAR_HEIGHT = 2;
const VOICE_NOTE_WAVEFORM_MAX_BAR_HEIGHT = 16;

interface VoiceNoteWaveformBar {
  'id': string;
  'renderKey': string;
  'height': number;
  'played': boolean;
  'isCurrent': boolean;
  'color': ResourceColor;
}

/**
 * Renders the dedicated voice-note bubble body with playback affordance and waveform progress.
 */
@Component
export struct VoiceNoteMessageBubble {
  @Prop message: TdChatMessageItem = {
    'id': '',
    'chatId': '',
    'senderUserId': '',
    'senderChatId': undefined,
    'senderAvatarPath': undefined,
    'sendingState': undefined,
    'deliveryState': undefined,
    'kind': 'text',
    'text': '',
    'textValue': createEmptyUiTextValue(),
    'caption': undefined,
    'mediaFileId': undefined,
    'mediaThumbFileId': undefined,
    'mediaLocalPath': undefined,
    'mediaThumbPath': undefined,
    'mediaWidth': undefined,
    'mediaHeight': undefined,
    'mediaMimeType': undefined,
    'mediaIsAnimated': undefined,
    'mediaDurationSec': undefined,
    'isOutgoing': false,
    'date': 0
  };
  @Prop voiceNotePlayback: VoiceNotePlaybackSnapshot = {
    'messageId': '',
    'phase': 'idle',
    'positionMs': 0,
    'durationMs': 0,
    'errorMessage': ''
  };
  onVoiceNoteToggle: (message: TdChatMessageItem) => void = (_message: TdChatMessageItem): void => {};
  private voiceNoteWaveformSignature: string = '';
  private voiceNoteWaveformBars: VoiceNoteWaveformBar[] = [];

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

  private voiceNoteHasLocalPath(): boolean {
    if (typeof this.message.mediaLocalPath !== 'string') {
      return false;
    }
    return this.message.mediaLocalPath.trim().length > 0;
  }

  private voiceNoteHasRemoteFile(): boolean {
    return typeof this.message.mediaFileId === 'number' && this.message.mediaFileId > 0;
  }

  private isActiveVoiceNotePlayback(): boolean {
    return this.voiceNotePlayback.messageId === this.message.id;
  }

  private effectiveVoiceNotePhase(): VoiceNotePlaybackPhase {
    if (this.isActiveVoiceNotePlayback()) {
      return this.voiceNotePlayback.phase;
    }
    if (!this.voiceNoteHasLocalPath() && this.voiceNoteHasRemoteFile()) {
      return 'loading';
    }
    return 'idle';
  }

  private voiceNoteDurationMs(): number {
    if (this.isActiveVoiceNotePlayback() && this.voiceNotePlayback.durationMs > 0) {
      return this.voiceNotePlayback.durationMs;
    }
    if (typeof this.message.mediaDurationSec === 'number' && this.message.mediaDurationSec > 0) {
      return this.message.mediaDurationSec * 1000;
    }
    return 0;
  }

  private voiceNotePositionMs(): number {
    if (!this.isActiveVoiceNotePlayback()) {
      return 0;
    }
    if (this.voiceNotePlayback.positionMs > 0) {
      return this.voiceNotePlayback.positionMs;
    }
    return 0;
  }

  private voiceNoteErrorMessage(): string {
    if (!this.isActiveVoiceNotePlayback()) {
      return '';
    }
    return this.voiceNotePlayback.errorMessage.trim();
  }

  private localizedVoiceNoteErrorMessage(): string {
    const errorMessage = this.voiceNoteErrorMessage();
    if (errorMessage.length === 0) {
      return '';
    }
    if (errorMessage === VOICE_NOTE_ERROR_MISSING_FILE_PATH) {
      return this.getString('chat_message_voice_note_missing_file');
    }
    if (errorMessage === VOICE_NOTE_ERROR_PLAYBACK_FAILED) {
      return this.getString('chat_message_voice_note_playback_failed');
    }
    return errorMessage;
  }

  private shouldShowVoiceNoteUnreadDot(): boolean {
    if (this.message.isOutgoing) {
      return false;
    }
    if (this.effectiveVoiceNotePhase() === 'error') {
      return false;
    }
    return this.message.voiceNoteIsListened === false;
  }

  private formatVoiceNoteTimeLabel(totalMs: number): string {
    if (totalMs <= 0) {
      return this.getString('common_time_zero_short');
    }
    const totalSeconds = Math.floor(totalMs / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    const secondsLabel = seconds < 10 ? `0${seconds}` : String(seconds);
    return `${minutes}:${secondsLabel}`;
  }

  private voiceNoteStatusLabel(): string {
    const phase = this.effectiveVoiceNotePhase();
    if (phase === 'error') {
      const errorMessage = this.localizedVoiceNoteErrorMessage();
      if (errorMessage.length > 0) {
        return errorMessage;
      }
      return this.getString('chat_message_voice_note_error');
    }
    if (phase === 'loading') {
      return this.getString('chat_message_voice_note_loading');
    }

    const positionLabel = this.formatVoiceNoteTimeLabel(this.voiceNotePositionMs());
    const durationLabel = this.formatVoiceNoteTimeLabel(this.voiceNoteDurationMs());
    return `${positionLabel} / ${durationLabel}`;
  }

  private voiceNoteProgressRatio(): number {
    const durationMs = this.voiceNoteDurationMs();
    if (durationMs <= 0) {
      return 0;
    }
    const ratio = this.voiceNotePositionMs() / durationMs;
    if (ratio < 0) {
      return 0;
    }
    if (ratio > 1) {
      return 1;
    }
    return ratio;
  }

  private buildFallbackVoiceNoteSamples(): number[] {
    return [7, 10, 13, 16, 14, 11, 8, 10, 13, 16, 15, 12, 9, 11, 14, 16, 13, 9];
  }

  private voiceNoteWaveformSamples(): number[] {
    if (this.message.voiceNoteWaveform && this.message.voiceNoteWaveform.length > 0) {
      return this.message.voiceNoteWaveform;
    }
    return this.buildFallbackVoiceNoteSamples();
  }

  private voiceNoteWaveformDataSignature(): string {
    const waveform = this.voiceNoteWaveformSamples();
    return `${this.message.id}:${waveform.length}:${this.voiceNoteDurationMs()}:${this.voiceNotePositionMs()}:${this.effectiveVoiceNotePhase()}`;
  }

  private clampVoiceNoteBarHeight(sample: number): number {
    const normalizedSample = sample < 0 ? 0 : sample > 31 ? 31 : sample;
    const scaledHeight =
      VOICE_NOTE_WAVEFORM_MIN_BAR_HEIGHT +
      Math.round(((VOICE_NOTE_WAVEFORM_MAX_BAR_HEIGHT - VOICE_NOTE_WAVEFORM_MIN_BAR_HEIGHT) * normalizedSample) / 31);
    if (scaledHeight < VOICE_NOTE_WAVEFORM_MIN_BAR_HEIGHT) {
      return VOICE_NOTE_WAVEFORM_MIN_BAR_HEIGHT;
    }
    if (scaledHeight > VOICE_NOTE_WAVEFORM_MAX_BAR_HEIGHT) {
      return VOICE_NOTE_WAVEFORM_MAX_BAR_HEIGHT;
    }
    return scaledHeight;
  }

  private voiceNoteWaveformBarColorForState(
    phase: VoiceNotePlaybackPhase,
    played: boolean,
    isCurrent: boolean
  ): ResourceColor {
    if (phase === 'error') {
      return $r('app.color.chat_voice_note_waveform_error');
    }
    if (phase === 'loading') {
      return $r('app.color.chat_voice_note_waveform_loading');
    }
    if (played) {
      return $r('app.color.chat_voice_note_waveform_played');
    }
    if (isCurrent) {
      return $r('app.color.chat_voice_note_waveform_current');
    }
    if (this.message.isOutgoing) {
      return $r('app.color.chat_voice_note_waveform_outgoing');
    }
    return $r('app.color.chat_voice_note_waveform_incoming');
  }

  private createVoiceNoteWaveformBars(): VoiceNoteWaveformBar[] {
    const waveform = this.voiceNoteWaveformSamples();
    const bars: VoiceNoteWaveformBar[] = [];
    const progressRatio = this.voiceNoteProgressRatio();
    const phase = this.effectiveVoiceNotePhase();
    const showCurrentBar = phase === 'playing' || phase === 'paused';

    for (let index = 0; index < VOICE_NOTE_WAVEFORM_BAR_COUNT; index += 1) {
      const start = Math.floor((index * waveform.length) / VOICE_NOTE_WAVEFORM_BAR_COUNT);
      const end = Math.floor(((index + 1) * waveform.length) / VOICE_NOTE_WAVEFORM_BAR_COUNT);
      let maxSample = 0;
      let sampleCount = 0;

      for (let sampleIndex = start; sampleIndex < end; sampleIndex += 1) {
        const sample = waveform[sampleIndex];
        if (sample > maxSample) {
          maxSample = sample;
        }
        sampleCount += 1;
      }

      if (sampleCount === 0 && start < waveform.length) {
        maxSample = waveform[start];
      }

      const barStartRatio = index / VOICE_NOTE_WAVEFORM_BAR_COUNT;
      const barEndRatio = (index + 1) / VOICE_NOTE_WAVEFORM_BAR_COUNT;
      const played = progressRatio >= barEndRatio;
      const isCurrent = showCurrentBar && progressRatio >= barStartRatio && progressRatio < barEndRatio;
      bars.push({
        'id': `voice-bar-${index}`,
        'renderKey': `voice-bar-${index}-${phase}-${played ? 'played' : isCurrent ? 'current' : 'pending'}`,
        'height': this.clampVoiceNoteBarHeight(maxSample),
        'played': played,
        'isCurrent': isCurrent,
        'color': this.voiceNoteWaveformBarColorForState(phase, played, isCurrent)
      });
    }

    return bars;
  }

  private currentVoiceNoteWaveformBars(): VoiceNoteWaveformBar[] {
    const signature = this.voiceNoteWaveformDataSignature();
    if (this.voiceNoteWaveformSignature !== signature) {
      this.voiceNoteWaveformSignature = signature;
      this.voiceNoteWaveformBars = this.createVoiceNoteWaveformBars();
    }
    return this.voiceNoteWaveformBars;
  }

  private voiceNotePrimaryButtonLabel(): string {
    const phase = this.effectiveVoiceNotePhase();
    if (phase === 'error') {
      return this.getString('common_error_symbol');
    }
    return '';
  }

  @Builder
  private buildVoiceNotePlaybackIcon(): void {
    if (this.effectiveVoiceNotePhase() === 'playing') {
      if (this.message.isOutgoing) {
        Image($r('app.media.chat_voice_note_pause_outgoing'))
          .width(22)
          .height(22)
          .objectFit(ImageFit.Contain)
      } else {
        Image($r('app.media.chat_voice_note_pause_incoming'))
          .width(22)
          .height(22)
          .objectFit(ImageFit.Contain)
      }
    } else {
      if (this.message.isOutgoing) {
        Image($r('app.media.chat_voice_note_play_outgoing'))
          .width(22)
          .height(22)
          .objectFit(ImageFit.Contain)
      } else {
        Image($r('app.media.chat_voice_note_play_incoming'))
          .width(22)
          .height(22)
          .objectFit(ImageFit.Contain)
      }
    }
  }

  private voiceNotePrimaryButtonBackgroundColor(): ResourceColor {
    const phase = this.effectiveVoiceNotePhase();
    if (phase === 'error') {
      return $r('app.color.chat_voice_note_button_background_error');
    }
    if (phase === 'loading') {
      return $r('app.color.chat_voice_note_button_background_loading');
    }
    return $r('app.color.chat_voice_note_button_background_default');
  }

  private voiceNotePrimaryButtonTextColor(): ResourceColor {
    const phase = this.effectiveVoiceNotePhase();
    if (phase === 'error') {
      return $r('app.color.chat_voice_note_button_label_error');
    }
    if (phase === 'loading') {
      return $r('app.color.chat_voice_note_button_label_loading');
    }
    return $r('app.color.chat_voice_note_button_label_default');
  }

  private voiceNoteErrorButtonFontSize(): number {
    return 16;
  }

  private canToggleVoiceNotePlayback(): boolean {
    return this.message.id.length > 0;
  }

  private shouldRenderCaption(): boolean {
    return this.captionText().length > 0;
  }

  private captionText(): string {
    if (typeof this.message.caption !== 'string') {
      return '';
    }
    const trimmedCaption = this.message.caption.trim();
    if (trimmedCaption.length === 0) {
      return '';
    }
    return this.message.caption;
  }

  private timerTextColor(): ResourceColor {
    if (this.message.isOutgoing) {
      return $r('app.color.chat_voice_note_timer_outgoing');
    }
    return $r('app.color.chat_voice_note_timer_incoming');
  }

  @Builder
  private buildVoiceNotePrimaryButtonContent(): void {
    if (this.effectiveVoiceNotePhase() === 'error') {
      Text(this.voiceNotePrimaryButtonLabel())
        .fontSize(this.voiceNoteErrorButtonFontSize())
        .fontWeight(FontWeight.Bold)
        .fontColor(this.voiceNotePrimaryButtonTextColor())
        .textAlign(TextAlign.Center)
    } else {
      this.buildVoiceNotePlaybackIcon()
    }
  }

  /**
   * Builds the voice-note bubble content used inside the chat message item shell.
   *
   * @returns Nothing.
   */
  build() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Column() {
          this.buildVoiceNotePrimaryButtonContent()
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.voiceNotePrimaryButtonBackgroundColor())
        .borderRadius(20)
        .onClick(() => {
          hilog.debug(
            DOMAIN,
            TAG,
            'Voice note button clicked (messageId=%{public}s, phase=%{public}s, hasLocalPath=%{public}d, fileId=%{public}d)',
            this.message.id,
            this.effectiveVoiceNotePhase(),
            this.voiceNoteHasLocalPath() ? 1 : 0,
            typeof this.message.mediaFileId === 'number' ? this.message.mediaFileId : 0
          );
          if (!this.canToggleVoiceNotePlayback()) {
            return;
          }
          this.onVoiceNoteToggle(this.message);
        })

        Column({ space: 5 }) {
          Row({ space: VOICE_NOTE_WAVEFORM_BAR_SPACING }) {
            ForEach(this.currentVoiceNoteWaveformBars(), (bar: VoiceNoteWaveformBar) => {
              Column() {}
                .width(VOICE_NOTE_WAVEFORM_BAR_WIDTH)
                .height(bar.height)
                .borderRadius(1)
                .backgroundColor(bar.color)
            }, (bar: VoiceNoteWaveformBar) => bar.renderKey)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .height(20)

          Row({ space: 5 }) {
            Text(this.voiceNoteStatusLabel())
              .layoutWeight(1)
              .fontSize(9)
              .fontColor(this.effectiveVoiceNotePhase() === 'error'
                ? $r('app.color.chat_voice_note_timer_error')
                : this.timerTextColor())
              .textAlign(TextAlign.Start)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (this.shouldShowVoiceNoteUnreadDot()) {
              Column() {}
                .width(5)
                .height(5)
                .borderRadius(3)
                .backgroundColor($r('app.color.chat_voice_note_unread_dot'))
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.shouldRenderCaption()) {
        Text(this.captionText())
          .fontSize(12)
          .width('100%')
          .fontColor($r('app.color.text_primary'))
          .maxLines(4)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
