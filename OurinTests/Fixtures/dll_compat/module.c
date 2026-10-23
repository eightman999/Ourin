/* DLLCompatibilityTests 用の最小モジュール。
 * MODULE_UKAGAKA: Windows DLL と同じ load(h,len) / request(h,&len) 規約（入力は free、出力は malloc）。
 * MODULE_SAORI:   SAORI/1.0。GET Version の受信回数を EXECUTE の Result で返す。
 */
/* テストターゲットにも取り込まれるため、clang で個別ビルドするときだけ中身を有効にする。 */
#ifdef DLL_COMPAT_FIXTURE_BUILD
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define EXPORT __attribute__((visibility("default")))

static char g_load_path[1024];
static int g_version_count = 0;

static char *dup_response(const char *text, long *len) {
    size_t n = strlen(text);
    char *out = malloc(n);
    memcpy(out, text, n);
    *len = (long)n;
    return out;
}

EXPORT int load(void *h, long len) {
    size_t n = (size_t)len < sizeof(g_load_path) - 1 ? (size_t)len : sizeof(g_load_path) - 1;
    memcpy(g_load_path, h, n);
    g_load_path[n] = 0;
#if defined(MODULE_UKAGAKA) || defined(MODULE_SAORI)
    free(h); /* 共通 ABI: 引数領域はモジュールが解放する */
#endif
    return 1;
}

EXPORT int unload(void) { return 1; }

#if defined(MODULE_UKAGAKA)
EXPORT void *request(void *h, long *len) {
    char req[2048];
    size_t n = (size_t)*len < sizeof(req) - 1 ? (size_t)*len : sizeof(req) - 1;
    memcpy(req, h, n);
    req[n] = 0;
    free(h);
    char body[2048];
    if (strstr(req, "ID: OnLoadPath")) {
        snprintf(body, sizeof(body), "PLUGIN/2.0 200 OK\r\nCharset: UTF-8\r\nValue: %s\r\n\r\n", g_load_path);
    } else {
        snprintf(body, sizeof(body), "PLUGIN/2.0 200 OK\r\nCharset: UTF-8\r\nValue: ukagaka\r\n\r\n");
    }
    return dup_response(body, len);
}
/* HEADLINE の execute も同じ規約。 */
EXPORT void *execute(void *h, long *len) { return request(h, len); }
#elif defined(MODULE_SAORI)
EXPORT void *request(void *h, long *len) {
    char req[2048];
    size_t n = (size_t)*len < sizeof(req) - 1 ? (size_t)*len : sizeof(req) - 1;
    memcpy(req, h, n);
    req[n] = 0;
    free(h);
    char body[512];
    if (strncmp(req, "GET Version", 11) == 0) {
        g_version_count++;
        snprintf(body, sizeof(body), "SAORI/1.0 200 OK\r\nCharset: UTF-8\r\n\r\n");
    } else {
        snprintf(body, sizeof(body), "SAORI/1.0 200 OK\r\nCharset: UTF-8\r\nResult: %d\r\nValue0: %s\r\n\r\n",
                 g_version_count, g_load_path);
    }
    return dup_response(body, len);
}
#endif
#else
typedef int dll_compat_fixture_disabled;
#endif
