cmake_minimum_required(VERSION 3.5.0)
project(bridge)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

if(NOT DEFINED OHOS_ARCH)
    set(OHOS_ARCH "arm64-v8a")
endif()

if(OHOS_ARCH STREQUAL "arm64-v8a")
    set(TD_ARCH_DIR "arm64-v8a")
    set(TD_BUILD_SUFFIX "arm64")
elseif(OHOS_ARCH STREQUAL "x86_64")
    set(TD_ARCH_DIR "x86_64")
    set(TD_BUILD_SUFFIX "x86_64")
else()
    message(FATAL_ERROR "Unsupported OHOS_ARCH: ${OHOS_ARCH}. Provide prebuilt TDLib for this ABI first.")
endif()

set(TDLIB_SRC_ROOT "${NATIVERENDER_ROOT_PATH}/../../../../third_party/td")
set(TDLIB_BUILD_ROOT "${NATIVERENDER_ROOT_PATH}/../../../../third_party/build/td-ohos-${TD_BUILD_SUFFIX}")
set(TDLIB_PREBUILT_ROOT "${NATIVERENDER_ROOT_PATH}/prebuilt/${TD_ARCH_DIR}")
set(TDLIB_SO_PATH "${TDLIB_PREBUILT_ROOT}/libtdjson.so")
# The versioned soname tracks the TDLib version pinned in third_party/td — resolve it
# by glob instead of hardcoding (1.8.60 -> 1.8.63 bump for MTProto layer 224, #65).
file(GLOB TDLIB_SO_VERSION_CANDIDATES "${TDLIB_PREBUILT_ROOT}/libtdjson.so.*")
list(LENGTH TDLIB_SO_VERSION_CANDIDATES TDLIB_SO_VERSION_COUNT)
if(NOT TDLIB_SO_VERSION_COUNT EQUAL 1)
    message(FATAL_ERROR "Expected exactly one libtdjson.so.<version> in ${TDLIB_PREBUILT_ROOT}, found ${TDLIB_SO_VERSION_COUNT}. Build TDLib before building this module (scripts/build_tdlib_ohos.ps1).")
endif()
list(GET TDLIB_SO_VERSION_CANDIDATES 0 TDLIB_SO_VERSION_PATH)
set(BRIDGE_NATIVE_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/native-out")

add_library(tdjson SHARED IMPORTED GLOBAL)
set_target_properties(tdjson PROPERTIES IMPORTED_LOCATION "${TDLIB_SO_VERSION_PATH}")

include_directories(
    ${NATIVERENDER_ROOT_PATH}
    ${TDLIB_SRC_ROOT}
    ${TDLIB_BUILD_ROOT}
)

add_library(bridge SHARED
    napi_init.cpp
    td_bridge.cpp
)

set_target_properties(bridge PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${BRIDGE_NATIVE_OUTPUT_DIR}"
)

target_link_libraries(bridge PUBLIC
    tdjson
    libace_napi.z.so
    libhilog_ndk.z.so
)
