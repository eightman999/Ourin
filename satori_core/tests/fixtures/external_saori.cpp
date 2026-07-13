#include <cstdlib>
#include <cstring>
#include <string>

extern "C" bool load(char* directory, long) {
    std::free(directory);
    return true;
}

extern "C" bool unload() {
    return true;
}

extern "C" char* request(char* input, long* length) {
    std::string requestText;
    if (input != nullptr && length != nullptr && *length > 0) {
        requestText.assign(input, static_cast<std::size_t>(*length));
    }
    std::free(input);

    const bool version = requestText.rfind("GET Version SAORI/1.0", 0) == 0;
    const std::string response = version
        ? "SAORI/1.0 200 OK\r\nCharset: Shift_JIS\r\n\r\n"
        : "SAORI/1.0 200 OK\r\nCharset: Shift_JIS\r\nResult: external-saori-ok\r\nValue0: fixture-value\r\n\r\n";
    char* output = static_cast<char*>(std::malloc(response.size()));
    if (output == nullptr) return nullptr;
    std::memcpy(output, response.data(), response.size());
    if (length != nullptr) *length = static_cast<long>(response.size());
    return output;
}
