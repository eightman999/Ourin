# cshiori macOS 移植差分

対象は `UPSTREAM.json` の `Narazaka/cshiori` revision `4aaf9df77cc55401feb1a1beb742048e0de541c0`。`build.py` は取得アーカイブのSHA256を照合し、展開した一時コピーだけに以下の変更を加えます。上流の `shiori_events.c` の応答内容、状態変数、GET/NOTIFY分岐は変更しません。

## 1. getline のシンボル衝突

macOS `<stdio.h>` はPOSIX `getline(char **, size_t *, FILE *)` を宣言します。上流 `strutl.h` / `strutl.c` の `getline(const FILE *)` と衝突するため、独自関数の宣言・定義・ `cshiolink.c` の呼出箇所を `cshiori_getline` に改名します。対象ファイルごとの出現数を確認してから置換するので、固定上流と異なる入力へ黙って適用しません。

## 2. 上流サンプルと応答の所有権

改名だけを適用した実行ファイルに、次のSHIOLINK通信を送ると、macOSでSIGABRTが再現しました。

```text
*L:/tmp/
*S:probe
GET SHIORI/3.0
Charset: Shift_JIS
ID: version

*U:
```

送信バイトの改行はCRLFです。同期エコー `*S:probe` は返りますが、要求の応答を返す前に停止します。

上流 `shiori_events.c` は `res->value = "0.0.1"`、`res->sender = "cshiori"`、`res->charset = "Shift_JIS"` などの借用文字列リテラルを設定します。一方、`cshiori_request` はコールバックの応答を構築後、`cshiori_response_message_delete` を呼びます。この解放関数はvalue/sender/charsetと各Referenceを `free` するため、サンプルの借用値とフレームワークの所有権規約が一致していません。

修正は `shiolink.c` のサンプル接続部分だけです。上流イベント関数を `cshiori_example_request` としてそのままコンパイルし、ラッパーが返却されたvalue/sender/charset/Referenceを `strdup` してからフレームワークへ戻します。これにより既存の解放処理が所有するコピーを解放できます。versionはフレームワークが解放しないためコピーしません。独自イベント実装で既に所有権を渡しているケースに、このサンプル用ラッパーを適用してはいけません。

## 検証

2026-10-26、上流アーカイブからビルドしたmacOS実行ファイルを本番の `ShiolinkAdapter` / `ShioriWireCodec` / `EncodingAdapter` に接続した独立Swift probeで確認しました。

- `load`、`version=0.0.1`、`name=cshiori`、`craftmanw=奈良阪某`
- Shift_JISの `OnBoot`（`起動。`）と `OnClose`（`終了。`）の応答本文
- 日本語Referenceを持つNOTIFYの204応答
- `unload` 後の子プロセス回収、再loadからの再要求（2 lifecycle）

Xcode側の本番factoryを含む回帰は `CshioriEngineTests` で継続確認します。上流サンプルのsave/load永続化、任意のCゴーストの全互換性、配布Windows DLLの実行はこの試験の確認範囲に含みません。
