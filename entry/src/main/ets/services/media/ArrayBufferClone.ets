/**
 * Returns a detached byte-level copy of the given ArrayBuffer so that callers
 * can retain the content after the source buffer is reused or released by the
 * audio pipeline.
 */
export function cloneArrayBuffer(source: ArrayBuffer): ArrayBuffer {
  const sourceBytes = new Uint8Array(source);
  const targetBytes = new Uint8Array(sourceBytes.length);
  targetBytes.set(sourceBytes);
  return targetBytes.buffer;
}
