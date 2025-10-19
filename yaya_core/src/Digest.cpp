#include "Digest.hpp"
#include <sstream>
#include <iomanip>
#include <vector>

extern "C" {
#include "../third_party/yaya/md5.h"
#include "../third_party/yaya/sha1.h"
#include "../third_party/yaya/crc32.h"
}

static std::string to_hex(const unsigned char* bytes, size_t len) {
    std::ostringstream oss;
    oss << std::hex << std::setfill('0');
    for (size_t i = 0; i < len; ++i) {
        oss << std::setw(2) << static_cast<int>(bytes[i]);
    }
    return oss.str();
}

std::string md5_hex(const std::string& data) {
    MD5_CTX ctx;
    unsigned char digest[16];
    MD5Init(&ctx);
    MD5Update(&ctx, (unsigned char*)const_cast<char*>(data.data()), static_cast<unsigned int>(data.size()));
    MD5Final(digest, &ctx);
    return to_hex(digest, sizeof(digest));
}

std::string sha1_hex(const std::string& data) {
    SHA1Context ctx;
    uint8_t digest[SHA1HashSize];
    SHA1Reset(&ctx);
    SHA1Input(&ctx, reinterpret_cast<const uint8_t*>(data.data()), static_cast<unsigned int>(data.size()));
    SHA1Result(&ctx, digest);
    return to_hex(digest, sizeof(digest));
}

std::string crc32_hex(const std::string& data) {
    unsigned long crc = update_crc32(reinterpret_cast<const unsigned char*>(data.data()), static_cast<unsigned int>(data.size()), 0);
    unsigned char out[4] = {
        static_cast<unsigned char>((crc >> 24) & 0xFF),
        static_cast<unsigned char>((crc >> 16) & 0xFF),
        static_cast<unsigned char>((crc >> 8) & 0xFF),
        static_cast<unsigned char>((crc) & 0xFF)
    };
    return to_hex(out, sizeof(out));
}
