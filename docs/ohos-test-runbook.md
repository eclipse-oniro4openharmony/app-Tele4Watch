# OHOS test runbook

### Purpose

- Quick runbook for running local unit tests and `ohosTest` manually in this repository.

### Source of truth

- Official Huawei HarmonyOS app testing guide:
  - `https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-app-test`
- Upstream OpenHarmony docs source used for the testing guidance:
  - `https://gitee.com/openharmony/docs/blob/OpenHarmony-v6.0-Release/en/application-dev/application-test/arkxtest-guidelines.md`
  - `https://gitee.com/openharmony/testfwk_arkxtest/blob/master/README_en.md`
  - `https://gitee.com/openharmony/interface_sdk-js/blob/master/api/%40ohos.UiTest.d.ts`

### What the official docs confirm

- Tests are split into unit tests and UI tests under the `arkXtest` model.
- UI tests are built on top of the unit test framework and add `@ohos.UiTest` driver operations.
- DevEco Studio can generate a starter test via `Show Context Actions` -> `Create Ohos Test`.
- On-device execution can also be driven by `aa test` with `OpenHarmonyTestRunner`, including filtering by:
  - `class` / `notClass`
  - `size`
  - `level`
  - `testType`
  - `timeout`
  - `breakOnError`
  - `dryRun`
  - `stress`
  - `random`

### Requirements

- `hvigorw.bat` available from DevEco Studio.
- For `ohosTest`: a running emulator or a connected device visible in `hdc list targets`.

### Local unit tests

The pure logic suite now lives in:

- `entry/src/test/List.test.ets`

The current migrated suite covers:

- `ContactsPageViewModel.test.ets`
- `TdAuthReducer.test.ets`
- `TdContactsCoordinator.test.ets`
- `TdUserParser.test.ets`

Verified command for the local unit suite:

```powershell
"C:\Program Files\Huawei\DevEco Studio 5.1.1.840\tools\node\node.exe" "C:\Program Files\Huawei\DevEco Studio 5.1.1.840\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default test --no-daemon
```

Current result:

- `BUILD SUCCESSFUL`
- the command finishes `:entry:test`
- the local report is refreshed under:
  - `entry\.test\default\outputs\test\reports\index.html`
  - `entry\.test\default\outputs\test\reports\coverageReport.json`
- the detailed result file is refreshed under:
  - `entry\.test\default\intermediates\test\coverage_data\test_result.txt`
- current suite result:
  - `Tests run: 27, Failure: 0, Error: 0, Pass: 27, Ignore: 0`

Verified example CLI entrypoint for one local unit test build path:

```powershell
"C:\Program Files\Huawei\DevEco Studio 5.1.1.840\tools\node\node.exe" "C:\Program Files\Huawei\DevEco Studio 5.1.1.840\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default -p unit.test.replace.page=../../../.test/testability/pages/Index -p product=default -p pageType=page -p isLocalTest=true -p unitTestMode=true -p ohos-test-coverage=true -p buildRoot=.test UnitTestBuild --analyze=normal --parallel --incremental --daemon
```

Current result:

- `BUILD SUCCESSFUL`
- the command finishes `:entry:UnitTestBuild`
- the local unit test build path is valid for this repository

Practical conclusion:

- the local unit suite is present in source code,
- there is a confirmed Hvigor CLI entrypoint for executing the local unit suite,
- there is also a lower-level Hvigor CLI entrypoint for the local unit test build path,
- the module HAP build still passes after the migration,
- and `ohosTest` runtime validation on emulator also works in this repository.

### Verified HAP build command

Confirmed manual command for building the wearable entry HAP:

```powershell
"C:\Program Files\Huawei\DevEco Studio 5.1.1.840\tools\node\node.exe" "C:\Program Files\Huawei\DevEco Studio 5.1.1.840\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default -p product=default -p requiredDeviceType=wearable assembleHap --analyze=normal --parallel --incremental --daemon
```

Current result:

- `BUILD SUCCESSFUL`
- the command finishes `:entry:assembleHap`
- existing ArkTS warnings remain, but they do not block the build

### Check the target

```powershell
hdc list targets
```

Example of a valid result:

```text
127.0.0.1:5555
```

### Correct command to run tests and generate the report

From the repository root:

```powershell
hvigorw.bat --mode module -p module=entry@ohosTest -p product=default -p requiredDeviceType=wearable onDeviceTest --no-daemon
```

If `hvigorw.bat` is not in `PATH`, use the full path from DevEco Studio, for example:

```powershell
"C:\Program Files\Huawei\DevEco Studio 5.1.1.840\tools\hvigor\bin\hvigorw.bat" --mode module -p module=entry@ohosTest -p product=default -p requiredDeviceType=wearable onDeviceTest --no-daemon
```

This task:

- builds `entry@ohosTest`,
- installs the test HAP,
- runs the test runner on the device / emulator,
- generates the HTML and coverage report.

The current instrumented suite lives in:

- `entry/src/ohosTest/ets/test/List.test.ets`

The current on-device suite covers:

- `ContactsPage.test.ets`
  - filled state
  - empty state
  - loading-then-filled state
  - `updateUser` refresh
  - bootstrap restart

Look for these entries in the log:

- `Finished write html report`
- `:entry:default@GenerateDeviceCoverage`
- `OHOS_REPORT_RESULT: ... Pass: ...`

Current verified result in this repository:

- `BUILD SUCCESSFUL`
- `Finished install haps`
- `Finished write html report`
- `:entry:default@GenerateDeviceCoverage`
- `Tests run: 5, Failure: 0, Error: 0, Pass: 5, Ignore: 0`

### Where the report is generated

Output files:

- `entry\.test\default\outputs\ohosTest\reports\index.html`
- `entry\.test\default\outputs\ohosTest\reports\coverageReport.json`

These local files are the source of truth for the report.

### Important distinctions

1. Running only this command manually:

```powershell
hdc shell aa test -b com.ostc.tele4watch -m entry_test -s unittest OpenHarmonyTestRunner
```

can execute the tests correctly, but it **does not refresh the coverage report in the same way as `onDeviceTest`**.

2. The task:

```powershell
hvigorw.bat collectCoverage --no-daemon
```

is not currently needed for this flow and may return:

```text
ErrorCode: 00507005
Description: projectPath does not exist
```

3. A URL like:

```text
http://localhost:63342/.../entry/.test/default/outputs/ohosTest/reports/index.html
```

depends on the local IDE server mapping. If it returns `404`, check the local file on disk first instead of the URL.

4. The current `onDeviceTest` run may still print a non-blocking coverage parser error:

```text
getInitCoverageData failed, SyntaxError: Unexpected non-whitespace character after JSON ...
```

The task still ends with `BUILD SUCCESSFUL`, the test report is refreshed, and `test_result.txt` remains the reliable source of pass/fail status.

### Minimal diagnostic procedure

1. `hdc list targets`
2. `hvigorw.bat --mode module -p module=entry@ohosTest -p product=default -p requiredDeviceType=wearable onDeviceTest --no-daemon`
3. check the timestamps:

```powershell
Get-Item entry\.test\default\outputs\ohosTest\reports\index.html,
         entry\.test\default\outputs\ohosTest\reports\coverageReport.json
```

4. if needed, read the coverage summary:

```powershell
$json = Get-Content 'entry\.test\default\outputs\ohosTest\reports\coverageReport.json' -Raw | ConvertFrom-Json
$json.summary
```
