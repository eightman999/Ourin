#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <iconv.h>
#include <stdexcept>
#include <string>

namespace {

std::string convertEncoding(const std::string& input, const char* from, const char* to) {
    if (input.empty()) {
        return {};
    }

    iconv_t converter = iconv_open(to, from);
    if (converter == reinterpret_cast<iconv_t>(-1)) {
        throw std::runtime_error("iconv_open failed");
    }

    const char* source = input.data();
    size_t sourceRemaining = input.size();
    std::string output(input.size() * 4 + 32, '\0');
    char* destination = output.data();
    size_t destinationRemaining = output.size();

    while (sourceRemaining > 0) {
        char* mutableSource = const_cast<char*>(source);
        const size_t result = iconv(
            converter,
            &mutableSource,
            &sourceRemaining,
            &destination,
            &destinationRemaining
        );
        source = mutableSource;
        if (result != static_cast<size_t>(-1)) {
            continue;
        }
        if (errno != E2BIG) {
            iconv_close(converter);
            throw std::runtime_error("iconv conversion failed");
        }

        const size_t used = output.size() - destinationRemaining;
        output.resize(output.size() * 2);
        destination = output.data() + used;
        destinationRemaining = output.size() - used;
    }

    const size_t used = output.size() - destinationRemaining;
    iconv_close(converter);
    output.resize(used);
    return output;
}

} // namespace

std::string SJIStoUTF8(const std::string& source) {
    return convertEncoding(source, "CP932", "UTF-8");
}

std::string UTF8toSJIS(const std::string& source) {
    return convertEncoding(source, "UTF-8", "CP932");
}

std::string UTF8toSJISEscapingUnknown(const std::string& source) {
    std::string output;
    for (size_t index = 0; index < source.size();) {
        const unsigned char first = static_cast<unsigned char>(source[index]);
        size_t length = 1;
        uint32_t scalar = first;
        if ((first & 0xE0) == 0xC0) {
            length = 2;
            scalar = first & 0x1F;
        } else if ((first & 0xF0) == 0xE0) {
            length = 3;
            scalar = first & 0x0F;
        } else if ((first & 0xF8) == 0xF0) {
            length = 4;
            scalar = first & 0x07;
        }
        if (index + length > source.size()) {
            length = 1;
            scalar = first;
        }
        for (size_t offset = 1; offset < length; ++offset) {
            scalar = (scalar << 6) | (static_cast<unsigned char>(source[index + offset]) & 0x3F);
        }

        const std::string character = source.substr(index, length);
        try {
            output += convertEncoding(character, "UTF-8", "CP932");
        } catch (...) {
            char escaped[40];
            std::snprintf(escaped, sizeof(escaped), "?escape!unicode[0x%X]", scalar);
            output += escaped;
        }
        index += length;
    }
    return output;
}
