#include <cstdlib>
#include <cstring>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

extern "C" int satori_load(char* data, long length);
extern "C" int satori_unload(int id);
extern "C" char* satori_request(int id, char* data, long* length);

std::string SJIStoUTF8(const std::string& source);
std::string UTF8toSJIS(const std::string& source);
std::string UTF8toSJISEscapingUnknown(const std::string& source);

namespace {

using json = nlohmann::json;
int runtimeId = 0;
std::string runtimeProtocolVersion = "SHIORI/3.0";
bool escapeUnknown = false;

void configureSaoriSearchPath(const json& request) {
    if (!request.contains("saori_paths") || !request["saori_paths"].is_array()) {
        unsetenv("SAORI_FALLBACK_PATH");
        unsetenv("SAORI_FALLBACK_ALWAYS");
        return;
    }
    std::ostringstream joined;
    bool first = true;
    for (const auto& path : request["saori_paths"]) {
        if (!path.is_string() || path.get<std::string>().empty()) {
            continue;
        }
        if (!first) joined << ':';
        joined << path.get<std::string>();
        first = false;
    }
    const std::string value = joined.str();
    if (value.empty()) {
        unsetenv("SAORI_FALLBACK_PATH");
        unsetenv("SAORI_FALLBACK_ALWAYS");
    } else {
        setenv("SAORI_FALLBACK_PATH", value.c_str(), 1);
        setenv("SAORI_FALLBACK_ALWAYS", "1", 1);
    }
}

std::string ensureTrailingSlash(std::string path) {
    if (!path.empty() && path.back() != '/') {
        path.push_back('/');
    }
    return path;
}

std::string buildWire(const json& request) {
    const std::string method = request.value("method", "GET");
    std::ostringstream wire;
    wire << method << " " << runtimeProtocolVersion << "\r\n";
    wire << "Charset: Shift_JIS\r\n";
    wire << "Sender: Ourin\r\n";
    wire << "ID: " << request.value("id", "") << "\r\n";

    if (request.contains("headers") && request["headers"].is_object()) {
        for (const auto& [name, value] : request["headers"].items()) {
            if (name == "Charset" || name == "Sender" || name == "ID") {
                continue;
            }
            wire << name << ": " << value.get<std::string>() << "\r\n";
        }
    }
    if (request.contains("ref") && request["ref"].is_array()) {
        size_t index = 0;
        for (const auto& value : request["ref"]) {
            wire << "Reference" << index++ << ": " << value.get<std::string>() << "\r\n";
        }
    }
    wire << "\r\n";
    return wire.str();
}

std::string invokeSatori(const std::string& utf8Wire) {
    const std::string sjisWire = escapeUnknown
        ? UTF8toSJISEscapingUnknown(utf8Wire)
        : UTF8toSJIS(utf8Wire);
    long length = static_cast<long>(sjisWire.size());
    char* input = static_cast<char*>(std::malloc(sjisWire.size()));
    if (input == nullptr && !sjisWire.empty()) {
        throw std::bad_alloc();
    }
    if (!sjisWire.empty()) {
        std::memcpy(input, sjisWire.data(), sjisWire.size());
    }
    char* response = satori_request(runtimeId, input, &length);
    if (response == nullptr) {
        return {};
    }
    std::string sjisResponse(response, static_cast<size_t>(length));
    std::free(response);
    return SJIStoUTF8(sjisResponse);
}

json parseResponse(const std::string& wire) {
    json response = {
        {"ok", false},
        {"status", 500},
        {"headers", json::object()},
        {"value", ""}
    };
    if (wire.empty()) {
        return response;
    }

    std::istringstream stream(wire);
    std::string line;
    if (!std::getline(stream, line)) {
        return response;
    }
    if (!line.empty() && line.back() == '\r') {
        line.pop_back();
    }
    const size_t firstSpace = line.find(' ');
    if (firstSpace == std::string::npos || line.rfind("SHIORI/", 0) != 0) {
        return response;
    }
    try {
        response["status"] = std::stoi(line.substr(firstSpace + 1, 3));
    } catch (...) {
        return response;
    }

    while (std::getline(stream, line)) {
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        if (line.empty()) {
            break;
        }
        const size_t separator = line.find(':');
        if (separator == std::string::npos) {
            continue;
        }
        std::string value = line.substr(separator + 1);
        if (!value.empty() && value.front() == ' ') {
            value.erase(value.begin());
        }
        const std::string name = line.substr(0, separator);
        response["headers"][name] = value;
        if (name == "Value") {
            response["value"] = value;
        }
    }
    // okはSHIORI statusではなく、通信と応答解析が完了したことを表す。
    response["ok"] = true;
    return response;
}

json loadRuntime(const json& request) {
    if (runtimeId != 0) {
        satori_unload(runtimeId);
        runtimeId = 0;
    }

    const std::string root = ensureTrailingSlash(request.value("ghost_root", ""));
    if (root.empty()) {
        return {{"ok", false}, {"status", 400}, {"headers", json::object()}, {"value", "ghost_root is required"}};
    }
    char* input = static_cast<char*>(std::malloc(root.size()));
    if (input == nullptr && !root.empty()) {
        throw std::bad_alloc();
    }
    std::memcpy(input, root.data(), root.size());
    runtimeProtocolVersion = request.value("protocol_version", "SHIORI/3.0");
    if (runtimeProtocolVersion.rfind("SHIORI/", 0) != 0) {
        runtimeProtocolVersion = "SHIORI/3.0";
    }
    escapeUnknown = request.value("escape_unknown", false);
    configureSaoriSearchPath(request);
    runtimeId = satori_load(input, static_cast<long>(root.size()));
    if (runtimeId <= 0) {
        runtimeId = 0;
        return {{"ok", false}, {"status", 500}, {"headers", json::object()}, {"value", "satori_load failed"}};
    }

    const std::string probe = invokeSatori("GET " + runtimeProtocolVersion + "\r\nCharset: Shift_JIS\r\nSender: Ourin\r\nID: version\r\n\r\n");
    if (probe.rfind("SHIORI/", 0) != 0) {
        satori_unload(runtimeId);
        runtimeId = 0;
        return {{"ok", false}, {"status", 500}, {"headers", json::object()}, {"value", "post-load SHIORI probe failed"}};
    }
    return {{"ok", true}, {"status", 200}, {"headers", json::object()}, {"value", ""}};
}

json dispatch(const json& request) {
    const std::string command = request.value("cmd", "");
    if (command == "ping") {
        return {{"ok", true}, {"status", 200}, {"headers", json::object()}, {"value", "pong"}};
    }
    if (command == "load") {
        return loadRuntime(request);
    }
    if (command == "request") {
        if (runtimeId == 0) {
            return {{"ok", false}, {"status", 503}, {"headers", json::object()}, {"value", "not loaded"}};
        }
        return parseResponse(invokeSatori(buildWire(request)));
    }
    if (command == "unload") {
        if (runtimeId != 0) {
            satori_unload(runtimeId);
            runtimeId = 0;
        }
        return {{"ok", true}, {"status", 200}, {"headers", json::object()}, {"value", ""}};
    }
    return {{"ok", false}, {"status", 400}, {"headers", json::object()}, {"value", "unknown command"}};
}

} // namespace

int main() {
    std::ios::sync_with_stdio(false);
    std::string line;
    while (std::getline(std::cin, line)) {
        json response;
        try {
            response = dispatch(json::parse(line));
        } catch (const std::exception& error) {
            response = {{"ok", false}, {"status", 500}, {"headers", json::object()}, {"value", error.what()}};
        }
        std::cout << response.dump() << '\n' << std::flush;
    }
    if (runtimeId != 0) {
        satori_unload(runtimeId);
    }
    return 0;
}
