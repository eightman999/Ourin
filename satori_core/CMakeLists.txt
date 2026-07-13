cmake_minimum_required(VERSION 3.20)
project(satori_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS version")
if(APPLE AND NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "Build architectures" FORCE)
endif()

find_package(nlohmann_json 3.11.0 REQUIRED)

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
