/**
 * Extracts top-level TDLib `@type` from raw JSON payload.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Top-level `@type` or empty string when payload doesn't match.
 */
export function extractTopLevelType(payload: string): string {
  const match = payload.match(/^\s*\{\s*\"@type\"\s*:\s*\"([^\"]+)\"/);
  if (!match || match.length < 2) {
    return '';
  }
  return match[1];
}

/**
 * Extracts authorization state type from `updateAuthorizationState` payload.
 *
 * Supports both snake_case (`authorization_state`) and camelCase
 * (`authorizationState`) formats.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Authorization state type or empty string when missing.
 */
export function extractAuthorizationStateType(payload: string): string {
  const snakeCase = payload.match(/\"authorization_state\"\s*:\s*\{\s*\"@type\"\s*:\s*\"([^\"]+)\"/);
  if (snakeCase && snakeCase.length >= 2) {
    return snakeCase[1];
  }
  const camelCase = payload.match(/\"authorizationState\"\s*:\s*\{\s*\"@type\"\s*:\s*\"([^\"]+)\"/);
  if (camelCase && camelCase.length >= 2) {
    return camelCase[1];
  }
  return '';
}

/**
 * Extracts QR login link from `authorizationStateWaitOtherDeviceConfirmation`.
 *
 * Supports both direct authorization-state payload and wrapped
 * `updateAuthorizationState` payload in snake_case/camelCase variants.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns QR login link (`tg://...`) or empty string when unavailable.
 */
export function extractAuthorizationStateQrLink(payload: string): string {
  if (!payload.includes('authorizationStateWaitOtherDeviceConfirmation')) {
    return '';
  }

  const fallbackDirect = payload.match(
    /^\s*\{\s*\"@type\"\s*:\s*\"authorizationStateWaitOtherDeviceConfirmation\"[\s\S]*?\"link\"\s*:\s*\"([^\"]+)\"/
  );
  if (fallbackDirect && fallbackDirect.length >= 2) {
    return fallbackDirect[1].replace(/\\\//g, '/');
  }

  const fallbackSnakeCase = payload.match(
    /\"authorization_state\"\s*:\s*\{\s*\"@type\"\s*:\s*\"authorizationStateWaitOtherDeviceConfirmation\"[\s\S]*?\"link\"\s*:\s*\"([^\"]+)\"/
  );
  if (fallbackSnakeCase && fallbackSnakeCase.length >= 2) {
    return fallbackSnakeCase[1].replace(/\\\//g, '/');
  }

  const fallbackCamelCase = payload.match(
    /\"authorizationState\"\s*:\s*\{\s*\"@type\"\s*:\s*\"authorizationStateWaitOtherDeviceConfirmation\"[\s\S]*?\"link\"\s*:\s*\"([^\"]+)\"/
  );
  if (fallbackCamelCase && fallbackCamelCase.length >= 2) {
    return fallbackCamelCase[1].replace(/\\\//g, '/');
  }

  return '';
}

/**
 * Extracts expected authentication-code length from `authorizationStateWaitCode`.
 *
 * Supports direct authorization-state payloads and wrapped
 * `updateAuthorizationState` payloads, with both TDLib snake_case
 * (`code_info`) and camelCase (`codeInfo`) variants.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Positive expected code length, or `0` when unavailable.
 */
export function extractAuthorizationStateCodeLength(payload: string): number {
  if (!payload.includes('authorizationStateWaitCode')) {
    return 0;
  }

  const match = payload.match(
    /\"(?:code_info|codeInfo)\"\s*:\s*\{[\s\S]*?\"type\"\s*:\s*\{[\s\S]*?\"length\"\s*:\s*\"?(\d+)\"?/
  );
  if (!match || match.length < 2) {
    return 0;
  }
  const parsed = Number.parseInt(match[1], 10);
  if (Number.isNaN(parsed) || parsed <= 0) {
    return 0;
  }
  return parsed;
}

/**
 * Extracts TDLib error code from error payload.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Parsed error code, or `-1` if payload doesn't contain valid code.
 */
export function extractErrorCode(payload: string): number {
  const match = payload.match(/\"code\"\s*:\s*(-?\d+)/);
  if (!match || match.length < 2) {
    return -1;
  }
  const parsed = Number.parseInt(match[1], 10);
  if (Number.isNaN(parsed)) {
    return -1;
  }
  return parsed;
}

/**
 * Extracts TDLib error message from error payload.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Error message, or `"unknown"` if unavailable.
 */
export function extractErrorMessage(payload: string): string {
  const match = payload.match(/\"message\"\s*:\s*\"([^\"]*)\"/);
  if (!match || match.length < 2) {
    return 'unknown';
  }
  return match[1];
}

/**
 * Extracts connection-state type from `updateConnectionState` payload.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Connection state type or empty string when missing.
 */
export function extractConnectionStateType(payload: string): string {
  const match = payload.match(/\"state\"\s*:\s*\{\s*\"@type\"\s*:\s*\"([^\"]+)\"/);
  if (!match || match.length < 2) {
    return '';
  }
  return match[1];
}

/**
 * Extracts option name from `updateOption` payload.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Option name or empty string when missing.
 */
export function extractUpdateOptionName(payload: string): string {
  const match = payload.match(/\"name\"\s*:\s*\"([^\"]+)\"/);
  if (!match || match.length < 2) {
    return '';
  }
  return match[1];
}

/**
 * Extracts integer value from option payload shaped as `optionValueInteger`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Parsed integer value, or `0` when value is missing/invalid.
 */
export function extractOptionIntegerValue(payload: string): number {
  const match = payload.match(/\"value\"\s*:\s*\{\s*\"@type\"\s*:\s*\"optionValueInteger\"\s*,\s*\"value\"\s*:\s*\"?(-?\d+)\"?\s*\}/);
  if (!match || match.length < 2) {
    return 0;
  }
  const parsed = Number.parseInt(match[1], 10);
  if (Number.isNaN(parsed)) {
    return 0;
  }
  return parsed;
}

/**
 * Extracts request correlation token from `@extra` field.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns `@extra` value or empty string when absent.
 */
export function extractExtra(payload: string): string {
  const match = payload.match(/\"@extra\"\s*:\s*\"([^\"]+)\"/);
  if (!match || match.length < 2) {
    return '';
  }
  return match[1];
}
