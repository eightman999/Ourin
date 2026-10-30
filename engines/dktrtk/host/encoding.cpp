// Ourin-owned strict byte conversion at the optional process-host boundary.
#include "encoding.hpp"
#include <iconv.h>
#include <cerrno>
#include <cstring>
#include <algorithm>
#include <cctype>
#include <cstdio>
bool OurinTranscode(std::string& text, const char* to, const char* from) {
    iconv_t converter = iconv_open(to, from);
    if (converter == reinterpret_cast<iconv_t>(-1)) return false;
    std::string result;
    char* source = text.empty() ? nullptr : &text[0];
    size_t remaining = text.size();
    bool valid = true;
    while (remaining) {
        char buffer[4096]; char* output = buffer; size_t available = sizeof(buffer);
        size_t status = iconv(converter, &source, &remaining, &output, &available);
        result.append(buffer, sizeof(buffer) - available);
        if (status == static_cast<size_t>(-1)) {
            if (errno == E2BIG) continue;
            valid = false; break;
        }
        if (status != 0) { valid = false; break; } // No lossy substitutions.
    }
    iconv_close(converter);
    if (valid) text.swap(result);
    return valid;
}
bool OurinValidateSourceUTF8(const char* data, size_t length) {
    std::string source(data, length);
    bool valid = OurinTranscode(source, "UTF-8", "UTF-8");
    if (!valid) std::fputs("dktrtk: source must be UTF-8; legacy CP932 source is unsupported\n", stderr);
    return valid;
}
static std::string normalize(std::string text) {
    text.erase(std::remove_if(text.begin(), text.end(), [](unsigned char c) { return c == ' ' || c == '\t' || c == '_' || c == '-'; }), text.end());
    for (char& c : text) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    if (text == "cp932" || text == "windows31j" || text == "ms932") return "shiftjis";
    return text;
}
bool OurinRewriteCharset(std::string& frame, const char* expected, const char* replacement) {
    auto end = frame.find("\r\n\r\n");
    if (end == std::string::npos) return false;
    bool found = false;
    for (auto position = frame.find("\r\n") + 2; position < end;) {
        const auto next = frame.find("\r\n", position);
        const auto colon = frame.find(':', position);
        if (next == std::string::npos || colon >= next) return false;
        if (normalize(frame.substr(position, colon - position)) == "charset") {
            if (found || normalize(frame.substr(colon + 1, next - colon - 1)) != normalize(expected)) return false;
            frame.replace(colon + 1, next - colon - 1, std::string(" ") + replacement);
            // Charset occurs exactly once in compliant frames. Re-scan to validate duplicates.
            found = true;
            end = frame.find("\r\n\r\n");
            position = frame.find("\r\n", colon) + 2;
        } else position = next + 2;
    }
    return true;
}
