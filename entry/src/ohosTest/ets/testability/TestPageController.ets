import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

const WINDOW_STAGE_WAIT_STEP_MS = 50;
const WINDOW_STAGE_WAIT_TIMEOUT_MS = 5000;

let testWindowStage: window.WindowStage | undefined = undefined;

/**
 * Stores the current test window stage so UI tests can switch between real pages.
 *
 * @param windowStage The current TestAbility window stage.
 */
export function bindTestWindowStage(windowStage: window.WindowStage): void {
  testWindowStage = windowStage;
}

/**
 * Waits until the test window stage becomes available.
 *
 * @returns Promise resolved after the window stage is ready.
 */
export async function waitForTestWindowStage(): Promise<void> {
  let elapsedMs = 0;
  while (!testWindowStage) {
    if (elapsedMs >= WINDOW_STAGE_WAIT_TIMEOUT_MS) {
      throw new Error('Test window stage is unavailable.');
    }
    await delayMs(WINDOW_STAGE_WAIT_STEP_MS);
    elapsedMs += WINDOW_STAGE_WAIT_STEP_MS;
  }
}

/**
 * Loads one page into the current test window stage.
 *
 * @param pageUrl The page route loaded by the test ability.
 * @returns Promise resolved after the page is loaded.
 */
export async function loadTestPage(pageUrl: string): Promise<void> {
  await waitForTestWindowStage();
  const currentWindowStage = testWindowStage;
  if (!currentWindowStage) {
    throw new Error('Test window stage is unavailable.');
  }

  return new Promise<void>((resolve, reject): void => {
    currentWindowStage.loadContent(pageUrl, (error: BusinessError): void => {
      if (error.code) {
        reject(new Error(`Failed to load page ${pageUrl}: ${JSON.stringify(error) ?? ''}`));
        return;
      }
      resolve();
    });
  });
}

function delayMs(durationMs: number): Promise<void> {
  return new Promise<void>((resolve): void => {
    setTimeout((): void => {
      resolve();
    }, durationMs);
  });
}
