/**
 * Parses a strictly digit-only positive integer.
 *
 * @param value Source text to parse.
 * @returns Positive integer, or 0 when the text is empty, non-numeric, or not positive.
 */
export function parsePositiveIntegerText(value: string): number {
  const trimmed = value.trim();
  if (trimmed.length === 0 || !isDigitText(trimmed)) {
    return 0;
  }
  const parsed = Number.parseInt(trimmed, 10);
  if (!Number.isNaN(parsed) && parsed > 0) {
    return parsed;
  }
  return 0;
}

/**
 * Checks whether a string contains ASCII digits only.
 *
 * @param value Source text to validate.
 * @returns `true` when every character is in the `0..9` range.
 */
export function isDigitText(value: string): boolean {
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}
