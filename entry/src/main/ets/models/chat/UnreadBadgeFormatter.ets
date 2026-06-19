/**
 * Returns a presentation-safe unread badge counter.
 *
 * @param count The raw unread count.
 * @returns The normalized unread count.
 */
export function normalizeUnreadBadgeCount(count: number | undefined): number {
  if (typeof count === 'number' && count > 0) {
    return count;
  }
  return 0;
}

/**
 * Formats unread counter text for the watch badge.
 *
 * @param count The raw unread count.
 * @returns Empty text for zero, a number for `1..99`, or `99+`.
 */
export function formatUnreadBadgeCount(count: number | undefined): string {
  const normalizedCount = normalizeUnreadBadgeCount(count);
  if (normalizedCount <= 0) {
    return '';
  }
  if (normalizedCount >= 100) {
    return '99+';
  }
  return `${normalizedCount}`;
}
