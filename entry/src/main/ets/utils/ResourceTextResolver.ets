import resourceManager from '@ohos.resourceManager';

/**
 * Resolves a localized string by resource name and falls back to the key when unavailable.
 *
 * @param resourceManagerValue The active module resource manager.
 * @param resourceName The `string.json` resource key without the `app.string.` prefix.
 * @param args Optional formatting arguments.
 * @returns The localized string resolved for the active application locale.
 */
export function resolveString(
  resourceManagerValue: resourceManager.ResourceManager,
  resourceName: string,
  ...args: Array<string | number>
): string {
  try {
    return resourceManagerValue.getStringByNameSync(resourceName, ...args);
  } catch (_error) {
    return resourceName;
  }
}
