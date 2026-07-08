#define OURIN_FIXTURE_PREFIX property_fixture_
#include "../fixture_common.h"

static unsigned char property_value[256] = "initial-value";
static size_t property_value_len = sizeof("initial-value") - 1;

OURIN_FIXTURE_DECLARE_LIFECYCLE()

static int is_fixture_value_key(const unsigned char *buf, size_t len) {
    const unsigned char *key = NULL;
    size_t key_len = 0;
    if (!ourin_fixture_find_header(buf, len, "Reference0", &key, &key_len)) {
        return 0;
    }
    return ourin_fixture_value_equals_ascii(key, key_len, "fixture.value");
}

OURIN_FIXTURE_EXPORT const unsigned char *OURIN_FIXTURE_SYMBOL(request)(
    const unsigned char *buf,
    size_t len,
    size_t *out_len
) {
    if (ourin_fixture_header_equals_ascii(buf, len, "ID", "version")) {
        return ourin_fixture_static_response(
            "PLUGIN/2.0M 200 OK\r\n"
            "Charset: UTF-8\r\n"
            "Value: PropertyFixture 1.0\r\n"
            "\r\n",
            out_len
        );
    }

    if (ourin_fixture_header_equals_ascii(buf, len, "ID", "property.get")) {
        if (!is_fixture_value_key(buf, len)) {
            return ourin_fixture_static_response(
                "PLUGIN/2.0M 404 Not Found\r\n"
                "Charset: UTF-8\r\n"
                "\r\n",
                out_len
            );
        }
        return ourin_fixture_response_with_value(
            "PLUGIN/2.0M 200 OK\r\n"
            "Charset: UTF-8\r\n"
            "Value: ",
            property_value,
            property_value_len,
            "\r\n\r\n",
            out_len
        );
    }

    if (ourin_fixture_header_equals_ascii(buf, len, "ID", "property.set")) {
        const unsigned char *value = NULL;
        size_t value_len = 0;
        if (!is_fixture_value_key(buf, len) ||
            !ourin_fixture_find_header(buf, len, "Reference1", &value, &value_len)) {
            return ourin_fixture_static_response(
                "PLUGIN/2.0M 400 Bad Request\r\n"
                "Charset: UTF-8\r\n"
                "\r\n",
                out_len
            );
        }
        if (value_len >= sizeof(property_value)) {
            value_len = sizeof(property_value) - 1;
        }
        memcpy(property_value, value, value_len);
        property_value[value_len] = 0;
        property_value_len = value_len;
        return ourin_fixture_static_response(
            "PLUGIN/2.0M 200 OK\r\n"
            "Charset: UTF-8\r\n"
            "Value: OK\r\n"
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
