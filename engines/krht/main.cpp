// SHIOLINK lifecycle stays on one thread: Tcl interpreters are thread-affine.
#include "dllmain.posix.cpp"
#include <iostream>
#ifdef OURIN_KRHT_BUNDLED_TCL
#include <mach-o/dyld.h>
#include <vector>
#endif

static bool line(std::string& result) {
    result.clear();
    char c;
    while (std::cin.get(c)) {
        if (c == '\n') break;
        if (result.size() >= 1048576) { std::cin.setstate(std::ios::failbit); return false; }
        result.push_back(c);
    }
    if (!std::cin) return false;
    if (!result.empty() && result.back() == '\r') result.pop_back();
    return result.size() <= 1048576;
}
static void* owned(const std::string& text) {
    void* result = malloc(text.size() + 1);
    if (result) memcpy(result, text.c_str(), text.size() + 1);
    return result;
}
int main(int, char** argv) {
#ifdef OURIN_KRHT_BUNDLED_TCL
    uint32_t size = 0;
    _NSGetExecutablePath(nullptr, &size);
    std::vector<char> executable(size);
    if (_NSGetExecutablePath(executable.data(), &size) != 0) return 10;
    char* resolved = realpath(executable.data(), nullptr);
    if (!resolved) return 10;
    std::string directory(resolved); free(resolved);
    directory.erase(directory.find_last_of('/'));
    const std::string library = directory + "/lib/tcl9.1";
    if (setenv("TCL_LIBRARY", library.c_str(), 1) != 0) return 10;
#endif
    Tcl_FindExecutable(argv[0]);
    struct Lifetime {
        bool loaded = false;
        ~Lifetime() {
            if (loaded) { unload(); interp = nullptr; }
            else if (interp) { Tcl_DeleteInterp(interp); interp = nullptr; }
            Tcl_Finalize();
        }
    } lifetime;
    bool& loaded = lifetime.loaded;
    std::string command;
    while (line(command)) {
        if (command.rfind("*L:", 0) == 0) {
            if (loaded) return 2;
            const std::string directory = command.substr(3);
            void* path = owned(directory);
            if (!path || !load(path, static_cast<long>(directory.size()))) return 3;
            loaded = true;
        } else if (command == "*U:") {
            const bool success = !loaded || unload() != 0;
            loaded = false; interp = nullptr;
            return success ? 0 : 4;
        } else if (command.rfind("*S:", 0) == 0 && loaded) {
            std::cout << command << "\r\n" << std::flush;
            std::string wire, part;
            bool complete = false;
            while (line(part)) {
                wire += part + "\r\n";
                if (wire.size() > 1048576) return 5;
                if (part.empty()) { complete = true; break; }
            }
            if (!complete) return 6;
            long length = static_cast<long>(wire.size());
            void* input = owned(wire);
            if (!input) return 7;
            char* response = static_cast<char*>(request(input, &length));
            if (!response || length <= 0 || length > 1048576) { free(response); return 8; }
            // Upstream includes its C terminator in the reported buffer length.
            if (response[length - 1] == '\0') --length;
            std::cout.write(response, length);
            std::cout.flush();
            free(response);
        } else return 9;
    }
    return 0;
}
