#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int  load (const char* plugin_dir_utf8);
int  loadu(const char* plugin_dir_utf8);
void unload(void);

/** request:
 *  入力:  CRLF区切りヘッダ + 空行終端（BODY無し、UTF-8既定／SJIS系も受理）
 *  出力:  同形式（PLUGIN/2.0M 先頭行を含むレスポンス, 常に UTF-8）
 *  返却ポインタの寿命は呼び出し後短期間のみ有効（呼び出し側で即コピー）。
 */
const unsigned char* request(const unsigned char* buf, size_t len, size_t* out_len);

/** 任意: 呼び出し側で解放したい場合だけ提供 */
void plugin_free(void* p);

#ifdef __cplusplus
}
#endif
