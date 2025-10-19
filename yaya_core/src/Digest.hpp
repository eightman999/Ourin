#pragma once
#include <string>

// Simple wrappers around MD5/SHA1/CRC32 implementations from yaya-shiori-500

std::string md5_hex(const std::string& data);
std::string sha1_hex(const std::string& data);
std::string crc32_hex(const std::string& data);

