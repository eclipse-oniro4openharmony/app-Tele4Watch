@Component
export struct MediaPlaybackTimerBadge {
  @Prop elapsedSec: number = 0;
  @Prop elapsedMs: number = 0;
  @Prop mediaDurationSec: number = 0;
  @Prop showMilliseconds: boolean = false;

  /**
   * Pads non-negative integer value to two digits.
   *
   * @param value Numeric value.
   * @returns Two-digit string representation.
   */
  private twoDigit(value: number): string {
    if (value < 10) {
      return `0${value}`;
    }
    return String(value);
  }

  /**
   * Pads non-negative integer value to three digits.
   *
   * @param value Numeric value.
   * @returns Three-digit string representation.
   */
  private threeDigit(value: number): string {
    if (value < 10) {
      return `00${value}`;
    }
    if (value < 100) {
      return `0${value}`;
    }
    return String(value);
  }

  /**
   * Calculates elapsed playback time in milliseconds.
   *
   * @returns Non-negative elapsed time in milliseconds.
   */
  private elapsedMilliseconds(): number {
    if (this.showMilliseconds && this.elapsedMs > 0) {
      return this.elapsedMs;
    }
    return this.elapsedSec > 0 ? this.elapsedSec * 1000 : 0;
  }

  /**
   * Formats timer label in mm:ss(.SSS) or hh:mm:ss(.SSS) depending on media duration.
   *
   * @returns Human-readable elapsed playback time.
   */
  private timerLabel(): string {
    const elapsedValueMs = this.elapsedMilliseconds();
    const elapsedValueSec = Math.floor(elapsedValueMs / 1000);
    const seconds = elapsedValueSec % 60;
    const minutesTotal = Math.floor(elapsedValueSec / 60);
    const milliseconds = elapsedValueMs % 1000;
    const millisecondsSuffix = this.showMilliseconds ? `.${this.threeDigit(milliseconds)}` : '';
    const shouldUseHours = this.mediaDurationSec >= 3600;
    if (shouldUseHours) {
      const hours = Math.floor(minutesTotal / 60);
      const minutes = minutesTotal % 60;
      return `${this.twoDigit(hours)}:${this.twoDigit(minutes)}:${this.twoDigit(seconds)}${millisecondsSuffix}`;
    }
    return `${this.twoDigit(minutesTotal)}:${this.twoDigit(seconds)}${millisecondsSuffix}`;
  }

  build() {
    Text(this.timerLabel())
      .fontSize(7)
      .fontColor($r('app.color.text_primary'))
      .padding({ left: 4, right: 4, top: 4, bottom: 4 })
      .backgroundColor($r('app.color.surface_media_badge_background'))
      .borderRadius(8)
      .align(Alignment.TopStart)
  }
}
