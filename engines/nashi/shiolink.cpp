// Ourin process boundary. The real nashi interpreter is private to each child.
#include "shiori.h"
#include "util.h"
#include <iostream>
#include <memory>
#include <sys/stat.h>

namespace {
constexpr size_t limit = 1048576;
bool line(std::string& result) {
    if (!std::getline(std::cin, result)) return false;
    if (!result.empty() && result.back() == '\r') result.pop_back();
    if (result.size() > limit) throw std::runtime_error("SHIOLINK line exceeds limit");
    return true;
}
}
int main() {
    std::unique_ptr<nashi::Shiori> engine;
    int status = 0;
    try {
        std::string command;
        while (line(command)) {
            if (command.compare(0, 3, "*L:") == 0) {
                if (engine) throw std::runtime_error("Duplicate load");
                std::string directory = command.substr(3);
                struct stat info;
                if (stat(directory.c_str(), &info) || !S_ISDIR(info.st_mode)) throw std::runtime_error("Load directory is missing");
                engine.reset(new nashi::Shiori());
                if (!engine->Load(nashi::Utf8ToWide(directory))) throw std::runtime_error("nashi load failed");
            } else if (command.compare(0, 3, "*S:") == 0) {
                if (!engine) throw std::runtime_error("Request before load");
                std::cout << command << "\r\n" << std::flush;
                std::string request, part;
                bool complete = false;
                while (line(part)) {
                    request += part + "\r\n";
                    if (request.size() > limit) throw std::runtime_error("SHIORI request exceeds limit");
                    if (part.empty()) { complete = true; break; }
                }
                if (!complete) break; // EOF still follows the upstream unload/save path.
                std::string response = engine->Request(request);
                if (response.size() > limit) throw std::runtime_error("SHIORI response exceeds limit");
                std::cout << response << std::flush;
            } else if (command == "*U:") {
                break;
            } else {
                throw std::runtime_error("Unknown SHIOLINK command");
            }
        }
    } catch (const std::exception& error) {
        std::cerr << "[nashi macOS] " << error.what() << '\n'; status = 1;
    } catch (...) {
        std::cerr << "[nashi macOS] native engine failed\n"; status = 1;
    }
    if (engine) engine->Unload();
    return status;
}
