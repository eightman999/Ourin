/*
 * ScriptBridge — 他の伺か形式のスクリプトを解釈してさくらスクリプトにする PLUGIN/2.0M プラグイン。
 *
 * 対応するもの:
 *   - 里々（Satori）辞書の基本構文: ＊トーク / ＠単語群 / （単語群） / ：による話者切替 / ＃コメント
 *   - 華和梨（Kawari）辞書の基本構文: name : 単語 , 単語 / ${name} / # コメント / =kis〜=end は読み飛ばし
 *   - AYA / YAYA 辞書の基本構文: 関数名 { "候補" "候補" } / %(関数名) / 行コメントとブロックコメント
 *   - さくらスクリプトのテキスト（空行区切りのブロックから 1 つを再生）
 *   - 旧仕様タグを UKADOC の現行タグへ変換する後方互換（すべての出力に適用）
 *
 * ABI は SPEC_PLUGIN_2.0M の Ourin C ABI（request(buf,len,&out_len)、戻り値はモジュール所有）。
 */
#include <ctype.h>
#include <dirent.h>
#include <iconv.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define EXPORT __attribute__((visibility("default")))
#define SB_VERSION "ScriptBridge/1.0"
#define SB_MAX_DEPTH 16

/* ------------------------------------------------------------------ */
/* 可変長文字列                                                          */
/* ------------------------------------------------------------------ */

typedef struct {
    char *data;
    size_t len;
    size_t cap;
} sb_str;

static void str_reserve(sb_str *s, size_t extra) {
    if (s->len + extra + 1 <= s->cap) return;
    size_t cap = s->cap ? s->cap : 64;
    while (cap < s->len + extra + 1) cap *= 2;
    char *p = realloc(s->data, cap);
    if (!p) abort();
    s->data = p;
    s->cap = cap;
}

static void str_append_n(sb_str *s, const char *text, size_t n) {
    str_reserve(s, n);
    memcpy(s->data + s->len, text, n);
    s->len += n;
    s->data[s->len] = 0;
}

static void str_append(sb_str *s, const char *text) { str_append_n(s, text, strlen(text)); }

static void str_appendf(sb_str *s, const char *fmt, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n > 0) str_append_n(s, buf, (size_t)n < sizeof(buf) ? (size_t)n : sizeof(buf) - 1);
}

static void str_free(sb_str *s) {
    free(s->data);
    s->data = NULL;
    s->len = s->cap = 0;
}

static const char *str_cstr(sb_str *s) {
    if (!s->data) str_reserve(s, 0), s->data[0] = 0;
    return s->data;
}

static char *dup_n(const char *p, size_t n) {
    char *out = malloc(n + 1);
    memcpy(out, p, n);
    out[n] = 0;
    return out;
}

static int starts_with(const char *s, const char *prefix) { return strncmp(s, prefix, strlen(prefix)) == 0; }

static const char *skip_space(const char *p) {
    while (*p == ' ' || *p == '\t') p++;
    return p;
}

static char *trim_dup(const char *p, size_t n) {
    while (n && (*p == ' ' || *p == '\t')) p++, n--;
    while (n && (p[n - 1] == ' ' || p[n - 1] == '\t' || p[n - 1] == '\r')) n--;
    return dup_n(p, n);
}

/* ------------------------------------------------------------------ */
/* 乱数（Reference2 で種を固定できる）                                   */
/* ------------------------------------------------------------------ */

static uint64_t g_seed;
static int g_seeded;

static size_t pick(size_t count) {
    if (count == 0) return 0;
    if (!g_seeded) return (size_t)arc4random_uniform((uint32_t)count);
    g_seed = g_seed * 6364136223846793005ULL + 1442695040888963407ULL;
    return (size_t)((g_seed >> 33) % count);
}

/* ------------------------------------------------------------------ */
/* 辞書データ: 名前 → 候補リスト                                          */
/* ------------------------------------------------------------------ */

typedef struct {
    char *name;
    char **items;
    size_t count;
    size_t cap;
} sb_entry;

typedef struct {
    sb_entry *entries;
    size_t count;
    size_t cap;
} sb_dict;

static sb_entry *dict_find(sb_dict *d, const char *name) {
    for (size_t i = 0; i < d->count; i++)
        if (strcmp(d->entries[i].name, name) == 0) return &d->entries[i];
    return NULL;
}

static sb_entry *dict_get(sb_dict *d, const char *name) {
    sb_entry *e = dict_find(d, name);
    if (e) return e;
    if (d->count == d->cap) {
        d->cap = d->cap ? d->cap * 2 : 16;
        d->entries = realloc(d->entries, d->cap * sizeof(sb_entry));
    }
    e = &d->entries[d->count++];
    memset(e, 0, sizeof(*e));
    e->name = strdup(name);
    return e;
}

