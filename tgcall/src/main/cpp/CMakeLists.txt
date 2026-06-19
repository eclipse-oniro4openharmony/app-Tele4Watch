cmake_minimum_required(VERSION 3.5.0)
project(tgcall)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_SKIP_INSTALL_RULES ON CACHE BOOL "" FORCE)

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

if(NOT DEFINED OHOS_ARCH)
    set(OHOS_ARCH "arm64-v8a")
endif()

set(REPO_ROOT "${NATIVERENDER_ROOT_PATH}/../../../..")
set(TGCALLS_ROOT "${REPO_ROOT}/third_party/tgcalls")
set(TGCALLS_SRC_ROOT "${TGCALLS_ROOT}/tgcalls")
set(WEBRTC_ROOT "${REPO_ROOT}/third_party/ohos_webrtc")
set(BORINGSSL_ROOT "${REPO_ROOT}/third_party/boringssl")
set(TGCALL_DEPS_HELP "Run scripts/prepare_tgcall_deps_wsl.sh first. See docs/tgcall-native-deps.md.")

if(OHOS_ARCH STREQUAL "arm64-v8a")
    set(TGCALL_WEBRTC_OUT_DIR "ohos_arm64_linux")
    set(TGCALL_WEBRTC_ARCH_DEFINE WEBRTC_ARCH_ARM64)
elseif(OHOS_ARCH STREQUAL "x86_64")
    set(TGCALL_WEBRTC_OUT_DIR "ohos_x64_linux")
    set(TGCALL_WEBRTC_ARCH_DEFINE WEBRTC_ENABLE_AVX2)
else()
    message(FATAL_ERROR "Unsupported OHOS_ARCH: ${OHOS_ARCH}. Build ohos_webrtc for this ABI first.")
endif()

set(TGCALL_WEBRTC_OUT_ROOT "${WEBRTC_ROOT}/out/${TGCALL_WEBRTC_OUT_DIR}")
set(TGCALL_BORINGSSL_CRYPTO "${TGCALL_WEBRTC_OUT_ROOT}/obj/third_party/boringssl/libboringssl.a")
set(TGCALL_BORINGSSL_ASM_ROOT "${TGCALL_WEBRTC_OUT_ROOT}/obj/third_party/boringssl/boringssl_asm")
set(TGCALL_BORINGSSL_ASM_OBJECTS "")
if(OHOS_ARCH STREQUAL "arm64-v8a")
    set(TGCALL_BORINGSSL_ASM_OBJECTS
        "${TGCALL_BORINGSSL_ASM_ROOT}/aesv8-armv8-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/aesv8-gcm-armv8-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/armv8-mont-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/bn-armv8-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/chacha-armv8-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/chacha20_poly1305_armv8-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/ghash-neon-armv8-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/ghashv8-armv8-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/p256-armv8-asm-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/p256_beeu-armv8-asm-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/sha1-armv8-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/sha256-armv8-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/sha512-armv8-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/vpaes-armv8-linux.o"
    )
elseif(OHOS_ARCH STREQUAL "x86_64")
    set(TGCALL_BORINGSSL_ASM_OBJECTS
        "${TGCALL_BORINGSSL_ASM_ROOT}/aesni-gcm-x86_64-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/aesni-x86_64-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/chacha-x86_64-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/chacha20_poly1305_x86_64-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/fiat_p256_adx_mul.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/fiat_p256_adx_sqr.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/ghash-ssse3-x86_64-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/ghash-x86_64-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/md5-x86_64-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/p256-x86_64-asm-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/p256_beeu-x86_64-asm-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/rdrand-x86_64-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/rsaz-avx2-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/sha1-x86_64-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/sha256-x86_64-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/sha512-x86_64-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/vpaes-x86_64-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/x86_64-mont-linux.o"
        "${TGCALL_BORINGSSL_ASM_ROOT}/x86_64-mont5-linux.o"
    )
