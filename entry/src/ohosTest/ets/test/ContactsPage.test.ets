import { describe, beforeAll, beforeEach, it } from '@ohos/hypium';
import { Driver, MatchPattern, ON } from '@ohos.UiTest';
import { loadTestPage } from '../testability/TestPageController';
import {
  queueMockContactNameUpdate,
  resetMockBridge,
  setMockContactsScenario
} from '../../../mock/bridge.mock';
import { tdClient } from '../../../main/ets/services/td/TdClient';

const CONTACTS_HEADER_ID = 'contacts-header';
const CONTACTS_LOADING_ID = 'contacts-loading';
const CONTACTS_EMPTY_ID = 'contacts-empty';
const TEST_INDEX_ROUTE = 'testability/pages/Index';
const CONTACTS_ROUTE = 'pages/Contacts';
const AUTH_READY_STATE = 'authorizationStateReady';
const AUTH_POLL_STEP_MS = 50;
const AUTH_POLL_TIMEOUT_MS = 5000;

export default function contactsPageTest() {
  describe('ContactsPageTest', () => {
    let driver: Driver;

    beforeAll(() => {
      driver = Driver.create();
    });

    beforeEach(async (): Promise<void> => {
      tdClient.resetRuntimeStateForTesting();
      resetMockBridge();
      await loadTestPage(TEST_INDEX_ROUTE);
      await driver.delayMs(150);
    });

    it('opens the real Contacts page from the app flow with mocked tdClient data', 0, async (): Promise<void> => {
      setMockContactsScenario('filled');
      await startAuthorizationBootstrapAndWaitForReady();
      await loadTestPage(CONTACTS_ROUTE);

      await driver.assertComponentExist(ON.id(CONTACTS_HEADER_ID));
      await driver.waitForComponent(ON.text('Test Account'), 3000);
      await driver.waitForComponent(ON.text('Alice Example'), 3000);
      await driver.assertComponentExist(ON.text('Bob Example', MatchPattern.EQUALS));
    });

    it('shows empty state when Telegram account has no contacts', 0, async (): Promise<void> => {
      setMockContactsScenario('empty');
      await startAuthorizationBootstrapAndWaitForReady();
      await loadTestPage(CONTACTS_ROUTE);

      await driver.assertComponentExist(ON.id(CONTACTS_HEADER_ID));
      await driver.waitForComponent(ON.id(CONTACTS_EMPTY_ID), 3000);
      await driver.waitForComponent(ON.text('Test Account'), 3000);
    });

    it('shows loading state before delayed contacts hydration completes', 0, async (): Promise<void> => {
      setMockContactsScenario('loadingThenFilled');
      await startAuthorizationBootstrapAndWaitForReady();
      await loadTestPage(CONTACTS_ROUTE);

      await driver.assertComponentExist(ON.id(CONTACTS_HEADER_ID));
      await driver.waitForComponent(ON.id(CONTACTS_LOADING_ID), 1500);
      await driver.waitForComponent(ON.text('Alice Example'), 5000);
      await driver.assertComponentExist(ON.text('Bob Example', MatchPattern.EQUALS));
    });

    it('refreshes one rendered contact after updateUser without restarting the page', 0, async (): Promise<void> => {
      setMockContactsScenario('filled');
      await startAuthorizationBootstrapAndWaitForReady();
      await loadTestPage(CONTACTS_ROUTE);

      await driver.waitForComponent(ON.text('Alice Example'), 3000);
      queueMockContactNameUpdate(1001, 'Alice Updated', 'Example', 'alice-updated');
      await driver.waitForComponent(ON.text('Alice Updated Example'), 3000);
    });

    it('keeps contacts page working after bootstrap restart', 0, async (): Promise<void> => {
      setMockContactsScenario('filled');
      await startAuthorizationBootstrapAndWaitForReady();
      await loadTestPage(CONTACTS_ROUTE);
      await driver.waitForComponent(ON.text('Alice Example'), 3000);

      tdClient.stopAuthorizationBootstrap();
      tdClient.resetRuntimeStateForTesting();
      resetMockBridge();
      setMockContactsScenario('filled');

      await loadTestPage(TEST_INDEX_ROUTE);
      await driver.delayMs(150);
      await startAuthorizationBootstrapAndWaitForReady();
      await loadTestPage(CONTACTS_ROUTE);

      await driver.assertComponentExist(ON.id(CONTACTS_HEADER_ID));
      await driver.waitForComponent(ON.text('Alice Example'), 3000);
      await driver.assertComponentExist(ON.text('Bob Example', MatchPattern.EQUALS));
    });
  });
}

/**
 * Starts TDLib bootstrap and waits for a stable `authorizationStateReady`.
 */
async function startAuthorizationBootstrapAndWaitForReady(): Promise<void> {
  tdClient.startAuthorizationBootstrap();
  await waitForAuthorizationReady();
}

async function waitForAuthorizationReady(): Promise<void> {
  let elapsedMs = 0;
  while (tdClient.getAuthorizationStateName() !== AUTH_READY_STATE) {
    if (elapsedMs >= AUTH_POLL_TIMEOUT_MS) {
      throw new Error(`Timed out while waiting for ${AUTH_READY_STATE}.`);
    }
    await delayMs(AUTH_POLL_STEP_MS);
    elapsedMs += AUTH_POLL_STEP_MS;
  }
}

function delayMs(durationMs: number): Promise<void> {
  return new Promise<void>((resolve): void => {
    setTimeout((): void => {
      resolve();
    }, durationMs);
  });
}
