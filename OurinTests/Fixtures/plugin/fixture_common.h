#ifndef OURIN_PLUGIN_FIXTURE_COMMON_H
#define OURIN_PLUGIN_FIXTURE_COMMON_H

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#ifdef OURIN_PLUGIN_FIXTURE_BUILD
#define OURIN_FIXTURE_SYMBOL(name) name
#else
#define OURIN_FIXTURE_JOIN2(a, b) a##b
#define OURIN_FIXTURE_JOIN(a, b) OURIN_FIXTURE_JOIN2(a, b)
#define OURIN_FIXTURE_SYMBOL(name) OURIN_FIXTURE_JOIN(OURIN_FIXTURE_PREFIX, name)
#endif

#define OURIN_FIXTURE_EXPORT __attribute__((visibility("default")))

static int ourin_fixture_lower(int c) {
    return (c >= 'A' && c <= 'Z') ? (c + ('a' - 'A')) : c;
}

static int ourin_fixture_header_name_equals(const unsigned char *line, size_t line_len, const char *key) {
    size_t key_len = strlen(key);
    if (line_len <= key_len || line[key_len] != ':') {
        return 0;
    }
    for (size_t i = 0; i < key_len; i++) {
        if (ourin_fixture_lower(line[i]) != ourin_fixture_lower((unsigned char)key[i])) {
            return 0;
        }
    }
    return 1;
}

static int ourin_fixture_find_header(
    const unsigned char *buf,
    size_t len,
    const char *key,
    const unsigned char **value,
    size_t *value_len
) {
    size_t pos = 0;
    while (pos < len) {
        size_t line_end = pos;
        while (line_end < len && buf[line_end] != '\r' && buf[line_end] != '\n') {
            line_end++;
        }

        if (line_end == pos) {
            return 0;
        }

        size_t line_len = line_end - pos;
        if (ourin_fixture_header_name_equals(buf + pos, line_len, key)) {
            size_t start = pos + strlen(key) + 1;
            while (start < line_end && (buf[start] == ' ' || buf[start] == '\t')) {
                start++;
            }
            size_t end = line_end;
            while (end > start && (buf[end - 1] == ' ' || buf[end - 1] == '\t')) {
                end--;
            }
            *value = buf + start;
            *value_len = end - start;
            return 1;
        }

        pos = line_end;
        while (pos < len && (buf[pos] == '\r' || buf[pos] == '\n')) {
            pos++;
        }
    }
    return 0;
}

static int ourin_fixture_value_equals_ascii(const unsigned char *value, size_t value_len, const char *expected) {
    size_t expected_len = strlen(expected);
    if (value_len != expected_len) {
        return 0;
    }
    return memcmp(value, expected, expected_len) == 0;
}

static int ourin_fixture_header_equals_ascii(
    const unsigned char *buf,
    size_t len,
    const char *key,
    const char *expected
) {
    const unsigned char *value = NULL;
    size_t value_len = 0;
    if (!ourin_fixture_find_header(buf, len, key, &value, &value_len)) {
        return 0;
    }
    return ourin_fixture_value_equals_ascii(value, value_len, expected);
}

static const unsigned char *ourin_fixture_static_response(const char *text, size_t *out_len) {
    *out_len = strlen(text);
    return (const unsigned char *)text;
}

static const unsigned char *ourin_fixture_response_with_value(
    const char *prefix,
    const unsigned char *value,
    size_t value_len,
    const char *suffix,
    size_t *out_len
) {
    size_t prefix_len = strlen(prefix);
    size_t suffix_len = strlen(suffix);
    size_t total = prefix_len + value_len + suffix_len;
    unsigned char *out = (unsigned char *)malloc(total + 1);
    if (!out) {
        *out_len = 0;
        return NULL;
    }
    memcpy(out, prefix, prefix_len);
    memcpy(out + prefix_len, value, value_len);
    memcpy(out + prefix_len + value_len, suffix, suffix_len);
    out[total] = 0;
    *out_len = total;
    return out;
}

#define OURIN_FIXTURE_DECLARE_LIFECYCLE() \
    OURIN_FIXTURE_EXPORT int OURIN_FIXTURE_SYMBOL(load)(const char *plugin_dir_utf8) { \
        (void)plugin_dir_utf8; \
        return 0; \
    } \
    OURIN_FIXTURE_EXPORT int OURIN_FIXTURE_SYMBOL(loadu)(const char *plugin_dir_utf8) { \
        (void)plugin_dir_utf8; \
        return 0; \
    } \
    OURIN_FIXTURE_EXPORT void OURIN_FIXTURE_SYMBOL(unload)(void) {} \
    OURIN_FIXTURE_EXPORT void OURIN_FIXTURE_SYMBOL(plugin_free)(void *p) { \
        free(p); \
    }

#endif
