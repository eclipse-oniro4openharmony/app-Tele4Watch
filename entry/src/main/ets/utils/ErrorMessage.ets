export function buildErrorMessage(error: string | Error | Object): string {
  if (typeof error === 'string') {
    const trimmed = error.trim();
    if (trimmed.length > 0) {
      return trimmed;
    }
  }

  if (error instanceof Error && typeof error.message === 'string') {
    const trimmedMessage = error.message.trim();
    if (trimmedMessage.length > 0) {
      return trimmedMessage;
    }
  }

  return String(error);
}
