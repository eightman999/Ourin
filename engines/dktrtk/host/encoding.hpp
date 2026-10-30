#pragma once
#include <cstddef>
#include <string>
// Source sections always use AngelScript's documented UTF-8 encoding.
bool OurinValidateSourceUTF8(const char* data, size_t length);
bool OurinTranscode(std::string& text, const char* to, const char* from);
bool OurinRewriteCharset(std::string& frame, const char* expected, const char* replacement);
