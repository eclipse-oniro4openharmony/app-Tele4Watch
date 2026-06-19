cmake_minimum_required(VERSION 3.5.0)
project(opusdecoder)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_SKIP_INSTALL_RULES ON CACHE BOOL "" FORCE)

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(INSTALL_DOCS OFF CACHE BOOL "" FORCE)
set(INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(INSTALL_CMAKE_PACKAGE_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_DISABLE_INTRINSICS ON CACHE BOOL "" FORCE)
set(OPUS_MAY_HAVE_NEON OFF CACHE BOOL "" FORCE)
set(OPUS_PRESUME_NEON ON CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OP_DISABLE_HTTP ON CACHE BOOL "" FORCE)
set(OP_DISABLE_EXAMPLES ON CACHE BOOL "" FORCE)
set(OP_DISABLE_DOCS ON CACHE BOOL "" FORCE)

add_subdirectory(${NATIVERENDER_ROOT_PATH}/../../../../third_party/ogg ${CMAKE_CURRENT_BINARY_DIR}/third_party/ogg)
add_subdirectory(${NATIVERENDER_ROOT_PATH}/../../../../third_party/opus ${CMAKE_CURRENT_BINARY_DIR}/third_party/opus)
add_subdirectory(${NATIVERENDER_ROOT_PATH}/../../../../third_party/opusfile ${CMAKE_CURRENT_BINARY_DIR}/third_party/opusfile)

add_library(opusdecoder SHARED
    napi_init.cpp
    opus_encode.cpp
    opus_decode.cpp
    opus_decoder.cpp
)

target_include_directories(opusdecoder PUBLIC
    ${NATIVERENDER_ROOT_PATH}
)

set_target_properties(opusdecoder PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/native-out"
)

target_link_libraries(opusdecoder PUBLIC
    ogg
    opus
    opusfile
    libace_napi.z.so
    libhilog_ndk.z.so
)
