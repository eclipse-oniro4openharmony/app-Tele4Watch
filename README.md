# app-Tele4Watch

A Telegram client for **HarmonyOS / OpenHarmony (wearable)** - Huawei Watch 5,
466×466 screen. UI in ArkTS/ETS (MVVM), networking core on native **TDLib**, and
voice calls (VoIP) on native **tgcalls + WebRTC**. This README covers the product,
the repo layout, and the **full build from a clean clone** (all `third_party`
libraries, patches, both ABIs) through to the HAP package, plus a runtime/auth
runbook.

> This document reflects the current VoIP-era repository state: TDLib,
> tgcalls/WebRTC, Opus media support, and the build scripts needed for a clean
> clone.

---

## 1. What the app does

- Telegram login (phone number / QR / 2FA password), chats, messages, media
  (photos, video, **voice notes** and **video notes**), contacts, notifications
  with deeplinks and quick replies.
- **Voice calls** watch ↔ Telegram (Web-K, iOS, Android) on the tgcalls v2
  protocol `13.0.0`: receiving/placing calls, two-way audio, mute, the call
  screen, background operation.
- Bundle id: `com.ostc.tele4watch`. App logs go to the hilog domain `0x2026`.

## 2. Repo layout (4 modules + native dependencies)

| Module | Role | Native |
|---|---|---|
| `entry` | the app: ArkTS UI (MVVM), `TdClient`, screens, navigation | - |
| `bridge` | N-API bridge to TDLib + `libtdjson.so` prebuilts per ABI | TDLib |
| `tgcall` | VoIP: tgcalls + WebRTC + our `InstanceV4_0_0Impl`/`InstanceV13_0_0Impl` | tgcalls, ohos_webrtc, boringssl |
| `opusdecoder` | Opus encode/decode (voice notes) | ogg, opus, opusfile |

`/third_party` is **gitignored** - a fresh clone has none of it; all libraries are
downloaded and built with scripts (section 4). Our native code lives only in
`*/src/main/cpp/` (LGPL boundary - `third_party/` is untouched).

## 3. Requirements (toolchain)

The build is **hybrid**: TDLib builds on **Windows**, while WebRTC/tgcalls build
on **WSL/Linux** (the Chromium gn/ninja chain requires Linux).

**Common**
- Git, Python 3, CMake 3.22+, Ninja
- **OpenHarmony Native SDK** from DevEco Studio (provides `build/cmake/ohos.toolchain.cmake`,
  `build-tools/cmake/bin/{cmake,ninja}` and clang). Typically:
  `C:/Program Files/Huawei/DevEco Studio <ver>/sdk/default/openharmony/native`.

**Windows (TDLib build)**
- PowerShell 5+/7, Visual Studio 2022 with the C++ toolchain (TDLib host tools)
- `gperf.exe` → `third_party/tools/gperf/gperf.exe`

**WSL/Linux (WebRTC + tgcalls build)**
- A Linux OpenHarmony Native SDK (separate from the Windows one)
- `depot_tools` (fetched by the deps script), `gn`/`ninja`
- `build-essential` (or distro equivalent)

## 4. Build from a clean clone

The chain has 4 steps. The scripts are idempotent.

### `third_party` dependency table

| Library | Used by | Pin (commit) | Source | Built by |
|---|---|---|---|---|
| `td` (TDLib 1.8.63) | bridge | `8ff05a0e7` | github.com/tdlib/td | `build_tdlib_ohos.ps1` (Win) |
| `boringssl` | TDLib + WebRTC | `c1c5839` | github.com/google/boringssl | both build scripts |
| `tgcalls` | tgcall | `8099768` | github.com/TelegramMessenger/tgcalls | hvigor (in `tgcall`) |
| `ohos_webrtc` | tgcall | `3c9c905` | gitcode.com/openharmony-sig/ohos_webrtc | `prepare_tgcall_deps_wsl.sh` (WSL) |
| `ogg` | opusdecoder | `06a5e02` | github.com/xiph/ogg | hvigor (in `opusdecoder`) |
| `opus` | opusdecoder | `788cc89` | github.com/xiph/opus | hvigor |
| `opusfile` | opusdecoder | `6dfd29e` | github.com/xiph/opusfile | hvigor |

### Step 0 - clone the repo and set the SDK

```bash
git clone git@gitea.ostc:pmandes/oh-app-telegram-4-watch.git
cd oh-app-telegram-4-watch
```

### Step 1 - download dependency sources (download dependencies)

Clones and pins all 7 source libraries into `third_party/` (idempotent).
Run in WSL/Linux or Git Bash:

```bash
bash scripts/download_dependencies.sh
```

> `ohos_webrtc` is large - the first clone takes a while. `depot_tools` is fetched
> by step 2; place `gperf.exe` manually in `third_party/tools/gperf/`.

### Step 2 - build tgcall native dependencies (WSL/Linux, both ABIs)

Pulls `ohos_webrtc/third_party` + submodules, applies the
`tgcalls-ohos-webrtc-compat.patch`, and builds BoringSSL and WebRTC for **arm64
and x86_64** (into `third_party/ohos_webrtc/out/ohos_arm64_linux` and
`out/ohos_x64_linux`):

```bash
bash scripts/prepare_tgcall_deps_wsl.sh --sdk-native /path/to/linux/openharmony/native
```

If this step fails, start with the missing-path or missing-archive message; the
tgcall CMake checks the WebRTC output folders before linking.

### Step 3 - build TDLib (Windows, both ABIs)

