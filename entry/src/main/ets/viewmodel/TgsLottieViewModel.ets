import {
  clearTgsLottieCache as clearTgsLottieCacheFromService,
  loadTgsLottieData as loadTgsLottieDataFromService
} from '../services/tgs/TgsLottieLoader';
import { TgsLottieLoadResult } from '../models/tgs/TgsViewTypes';

export function clearTgsLottieCache(filePath: string): void {
  clearTgsLottieCacheFromService(filePath);
}

export async function loadTgsLottieData(filePath: string): Promise<TgsLottieLoadResult> {
  return loadTgsLottieDataFromService(filePath);
}
