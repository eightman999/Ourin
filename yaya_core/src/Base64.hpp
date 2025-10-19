#pragma once
#include <string>

// Base64 encoder/decoder adapted from yaya-shiori-500 misc.cpp
namespace Base64 {
    std::string encode(const std::string& input);
    std::string decode(const std::string& input);
}

