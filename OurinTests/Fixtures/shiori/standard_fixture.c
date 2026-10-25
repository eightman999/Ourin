#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#ifdef LENGTH32
typedef int32_t shiori_length;
#else
typedef long shiori_length;
#endif
static char directory[4096];
int load(void *input, shiori_length length) {
    if (!input || length <= 0 || (size_t)length >= sizeof(directory)) { free(input); return 0; }
    memcpy(directory, input, (size_t)length);
    directory[length] = 0;
    free(input);
#ifdef FAIL_LOAD
    return 0;
#endif
    char path[8192];
    snprintf(path, sizeof(path), "%sloaded.pid", directory);
    FILE *f = fopen(path, "w");
    if (!f) return 0;
    fprintf(f, "%d", getpid()); fclose(f);
    return 1;
}
void *request(void *input, shiori_length *length) {
    char *message = calloc((size_t)*length + 1, 1);
    memcpy(message, input, (size_t)*length);
    free(input);
    const char *response = strncmp(message, "NOTIFY ", 7) == 0
        ? "SHIORI/3.0 204 No Content\r\n\r\n"
        : "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: standard-fixture\r\n\r\n";
    free(message);
    *length = (shiori_length)strlen(response);
    void *output = malloc((size_t)*length);
    memcpy(output, response, (size_t)*length);
    return output;
}
int unload(void) {
    char path[8192]; snprintf(path, sizeof(path), "%sunloaded.marker", directory);
    FILE *f = fopen(path, "w"); if (f) { fputs("unloaded", f); fclose(f); }
    return 1;
}
