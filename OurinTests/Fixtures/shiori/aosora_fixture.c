#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Exercise LP64 instance IDs: using KAGARI's int32 signature truncates this ID.
static const long instance = 0x100000003L;
static int loaded;
long aosora_load(char *path, long len) {
    int ok = path && len > 0 && strstr(path, "reject") == NULL && !loaded;
    free(path);
    loaded = ok;
    return ok ? instance : 0;
}
int aosora_unload(long id) {
    if (id != instance || !loaded) return 0;
    loaded = 0;
    return 1;
}
char *aosora_request(long id, char *req, long *len) {
    free(req);
    if (id != instance || !loaded) { *len = 0; return NULL; }
    const char *response = "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: aosora-long-id\r\n\r\n";
    *len = (long)strlen(response);
    return strdup(response);
}
