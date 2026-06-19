import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { resourceManager } from '@kit.LocalizationKit';
import { util } from '@kit.ArkTS';

let abilityDelegator: abilityDelegatorRegistry.AbilityDelegator;
let abilityDelegatorArguments: abilityDelegatorRegistry.AbilityDelegatorArgs;
const MOCK_CONFIG_PATH: string = 'mock/mock-config.json';
const LOG_TAG: string = 'testTag';
const BRIDGE_INDEX_OHM_URL: string = '@normalized:N&&&bridge/Index&1.0.0';
const BRIDGE_MOCK_SOURCE_OHM_URL: string = '@normalized:N&&&entry/src/mock/bridge.mock&';

interface MockConfigEntry {
  source?: string;
}

type MockConfigMap = Record<string, MockConfigEntry>;

async function onAbilityCreateCallback(data: UIAbility): Promise<void> {
  hilog.info(0x0000, LOG_TAG, 'onAbilityCreateCallback, data: %{public}s', JSON.stringify(data) ?? '');
}

async function addAbilityMonitorCallback(err: BusinessError): Promise<void> {
  hilog.info(0x0000, LOG_TAG, 'addAbilityMonitorCallback : %{public}s', JSON.stringify(err) ?? '');
}

export default class OpenHarmonyTestRunner implements TestRunner {
  constructor() {}

  onPrepare(): void {
    hilog.info(0x0000, LOG_TAG, '%{public}s', 'OpenHarmonyTestRunner OnPrepare');
  }

  async onRun(): Promise<void> {
    hilog.info(0x0000, LOG_TAG, '%{public}s', 'OpenHarmonyTestRunner onRun run');
    abilityDelegatorArguments = abilityDelegatorRegistry.getArguments();
    abilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
    const moduleName = abilityDelegatorArguments.parameters['-m'];
    const moduleContext = abilityDelegator.getAppContext().getApplicationContext().createModuleContext(moduleName);
    await configureMocks(abilityDelegator, moduleContext.resourceManager);
    const bundleName: string = abilityDelegatorArguments.bundleName;
    const testAbilityName: string = 'TestAbility';
    const lMonitor: abilityDelegatorRegistry.AbilityMonitor = {
      abilityName: testAbilityName,
      onAbilityCreate: onAbilityCreateCallback,
      moduleName: moduleName
    };
    abilityDelegator.addAbilityMonitor(lMonitor, addAbilityMonitorCallback);
    const want: Want = {
      bundleName: bundleName,
      abilityName: testAbilityName,
      moduleName: moduleName
    };
    abilityDelegator.startAbility(want, (err: BusinessError) => {
      hilog.info(0x0000, LOG_TAG, 'startAbility : err : %{public}s', JSON.stringify(err) ?? '');
    });
    hilog.info(0x0000, LOG_TAG, '%{public}s', 'OpenHarmonyTestRunner onRun end');
  }
}

async function configureMocks(
  delegator: abilityDelegatorRegistry.AbilityDelegator,
  moduleResourceManager: resourceManager.ResourceManager
): Promise<void> {
  try {
    const rawMockConfig = moduleResourceManager.getRawFileContentSync(MOCK_CONFIG_PATH);
    const mockConfigText = util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeWithStream(rawMockConfig);
    const parsedMockList = parseMockList(mockConfigText);
    const mockList = Object.keys(parsedMockList).length > 0 ? parsedMockList : createFallbackMockList();
    if (Object.keys(mockList).length === 0) {
      hilog.info(0x0000, LOG_TAG, '%{public}s', 'Mock configuration is empty.');
      return;
    }

    delegator.setMockList(mockList);
    hilog.info(0x0000, LOG_TAG, 'Loaded mock list: %{public}s', JSON.stringify(mockList) ?? '');
  } catch (error) {
    const businessError = error as BusinessError;
    hilog.error(
      0x0000,
      LOG_TAG,
      'Failed to configure mocks, error code: %{public}d, message: %{public}s',
      businessError.code,
      businessError.message
    );
  }
}

function createFallbackMockList(): Record<string, string> {
  const mockList: Record<string, string> = {};
  mockList[BRIDGE_INDEX_OHM_URL] = BRIDGE_MOCK_SOURCE_OHM_URL;
  hilog.info(0x0000, LOG_TAG, 'Using fallback mock list: %{public}s', JSON.stringify(mockList) ?? '');
  return mockList;
}

function parseMockList(jsonText: string): Record<string, string> {
  const parsedConfig = JSON.parse(jsonText) as MockConfigMap;
  const configEntries = new Map<string, MockConfigEntry>(Object.entries(parsedConfig));
  const mockList: Record<string, string> = {};
  configEntries.forEach((entry: MockConfigEntry, specifier: string): void => {
    if (typeof entry.source === 'string' && entry.source.length > 0) {
      mockList[specifier] = entry.source;
    }
  });
  return mockList;
}