static void entry_add(sb_entry *e, char *item_owned) {
    if (e->count == e->cap) {
        e->cap = e->cap ? e->cap * 2 : 8;
        e->items = realloc(e->items, e->cap * sizeof(char *));
    }
    e->items[e->count++] = item_owned;
}

static void dict_free(sb_dict *d) {
    for (size_t i = 0; i < d->count; i++) {
        for (size_t j = 0; j < d->entries[i].count; j++) free(d->entries[i].items[j]);
        free(d->entries[i].items);
        free(d->entries[i].name);
    }
    free(d->entries);
    memset(d, 0, sizeof(*d));
}

static const char *dict_pick(sb_dict *d, const char *name) {
    sb_entry *e = dict_find(d, name);
    if (!e || e->count == 0) return NULL;
    return e->items[pick(e->count)];
}

/* ------------------------------------------------------------------ */
/* 文字コード: UTF-8 として不正なら CP932 とみなして UTF-8 へ変換            */
/* ------------------------------------------------------------------ */

static int is_valid_utf8(const unsigned char *s, size_t n) {
    size_t i = 0;
    while (i < n) {
        unsigned char c = s[i];
        size_t extra;
        if (c < 0x80) extra = 0;
        else if ((c & 0xE0) == 0xC0) extra = 1;
        else if ((c & 0xF0) == 0xE0) extra = 2;
        else if ((c & 0xF8) == 0xF0) extra = 3;
        else return 0;
        if (i + extra >= n && extra) return 0;
        for (size_t k = 1; k <= extra; k++)
            if ((s[i + k] & 0xC0) != 0x80) return 0;
        i += extra + 1;
    }
    return 1;
}

static char *to_utf8(const char *bytes, size_t n) {
    if (n >= 3 && (unsigned char)bytes[0] == 0xEF && (unsigned char)bytes[1] == 0xBB && (unsigned char)bytes[2] == 0xBF) {
        bytes += 3;
        n -= 3;
    }
    if (is_valid_utf8((const unsigned char *)bytes, n)) return dup_n(bytes, n);
    iconv_t cd = iconv_open("UTF-8", "CP932");
    if (cd == (iconv_t)-1) return dup_n(bytes, n);
    size_t cap = n * 3 + 1;
    char *out = malloc(cap);
    char *in = (char *)bytes, *o = out;
    size_t inleft = n, outleft = cap - 1;
    while (inleft > 0) {
        if (iconv(cd, &in, &inleft, &o, &outleft) == (size_t)-1) {
            if (outleft == 0) break;
            *o++ = '?';
            outleft--;
            in++;
            inleft--;
        }
    }
    *o = 0;
    iconv_close(cd);
    return out;
}

static char *read_file_utf8(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    sb_str raw = {0};
    char buf[8192];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0) str_append_n(&raw, buf, n);
    fclose(f);
    char *text = to_utf8(raw.data ? raw.data : "", raw.len);
    str_free(&raw);
    return text;
}

/* 行単位の走査（CRLF / LF） */
typedef struct {
    const char *p;
} line_iter;

static int next_line(line_iter *it, const char **line, size_t *len) {
    if (!it->p || !*it->p) return 0;
    const char *start = it->p;
    const char *end = strchr(start, '\n');
    size_t n = end ? (size_t)(end - start) : strlen(start);
    *line = start;
    *len = (n && start[n - 1] == '\r') ? n - 1 : n;
    it->p = end ? end + 1 : start + n;
    return 1;
}

/* ------------------------------------------------------------------ */
/* 後方互換: 旧仕様タグ → 現行タグ（UKADOC さくらスクリプトリストの[旧仕様]） */
/* ------------------------------------------------------------------ */

static size_t read_bracket(const char *p, char **content) {
    /* p は '[' を指す。対応する ']' までを返す（\] はエスケープ）。戻り値は消費バイト数。 */
    if (*p != '[') return 0;
    const char *q = p + 1;
    sb_str out = {0};
    while (*q && *q != ']') {
        if (*q == '\\' && q[1] == ']') {
            str_append_n(&out, "\\]", 2);
            q += 2;
            continue;
        }
        str_append_n(&out, q, 1);
        q++;
    }
    if (*q != ']') {
        str_free(&out);
        return 0;
    }
    *content = out.data ? out.data : strdup("");
    return (size_t)(q - p) + 1;
}

