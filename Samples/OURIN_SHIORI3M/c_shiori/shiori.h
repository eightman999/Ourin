#pragma once
#include <stddef.h>
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
bool shiori_load(const char* dir_utf8);
void shiori_unload(void);
bool shiori_request(const unsigned char* req, size_t req_len,
                    unsigned char** res, size_t* res_len);
void shiori_free(unsigned char* p);
#ifdef __cplusplus
} // extern "C"
#endif
