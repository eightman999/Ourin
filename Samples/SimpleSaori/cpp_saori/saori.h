#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t load(char* module_dir_utf8, long module_dir_len);
int32_t unload(void);
char* request(char* req, long* res_len);

#ifdef __cplusplus
}
#endif
