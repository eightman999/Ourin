
#pragma once
#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int width;
    int height;
    size_t stride;     // bytes per row (>= width*4)
    uint8_t* rgba;     // RGBA8 buffer (malloc/free)
} OurinImage;

typedef bool (*OurinDecoderProbe)(const void* data, size_t len, const char* uti_hint);
typedef bool (*OurinDecoderDecode)(const void* data, size_t len, OurinImage* out_image, char** out_err);

typedef struct {
    int api_version;              // = 1
    const char* name;             // "MAG" / "PI" / "XBM" etc.
    OurinDecoderProbe probe;      // quick magic/UTI check
    OurinDecoderDecode decode;    // produce RGBA8 (caller frees out_image.rgba with free())
} OurinDecoderV1;

// Plugin must export this symbol
const OurinDecoderV1* ourin_get_decoder_v1(void);

#ifdef __cplusplus
}
#endif