endif()
file(GLOB_RECURSE TGCALL_WEBRTC_ALL_ARCHIVES "${TGCALL_WEBRTC_OUT_ROOT}/obj/*.a")
list(FILTER TGCALL_WEBRTC_ALL_ARCHIVES EXCLUDE REGEX ".*/third_party/boringssl/.*")
list(FILTER TGCALL_WEBRTC_ALL_ARCHIVES EXCLUDE REGEX ".*/third_party/libjpeg_turbo/.*")
list(FILTER TGCALL_WEBRTC_ALL_ARCHIVES EXCLUDE REGEX ".*/third_party/libyuv/.*")
file(GLOB_RECURSE TGCALL_WEBRTC_ALL_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/*.o")
list(FILTER TGCALL_WEBRTC_ALL_OBJECTS EXCLUDE REGEX ".*/third_party/boringssl/.*")
list(FILTER TGCALL_WEBRTC_ALL_OBJECTS EXCLUDE REGEX ".*/third_party/libjpeg_turbo/.*")
list(FILTER TGCALL_WEBRTC_ALL_OBJECTS EXCLUDE REGEX ".*/third_party/libyuv/libyuv_internal/convert_jpeg\\.o$")
list(FILTER TGCALL_WEBRTC_ALL_OBJECTS EXCLUDE REGEX ".*/third_party/libyuv/libyuv_internal/mjpeg_decoder\\.o$")
list(FILTER TGCALL_WEBRTC_ALL_OBJECTS EXCLUDE REGEX ".*/third_party/googletest/.*")
list(FILTER TGCALL_WEBRTC_ALL_OBJECTS EXCLUDE REGEX ".*/third_party/google_benchmark/.*")
list(FILTER TGCALL_WEBRTC_ALL_OBJECTS EXCLUDE REGEX ".*/third_party/fuzztest/.*")
list(FILTER TGCALL_WEBRTC_ALL_OBJECTS EXCLUDE REGEX ".*/sdk/ohos/libohos_webrtc/.*")
list(FILTER TGCALL_WEBRTC_ALL_OBJECTS EXCLUDE REGEX ".*/test/.*")
list(FILTER TGCALL_WEBRTC_ALL_OBJECTS EXCLUDE REGEX ".*/testing/.*")
list(FILTER TGCALL_WEBRTC_ALL_OBJECTS EXCLUDE REGEX ".*_test[^/]*\\.o$")
list(FILTER TGCALL_WEBRTC_ALL_OBJECTS EXCLUDE REGEX ".*unittest[^/]*\\.o$")
file(GLOB_RECURSE TGCALL_WEBRTC_ABSL_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/third_party/abseil-cpp/absl/*.o")
file(GLOB_RECURSE TGCALL_WEBRTC_ZLIB_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/third_party/zlib/zlib/*.o")
file(GLOB_RECURSE TGCALL_WEBRTC_PC_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/pc/*/*.o")
file(GLOB_RECURSE TGCALL_WEBRTC_SDP_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/pc/webrtc_sdp/*.o")
file(GLOB_RECURSE TGCALL_WEBRTC_STUN_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/api/transport/stun_types/*.o")
file(GLOB_RECURSE TGCALL_WEBRTC_MEDIA_SESSION_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/pc/media_session/*.o")
file(GLOB_RECURSE TGCALL_WEBRTC_SESSION_DESCRIPTION_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/pc/session_description/*.o")
file(GLOB_RECURSE TGCALL_WEBRTC_PEER_FACTORY_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/pc/peer_connection_factory/*.o")
file(GLOB_RECURSE TGCALL_WEBRTC_PEER_CONNECTION_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/pc/peer_connection/*.o")
file(GLOB_RECURSE TGCALL_WEBRTC_LOCAL_AUDIO_SOURCE_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/pc/local_audio_source/*.o")
file(GLOB_RECURSE TGCALL_WEBRTC_SIMULCAST_OBJECTS
    "${TGCALL_WEBRTC_OUT_ROOT}/obj/pc/simulcast_description/*.o"
    "${TGCALL_WEBRTC_OUT_ROOT}/obj/pc/simulcast_sdp_serializer/*.o"
)
file(GLOB_RECURSE TGCALL_WEBRTC_RTP_TRANSCEIVER_DIRECTION_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/api/rtp_transceiver_direction/*.o")
file(GLOB_RECURSE TGCALL_WEBRTC_SCALABILITY_MODE_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/api/video_codecs/scalability_mode/*.o")
file(GLOB_RECURSE TGCALL_WEBRTC_NETWORK_CONSTANTS_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/network_constants/*.o")
file(GLOB_RECURSE TGCALL_WEBRTC_BITSTREAM_READER_OBJECTS "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/bitstream_reader/*.o")
set(TGCALL_WEBRTC_RTP_PARAMETERS "${TGCALL_WEBRTC_OUT_ROOT}/obj/api/librtp_parameters.a")
set(TGCALL_WEBRTC_LOGGING "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/liblogging.a")
set(TGCALL_WEBRTC_CHECKS "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/libchecks.a")
set(TGCALL_WEBRTC_STRINGUTILS "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/libstringutils.a")
set(TGCALL_WEBRTC_TIMEUTILS "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/libtimeutils.a")
set(TGCALL_WEBRTC_PLATFORM_THREAD_TYPES "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/libplatform_thread_types.a")
set(TGCALL_WEBRTC_THREADING "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/libthreading.a")
set(TGCALL_WEBRTC_PLATFORM_THREAD "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/libplatform_thread.a")
set(TGCALL_WEBRTC_TASK_QUEUE "${TGCALL_WEBRTC_OUT_ROOT}/obj/api/task_queue/libtask_queue.a")
set(TGCALL_WEBRTC_PENDING_TASK_SAFETY_FLAG "${TGCALL_WEBRTC_OUT_ROOT}/obj/api/task_queue/libpending_task_safety_flag.a")
set(TGCALL_WEBRTC_EVENT_TRACER "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/libevent_tracer.a")
set(TGCALL_WEBRTC_NULL_SOCKET_SERVER "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/libnull_socket_server.a")
set(TGCALL_WEBRTC_RTC_EVENT "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/librtc_event.a")
set(TGCALL_WEBRTC_FIELD_TRIAL "${TGCALL_WEBRTC_OUT_ROOT}/obj/system_wrappers/libfield_trial.a")
set(TGCALL_WEBRTC_SOCKET_ADDRESS "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/libsocket_address.a")
set(TGCALL_WEBRTC_IP_ADDRESS "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/libip_address.a")
set(TGCALL_WEBRTC_ASYNC_DNS_RESOLVER "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/libasync_dns_resolver.a")
set(TGCALL_WEBRTC_CRITICALSECTION "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/libcriticalsection.a")
set(TGCALL_WEBRTC_YIELD_POLICY "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/synchronization/libyield_policy.a")
set(TGCALL_WEBRTC_SEQUENCE_CHECKER_INTERNAL "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/synchronization/libsequence_checker_internal.a")
set(TGCALL_WEBRTC_NET_HELPERS "${TGCALL_WEBRTC_OUT_ROOT}/obj/rtc_base/libnet_helpers.a")

set(TGCALL_FACTORY_IMPLEMENTATION_EXTRA_SOURCES "")
set(TGCALL_FACTORY_WEBRTC_ARCHIVES "")
if(EXISTS "${WEBRTC_ROOT}/api/environment/environment_factory.h")
    set(TGCALL_FACTORY_IMPLEMENTATION_SOURCE "${TGCALLS_SRC_ROOT}/v2/InstanceV2Impl.cpp")
    set(TGCALL_FACTORY_IMPLEMENTATION_DEFINE TGCALL_USE_INSTANCE_V2_IMPL)
    set(TGCALL_FACTORY_IMPLEMENTATION_EXTRA_SOURCES "${TGCALLS_SRC_ROOT}/StaticThreads.cpp")
elseif(EXISTS "${WEBRTC_ROOT}/api/enable_media.h")
    set(TGCALL_FACTORY_IMPLEMENTATION_SOURCE "${TGCALLS_SRC_ROOT}/v2/InstanceV2ReferenceImpl.cpp")
    set(TGCALL_FACTORY_IMPLEMENTATION_DEFINE TGCALL_USE_INSTANCE_V2_REFERENCE_IMPL)
    set(TGCALL_FACTORY_IMPLEMENTATION_EXTRA_SOURCES "${TGCALLS_SRC_ROOT}/StaticThreads.cpp")
elseif(EXISTS "${WEBRTC_ROOT}/api/create_peerconnection_factory.h")
    set(TGCALL_FACTORY_IMPLEMENTATION_SOURCE "${TGCALLS_SRC_ROOT}/v2/InstanceV2ReferenceImpl.cpp")
    set(TGCALL_FACTORY_IMPLEMENTATION_DEFINE TGCALL_USE_INSTANCE_V2_REFERENCE_IMPL TGCALL_WEBRTC_LEGACY_MEDIA_DEPS)
    set(TGCALL_FACTORY_IMPLEMENTATION_EXTRA_SOURCES
        "${TGCALLS_SRC_ROOT}/AudioDeviceHelper.cpp"
        "${TGCALLS_SRC_ROOT}/CodecSelectHelper.cpp"
        "${TGCALLS_SRC_ROOT}/EncryptedConnection.cpp"
        "${TGCALLS_SRC_ROOT}/LogSinkImpl.cpp"
        "${TGCALLS_SRC_ROOT}/Message.cpp"
        "${TGCALLS_SRC_ROOT}/SctpDataChannelProviderInterfaceImpl.cpp"
        "${TGCALLS_SRC_ROOT}/StaticThreads.cpp"
        "${TGCALLS_SRC_ROOT}/ThreadLocalObject.cpp"
        "${TGCALLS_SRC_ROOT}/TurnCustomizerImpl.cpp"
        "${TGCALLS_SRC_ROOT}/VideoCaptureInterface.cpp"
        "video_capture_interface_impl_voice_stub.cpp"
        "${TGCALLS_SRC_ROOT}/platform/fake/FakeInterface.cpp"
        "${TGCALLS_SRC_ROOT}/utils/gzip.cpp"
        "${TGCALLS_SRC_ROOT}/v2/ContentNegotiation.cpp"
        "${TGCALLS_SRC_ROOT}/v2/ExternalSignalingConnection.cpp"
        "${TGCALLS_SRC_ROOT}/v2/SignalingConnection.cpp"
        "${TGCALLS_SRC_ROOT}/v2/SignalingEncryption.cpp"
        "${TGCALLS_SRC_ROOT}/v2/SignalingSctpConnection.cpp"
    )
    set(TGCALL_FACTORY_WEBRTC_ARCHIVES ${TGCALL_WEBRTC_ALL_ARCHIVES})
    set(TGCALL_FACTORY_WEBRTC_OBJECTS
        ${TGCALL_WEBRTC_ALL_OBJECTS}
    )
    list(REMOVE_DUPLICATES TGCALL_FACTORY_WEBRTC_OBJECTS)
else()
    set(TGCALL_FACTORY_IMPLEMENTATION_SOURCE "")
    set(TGCALL_FACTORY_IMPLEMENTATION_DEFINE TGCALL_REAL_FACTORY_UNAVAILABLE)
endif()

if(NOT "${TGCALL_FACTORY_IMPLEMENTATION_SOURCE}" STREQUAL "")
    list(APPEND TGCALL_FACTORY_WEBRTC_ARCHIVES
        "${TGCALL_WEBRTC_THREADING}"
        "${TGCALL_WEBRTC_PLATFORM_THREAD}"
        "${TGCALL_WEBRTC_TASK_QUEUE}"
        "${TGCALL_WEBRTC_PENDING_TASK_SAFETY_FLAG}"
        "${TGCALL_WEBRTC_EVENT_TRACER}"
        "${TGCALL_WEBRTC_NULL_SOCKET_SERVER}"
        "${TGCALL_WEBRTC_RTC_EVENT}"
        "${TGCALL_WEBRTC_FIELD_TRIAL}"
        "${TGCALL_WEBRTC_SOCKET_ADDRESS}"
        "${TGCALL_WEBRTC_IP_ADDRESS}"
        "${TGCALL_WEBRTC_ASYNC_DNS_RESOLVER}"
        "${TGCALL_WEBRTC_CRITICALSECTION}"
        "${TGCALL_WEBRTC_YIELD_POLICY}"
        "${TGCALL_WEBRTC_SEQUENCE_CHECKER_INTERNAL}"
        "${TGCALL_WEBRTC_NET_HELPERS}"
    )
endif()

foreach(required_source IN ITEMS
    "${TGCALLS_SRC_ROOT}/CryptoHelper.cpp"
    "${TGCALLS_SRC_ROOT}/third-party/json11.cpp"
    "${TGCALLS_SRC_ROOT}/v2/Signaling.cpp"
    "${BORINGSSL_ROOT}/include"
)
    if(NOT EXISTS "${required_source}")
        message(FATAL_ERROR "Missing tgcall source dependency: ${required_source}. ${TGCALL_DEPS_HELP}")
    endif()
endforeach()

if(NOT EXISTS "${TGCALL_BORINGSSL_CRYPTO}")
    message(FATAL_ERROR "Missing BoringSSL crypto archive: ${TGCALL_BORINGSSL_CRYPTO}. ${TGCALL_DEPS_HELP}")
endif()

foreach(required_archive IN ITEMS
    "${TGCALL_WEBRTC_RTP_PARAMETERS}"
    "${TGCALL_WEBRTC_LOGGING}"
    "${TGCALL_WEBRTC_CHECKS}"
    "${TGCALL_WEBRTC_STRINGUTILS}"
    "${TGCALL_WEBRTC_TIMEUTILS}"
    "${TGCALL_WEBRTC_PLATFORM_THREAD_TYPES}"
    "${TGCALL_WEBRTC_SEQUENCE_CHECKER_INTERNAL}"
    ${TGCALL_FACTORY_WEBRTC_ARCHIVES}
)
    if(NOT EXISTS "${required_archive}")
        message(FATAL_ERROR "Missing WebRTC archive: ${required_archive}. ${TGCALL_DEPS_HELP}")
    endif()
endforeach()

add_library(tgcall SHARED
    base64_util.cpp
    diagnostic_tgcall_instance.cpp
    libyuv_mjpeg_voice_stub.cpp
    napi_init.cpp
    real_tgcall_factory_registry.cpp
    tgcall_session.cpp
    tgcall_native.cpp
    webk_signaling_adapter.cpp
    InstanceV4_0_0Impl.cpp
    InstanceV13_0_0Impl.cpp
    ${TGCALLS_SRC_ROOT}/ChannelManager.cpp
    ${TGCALLS_SRC_ROOT}/CryptoHelper.cpp
    ${TGCALLS_SRC_ROOT}/EncryptedConnection.cpp
    ${TGCALLS_SRC_ROOT}/FieldTrialsConfig.cpp
    ${TGCALLS_SRC_ROOT}/Instance.cpp
    ${TGCALLS_SRC_ROOT}/Message.cpp
    ${TGCALLS_SRC_ROOT}/SctpDataChannelProviderInterfaceImpl.cpp
    ${TGCALLS_SRC_ROOT}/third-party/json11.cpp
    ${TGCALLS_SRC_ROOT}/TurnCustomizerImpl.cpp
    ${TGCALLS_SRC_ROOT}/v2/NativeNetworkingImpl.cpp
    ${TGCALLS_SRC_ROOT}/v2/RawTcpSocket.cpp
    ${TGCALLS_SRC_ROOT}/v2/ReflectorPort.cpp
    ${TGCALLS_SRC_ROOT}/v2/ReflectorRelayPortFactory.cpp
    ${TGCALL_FACTORY_IMPLEMENTATION_EXTRA_SOURCES}
    ${TGCALL_FACTORY_IMPLEMENTATION_SOURCE}
    ${TGCALLS_SRC_ROOT}/v2_4_0_0/Signaling_4_0_0.cpp
    ${TGCALLS_SRC_ROOT}/v2/Signaling.cpp
    ${TGCALL_BORINGSSL_ASM_OBJECTS}
)

target_include_directories(tgcall PUBLIC
    ${NATIVERENDER_ROOT_PATH}
    ${TGCALLS_ROOT}
    ${TGCALLS_SRC_ROOT}
    ${TGCALLS_SRC_ROOT}/v2
    ${BORINGSSL_ROOT}/include
    ${WEBRTC_ROOT}
    ${WEBRTC_ROOT}/third_party/abseil-cpp
    ${TGCALL_WEBRTC_OUT_ROOT}/gen
)

target_compile_definitions(tgcall PRIVATE
    __STDC_CONSTANT_MACROS
    __STDC_FORMAT_MACROS
    _FILE_OFFSET_BITS=64
    _LARGEFILE_SOURCE
    _LARGEFILE64_SOURCE
    NDEBUG
    HAVE_SYS_UIO_H
    OHOS
    __MUSL__
    __BUILD_LINUX_WITH_CLANG
    __GNU_SOURCE
    _GNU_SOURCE
    WEBRTC_POSIX
    WEBRTC_OHOS
    WEBRTC_LINUX
    WEBRTC_ENABLE_PROTOBUF=1
    WEBRTC_STRICT_FIELD_TRIALS=0
    WEBRTC_INCLUDE_INTERNAL_AUDIO_DEVICE
    WEBRTC_HAVE_SCTP
    WEBRTC_ENABLE_LIBEVENT
    WEBRTC_NON_STATIC_TRACE_EVENT_HANDLERS=0
    TGCALL_WEBRTC_SCOPED_REFPTR_ALIAS
    ABSL_ALLOCATOR_NOTHROW=1
    ${TGCALL_WEBRTC_ARCH_DEFINE}
    ${TGCALL_FACTORY_IMPLEMENTATION_DEFINE}
)

if(NOT "${TGCALL_FACTORY_IMPLEMENTATION_SOURCE}" STREQUAL "")
    target_compile_options(tgcall PRIVATE
        -include tgcall_webrtc_compat.h
        -fno-rtti
    )
endif()

set_target_properties(tgcall PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/native-out"
)

target_link_libraries(tgcall PRIVATE
    "-Wl,--start-group"
    ${TGCALL_FACTORY_WEBRTC_OBJECTS}
    ${TGCALL_WEBRTC_RTP_PARAMETERS}
    ${TGCALL_WEBRTC_LOGGING}
    ${TGCALL_WEBRTC_CHECKS}
    ${TGCALL_WEBRTC_STRINGUTILS}
    ${TGCALL_WEBRTC_TIMEUTILS}
    ${TGCALL_WEBRTC_PLATFORM_THREAD_TYPES}
    ${TGCALL_FACTORY_WEBRTC_ARCHIVES}
    ${TGCALL_BORINGSSL_CRYPTO}
    "-Wl,--end-group"
    libace_napi.z.so
    libhilog_ndk.z.so
    libohaudio.so
    z
)
