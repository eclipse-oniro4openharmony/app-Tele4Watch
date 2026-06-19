/**
 * Presentation-safe text value resolved by the UI layer.
 */
export interface UiTextValue {
  resourceName: string;
  rawText: string;
  args: Array<string | number>;
}

/**
 * Creates one empty UI text descriptor.
 *
 * @returns Empty text descriptor.
 */
export function createEmptyUiTextValue(): UiTextValue {
  return {
    resourceName: '',
    rawText: '',
    args: []
  };
}

/**
 * Creates one resource-backed UI text descriptor.
 *
 * @param resourceName The `string.json` key without the `app.string.` prefix.
 * @param args Optional formatting arguments.
 * @returns Resource-backed text descriptor.
 */
export function createResourceUiText(resourceName: string, ...args: Array<string | number>): UiTextValue {
  return {
    resourceName: resourceName,
    rawText: '',
    args: args
  };
}

/**
 * Creates one raw-text descriptor for externally supplied messages.
 *
 * @param rawText Raw text that should bypass resource lookup.
 * @returns Raw-text descriptor.
 */
export function createRawUiText(rawText: string): UiTextValue {
  return {
    resourceName: '',
    rawText: rawText,
    args: []
  };
}

/**
 * Creates an owned copy of one UI text descriptor.
 *
 * @param value Source UI text descriptor.
 * @returns Cloned descriptor or `undefined` when descriptor is empty.
 */
export function cloneUiTextValue(value: UiTextValue | undefined): UiTextValue | undefined {
  if (!value) {
    return undefined;
  }
  if (value.resourceName.length === 0 && value.rawText.length === 0) {
    return undefined;
  }

  const clonedArgs: Array<string | number> = [];
  for (const arg of value.args) {
    clonedArgs.push(arg);
  }
  return {
    resourceName: value.resourceName,
    rawText: value.rawText,
    args: clonedArgs
  };
}
