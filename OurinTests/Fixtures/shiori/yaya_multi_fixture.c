#ifdef OURIN_YAYA_MULTI_FIXTURE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    long id;
    unsigned requests;
    char directory[4096];
} Session;
static Session sessions[8];

long multi_loadu(void *input, long length) {
    if (!input || length <= 0 || length >= 4096) { free(input); return 0; }
#ifdef FAIL_LOAD
    free(input);
    return 0;
#endif
    for (int i = 0; i < 8; ++i) {
        if (sessions[i].id) continue;
        sessions[i].id = 0x100000001L + i;
        sessions[i].requests = 0;
        memcpy(sessions[i].directory, input, (size_t)length);
        sessions[i].directory[length] = 0;
        free(input);
        return sessions[i].id;
    }
    free(input);
    return 0;
}

void *multi_request(long id, void *input, long *length) {
    int notify = input && *length >= 7 && memcmp(input, "NOTIFY ", 7) == 0;
    free(input);
    for (int i = 0; i < 8; ++i) {
        if (sessions[i].id != id || id <= 0) continue;
        char response[512];
        if (notify) {
            snprintf(response, sizeof(response), "SHIORI/3.0 204 No Content\r\n\r\n");
        } else {
            snprintf(response, sizeof(response),
                     "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: instance-%ld:%u\r\n\r\n",
                     id, ++sessions[i].requests);
        }
        *length = (long)strlen(response);
        void *result = malloc((size_t)*length);
        if (result) memcpy(result, response, (size_t)*length);
        return result;
    }
    *length = 0;
    return NULL;
}

int multi_unload(long id) {
    for (int i = 0; i < 8; ++i) {
        if (sessions[i].id != id || id <= 0) continue;
        char path[8192];
        snprintf(path, sizeof(path), "%sunloaded.marker", sessions[i].directory);
        FILE *file = fopen(path, "w");
        if (file) { fputs("unloaded", file); fclose(file); }
        sessions[i].id = 0;
        return 1;
    }
    return 0;
}

/* Selecting YAYA's legacy global VM would invalidate isolation between ghosts. */
int loadu(void *input, long length) { (void)input; (void)length; abort(); }
void *request(void *input, long *length) { (void)input; (void)length; abort(); }
int unload(void) { abort(); }
#endif
