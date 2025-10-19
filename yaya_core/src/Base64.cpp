#include "Base64.hpp"
#include <string>

namespace Base64 {
    std::string encode(const std::string& input) {
        static const char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        std::string out;
        const unsigned char* p = reinterpret_cast<const unsigned char*>(input.data());
        int len = static_cast<int>(input.size());
        out.reserve(((len + 2) / 3) * 4);
        while (len > 0) {
            unsigned char b0 = *p; // first byte
            out.push_back(table[b0 >> 2]);
            if (len - 1 > 0) out.push_back(table[((b0 << 4) & 0x30) | ((*(p+1) >> 4) & 0x0F)]);
            else out.push_back(table[((b0 << 4) & 0x30)]);
            --len; ++p;
            if (len > 0) {
                unsigned char b1 = *p;
                if (len - 1 > 0) out.push_back(table[((b1 << 2) & 0x3C) | ((*(p+1) >> 6) & 0x03)]);
                else out.push_back(table[((b1 << 2) & 0x3C)]);
                ++p;
            } else {
                out.push_back('=');
            }
            out.push_back((--len > 0) ? table[*p & 0x3F] : '=');
            if (--len > 0) ++p;
        }
        return out;
    }

    std::string decode(const std::string& input) {
        static const unsigned char reverse_64[] = {
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,0,0,0,0,62,0,0,0,63,
            52,53,54,55,56,57,58,59,60,61,0,0,0,0,0,0,
            0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,
            15,16,17,18,19,20,21,22,23,24,25,0,0,0,0,0,
            0,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,
            41,42,43,44,45,46,47,48,49,50,51,0,0,0,0,0
        };
        std::string out;
        const unsigned char* p = reinterpret_cast<const unsigned char*>(input.data());
        size_t in_len = input.size();
        out.reserve((in_len / 4) * 3);
        while (*p != '=' && (p - reinterpret_cast<const unsigned char*>(input.data())) < (ptrdiff_t)in_len) {
            if (*p == '\0' || *(p+1) == '=') break;
            out.push_back(static_cast<char>(((reverse_64[*p & 0x7f] << 2) & 0xFC) | ((reverse_64[*(p+1) & 0x7f] >> 4) & 0x03)));
            ++p;
            if (*p == '\0' || *(p+1) == '=') break;
            out.push_back(static_cast<char>(((reverse_64[*p & 0x7f] << 4) & 0xF0) | ((reverse_64[*(p+1) & 0x7f] >> 2) & 0x0F)));
            ++p;
            if (*p == '\0' || *(p+1) == '=') break;
            out.push_back(static_cast<char>(((reverse_64[*p & 0x7f] << 6) & 0xC0) | (reverse_64[*(p+1) & 0x7f] & 0x3f)));
            ++p;
            if (*p == '\0' || *(p+1) == '=') break;
            ++p;
        }
        return out;
    }
}

