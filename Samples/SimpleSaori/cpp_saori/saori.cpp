#include "saori.h"
#include <string>

namespace {
std::string g_lastResponse;
std::string g_moduleDir;

std::string buildResponse(const std::string& value) {
  return "SAORI/1.0 200 OK\r\n"
         "Charset: UTF-8\r\n"
         "Result: 1\r\n"
         "Value: " + value + "\r\n"
         "\r\n";
}
} // namespace

int32_t load(const char* module_dir_utf8) {
  g_moduleDir = module_dir_utf8 ? module_dir_utf8 : "";
  return 1;
}

void unload(void) {
  g_lastResponse.clear();
  g_moduleDir.clear();
}

const uint8_t* request(const uint8_t* req, int req_len, int* res_len) {
  std::string requestText;
  if (req && req_len > 0) {
    requestText.assign(reinterpret_cast<const char*>(req), static_cast<size_t>(req_len));
  }

  std::string value = "Hello from C++ SAORI";
  if (requestText.find("Argument0:") != std::string::npos) {
    const auto pos = requestText.find("Argument0:");
    const auto lineEnd = requestText.find("\r\n", pos);
    const auto head = (lineEnd == std::string::npos) ? requestText.size() : lineEnd;
    value = "Echo " + requestText.substr(pos + 10, head - (pos + 10));
    while (!value.empty() && value[0] == ' ') value.erase(value.begin());
  }
  g_lastResponse = buildResponse(value);
  if (res_len) *res_len = static_cast<int>(g_lastResponse.size());
  return reinterpret_cast<const uint8_t*>(g_lastResponse.data());
}

