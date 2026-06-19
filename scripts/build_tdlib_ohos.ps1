param(
  [string]$Arch = "arm64-v8a",
  [string]$SdkNative = "C:/Program Files/Huawei/DevEco Studio 5.1.1.840/sdk/default/openharmony/native"
)

$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$tdRepo = Join-Path $projectRoot "third_party/td"
$boringRepo = Join-Path $projectRoot "third_party/boringssl"
$gperfExe = Join-Path $projectRoot "third_party/tools/gperf/gperf.exe"
$threadHeader = Join-Path $tdRepo "tdutils/td/utils/port/detail/ThreadPthread.h"

$cmake = Join-Path $SdkNative "build-tools/cmake/bin/cmake.exe"
$ninja = Join-Path $SdkNative "build-tools/cmake/bin/ninja.exe"
$toolchain = Join-Path $SdkNative "build/cmake/ohos.toolchain.cmake"

foreach ($requiredPath in @($tdRepo, $boringRepo, $gperfExe, $cmake, $ninja, $toolchain, $threadHeader)) {
  if (!(Test-Path $requiredPath)) {
    throw "Missing required path: $requiredPath"
  }
}


$archSuffixMap = @{
  "arm64-v8a" = "arm64"
  "x86_64" = "x86_64"
}
if (-not $archSuffixMap.ContainsKey($Arch)) {
  throw "Unsupported Arch '$Arch'. Supported values: arm64-v8a, x86_64"
}
$buildSuffix = $archSuffixMap[$Arch]

# OHOS currently misses pthread affinity APIs used by TDLib.
$threadHeaderContent = Get-Content $threadHeader -Raw
if ($threadHeaderContent -notmatch "__OHOS__") {
  $threadHeaderContent = $threadHeaderContent -replace `
    "#if TD_LINUX \|\| TD_FREEBSD \|\| TD_NETBSD", `
    "#if (TD_LINUX || TD_FREEBSD || TD_NETBSD) && !defined(__OHOS__)"
  Set-Content -Path $threadHeader -Value $threadHeaderContent -Encoding ascii
}

$boringBuild = Join-Path $projectRoot "third_party/build/boringssl-ohos-$buildSuffix"
& $cmake -S $boringRepo -B $boringBuild -G Ninja `
  "-DCMAKE_MAKE_PROGRAM=$ninja" `
  "-DCMAKE_TOOLCHAIN_FILE=$toolchain" `
  "-DOHOS_ARCH=$Arch" `
  "-DCMAKE_BUILD_TYPE=Release" `
  "-DBUILD_SHARED_LIBS=OFF" `
  "-DBUILD_TESTING=OFF" `
  "-DCMAKE_C_FLAGS=-Wno-error=unused-command-line-argument" `
  "-DCMAKE_CXX_FLAGS=-Wno-error=unused-command-line-argument"

& $cmake --build $boringBuild --target crypto ssl -j 8
if ($LASTEXITCODE -ne 0) { throw "BoringSSL build failed (exit $LASTEXITCODE)" }

$tdHostBuild = Join-Path $projectRoot "third_party/build/td-host-vs"
& $cmake -S $tdRepo -B $tdHostBuild -G "Visual Studio 17 2022" -A x64 `
  "-DBUILD_TESTING=OFF" `
  "-DTD_ENABLE_JNI=OFF" `
  "-DGPERF_EXECUTABLE=$gperfExe"

& $cmake --build $tdHostBuild --target prepare_cross_compiling --config Release -j 8
if ($LASTEXITCODE -ne 0) { throw "TDLib host prepare_cross_compiling failed (exit $LASTEXITCODE)" }

$tdCrossBuild = Join-Path $projectRoot "third_party/build/td-ohos-$buildSuffix"
$opensslInclude = Join-Path $boringRepo "include"
$opensslCrypto = Join-Path $boringBuild "libcrypto.a"
$opensslSsl = Join-Path $boringBuild "libssl.a"

& $cmake -S $tdRepo -B $tdCrossBuild -G Ninja `
  "-DCMAKE_MAKE_PROGRAM=$ninja" `
  "-DCMAKE_TOOLCHAIN_FILE=$toolchain" `
  "-DOHOS_ARCH=$Arch" `
  "-DCMAKE_BUILD_TYPE=Release" `
  "-DBUILD_TESTING=OFF" `
  "-DTD_ENABLE_JNI=OFF" `
  "-DOPENSSL_INCLUDE_DIR=$opensslInclude" `
  "-DOPENSSL_CRYPTO_LIBRARY=$opensslCrypto" `
  "-DOPENSSL_SSL_LIBRARY=$opensslSsl" `
  "-DCMAKE_C_FLAGS=-Wno-error=unused-command-line-argument" `
  "-DCMAKE_CXX_FLAGS=-Wno-error=unused-command-line-argument"

& $cmake --build $tdCrossBuild --target tdjson -j 8
if ($LASTEXITCODE -ne 0) { throw "TDLib cross build (tdjson) failed (exit $LASTEXITCODE)" }

$prebuiltDir = Join-Path $projectRoot "bridge/src/main/cpp/prebuilt/$Arch"
New-Item -ItemType Directory -Force -Path $prebuiltDir | Out-Null

# Resolve the versioned soname BEFORE touching prebuilt/ — validation must not
# leave a half-updated prebuilt dir if it throws (review F1 re-check, PR #69).
# The versioned soname follows the TDLib version in third_party/td — resolve it
# dynamically instead of hardcoding (1.8.60 -> 1.8.63 bump, task 5.1 / #65).
# NOTE: Windows -Filter "libtdjson.so.*" also matches plain "libtdjson.so"
# (8.3-style matching), so always re-filter with a regex before acting.
# The incremental cross-build dir is never cleaned, so after a TDLib version
# bump a stale older soname coexists with the fresh one and an unsorted
# first-match pick would silently ship the OLD library.
# Mirror the bridge CMake contract instead: exactly one candidate or fail.
$versionedSoCandidates = @(Get-ChildItem -Path $tdCrossBuild |
  Where-Object { $_.Name -match '^libtdjson\.so\.[0-9.]+$' })
if ($versionedSoCandidates.Count -ne 1) {
  $foundNames = ($versionedSoCandidates | ForEach-Object { $_.Name }) -join ', '
  throw "Expected exactly one libtdjson.so.<version> in $tdCrossBuild, found $($versionedSoCandidates.Count) [$foundNames]. Stale soname from a previous TDLib checkout? Delete it (or the whole build dir) and re-run."
}
$versionedSo = $versionedSoCandidates[0]

# Validation passed — now mutate prebuilt/ (clear stale sonames, copy both files).
Get-ChildItem -Path $prebuiltDir |
  Where-Object { $_.Name -match '^libtdjson\.so\.[0-9.]+$' -and $_.Name -ne $versionedSo.Name } |
  Remove-Item -Force
Copy-Item -Force (Join-Path $tdCrossBuild "libtdjson.so") (Join-Path $prebuiltDir "libtdjson.so")
Copy-Item -Force $versionedSo.FullName (Join-Path $prebuiltDir $versionedSo.Name)

Write-Host "TDLib build completed and copied to $prebuiltDir ($($versionedSo.Name))"
