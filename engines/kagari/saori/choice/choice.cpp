// Ourin independent implementation of the documented choice SAORI operation.
// Copyright (c) 2026 Ourin contributors. SPDX-License-Identifier: MIT
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>

extern "C" int load(char* directory, long) { std::free(directory); return 1; }
extern "C" int unload() { return 1; }

static std::string trim(std::string value) {
    const auto first = value.find_first_not_of(" \t");
    if (first == std::string::npos) return {};
    return value.substr(first, value.find_last_not_of(" \t") - first + 1);
}
static std::string execute(const std::string& input) {
    const auto end = input.find("\r\n\r\n");
    const auto first = input.find("\r\n");
    if (end == std::string::npos || first == std::string::npos)
        return "SAORI/1.0 400 Bad Request\r\n\r\n";
    const auto method = input.substr(0, first);
    std::map<std::string, std::string> headers;
    for (auto pos = first + 2; pos < end;) {
        const auto next = input.find("\r\n", pos);
        const auto colon = input.find(':', pos);
        if (next == std::string::npos || colon >= next)
            return "SAORI/1.0 400 Bad Request\r\n\r\n";
        const auto key = input.substr(pos, colon - pos);
        if (!headers.emplace(key, trim(input.substr(colon + 1, next - colon - 1))).second)
            return "SAORI/1.0 400 Bad Request\r\n\r\n";
        pos = next + 2;
    }
    const auto charset = headers.count("Charset") ? headers.at("Charset") : "Shift_JIS";
    // Argument bytes are never transcoded; the selected value retains its encoding.
    const auto prefix = "SAORI/1.0 200 OK\r\nCharset: " + charset + "\r\nResult: ";
    if (method == "GET Version SAORI/1.0")
        return prefix + "Ourin choice compatibility 1.0\r\n\r\n";
    if (method != "EXECUTE SAORI/1.0")
        return "SAORI/1.0 400 Bad Request\r\n\r\n";
    std::vector<std::string> arguments;
    for (size_t index = 0; index < headers.size(); ++index) {
        const auto found = headers.find("Argument" + std::to_string(index));
        if (found == headers.end()) break;
        arguments.push_back(found->second);
    }
    size_t argumentHeaders = 0;
    for (const auto& header : headers)
        if (header.first.rfind("Argument", 0) == 0) ++argumentHeaders;
    if (arguments.empty() || argumentHeaders != arguments.size())
        return "SAORI/1.0 400 Bad Request\r\n\r\n";
    return prefix + arguments[arc4random_uniform(static_cast<uint32_t>(arguments.size()))] + "\r\n\r\n";
}
extern "C" char* request(char* input, long* length) {
    std::string response;
    try {
        response = input && length && *length >= 0 && *length <= 1024 * 1024
            ? execute(std::string(input, static_cast<size_t>(*length)))
            : "SAORI/1.0 400 Bad Request\r\n\r\n";
    } catch (...) { response = "SAORI/1.0 500 Internal Server Error\r\n\r\n"; }
    std::free(input);
    if (!length) return nullptr;
    auto* output = static_cast<char*>(std::malloc(response.size() + 1));
    if (!output) { *length = 0; return nullptr; }
    std::memcpy(output, response.c_str(), response.size() + 1);
    *length = static_cast<long>(response.size());
    return output;
}