/* \![move,x,y,time,base,base-offset,move-offset] → --key=value 形式。新形式（--で始まる）はそのまま。 */
static int convert_legacy_move(const char *args, sb_str *out) {
    const char *cmd_end = strchr(args, ',');
    if (!cmd_end) return 0;
    size_t cmd_len = (size_t)(cmd_end - args);
    if (!((cmd_len == 4 && starts_with(args, "move")) || (cmd_len == 9 && starts_with(args, "moveasync")))) return 0;
    const char *rest = cmd_end + 1;
    if (starts_with(skip_space(rest), "--") || starts_with(skip_space(rest), "cancel")) return 0;

    static const char *keys[] = {"--X=", "--Y=", "--time=", "--base=", "--base-offset=", "--move-offset="};
    str_append(out, "\\![");
    str_append_n(out, args, cmd_len);
    const char *p = rest;
    for (int i = 0; i < 6 && p; i++) {
        const char *comma = strchr(p, ',');
        size_t n = comma ? (size_t)(comma - p) : strlen(p);
        char *value = trim_dup(p, n);
        /* 省略・"fix" の座標はその軸を維持する（新形式ではキー自体を書かない） */
        int omit = value[0] == 0 || ((i == 0 || i == 1) && strcasecmp(value, "fix") == 0);
        if (!omit) {
            str_append(out, ",");
            str_append(out, keys[i]);
            str_append(out, value);
        }
        free(value);
        p = comma ? comma + 1 : NULL;
    }
    str_append(out, "]");
    return 1;
}

static char *convert_legacy(const char *in) {
    sb_str out = {0};
    const char *p = in;
    int escaped_block = 0; /* \_! ... \_! の中 */
    while (*p) {
        if (*p != '\\') {
            str_append_n(&out, p, 1);
            p++;
            continue;
        }
        if (p[1] == '\\' || p[1] == '%') { /* エスケープはそのまま */
            str_append_n(&out, p, 2);
            p += 2;
            continue;
        }
        if (starts_with(p, "\\_!")) { /* [旧仕様] \_!〜\_! → 現行 \_?〜\_? */
            str_append(&out, "\\_?");
            escaped_block = !escaped_block;
            p += 3;
            continue;
        }
        if (escaped_block) {
            str_append_n(&out, p, 1);
            p++;
            continue;
        }
        if (starts_with(p, "\\__t")) { /* [旧仕様] TeachBox */
            str_append(&out, "\\![open,teachbox]");
            p += 4;
            continue;
        }
        if (starts_with(p, "\\__c")) { /* [旧仕様] CommunicateBox */
            str_append(&out, "\\![open,communicatebox]");
            p += 4;
            continue;
        }
        if (p[1] == 'z') { /* [旧仕様] 選択肢を含むスクリプトの \e */
            str_append(&out, "\\e");
            p += 2;
            continue;
        }
        if (p[1] == 'a' && p[2] != '[') { /* [旧仕様] ランダムトークを喋る */
            str_append(&out, "\\![raise,OnAITalk]");
            p += 2;
            continue;
        }
        if (p[1] == 'q' && (p[2] == '[' || (isdigit((unsigned char)p[2]) && strchr(p + 2, '[')))) {
            /* [旧仕様] \q[ID][タイトル] / \q*[ID][タイトル] → \q[タイトル,ID]\n（旧形式は選択肢ごとに改行） */
            const char *q = p + 2;
            while (isdigit((unsigned char)*q)) q++;
            char *id = NULL, *title = NULL;
            size_t n1 = read_bracket(q, &id);
            size_t n2 = n1 ? read_bracket(q + n1, &title) : 0;
            if (n1 && n2) {
                str_append(&out, "\\q[");
                str_append(&out, title);
                str_append(&out, ",");
                str_append(&out, id);
                str_append(&out, "]\\n");
                p = q + n1 + n2;
                free(id);
                free(title);
                continue;
            }
            free(id);
            free(title);
        }
        if (p[1] == '!' && p[2] == '[') {
            char *args = NULL;
            size_t n = read_bracket(p + 2, &args);
            if (n) {
                if (strcmp(args, "reloadsurface") == 0) { /* [旧仕様] SSP では \![reload,shell] と同じ */
                    str_append(&out, "\\![reload,shell]");
                    p += 2 + n;
                    free(args);
                    continue;
                }
                if (convert_legacy_move(args, &out)) {
                    p += 2 + n;
                    free(args);
                    continue;
                }
                free(args);
            }
        }
        str_append_n(&out, p, 1);
        p++;
    }
    return out.data ? out.data : strdup("");
}

