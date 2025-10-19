cmake_minimum_required(VERSION 3.20)
project(yaya_core)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")

find_package(nlohmann_json REQUIRED)

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

target_link_libraries(yaya_core PRIVATE nlohmann_json::nlohmann_json)
