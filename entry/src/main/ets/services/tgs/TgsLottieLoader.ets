import zlib from '@ohos.zlib';
import util from '@ohos.util';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TgsLottieAnimationPayload, TgsLottieLoadResult } from './TgsLottieTypes';

const DOMAIN = 0x2026;
const TAG = 'TgsLottieLoader';
const TGS_READ_CHUNK_BYTES = 4096;
const TGS_MAX_DECOMPRESSED_BYTES = 1024 * 1024;
const TGS_CACHE_MAX_ENTRIES = 24;
const TGS_CACHE_MAX_TOTAL_BYTES = 4 * 1024 * 1024;

interface TgsLottieCacheEntry {
  'animationData': TgsLottieAnimationPayload;
  'decompressedBytes': number;
  'chunkCount': number;
}

const tgsAnimationDataCache: Map<string, TgsLottieCacheEntry> = new Map<string, TgsLottieCacheEntry>();
const tgsInFlightLoads: Map<string, Promise<TgsLottieLoadResult>> = new Map<string, Promise<TgsLottieLoadResult>>();
let tgsCacheTotalBytes: number = 0;

/**
 * Builds a standardized error result object for TGS load flow.
 *
 * @param message Error code/message used by diagnostics and UI fallback path.
 * @param decodeMs Time spent before failure in milliseconds.
 * @returns Typed load result marked as failed.
 */
function buildErrorResult(message: string, decodeMs: number): TgsLottieLoadResult {
  return {
    'ok': false,
    'error': message,
    'decodeMs': decodeMs
  };
}

/**
 * Normalizes numeric limits used by cache controls.
 *
 * @param value Requested limit value.
 * @param fallbackValue Fallback value used when request is invalid.
 * @returns Positive integer limit.
 */
function normalizePositiveLimit(value: number, fallbackValue: number): number {
  if (value > 0) {
    return Math.floor(value);
  }
  return fallbackValue;
}

/**
 * Performs lightweight JSON object-shape check before full parsing.
 *
 * @param value Raw decoded text content.
 * @returns `true` when content looks like a JSON object.
 */
function isLikelyJsonObject(value: string): boolean {
  const trimmed = value.trim();
  if (trimmed.length < 2) {
    return false;
  }
  return trimmed.startsWith('{') && trimmed.endsWith('}');
}

/**
 * Merges decompressed chunks into one contiguous byte array.
 *
 * @param chunks Ordered chunk list produced by gzip reader.
 * @param totalBytes Total merged size.
 * @returns Combined byte array with decoded payload bytes.
 */
function mergeChunks(chunks: Uint8Array[], totalBytes: number): Uint8Array {
  const output = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return output;
}

/**
 * Validates required Lottie fields expected in Telegram TGS payload.
 *
 * @param value Parsed JSON object candidate.
 * @returns `true` when payload contains required Lottie metadata.
 */
function isValidTgsAnimationPayload(value: TgsLottieAnimationPayload): boolean {
  if (typeof value.v !== 'string' || value.v.length === 0) {
    return false;
  }
  if (typeof value.fr !== 'number' || value.fr <= 0) {
    return false;
  }
  if (typeof value.ip !== 'number') {
    return false;
  }
  if (typeof value.op !== 'number' || value.op <= value.ip) {
    return false;
  }
  if (typeof value.w !== 'number' || value.w <= 0) {
    return false;
  }
  if (typeof value.h !== 'number' || value.h <= 0) {
    return false;
  }
  if (!Array.isArray(value.layers)) {
    return false;
  }
  return true;
}

/**
 * Parses JSON text to typed Lottie payload with validation.
 *
 * @param rawJson Raw JSON text after gzip decompression.
 * @returns Typed animation payload when valid; otherwise `undefined`.
 */
function parseJsonObject(rawJson: string): TgsLottieAnimationPayload | undefined {
  try {
    const parsedValue: TgsLottieAnimationPayload = JSON.parse(rawJson) as TgsLottieAnimationPayload;
    if (isValidTgsAnimationPayload(parsedValue)) {
      return parsedValue;
    }
    return undefined;
  } catch (error) {
    hilog.error(DOMAIN, TAG, 'TGS parse failed: %{public}s', String(error));
    return undefined;
  }
}

/**
 * Marks cache entry as recently used by reinserting map key.
 *
 * @param path Cache key (absolute TGS file path).
 * @param entry Existing cache value.
 * @returns Nothing.
 */
