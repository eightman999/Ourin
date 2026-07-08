#define OURIN_FIXTURE_PREFIX target_fixture_
#include "../fixture_common.h"

OURIN_FIXTURE_DECLARE_LIFECYCLE()

OURIN_FIXTURE_EXPORT const unsigned char *OURIN_FIXTURE_SYMBOL(request)(
    const unsigned char *buf,
    size_t len,
    size_t *out_len
) {
    if (ourin_fixture_header_equals_ascii(buf, len, "ID", "version")) {
        return ourin_fixture_static_response(
            "PLUGIN/2.0M 200 OK\r\n"
            "Charset: UTF-8\r\n"
            "Value: TargetFixture 1.0\r\n"
            "\r\n",
            out_len
        );
    }

    if (ourin_fixture_header_equals_ascii(buf, len, "ID", "OnTarget")) {
        return ourin_fixture_static_response(
            "PLUGIN/2.0M 200 OK\r\n"
            "Charset: UTF-8\r\n"
            "Target: Target Ghost\r\n"
            "Script: \\0targeted script\\e\r\n"
            "\r\n",
            out_len
        );
    }

    return ourin_fixture_static_response(
        "PLUGIN/2.0M 501 Not Implemented\r\n"
        "Charset: UTF-8\r\n"
        "\r\n",
        out_len
    );
}