/* 出力の仕上げ: 後方互換変換と、\e で終わる形への正規化 */
static char *finish_script(const char *script) {
    char *converted = convert_legacy(script);
    size_t n = strlen(converted);
    while (n && (converted[n - 1] == '\n' || converted[n - 1] == '\r' || converted[n - 1] == ' ')) converted[--n] = 0;
    if (n >= 2 && strcmp(converted + n - 2, "\\e") == 0 && !(n >= 3 && converted[n - 3] == '\\')) return converted;
    sb_str out = {0};
    str_append(&out, converted);
    str_append(&out, "\\e");
    free(converted);
    return out.data;
}

/* ------------------------------------------------------------------ */
/* 里々（Satori）                                                        */
/* ------------------------------------------------------------------ */

#define FW_ASTERISK "\xEF\xBC\x8A" /* ＊ */
#define FW_AT "\xEF\xBC\xA0"       /* ＠ */
#define FW_COLON "\xEF\xBC\x9A"    /* ： */
#define FW_SHARP "\xEF\xBC\x83"    /* ＃ */
#define FW_LPAREN "\xEF\xBC\x88"   /* （ */
#define FW_RPAREN "\xEF\xBC\x89"   /* ） */

static void satori_parse(const char *text, sb_dict *talks, sb_dict *words) {
    line_iter it = {text};
    const char *line;
    size_t len;
    sb_entry *cur_talk = NULL, *cur_words = NULL;
    sb_str body = {0};
    int in_talk = 0;

#define FLUSH_TALK()                                                   \
    do {                                                               \
        if (in_talk && cur_talk) {                                     \
            while (body.len && body.data[body.len - 1] == '\n')        \
                body.data[--body.len] = 0;                             \
            entry_add(cur_talk, body.data ? body.data : strdup(""));   \
            body = (sb_str){0};                                        \
        }                                                              \
        in_talk = 0;                                                   \
    } while (0)

    while (next_line(&it, &line, &len)) {
        if (len >= 3 && starts_with(line, FW_ASTERISK)) {
            FLUSH_TALK();
            char *name = trim_dup(line + 3, len - 3);
            cur_talk = dict_get(talks, name);
            free(name);
            cur_words = NULL;
            in_talk = 1;
            continue;
        }
        if (len >= 3 && starts_with(line, FW_AT)) {
            FLUSH_TALK();
            char *name = trim_dup(line + 3, len - 3);
            cur_words = dict_get(words, name);
            free(name);
            continue;
        }
        if (len >= 3 && starts_with(line, FW_SHARP)) continue;
        if (in_talk) {
            str_append_n(&body, line, len);
            str_append_n(&body, "\n", 1);
        } else if (cur_words && len) {
            entry_add(cur_words, trim_dup(line, len));
        }
    }
    FLUSH_TALK();
    str_free(&body);
#undef FLUSH_TALK
}

static void satori_expand(const char *text, sb_dict *words, sb_str *out, int depth) {
    const char *p = text;
    while (*p) {
        if (starts_with(p, FW_LPAREN)) {
            const char *close = strstr(p + 3, FW_RPAREN);
            if (close) {
                char *name = dup_n(p + 3, (size_t)(close - (p + 3)));
                const char *word = depth < SB_MAX_DEPTH ? dict_pick(words, name) : NULL;
                if (word) {
                    satori_expand(word, words, out, depth + 1);
                } else {
                    str_append_n(out, p, (size_t)(close + 3 - p)); /* 未知の呼び出しは原文のまま */
                }
                free(name);
                p = close + 3;
                continue;
            }
        }
        str_append_n(out, p, 1);
        p++;
    }
}

static char *satori_render(const char *talk, sb_dict *words) {
    sb_str out = {0};
    int scope = 0, scope_has_text = 0;
    str_append(&out, "\\0");
    line_iter it = {talk};
    const char *line;
    size_t len;
    while (next_line(&it, &line, &len)) {
        int switched = 0;
        while (len >= 3 && starts_with(line, FW_COLON)) { /* ：で話者を切り替える */
            scope = !scope;
            line += 3;
            len -= 3;
            switched = 1;
        }
        if (switched) {
            str_append(&out, scope ? "\\1" : "\\0");
            scope_has_text = 0;
        } else if (scope_has_text) {
            str_append(&out, "\\n");
        }
        char *raw = dup_n(line, len);
        satori_expand(raw, words, &out, 0);
        free(raw);
        scope_has_text = 1;
    }
    return out.data ? out.data : strdup("");
}

static char *satori_talk(const char *text, const char *entry) {
    sb_dict talks = {0}, words = {0};
    satori_parse(text, &talks, &words);
    const char *talk = dict_pick(&talks, entry && *entry ? entry : "");
    char *result = talk ? satori_render(talk, &words) : NULL;
    dict_free(&talks);
    dict_free(&words);
    return result;
}