function touchCacheEntry(path: string, entry: TgsLottieCacheEntry): void {
  tgsAnimationDataCache.delete(path);
  tgsAnimationDataCache.set(path, entry);
}

/**
 * Reads cache entry and updates its recency.
 *
 * @param path Cache key (absolute TGS file path).
 * @returns Cache entry when present; otherwise `undefined`.
 */
function readCacheEntry(path: string): TgsLottieCacheEntry | undefined {
  const cachedEntry = tgsAnimationDataCache.get(path);
  if (!cachedEntry) {
    return undefined;
  }
  touchCacheEntry(path, cachedEntry);
  return cachedEntry;
}

/**
 * Removes the oldest cache entry.
 *
 * @returns `true` when an entry was removed; otherwise `false`.
 */
function evictOldestCacheEntry(): boolean {
  const firstEntry = tgsAnimationDataCache.entries().next();
  if (firstEntry.done) {
    return false;
  }
  const keyValue = firstEntry.value;
  const cachePath = keyValue[0];
  const cacheEntry = keyValue[1];
  tgsAnimationDataCache.delete(cachePath);
  tgsCacheTotalBytes -= cacheEntry.decompressedBytes;
  if (tgsCacheTotalBytes < 0) {
    tgsCacheTotalBytes = 0;
  }
  return true;
}

/**
 * Applies entry-count and byte-size limits to in-memory cache.
 *
 * @param maxEntries Maximum number of cached items.
 * @param maxTotalBytes Maximum cumulative decompressed bytes.
 * @returns Nothing.
 */
function applyCacheLimits(maxEntries: number, maxTotalBytes: number): void {
  while (tgsAnimationDataCache.size > maxEntries || tgsCacheTotalBytes > maxTotalBytes) {
    if (!evictOldestCacheEntry()) {
      return;
    }
  }
}

/**
 * Inserts or replaces one cache entry and enforces configured limits.
 *
 * @param path Cache key (absolute TGS file path).
 * @param animationData Parsed Lottie payload.
 * @param decompressedBytes Decompressed payload size in bytes.
 * @param chunkCount Number of decompressed chunks used to build payload.
 * @returns Nothing.
 */
function putCacheEntry(
  path: string,
  animationData: TgsLottieAnimationPayload,
  decompressedBytes: number,
  chunkCount: number
): void {
  const existingEntry = tgsAnimationDataCache.get(path);
  if (existingEntry) {
    tgsCacheTotalBytes -= existingEntry.decompressedBytes;
    if (tgsCacheTotalBytes < 0) {
      tgsCacheTotalBytes = 0;
    }
    tgsAnimationDataCache.delete(path);
  }

  const nextEntry: TgsLottieCacheEntry = {
    'animationData': animationData,
    'decompressedBytes': decompressedBytes,
    'chunkCount': chunkCount
  };
  tgsAnimationDataCache.set(path, nextEntry);
  tgsCacheTotalBytes += decompressedBytes;
  applyCacheLimits(TGS_CACHE_MAX_ENTRIES, TGS_CACHE_MAX_TOTAL_BYTES);
}

/**
 * Clears one cached TGS payload by absolute file path.
 *
 * @param filePath Absolute local path to `.tgs` file.
 * @returns Nothing.
 */
export function clearTgsLottieCache(filePath: string): void {
  const trimmedPath = filePath.trim();
  if (trimmedPath.length === 0) {
    return;
  }
  const existingEntry = tgsAnimationDataCache.get(trimmedPath);
  if (!existingEntry) {
    return;
  }
  tgsAnimationDataCache.delete(trimmedPath);
  tgsCacheTotalBytes -= existingEntry.decompressedBytes;
  if (tgsCacheTotalBytes < 0) {
    tgsCacheTotalBytes = 0;
  }
}

/**
 * Clears all cached TGS payloads.
 *
 * @returns Nothing.
 */
export function clearAllTgsLottieCache(): void {
  tgsAnimationDataCache.clear();
  tgsCacheTotalBytes = 0;
}

/**
 * Trims in-memory TGS cache to requested limits.
 *
 * @param maxEntries Maximum number of cached items.
 * @param maxTotalBytes Maximum cumulative decompressed size.
 * @returns Nothing.
 */
