// POSIX CLI boundary with the pinned upstream test_host output format.
// Used to run the original behavioral scenarios without changing their JSON.
#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <thread>
#include <chrono>

int main(int argc, char** argv) {
    if (argc < 2) return 2;
    std::string directory = argv[1]; if (directory.back() != '/') directory += '/';
    void* library = dlopen((directory + "nashi.dll").c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!library) { std::fprintf(stderr, "%s\n", dlerror()); return 3; }
    auto load = reinterpret_cast<bool (*)(const char*)>(dlsym(library, "shiori_load"));
    auto unload = reinterpret_cast<void (*)()>(dlsym(library, "shiori_unload"));
    auto request = reinterpret_cast<bool (*)(const unsigned char*, intptr_t, unsigned char**, intptr_t*)>(dlsym(library, "shiori_request"));
    auto release = reinterpret_cast<void (*)(void*)>(dlsym(library, "shiori_free"));
    if (!load || !unload || !request || !release || !load(directory.c_str())) return 4;
    bool loaded = true;
    for (int i = 2; i < argc; ++i) {
        std::string spec = argv[i];
        if (spec == "!unload") {
            unload(); loaded = false; dlclose(library); library = nullptr;
            std::printf("---- %s\n(unloaded)\n", spec.c_str()); continue;
        }
        if (spec.compare(0, 7, "!sleep:") == 0) {
            int delay = std::atoi(spec.c_str() + 7);
            std::this_thread::sleep_for(std::chrono::milliseconds(delay));
            std::printf("---- %s\n(slept)\n", spec.c_str()); continue;
        }
        if (!loaded) return 5;
        int repeat = 1;
        size_t star = spec.find('*');
        if (star != std::string::npos) { repeat = std::atoi(spec.c_str() + star + 1); spec.resize(star); }
        size_t colon = spec.find(':'); std::string id = spec.substr(0, colon);
        std::string wire = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nSender: TestHost\r\nSecurityLevel: local\r\nID: " + id + "\r\n";
        if (colon != std::string::npos) {
            std::string refs = spec.substr(colon + 1); size_t pos = 0; unsigned index = 0;
            while (pos <= refs.size()) {
                size_t end = refs.find(',', pos);
                wire += "Reference" + std::to_string(index++) + ": " + refs.substr(pos, end == std::string::npos ? end : end - pos) + "\r\n";
                if (end == std::string::npos) break; pos = end + 1;
            }
        }
        wire += "\r\n";
        for (int n = 0; n < repeat; ++n) {
            unsigned char* response = nullptr; intptr_t length = 0;
            if (!request(reinterpret_cast<const unsigned char*>(wire.data()), wire.size(), &response, &length)) return 6;
            std::string text(reinterpret_cast<char*>(response), static_cast<size_t>(length)); release(response);
            if (repeat == 1 || text.find("204 No Content") == std::string::npos) {
                std::printf("---- %s\n%s\n", argv[i], text.c_str());
            }
        }
    }
    if (loaded) unload(); if (library) dlclose(library); return 0;
}