/* ------------------------------------------------------------------ */
/* 華和梨（Kawari）                                                      */
/* ------------------------------------------------------------------ */

static void kawari_parse(const char *text, sb_dict *dict) {
    line_iter it = {text};
    const char *line;
    size_t len;
    int skipping = 0;
    while (next_line(&it, &line, &len)) {
        const char *s = skip_space(line);
        size_t n = len - (size_t)(s - line);
        if (n >= 4 && starts_with(s, "=kis")) { skipping = 1; continue; }
        if (n >= 4 && starts_with(s, "=end")) { skipping = 0; continue; }
        if (skipping || n == 0 || *s == '#' || *s == '=') continue;
        const char *colon = memchr(s, ':', n);
        if (!colon) continue;
        char *names = trim_dup(s, (size_t)(colon - s));
        const char *values = colon + 1;
        size_t vlen = n - (size_t)(values - s);
        /* "a , b : 単語" のように複数のエントリ名を並べられる */
        char *save = NULL;
        for (char *name = strtok_r(names, ",", &save); name; name = strtok_r(NULL, ",", &save)) {
            char *tname = trim_dup(name, strlen(name));
            if (!*tname) { free(tname); continue; }
            sb_entry *e = dict_get(dict, tname);
            free(tname);
            const char *v = values;
            size_t remaining = vlen;
            while (remaining > 0) {
                /* ${...} / $(...) / さくらスクリプトの [...] / "..." の中のカンマでは区切らない */
                size_t i = 0;
                int depth = 0, brackets = 0, quoted = 0;
                for (; i < remaining; i++) {
                    if (v[i] == '"') quoted = !quoted;
                    else if (quoted) continue;
                    else if (v[i] == '$' && i + 1 < remaining && (v[i + 1] == '{' || v[i + 1] == '(')) depth++;
                    else if ((v[i] == '}' || v[i] == ')') && depth > 0) depth--;
                    else if (v[i] == '[') brackets++;
                    else if (v[i] == ']' && brackets > 0) brackets--;
                    else if (v[i] == ',' && depth == 0 && brackets == 0) break;
                }
                char *word = trim_dup(v, i);
                /* "..." で囲んだ単語は囲みを外す */
                size_t wlen = strlen(word);
                if (wlen >= 2 && word[0] == '"' && word[wlen - 1] == '"') {
                    memmove(word, word + 1, wlen - 2);
                    word[wlen - 2] = 0;
                }
                if (*word) entry_add(e, word); else free(word);
                if (i >= remaining) break;
                v += i + 1;
                remaining -= i + 1;
            }
        }
        free(names);
    }
}

static void kawari_expand(const char *text, sb_dict *dict, sb_str *out, int depth) {
    const char *p = text;
    while (*p) {
        if (p[0] == '$' && p[1] == '{') {
            const char *close = strchr(p + 2, '}');
            if (close) {
                char *name = dup_n(p + 2, (size_t)(close - (p + 2)));
                const char *word = depth < SB_MAX_DEPTH ? dict_pick(dict, name) : NULL;
                if (word) kawari_expand(word, dict, out, depth + 1);
                free(name);
                p = close + 1;
                continue;
            }
        }
        if (p[0] == '$' && p[1] == '(') { /* KIS コマンドは実行しない（対象外） */
            int depth_paren = 0;
            const char *q = p + 1;
            for (; *q; q++) {
                if (*q == '(') depth_paren++;
                else if (*q == ')' && --depth_paren == 0) break;
            }
            p = *q ? q + 1 : q;
            continue;
        }
        str_append_n(out, p, 1);
        p++;
    }
}

static char *kawari_talk(const char *text, const char *entry) {
    sb_dict dict = {0};
    kawari_parse(text, &dict);
    const char *name = entry && *entry ? entry : "sentence";
    const char *word = dict_pick(&dict, name);
    char *result = NULL;
    if (word) {
        sb_str out = {0};
        kawari_expand(word, &dict, &out, 0);
        result = out.data ? out.data : strdup("");
    }
    dict_free(&dict);
    return result;
}

/* ------------------------------------------------------------------ */
/* AYA / YAYA                                                           */
/* ------------------------------------------------------------------ */

