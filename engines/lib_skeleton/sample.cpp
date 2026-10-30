// Self-authored development sample using the unmodified lib_skeleton SHIORI classes.
#include "lib_skeleton/shiori.h"
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <string>
#include <unistd.h>
using Request = lib_skeleton::shiori::Request;
using Response = lib_skeleton::shiori::Response;
static std::string directory;
static bool loaded = false;
static std::string respond(const std::string& wire) {
    auto input = Request::parse(wire);
    int code = 204;
    std::string value;
    if (input.getCommand() != "GET" && input.getCommand() != "NOTIFY") code = 400;
    else if (input.getCommand() == "GET") {
        const auto id = input().value_or("");
        if (id == "version") value = "0.1";
        else if (id == "name") value = "lib_skeleton SHIORI development example";
        else if (id == "OnBoot") value = "\\0\\s[0]桜鈴、こんにちは。\\e";
        else if (id == "OnEcho") value = input(0).value_or("");
        else if (id == "OnSparse") value = input(2).value_or("");
        if (!value.empty()) code = 200;
    }
    Response output(code, code == 200 ? "OK" : code == 204 ? "No Content" : "Bad Request");
    output["Charset"] = std::string("UTF-8");
    output["Sender"] = std::string("lib_skeleton-example");
    if (code == 200) output() = value;
    return static_cast<std::string>(output);
}
extern "C" int32_t load(void* input, long length) {
    std::unique_ptr<void, decltype(&free)> owned(input, free);
    if (!input || length <= 0 || length > 1048576) return 0;
    directory.assign(static_cast<const char*>(input), length);
    std::ofstream marker(directory + "loaded.pid");
    marker << getpid();
    loaded = marker.good();
    return loaded ? 1 : 0;
}
extern "C" int32_t unload() {
    if (!loaded) return 1;
    std::ofstream marker(directory + "unloaded.marker");
    marker << "unloaded";
    loaded = false;
    return marker.good() ? 1 : 0;
}
extern "C" void* request(void* input, long* length) {
    std::unique_ptr<void, decltype(&free)> owned(input, free);
    if (!loaded || !input || !length || *length < 0 || *length > 1048576) return nullptr;
    try {
        std::string output = respond(std::string(static_cast<const char*>(input), *length));
        void* result = malloc(output.size() + 1);
        if (!result) return nullptr;
        memcpy(result, output.c_str(), output.size() + 1);
        *length = static_cast<long>(output.size());
        return result;
    } catch (...) { return nullptr; }
}