Applies the thread-affinity patch (`__OHOS__` in `ThreadPthread.h`), builds
BoringSSL + host tools (VS2022) + `tdjson`, and copies the prebuilts into
`bridge/src/main/cpp/prebuilt/<abi>/`:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_tdlib_ohos.ps1 -Arch x86_64
powershell -ExecutionPolicy Bypass -File scripts/build_tdlib_ohos.ps1 -Arch arm64-v8a
```

Custom SDK: `-SdkNative "D:/DevEco/sdk/default/openharmony/native"`.

### Step 4 - configure API credentials

The app reads Telegram API credentials from
`entry/src/main/ets/config/TelegramSecrets.local.ets`, which is **gitignored** and
absent from a clean clone - the `entry` build fails without it. Create it from the
tracked template and fill in your own keys:

```bash
cp entry/src/main/ets/config/TelegramSecrets.template.ets \
   entry/src/main/ets/config/TelegramSecrets.local.ets
```

Edit `TelegramSecrets.local.ets` and set your own `apiId` / `apiHash` from
<https://my.telegram.org/apps> (`environment` / `useTestDc` as needed). Keep
`develDebug: false` for normal builds - it gates dev-only mock call screens on the
Profile page.

### Step 5 - build the app

`ogg`/`opus`/`opusfile` (step 1) are compiled by hvigor in the `opusdecoder`
module; `tgcall` links the WebRTC archives from `out/<abi>`.

```powershell
ohpm install
hvigorw.bat --mode project assembleApp -p product=default -p buildMode=debug
```

For wearable HAP and test variants, use the test runbook in section 7.

### Patches (ours)

| Patch | Purpose | Applied by |
|---|---|---|
| `scripts/patches/tdlib-ohos-thread-affinity.patch` | OHOS lacks the pthread affinity used by TDLib (`#if ... && !defined(__OHOS__)`) | `build_tdlib_ohos.ps1` (inline, regex) |
| `scripts/patches/tgcalls-ohos-webrtc-compat.patch` | tgcalls compatibility with our `ohos_webrtc` snapshot | `prepare_tgcall_deps_wsl.sh` (`git apply`) |

## 5. Artifact verification

```powershell
# TDLib (after step 3) - exactly one versioned soname per ABI
Get-ChildItem bridge/src/main/cpp/prebuilt/arm64-v8a | Select-Object Name,Length
Get-ChildItem bridge/src/main/cpp/prebuilt/x86_64   | Select-Object Name,Length
```

Expected in each ABI folder: `libtdjson.so` + `libtdjson.so.<version>` (currently
`1.8.63`) - the bridge CMake fails when the versioned soname count is 0 or >1.

WebRTC (after step 2): `third_party/ohos_webrtc/out/ohos_arm64_linux/obj/…` and
`out/ohos_x64_linux/obj/…` exist (the tgcall CMake requires these archives,
otherwise it FATAL_ERRORs with the hint `Run scripts/prepare_tgcall_deps_wsl.sh first`).

## 6. Runtime / auth runbook

### hdc and the device

```bash
hdc list targets                      # visible devices/emulators
hdc tconn 192.168.x.x:port            # reconnect over Wi-Fi (the watch drops when the screen sleeps)
hdc shell uname -m                    # aarch64 = real Watch; x86_64 = emulator
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

### hilog (app logs, domain 0x2026)

```bash
hdc shell hilog -G 16M                 # enlarge the buffer (long sessions/calls)
hdc shell hilog -r                     # clear the buffer before a scenario
hdc shell hilog -x -D 0x2026 > dump.log   # one-shot dump of the app domain
```

Tags: `TdClient`, `TdBridge` (core/auth), `CallScreenViewModel`,
`CallSessionController`, `TgCall` (VoIP), `TdNotificationsService` (notifications).

### Auth debugging

- TDLib states are visible in `TdClient` (`updateAuthorizationState`). Flow:
  `WaitPhoneNumber` → code → optionally `WaitPassword` (2FA) → `Ready`.
- QR login and 2FA go through the same TDLib authorization state machine; verify
  them in `TdClient` logs.
- After `connectionStateReady` the notification runtime starts
  (`NotificationRuntimeService`) - that is also where the microphone-permission
  bootstrap lives (before calls).

### VoIP debugging

- TDLib version and protocol registry: `getOption version=1.8.63`, registry
  `[10.0.0, 11.0.0, 13.0.0, 4.0.0]`.
- Media flow at call end: `InstanceV13_0_0Impl final media stats
  txOk=1 txPackets=… rxOk=1 rxPackets=…` (non-zero tx/rx = two-way audio).

## 7. Tests

Unit tests (ArkTS) and on-device `ohosTest` - verified hvigor commands, the
coverage report and paths are in **`docs/ohos-test-runbook.md`** (read it before
running anything).

## 8. Common issues

- **`Missing tgcall source dependency` / `Missing WebRTC archive`** - WebRTC was
  not built: run steps 1-2 (`download_dependencies.sh` → `prepare_tgcall_deps_wsl.sh`).
- **`Missing required path: third_party/...`** - sources not downloaded: step 1.
- **`libtdjson.so.<version>` not found / multiple** - a stale soname from an old
  TDLib checkout; `build_tdlib_ohos.ps1` cleans this automatically, otherwise
  remove `third_party/build/td-ohos-*` and rebuild.
- **Thread-affinity errors (TDLib)** - the `ThreadPthread.h` patch was not applied (step 3).
- **`gperf.exe` missing** (Windows) - place it at `third_party/tools/gperf/gperf.exe`.
- **Missing WebRTC `out/<abi>`** - step 2 did not run for that ABI (check the Linux SDK).

---

## License

Licensed under the [Apache License 2.0](LICENSE).
