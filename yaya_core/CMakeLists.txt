cmake_minimum_required(VERSION 3.20)
project(yaya_core)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")

# nlohmann/json dependency (version 3.12.0 or later recommended)
# Note: If the package config is unavailable, accept a header-only installation too.
# VTK distributes the same library under the `vtknlohmann` namespace and uses an
# include macro; a generated compatibility header keeps the source includes stable.
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
            set(YAYA_JSON_COMPAT_DIR "${CMAKE_BINARY_DIR}/generated/include")
            file(MAKE_DIRECTORY "${YAYA_JSON_COMPAT_DIR}/nlohmann")
            file(WRITE "${YAYA_JSON_COMPAT_DIR}/nlohmann/json.hpp"
                "#pragma once\n"
                "#define VTK_NLOHMANN_JSON(x) <vtknlohmann/x>\n"
                "#include <vtknlohmann/json.hpp>\n")
            set(NLOHMANN_JSON_INCLUDE_DIR "${YAYA_JSON_COMPAT_DIR}")
            set(YAYA_JSON_VENDOR_INCLUDE_DIR "${VTK_NLOHMANN_JSON_INCLUDE_DIR}")
        endif()
    endif()

    if(NLOHMANN_JSON_INCLUDE_DIR)
        add_library(yaya_nlohmann_json INTERFACE)
        target_include_directories(yaya_nlohmann_json SYSTEM INTERFACE
            "${NLOHMANN_JSON_INCLUDE_DIR}"
            $<$<BOOL:${YAYA_JSON_VENDOR_INCLUDE_DIR}>:${YAYA_JSON_VENDOR_INCLUDE_DIR}>)
        add_library(nlohmann_json::nlohmann_json ALIAS yaya_nlohmann_json)
    else()
        message(FATAL_ERROR
            "nlohmann_json package or a nlohmann/json.hpp header is required")
    endif()
endif()

add_executable(yaya_core
    src/main.cpp
    src/YayaCore.cpp
    src/DictionaryManager.cpp
    src/MessageManager.cpp
    src/Digest.cpp
    src/Base64.cpp
    src/Lexer.cpp
    src/Parser.cpp
    src/Value.cpp
    src/VM.cpp
    third_party/yaya/md5c.c
    third_party/yaya/sha1.c
    third_party/yaya/crc32.c
    third_party/yaya/posix_utils.cpp
)

set_target_properties(yaya_core PROPERTIES
    OUTPUT_NAME "yaya_core"
)

# iconv: 辞書ファイルの CP932/Shift_JIS -> UTF-8 変換に使用（macOS は libiconv が標準搭載）
target_link_libraries(yaya_core PRIVATE nlohmann_json::nlohmann_json iconv)
