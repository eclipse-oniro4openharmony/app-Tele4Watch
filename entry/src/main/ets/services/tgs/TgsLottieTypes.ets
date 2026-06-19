/**
 * Parsed Lottie JSON payload used by inline Telegram TGS rendering.
 */
export interface TgsLottieAnimationPayload {
  'v'?: string;
  'fr'?: number;
  'ip'?: number;
  'op'?: number;
  'w'?: number;
  'h'?: number;
  'layers'?: object[];
}

/**
 * Indicates whether animation data came from memory cache or fresh decode.
 */
export type TgsLottieLoadSource = 'cache' | 'decode';

/**
 * Result object returned by TGS loader.
 */
export interface TgsLottieLoadResult {
  'ok': boolean;
  'animationData'?: TgsLottieAnimationPayload;
  'source'?: TgsLottieLoadSource;
  'decodeMs'?: number;
  'decompressedBytes'?: number;
  'chunkCount'?: number;
  'error'?: string;
}
