// Deterministic real-process SHIOLINK peer; never accesses real ghost data.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    const char *mode = argc > 1 ? argv[1] : "normal";
    // Stop before reading *L or writing any marker: the parent must still reap us.
    if (!strcmp(mode, "startup-hang")) { signal(SIGTERM, SIG_IGN); for (;;) pause(); }
    char *line = NULL;
    size_t capacity = 0;
    char root[8192] = "";
    int requests = 0;
    while (getline(&line, &capacity, stdin) >= 0) {
        line[strcspn(line, "\r\n")] = 0;
        if (strncmp(line, "*L:", 3) == 0) {
            snprintf(root, sizeof(root), "%s", line + 3);
        } else if (strncmp(line, "*S:", 3) == 0) {
            if (!strcmp(mode, "bad-echo")) { printf("*S:wrong\r\n"); continue; }
            if (!strcmp(mode, "load-hang")) { signal(SIGTERM, SIG_IGN); for (;;) pause(); }
            printf("%s\r\n", line);
            char id[128] = "", reference[2048] = "", method[16] = "";
            int first = 1;
            while (getline(&line, &capacity, stdin) >= 0) {
                line[strcspn(line, "\r\n")] = 0;
                if (!line[0]) break;
                if (first) { sscanf(line, "%15s", method); first = 0; }
                if (!strncmp(line, "ID: ", 4)) snprintf(id, sizeof(id), "%s", line + 4);
                if (!strncmp(line, "Reference0: ", 12)) snprintf(reference, sizeof(reference), "%s", line + 12);
            }
            ++requests;
            if (!strcmp(mode, "hang") && requests > 1) { signal(SIGTERM, SIG_IGN); for (;;) pause(); }
            if (!strcmp(mode, "flood") && requests > 1) { for (;;) putchar('x'); }
            if (!strcmp(mode, "exit") && requests > 1) break;
            printf("SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: %s\r\nReference0: %s\r\nReference1: %s\r\nReference2: %s\r\n\r\n", reference[0] ? reference : "ready", root, method, id);
        } else if (!strcmp(line, "*U:")) {
            FILE *marker = fopen("unloaded.marker", "w");
            if (marker) { fputs("unloaded", marker); fclose(marker); }
            break;
        }
    }
    free(line);
    return 0;
}
