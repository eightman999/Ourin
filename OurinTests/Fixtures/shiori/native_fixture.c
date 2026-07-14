#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char base_path[4096];

bool shiori_loadu(const char *path) {
    if (path == NULL) return false;
    snprintf(base_path, sizeof(base_path), "%s", path);
    char marker[8192];
    snprintf(marker, sizeof(marker), "%s/native_loaded_pid.marker", base_path);
    FILE *file = fopen(marker, "wb");
    if (file != NULL) {
        fprintf(file, "%d", getpid());
        fclose(file);
    }
    return true;
}

bool shiori_request(const unsigned char *input, size_t input_len,
                    unsigned char **output, size_t *output_len) {
    if (output == NULL || output_len == NULL) return false;
    char *request = calloc(input_len + 1, 1);
    if (request == NULL) return false;
    if (input != NULL && input_len > 0) memcpy(request, input, input_len);

    const char *response;
    if (strstr(request, "GET Version SHIORI/2.0") != NULL) {
        response = "SHIORI/2.6 200 OK\r\nCharset: UTF-8\r\n\r\n";
    } else if (strstr(request, "GET Sentence SHIORI/2.") != NULL) {
        response = "SHIORI/2.2 200 OK\r\nCharset: UTF-8\r\nSentence: \\h\\s0legacy-fixture\\e\r\n\r\n";
    } else {
        response = "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nReference2: native-fixture\r\nValue: \\h\\s0native-fixture\\e\r\n\r\n";
    }
    free(request);

    *output_len = strlen(response);
    *output = malloc(*output_len);
    if (*output == NULL) return false;
    memcpy(*output, response, *output_len);
    return true;
}

void shiori_free(unsigned char *pointer) {
    free(pointer);
}

void shiori_unloadu(void) {
    if (base_path[0] == '\0') return;
    char marker[8192];
    snprintf(marker, sizeof(marker), "%s/native_unloaded.marker", base_path);
    FILE *file = fopen(marker, "wb");
    if (file != NULL) {
        fputs("unloaded", file);
        fclose(file);
    }
}
