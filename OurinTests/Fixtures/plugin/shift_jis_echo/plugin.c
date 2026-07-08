#define OURIN_FIXTURE_PREFIX shift_jis_echo_fixture_
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
            "Charset: Shift_JIS\r\n"
            "Value: ShiftJISEchoFixture 1.0\r\n"
            "\r\n",
            out_len
        );
    }

    if (ourin_fixture_header_equals_ascii(buf, len, "ID", "OnShiftJISEcho")) {
        const unsigned char *value = NULL;
        size_t value_len = 0;
        if (!ourin_fixture_find_header(buf, len, "Reference0", &value, &value_len)) {
            return ourin_fixture_static_response(
                "PLUGIN/2.0M 400 Bad Request\r\n"
                "Charset: Shift_JIS\r\n"
                "\r\n",
                out_len
            );
        }
        return ourin_fixture_response_with_value(
            "PLUGIN/2.0M 200 OK\r\n"
            "Charset: Shift_JIS\r\n"
            "Value: ",
            value,
            value_len,
            "\r\nX-Fixture: shift_jis_echo\r\n\r\n",
            out_len
        );
    }

    return ourin_fixture_static_response(
        "PLUGIN/2.0M 501 Not Implemented\r\n"
        "Charset: Shift_JIS\r\n"
        "\r\n",
        out_len
    );
}
