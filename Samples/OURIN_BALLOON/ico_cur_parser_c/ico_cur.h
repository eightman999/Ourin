
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
    int hotspot_x;   // for CUR (ignored for ICO)
    int hotspot_y;   // for CUR (ignored for ICO)
    bool is_cursor;
    const uint8_t* png_data;
    size_t png_size;
    uint8_t* rgba;   // RGBA8, width*height*4 bytes
} OurinIcoCurImage;

bool ourin_icocur_parse_best(const uint8_t* data, size_t size, OurinIcoCurImage* img);

#ifdef __cplusplus
} // extern "C"
#endif