static char *aya_strip_comments(const char *text) {
    sb_str out = {0};
    const char *p = text;
    char quote = 0;
    while (*p) {
        if (quote) {
            str_append_n(&out, p, 1);
            if (*p == quote) quote = 0;
            p++;
            continue;
        }
        if (*p == '"' || *p == '\'') { quote = *p; str_append_n(&out, p, 1); p++; continue; }
        if (p[0] == '/' && p[1] == '/') { while (*p && *p != '\n') p++; continue; }
        if (p[0] == '/' && p[1] == '*') {
            const char *end = strstr(p + 2, "*/");
            p = end ? end + 2 : p + strlen(p);
            continue;
        }
        str_append_n(&out, p, 1);
        p++;
    }
    return out.data ? out.data : strdup("");
}

static void aya_parse(const char *text, sb_dict *dict) {
    char *src = aya_strip_comments(text);
    const char *p = src;
    while (*p) {
        /* 関数名（: 以降の選択子 nonoverlap 等は無視）を読み、{ ... } の文字列リテラルを候補にする */
        while (*p && isspace((unsigned char)*p)) p++;
        if (*p == '#') { /* #define 等のプリプロセス行 */
            while (*p && *p != '\n') p++;
            continue;
        }
        const char *name_start = p;
        while (*p && *p != '{' && *p != '}' && *p != '\n' && *p != ':') p++;
        if (!*p) break;
        char *name = trim_dup(name_start, (size_t)(p - name_start));
        /* 選択子（: nonoverlap 等）と改行を越えて、関数本体の { を探す */
        while (*p && *p != '{' && *p != '}') p++;
        if (*p != '{' || !*name) { free(name); if (*p) p++; continue; }
        p++;
        sb_entry *e = dict_get(dict, name);
        free(name);
        int depth = 1;
        while (*p && depth > 0) {
            if (*p == '{') depth++;
            else if (*p == '}') depth--;
            else if (*p == '"' || *p == '\'') {
                char q = *p++;
                const char *start = p;
                while (*p && *p != q) p++;
                entry_add(e, dup_n(start, (size_t)(p - start)));
            }
            if (*p) p++;
        }
    }
    free(src);
}

static void aya_expand(const char *text, sb_dict *dict, sb_str *out, int depth) {
    const char *p = text;
    while (*p) {
        if (p[0] == '%' && p[1] == '(') {
            const char *close = strchr(p + 2, ')');
            if (close) {
                char *name = trim_dup(p + 2, (size_t)(close - (p + 2)));
                const char *word = depth < SB_MAX_DEPTH ? dict_pick(dict, name) : NULL;
                if (word) aya_expand(word, dict, out, depth + 1);
                else str_append_n(out, p, (size_t)(close + 1 - p));
                free(name);
                p = close + 1;
                continue;
            }
        }
        str_append_n(out, p, 1);
        p++;
    }
}

static char *aya_talk(const char *text, const char *entry) {
    sb_dict dict = {0};
    aya_parse(text, &dict);
    const char *word = NULL;
    if (entry && *entry) word = dict_pick(&dict, entry);
    else if (!(word = dict_pick(&dict, "OnAiTalk"))) word = dict_pick(&dict, "RandomTalk");
    char *result = NULL;
    if (word) {
        sb_str out = {0};
        aya_expand(word, &dict, &out, 0);
        result = out.data ? out.data : strdup("");
    }
    dict_free(&dict);
    return result;
}

/* ------------------------------------------------------------------ */
/* さくらスクリプトのテキスト                                              */
/* ------------------------------------------------------------------ */

static char *plain_talk(const char *text) {
    /* 空行区切りのブロックから 1 つを選び、ブロック内の改行は \n にする */
    sb_entry blocks = {0};
    sb_str cur = {0};
    line_iter it = {text};
    const char *line;
    size_t len;
    while (next_line(&it, &line, &len)) {
        const char *s = skip_space(line);
        if ((size_t)(s - line) == len) {
            if (cur.len) entry_add(&blocks, cur.data), cur = (sb_str){0};
            continue;
        }
        if (cur.len) str_append(&cur, "\\n");
        str_append_n(&cur, line, len);
    }
    if (cur.len) entry_add(&blocks, cur.data);
    char *result = blocks.count ? strdup(blocks.items[pick(blocks.count)]) : NULL;
    for (size_t i = 0; i < blocks.count; i++) free(blocks.items[i]);
    free(blocks.items);
    return result;
}

/* ------------------------------------------------------------------ */
/* 形式判定と入口                                                        */
/* ------------------------------------------------------------------ */

typedef enum { FMT_AUTO, FMT_SATORI, FMT_KAWARI, FMT_AYA, FMT_SAKURA } sb_format;

