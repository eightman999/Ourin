// SHIOLINK lifecycle stays on one thread: mruby state is owned by this child.
#include "dllmain.posix.cpp"
#include <iostream>

static bool line(std::string& result) {
    if (!std::getline(std::cin, result)) return false;
    if (!result.empty() && result.back() == '\r') result.pop_back();
    return result.size() <= 1048576;
}
static void* owned(const std::string& text) {
    void* result = malloc(text.size() + 1);
    if (result) memcpy(result, text.c_str(), text.size() + 1);
    return result;
}
int main() {
    bool loaded = false;
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
