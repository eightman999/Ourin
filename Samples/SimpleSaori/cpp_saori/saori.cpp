#include "saori.h"
#include <cstdlib>
#include <cstring>
#include <string>

namespace {
std::string g_lastResponse;
std::string g_moduleDir;

std::string buildResponse(const std::string& value) {
  return "SAORI/1.0 200 OK\r\n"
         "Charset: UTF-8\r\n"
         "Result: 1\r\n"
         "Value0: " + value + "\r\n"
         "\r\n";
}
} // namespace

int32_t load(char* module_dir_utf8, long module_dir_len) {
  if (module_dir_utf8 && module_dir_len > 0) {
    g_moduleDir.assign(module_dir_utf8, static_cast<size_t>(module_dir_len));
  } else {
    g_moduleDir.clear();
  }
  std::free(module_dir_utf8);
  return 1;
}

int32_t unload(void) {
  g_lastResponse.clear();
  g_moduleDir.clear();
  return 1;
}

char* request(char* req, long* res_len) {
  std::string requestText;
  if (req && res_len && *res_len > 0) {
    requestText.assign(req, static_cast<size_t>(*res_len));
  }
  std::free(req);

  std::string value = "Hello from C++ SAORI";
  if (requestText.find("Argument0:") != std::string::npos) {
    const auto pos = requestText.find("Argument0:");
    const auto lineEnd = requestText.find("\r\n", pos);
    const auto head = (lineEnd == std::string::npos) ? requestText.size() : lineEnd;
    value = "Echo " + requestText.substr(pos + 10, head - (pos + 10));
    while (!value.empty() && value[0] == ' ') value.erase(value.begin());
  }
  g_lastResponse = buildResponse(value);
  auto* output = static_cast<char*>(std::malloc(g_lastResponse.size()));
  if (!output) {
    if (res_len) *res_len = 0;
    return nullptr;
  }
  std::memcpy(output, g_lastResponse.data(), g_lastResponse.size());
  if (res_len) *res_len = static_cast<long>(g_lastResponse.size());
  return output;
}
