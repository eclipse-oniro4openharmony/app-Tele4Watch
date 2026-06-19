/**
 * Produces stable positive numeric signature for deterministic palette selection.
 *
 * @param value String used as hash source.
 * @returns Positive signature value.
 */
export function textSignature(value: string): number {
  let hashValue = 0;
  for (let index = 0; index < value.length; index += 1) {
    hashValue = (hashValue * 33 + value.charCodeAt(index)) % 2147483647;
  }
  return hashValue >= 0 ? hashValue : 0;
}
