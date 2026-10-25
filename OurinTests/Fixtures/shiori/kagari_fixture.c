#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static char g_loaded_path[4096];

int kagari_load(char *path, long len) {
    if (!path || len <= 0 || len >= (long)sizeof(g_loaded_path)) {
        free(path);
        return -1;
    }
    memcpy(g_loaded_path, path, (size_t)len);
    g_loaded_path[len] = '\0';
    free(path);
    return 3;
}

int kagari_unload(int id) {
    if (id != 3) return -1;
    g_loaded_path[0] = '\0';
    return 0;
}

char *kagari_request(int id, char *req, long *len) {
    if (!req || !len || id != 3) {
        if (req) free(req);
        if (len) *len = 0;
        return NULL;
    }
    char *body = (char *)malloc((size_t)*len + 1);
    if (!body) {
        free(req);
        *len = 0;
        return NULL;
    }
    memcpy(body, req, (size_t)*len);
    body[*len] = '\0';
    free(req);
    const char *marker = "ID: OnBoot";
    int is_boot = strstr(body, marker) != NULL;
    const char *response = is_boot
        ? "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\n\r\nValue: kagari-fixture-boot\r\n"
        : "SHIORI/3.0 204 No Content\r\n\r\n";
    size_t out_len = strlen(response);
    char *out = (char *)calloc(out_len + 1, 1);
    if (!out) {
        *len = 0;
        return NULL;
    }
    memcpy(out, response, out_len);
    *len = (long)out_len;
    return out;
}
