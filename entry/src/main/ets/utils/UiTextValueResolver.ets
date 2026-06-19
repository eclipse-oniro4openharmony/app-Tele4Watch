import resourceManager from '@ohos.resourceManager';
import { UiTextValue } from '../models/ui/UiTextValue';
import { resolveString } from './ResourceTextResolver';

/**
 * Resolves one presentation-safe text descriptor using the active locale.
 *
 * @param resourceManagerValue The active module resource manager.
 * @param textValue The UI text descriptor.
 * @returns Resolved localized text or raw text fallback.
 */
export function resolveUiTextValue(
  resourceManagerValue: resourceManager.ResourceManager,
  textValue: UiTextValue
): string {
  if (textValue.rawText.length > 0) {
    return textValue.rawText;
  }
  if (textValue.resourceName.length === 0) {
    return '';
  }
  return resolveString(resourceManagerValue, textValue.resourceName, ...textValue.args);
}
