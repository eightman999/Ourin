// Ourin ABI boundary for the unchanged upstream nashi SHIORI engine.
#include "shiori.h"
#include "util.h"
#include <mutex>
#include <memory>
#include <sys/stat.h>

namespace { std::mutex gate; std::unique_ptr<nashi::Shiori> engine; }
extern "C" {
bool shiori_load(const char* directory) {
    std::lock_guard<std::mutex> lock(gate);
    if (engine) engine->Unload();
    engine.reset();
    if (!directory) return false;
    struct stat info; if (stat(directory, &info) || !S_ISDIR(info.st_mode)) return false;
    try { engine.reset(new nashi::Shiori()); return engine->Load(nashi::Utf8ToWide(directory)); }
    catch (...) { engine.reset(); return false; }
}
bool shiori_request(const unsigned char* request, intptr_t size, unsigned char** response, intptr_t* length) {
    std::lock_guard<std::mutex> lock(gate);
    if (!engine || !request || size < 0 || size > 1048576 || !response || !length) return false;
    *response = nullptr; *length = 0;
    try {
        std::string result = engine->Request(std::string(reinterpret_cast<const char*>(request), static_cast<size_t>(size)));
        if (result.size() > 1048576) return false;
        auto output = static_cast<unsigned char*>(std::malloc(result.empty() ? 1 : result.size()));
        if (!output) return false;
        std::memcpy(output, result.data(), result.size()); *response = output; *length = static_cast<intptr_t>(result.size()); return true;
    } catch (...) { return false; }
}
void shiori_free(void* value) { std::free(value); }
void shiori_unload() { std::lock_guard<std::mutex> lock(gate); if (engine) engine->Unload(); engine.reset(); }
}