static sb_format parse_format(const char *name) {
    if (!name || !*name || strcasecmp(name, "auto") == 0) return FMT_AUTO;
    if (strcasecmp(name, "satori") == 0 || strcmp(name, "里々") == 0) return FMT_SATORI;
    if (strcasecmp(name, "kawari") == 0 || strcmp(name, "華和梨") == 0) return FMT_KAWARI;
    if (strcasecmp(name, "aya") == 0 || strcasecmp(name, "yaya") == 0) return FMT_AYA;
    return FMT_SAKURA;
}

static sb_format detect_format(const char *text, const char *filename) {
    if (filename) {
        const char *dot = strrchr(filename, '.');
        if (dot && (strcasecmp(dot, ".kis") == 0 || strcasecmp(dot, ".kawari") == 0)) return FMT_KAWARI;
        if (dot && (strcasecmp(dot, ".aya") == 0 || strcasecmp(dot, ".dic") == 0)) return FMT_AYA;
        if (dot && strcasecmp(dot, ".satori") == 0) return FMT_SATORI;
    }
    line_iter it = {text};
    const char *line;
    size_t len;
    int kawari_lines = 0, aya_braces = 0;
    while (next_line(&it, &line, &len)) {
        if (len >= 3 && (starts_with(line, FW_ASTERISK) || starts_with(line, FW_AT))) return FMT_SATORI;
        const char *s = skip_space(line);
        if (*s == '\\') continue;
        if (memchr(line, '{', len)) aya_braces++;
        const char *colon = memchr(line, ':', len);
        if (colon && colon > s && *s != '#' && !memchr(line, '{', len)) kawari_lines++;
    }
    if (aya_braces > 0) return FMT_AYA;
    if (kawari_lines > 0) return FMT_KAWARI;
    return FMT_SAKURA;
}

static char *interpret(const char *text, sb_format fmt, const char *entry, const char *filename) {
    if (fmt == FMT_AUTO) fmt = detect_format(text, filename);
    char *raw = NULL;
    switch (fmt) {
    case FMT_SATORI: raw = satori_talk(text, entry); break;
    case FMT_KAWARI: raw = kawari_talk(text, entry); break;
    case FMT_AYA: raw = aya_talk(text, entry); break;
    default: raw = plain_talk(text); break;
    }
    if (!raw) return NULL;
    char *script = finish_script(raw);
    free(raw);
    return script;
}

/* ------------------------------------------------------------------ */
/* PLUGIN/2.0M                                                          */
/* ------------------------------------------------------------------ */

static char g_dir[4096];
static sb_str g_response;

static char *header_value(const char *req, const char *key) {
    size_t klen = strlen(key);
    line_iter it = {req};
    const char *line;
    size_t len;
    int first = 1;
    while (next_line(&it, &line, &len)) {
        if (first) { first = 0; continue; }
        if (len == 0) break;
        if (len > klen && strncasecmp(line, key, klen) == 0 && line[klen] == ':')
            return trim_dup(line + klen + 1, len - klen - 1);
    }
    return NULL;
}

/* ヘッダ値に入れられるよう CR/LF を除く（さくらスクリプトの改行は \n タグで表す） */
static void append_header(sb_str *out, const char *key, const char *value) {
    str_append(out, key);
    str_append(out, ": ");
    for (const char *p = value; *p; p++)
        if (*p != '\r' && *p != '\n') str_append_n(out, p, 1);
    str_append(out, "\r\n");
}

/* プラグインディレクトリ配下の相対パスか絶対パスを解決する（scripts/ を優先） */
static char *resolve_path(const char *name) {
    if (!name || !*name) return NULL;
    char *norm = strdup(name);
    for (char *c = norm; *c; c++) if (*c == '\\') *c = '/';
    if (norm[0] == '/') return norm;
    if (strstr(norm, "..")) { free(norm); return NULL; }
    char path[8192];
    struct stat st;
    snprintf(path, sizeof(path), "%sscripts/%s", g_dir, norm);
    if (stat(path, &st) != 0) snprintf(path, sizeof(path), "%s%s", g_dir, norm);
    free(norm);
    return strdup(path);
}

static int is_listed_script(const char *name) {
    if (name[0] == '.') return 0;
    const char *dot = strrchr(name, '.');
    if (!dot) return 0;
    return strcasecmp(dot, ".txt") == 0 || strcasecmp(dot, ".kis") == 0 || strcasecmp(dot, ".kawari") == 0
        || strcasecmp(dot, ".aya") == 0 || strcasecmp(dot, ".dic") == 0 || strcasecmp(dot, ".satori") == 0;
}

static int compare_names(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }

