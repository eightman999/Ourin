cmake_minimum_required(VERSION 3.20)
project(satori_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS version")
if(APPLE AND NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "Build architectures" FORCE)
endif()

# nlohmann/json dependency.  Prefer a normal package, but accept a compatible
# header-only installation (including VTK's namespaced copy) just like
# yaya_core does.  Satori is built as part of the app and must not depend on a
# Homebrew package configuration being present on the host.
find_package(nlohmann_json 3.11.0 QUIET)
if(NOT nlohmann_json_FOUND)
    find_path(NLOHMANN_JSON_INCLUDE_DIR NAMES nlohmann/json.hpp)

    if(NOT NLOHMANN_JSON_INCLUDE_DIR)
        file(GLOB VTK_NLOHMANN_JSON_CANDIDATES
            "/usr/local/include/vtk-*/vtknlohmannjson/include"
            "/opt/homebrew/include/vtk-*/vtknlohmannjson/include")
        find_path(VTK_NLOHMANN_JSON_INCLUDE_DIR
            NAMES vtknlohmann/json.hpp
            PATHS ${VTK_NLOHMANN_JSON_CANDIDATES})

        if(VTK_NLOHMANN_JSON_INCLUDE_DIR)
            set(SATORI_JSON_COMPAT_DIR "${CMAKE_BINARY_DIR}/generated/include")
            file(MAKE_DIRECTORY "${SATORI_JSON_COMPAT_DIR}/nlohmann")
            file(WRITE "${SATORI_JSON_COMPAT_DIR}/nlohmann/json.hpp"
                "#pragma once\n"
                "#define VTK_NLOHMANN_JSON(x) <vtknlohmann/x>\n"
                "#include <vtknlohmann/json.hpp>\n")
            set(NLOHMANN_JSON_INCLUDE_DIR "${SATORI_JSON_COMPAT_DIR}")
            set(SATORI_JSON_VENDOR_INCLUDE_DIR "${VTK_NLOHMANN_JSON_INCLUDE_DIR}")
        endif()
    endif()

    if(NLOHMANN_JSON_INCLUDE_DIR)
        add_library(satori_nlohmann_json INTERFACE)
        target_include_directories(satori_nlohmann_json SYSTEM INTERFACE
            "${NLOHMANN_JSON_INCLUDE_DIR}"
            $<$<BOOL:${SATORI_JSON_VENDOR_INCLUDE_DIR}>:${SATORI_JSON_VENDOR_INCLUDE_DIR}>)
        add_library(nlohmann_json::nlohmann_json ALIAS satori_nlohmann_json)
    else()
        message(FATAL_ERROR
            "nlohmann_json package or a nlohmann/json.hpp header is required")
    endif()
endif()

set(SATORI_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/satoriya-shiori/satoriya")

add_executable(satori_core
    src/main.cpp
    src/EncodingIconv.cpp
    ${SATORI_ROOT}/_/Sender.cpp
    ${SATORI_ROOT}/_/Utilities.cpp
    ${SATORI_ROOT}/_/calc.cpp
    ${SATORI_ROOT}/_/calc_float.cpp
    ${SATORI_ROOT}/_/stltool.cpp
    ${SATORI_ROOT}/_/mt19937ar.cpp
    ${SATORI_ROOT}/_/random.cpp
    ${SATORI_ROOT}/satori/SakuraCS.cpp
    ${SATORI_ROOT}/satori/SakuraClient.cpp
    ${SATORI_ROOT}/satori/SakuraDLLClient.cpp
    ${SATORI_ROOT}/satori/SakuraDLLHost.cpp
    ${SATORI_ROOT}/satori/SaoriClient.cpp
    ${SATORI_ROOT}/satori/SaoriHost.cpp
    ${SATORI_ROOT}/satori/satori.cpp
    ${SATORI_ROOT}/satori/satoriTranslate.cpp
    ${SATORI_ROOT}/satori/satori_AnalyzeRequest.cpp
    ${SATORI_ROOT}/satori/satori_CreateResponce.cpp
    ${SATORI_ROOT}/satori/satori_EventOperation.cpp
    ${SATORI_ROOT}/satori/satori_Kakko.cpp
    ${SATORI_ROOT}/satori/satori_load_dict.cpp
    ${SATORI_ROOT}/satori/satori_load_unload.cpp
    ${SATORI_ROOT}/satori/satori_sentence.cpp
    ${SATORI_ROOT}/satori/satori_tool.cpp
    ${SATORI_ROOT}/satori/shiori_plugin.cpp
    ${SATORI_ROOT}/satori/ssu.cpp
)

target_compile_definitions(satori_core PRIVATE POSIX SATORI_DLL)
target_include_directories(satori_core PRIVATE
    ${SATORI_ROOT}/_
    ${SATORI_ROOT}/satori
)
target_compile_options(satori_core PRIVATE
    -Wno-deprecated-declarations
    -Wno-invalid-source-encoding
    -Werror=return-type
)
target_link_libraries(satori_core PRIVATE nlohmann_json::nlohmann_json iconv)

# P2 external-SAORI integration fixture. It implements the POSIX Sakura DLL ABI
# expected by the vendored SATORI runtime and is never shipped in the app bundle.
add_library(satori_external_saori_fixture SHARED tests/fixtures/external_saori.cpp)
set_target_properties(satori_external_saori_fixture PROPERTIES
    PREFIX ""
    OUTPUT_NAME "external_saori"
)
