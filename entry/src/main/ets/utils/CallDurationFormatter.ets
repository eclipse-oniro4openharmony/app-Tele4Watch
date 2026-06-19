/**
 * Long-form duration components used by the chat-history call bubble.
 * The renderer turns these into a localised string via the shared
 * `chat_call_event_duration_*` resource templates so plural forms /
 * translations stay in resource files, not in this util.
 */
export interface CallDurationLongParts {
  /** Whole minutes after the floor (>= 0). */
  minutes: number;
  /** Remaining whole seconds in the [0, 59] range. */
  seconds: number;
}

/**
 * Splits a duration in seconds into `(minutes, seconds)` parts for the
 * long-form chat bubble label. Negative / non-finite inputs collapse to
 * `(0, 0)` so the renderer can safely hide the duration line.
 *
 * @param totalSeconds Elapsed call time in whole seconds.
 * @returns `(minutes, seconds)` parts, both clamped to `>= 0`.
 */
export function splitCallDurationParts(totalSeconds: number): CallDurationLongParts {
  if (!Number.isFinite(totalSeconds) || totalSeconds <= 0) {
    return { minutes: 0, seconds: 0 };
  }
  const wholeSeconds = Math.floor(totalSeconds);
  return {
    minutes: Math.floor(wholeSeconds / 60),
    seconds: wholeSeconds % 60
  };
}

/**
 * Formats a call-duration value in whole seconds as `MM:SS`.
 *
 * Negative or non-finite inputs are clamped to `00:00` so the formatter is
 * total over the natural domain — the caller never has to guard the value
 * before passing it to the UI.
 *
 * @param totalSeconds Elapsed call time in whole seconds.
 * @returns `MM:SS` string with zero-padded minute and second components.
 */
export function formatCallDurationMMSS(totalSeconds: number): string {
  if (!Number.isFinite(totalSeconds) || totalSeconds <= 0) {
    return '00:00';
  }
  const wholeSeconds = Math.floor(totalSeconds);
  const minutes = Math.floor(wholeSeconds / 60);
  const seconds = wholeSeconds % 60;
  const minutesText = minutes < 10 ? `0${minutes}` : String(minutes);
  const secondsText = seconds < 10 ? `0${seconds}` : String(seconds);
  return `${minutesText}:${secondsText}`;
}