/* OnMenuExec: scripts/ のファイルを選択肢で並べ、選ぶと raiseplugin で再生する */
static char *menu_script(void) {
    char path[4200];
    snprintf(path, sizeof(path), "%sscripts", g_dir);
    sb_entry files = {0};
    DIR *d = opendir(path);
    if (d) {
        struct dirent *ent;
        while ((ent = readdir(d)))
            if (is_listed_script(ent->d_name)) entry_add(&files, strdup(ent->d_name));
        closedir(d);
    }
    qsort(files.items, files.count, sizeof(char *), compare_names);
    sb_str out = {0};
    str_append(&out, "\\0\\b[2]\\_q[ScriptBridge]\\_q\\n");
    if (files.count == 0) str_append(&out, "scripts フォルダにスクリプトがありません。\\n");
    for (size_t i = 0; i < files.count; i++)
        /* script: の中にカンマがあるので引数全体を "" で囲む（UKADOC の \q[タイトル,"script:..."] 形式） */
        str_appendf(&out, "\\q[%s,\"script:\\![raiseplugin,scriptbridge,OnScriptBridgePlay,%s]\"]\\n", files.items[i], files.items[i]);
    str_append(&out, "\\n\\q[閉じる,script:\\e]\\e");
    for (size_t i = 0; i < files.count; i++) free(files.items[i]);
    free(files.items);
    return out.data;
}

static void respond(const char *status, const char *key, const char *value) {
    str_free(&g_response);
    str_appendf(&g_response, "PLUGIN/2.0M %s\r\nCharset: UTF-8\r\n", status);
    if (key && value) append_header(&g_response, key, value);
    str_append(&g_response, "\r\n");
}

static void handle(const char *req) {
    char *id = header_value(req, "ID");
    char *ref0 = header_value(req, "Reference0");
    char *ref1 = header_value(req, "Reference1");
    char *ref2 = header_value(req, "Reference2");
    char *ref3 = header_value(req, "Reference3");
    g_seeded = ref3 && *ref3;
    if (g_seeded) g_seed = strtoull(ref3, NULL, 10);

    if (!id) {
        respond("400 Bad Request", NULL, NULL);
    } else if (strcmp(id, "version") == 0) {
        respond("200 OK", "Value", SB_VERSION);
    } else if (strcmp(id, "OnMenuExec") == 0) {
        char *script = menu_script();
        respond("200 OK", "Script", script);
        free(script);
    } else if (strcmp(id, "OnScriptBridgePlay") == 0) {
        /* Reference0=ファイル, Reference1=エントリ名/イベント名, Reference2=形式, Reference3=乱数の種 */
        char *path = resolve_path(ref0);
        char *text = path ? read_file_utf8(path) : NULL;
        char *script = text ? interpret(text, parse_format(ref2), ref1, path) : NULL;
        if (script) respond("200 OK", "Script", script);
        else respond("204 No Content", NULL, NULL);
        free(script);
        free(text);
        free(path);
    } else if (strcmp(id, "OnScriptBridgeEval") == 0 || strcmp(id, "OnScriptBridgeConvert") == 0) {
        /* Eval: Reference0=本文, Reference1=エントリ名, Reference2=形式。Convert: 旧仕様タグの変換だけを Value で返す */
        int convert_only = strcmp(id, "OnScriptBridgeConvert") == 0;
        char *body = ref0 ? strdup(ref0) : strdup("");
        /* ヘッダ値には改行を書けないので、本文の改行は U+0001 で渡す */
        for (char *c = body; *c; c++) if (*c == '\x01') *c = '\n';
        char *script = convert_only ? convert_legacy(body) : interpret(body, parse_format(ref2), ref1, NULL);
        if (script) respond("200 OK", convert_only ? "Value" : "Script", script);
        else respond("204 No Content", NULL, NULL);
        free(script);
        free(body);
    } else {
        respond("204 No Content", NULL, NULL);
    }
    free(id);
    free(ref0);
    free(ref1);
    free(ref2);
    free(ref3);
}

EXPORT int load(const char *dir) {
    snprintf(g_dir, sizeof(g_dir), "%s", dir ? dir : "");
    size_t n = strlen(g_dir);
    if (n && g_dir[n - 1] != '/' && n + 1 < sizeof(g_dir)) strcat(g_dir, "/");
    return 1;
}

EXPORT int loadu(const char *dir) { return load(dir); }

EXPORT void unload(void) { str_free(&g_response); }

EXPORT const unsigned char *request(const unsigned char *buf, size_t len, size_t *out_len) {
    char *req = to_utf8((const char *)buf, len);
    handle(req);
    free(req);
    *out_len = g_response.len;
    return (const unsigned char *)str_cstr(&g_response);
}
