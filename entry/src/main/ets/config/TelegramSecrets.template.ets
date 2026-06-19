export type TelegramEnvironment = 'test' | 'prod';

export interface TelegramApiCredentials {
  apiId: number;
  apiHash: string;
  useTestDc: boolean;
}

export interface TelegramSecretsConfig {
  environment: TelegramEnvironment;
  test: TelegramApiCredentials;
  prod: TelegramApiCredentials;
  /**
   * When true, dev-only UI affordances are rendered (currently the three
   * CallScreen mock entries on the Profile page). Flipped to `true` in the
   * gitignored `TelegramSecrets.local.ets` for local development, stays
   * `false` in the tracked template so production builds never expose them.
   */
  develDebug: boolean;
}

export const telegramSecrets: TelegramSecretsConfig = {
  environment: 'test',
  test: {
    apiId: 0,
    apiHash: 'REPLACE_WITH_TEST_API_HASH',
    useTestDc: true
  },
  prod: {
    apiId: 0,
    apiHash: 'REPLACE_WITH_PROD_API_HASH',
    useTestDc: false
  },
  develDebug: false
};

export function getActiveTelegramCredentials(): TelegramApiCredentials {
  if (telegramSecrets.environment === 'prod') {
    return telegramSecrets.prod;
  }
  return telegramSecrets.test;
}

/**
 * @returns `true` when the build runs with the developer-debug flag flipped
 *   on (typically only in a local `TelegramSecrets.local.ets`).
 */
export function isDevelDebugEnabled(): boolean {
  return telegramSecrets.develDebug;
}
