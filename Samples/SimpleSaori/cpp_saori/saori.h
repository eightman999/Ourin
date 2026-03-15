#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t load(const char* module_dir_utf8);
void unload(void);
const uint8_t* request(const uint8_t* req, int req_len, int* res_len);

#ifdef __cplusplus
}
#endif