export function trimTgsLottieCache(maxEntries: number = TGS_CACHE_MAX_ENTRIES, maxTotalBytes: number = TGS_CACHE_MAX_TOTAL_BYTES): void {
  const normalizedMaxEntries = normalizePositiveLimit(maxEntries, TGS_CACHE_MAX_ENTRIES);
  const normalizedMaxTotalBytes = normalizePositiveLimit(maxTotalBytes, TGS_CACHE_MAX_TOTAL_BYTES);
  applyCacheLimits(normalizedMaxEntries, normalizedMaxTotalBytes);
}

/**
 * Decodes gzip-compressed `.tgs` file and stores parsed payload in bounded cache.
 *
 * @param path Absolute local path to `.tgs` file.
 * @returns Typed decode result with metadata for diagnostics.
 */
async function decodeAndCacheTgs(path: string): Promise<TgsLottieLoadResult> {
  const startedAt = Date.now();
  let gzipReader: zlib.GZip | undefined = undefined;
  try {
    gzipReader = zlib.createGZipSync();
    await gzipReader.gzopen(path, 'rb');

    const chunks: Uint8Array[] = [];
    let totalBytes = 0;
    while (true) {
      const chunkBuffer = new ArrayBuffer(TGS_READ_CHUNK_BYTES);
      const readBytes = await gzipReader.gzread(chunkBuffer);
      if (readBytes <= 0) {
        break;
      }
      if (totalBytes + readBytes > TGS_MAX_DECOMPRESSED_BYTES) {
        return buildErrorResult('tgs-too-large', Date.now() - startedAt);
      }
      chunks.push(new Uint8Array(chunkBuffer, 0, readBytes));
      totalBytes += readBytes;
    }

    if (totalBytes <= 0) {
      return buildErrorResult('tgs-empty', Date.now() - startedAt);
    }

    const mergedBytes = mergeChunks(chunks, totalBytes);
    const decoder = new util.TextDecoder('utf-8', { 'ignoreBOM': true });
    const decodedText = decoder.decode(mergedBytes);
    if (!isLikelyJsonObject(decodedText)) {
      return buildErrorResult('invalid-json-shape', Date.now() - startedAt);
    }

    const animationData = parseJsonObject(decodedText);
    if (!animationData) {
      return buildErrorResult('invalid-json', Date.now() - startedAt);
    }

    const elapsedMs = Date.now() - startedAt;
    putCacheEntry(path, animationData, totalBytes, chunks.length);
    return {
      'ok': true,
      'animationData': animationData,
      'source': 'decode',
      'decodeMs': elapsedMs,
      'decompressedBytes': totalBytes,
      'chunkCount': chunks.length
    };
  } catch (error) {
    const elapsedMs = Date.now() - startedAt;
    hilog.error(
      DOMAIN,
      TAG,
      'TGS decode failed path=%{public}s ms=%{public}d err=%{public}s',
      path,
      elapsedMs,
      String(error)
    );
    return buildErrorResult('decode-failed', elapsedMs);
  } finally {
    if (gzipReader) {
      try {
        await gzipReader.gzclose();
      } catch (_closeError) {
      }
    }
  }
}

/**
 * Loads typed Lottie payload for `.tgs` source with cache and in-flight deduplication.
 *
 * @param filePath Absolute local path to `.tgs` file.
 * @returns Typed load result used by inline chat renderer.
 */
export async function loadTgsLottieData(filePath: string): Promise<TgsLottieLoadResult> {
  const trimmedPath = filePath.trim();
  if (trimmedPath.length === 0) {
    return buildErrorResult('empty-path', 0);
  }

  const cachedEntry = readCacheEntry(trimmedPath);
  if (cachedEntry) {
    return {
      'ok': true,
      'animationData': cachedEntry.animationData,
      'source': 'cache',
      'decodeMs': 0,
      'decompressedBytes': cachedEntry.decompressedBytes,
      'chunkCount': cachedEntry.chunkCount
    };
  }

  const inFlight = tgsInFlightLoads.get(trimmedPath);
  if (inFlight) {
    return await inFlight;
  }

  const loadPromise = decodeAndCacheTgs(trimmedPath);
  tgsInFlightLoads.set(trimmedPath, loadPromise);
  try {
    return await loadPromise;
  } finally {
    tgsInFlightLoads.delete(trimmedPath);
  }
}
