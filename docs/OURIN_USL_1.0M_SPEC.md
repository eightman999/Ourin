
# Ourin — Universal‑SHIORI Loader **USL/1.0M** 仕様書（macOS, ToC 付き）
**Status:** Draft  
**Updated:** 2025-07-28 (JST)  
**Target:** macOS 10.15+（Catalina〜）/ Universal 2（x86_64, arm64）

> 目的：Ourin（ベースウェア）が **SHIORI DLL 互換モジュール**（YAYA/AYA/華和梨/美坂など）を macOS で統一的にロード・実行するための“最小で実用的”なローダ規格。  
> **語彙・挙動は SHIORI/3.x に準拠**し（`GET/NOTIFY`・CRLF・`Charset`・`Reference*` 等）、DLL共通仕様の **`load(u)/request/unload` 3 関数**を呼び出す。

---

## 目次
- [0. 用語](#0-用語)
- [1. 適用範囲と非目標](#1-適用範囲と非目標)
- [2. 依存規格](#2-依存規格)
- [3. サポートするモジュール形式](#3-サポートするモジュール形式)
- [4. エントリポイントと呼出規約](#4-エントリポイントと呼出規約)
- [5. リクエスト/レスポンス規約（SHIORI/3.x 準拠）](#5-リクエストレスポンス規約shiori3x-準拠)
- [6. 文字コード・改行](#6-文字コード改行)
- [7. 検索パスと名称正規化](#7-検索パスと名称正規化)
- [8. アーキテクチャ互換（Universal/ Rosetta / OOP フォールバック）](#8-アーキテクチャ互換universal-rosetta-oop-フォールバック)
- [9. セキュリティ・署名・ロード先制限](#9-セキュリティ署名ロード先制限)
- [10. タイムアウト・エラー処理](#10-タイムアウトエラー処理)
- [11. ログと計測](#11-ログと計測)
- [12. 互換性メモ（Windows 由来との橋渡し）](#12-互換性メモwindows-由来との橋渡し)
- [付録A. USL/1.0M 要求仕様チェックリスト](#付録a-usl10m-要求仕様チェックリスト)
- [付録B. サンプル構成（典型的な YAYA ゴースト）](#付録b-サンプル構成典型的な-yaya-ゴースト)
- [変更履歴](#変更履歴)

---

## 0. 用語
- **SHIORI/3.x**：`GET/NOTIFY` とヘッダ群から成るメッセージ規約。  
- **DLL共通仕様**：`load(u)` / `request` / `unload` の 3 関数とメモリ受け渡し規約。  
- **USL（Universal‑SHIORI Loader）**：本仕様で定める Ourin のローダ。  
- **モジュール**：YAYA/AYA/華和梨/美坂などの SHIORI 実装 (`*.dylib` / `*.bundle` / `*.so` 相当)。

## 1. 適用範囲と非目標
- **対象**：macOS ネイティブで SHIORI をロード・実行し、**語彙／挙動互換**を満たすこと。  
- **非目標**：Windows DLL の**バイナリ互換**。名前やパスの互換吸収は行うが、PE/DLL を直接読み込まない。

## 2. 依存規格
- **SHIORI/3.x**：メッセージフォーマット、`Charset`、CRLF、末尾空行。  
- **DLL共通仕様**：`loadu`（UTF‑8）/`load`（CP932 等）/`request`/`unload` の存在と役割。

## 3. サポートするモジュール形式
- **Mach‑O ダイナミックライブラリ**：`*.dylib`（推奨）。  
- **バンドル**：`*.bundle`（`CFBundleExecutable` を `dlopen` 相当で解決）。  
- **互換名称**：`*.so` も受理（中身が Mach‑O であること）。  
- **想定格納**：ゴースト配下 `ghost/master/` または `modules/`。アプリバンドル `Frameworks/` も探索。

## 4. エントリポイントと呼出規約
### 4.1 必須/任意エントリ
- **必須**：`request(h, len) -> HGLOBAL`  
- **任意だが推奨**：`loadu(h, len) -> BOOL`（UTF‑8 パス）  
- **任意**：`load(h, len) -> BOOL`（CP932 等の従来互換）、`unload() -> BOOL`

### 4.2 呼出順と引数
1. **`loadu` → `load` の順で存在検出**。`loadu` があれば **優先**。  
2. 引数 `h` は **モジュールのディレクトリパス**。USL は UTF‑8（`loadu`）/CP932（`load`）でエンコード済みの **連続バイト列**を渡す。  
3. **`request`** には **SHIORI リクエスト全体（CRLF 区切り）**を渡す。戻りはレスポンス全体。  
4. **`unload`** はベースウェア終了時に 1 回。

### 4.3 Darwin メモリ契約（USL/1.0M 補足）
- 入力 `h`/`request` のバッファは **呼出中のみ有効**（モジュール側は解放しないこと）。  
- モジュールが返すレスポンスは **呼出側が `free()` で解放**できる領域で確保すること（`malloc` 系）。  
- 互換のため、USL は **返却文字列を常にコピー**し、モジュール側解放関数があれば呼び出す（将来拡張）。

## 5. リクエスト/レスポンス規約（SHIORI/3.x 準拠）
- 行末は **CR+LF**。末尾は **空行**で終端。  
- `Charset` を尊重。**既定 UTF‑8**、**CP932 を受理**。  
- `GET` は `Value` を返す、`NOTIFY` は `Value` を無視（`Status` は通例 `204` ）。

## 6. 文字コード・改行
- **入出力の既定**：UTF‑8。`load` 系に限り CP932 も受理。  
- SJIS/CP932 を受理した場合、**内部は UTF‑8 正規化**して SHIORI へ渡す/受け取る。

## 7. 検索パスと名称正規化
### 7.1 検索順
1. ゴースト直下 `ghost/master/`  
2. 同ディレクトリの `modules/`  
3. アプリバンドル `Contents/Frameworks/`  
4. `@rpath` / `DYLD_*` 経路（開発向け）
### 7.2 名称正規化（例）
- `yaya.dll` → `yaya.dylib` → `libyaya.dylib` の順で試行（接頭辞 `lib`／拡張子差を吸収）。  
- `shiori.dll` → `shiori.dylib`／`shiori.bundle`。  
- ファイル名の **大文字小文字**は厳格に一致させる。

## 8. アーキテクチャ互換（Universal/ Rosetta / OOP フォールバック）
- **優先**：**Universal 2**（arm64 + x86_64）なモジュールをロード。  
- **不一致**（arm64 アプリ ↔ x86_64 モジュール等）：  
  1) **同名の別アーキテクチャ版**があれば選択。  
  2) それも無い場合、**OOP（Out‑of‑Process）フォールバック**：同梱ヘルパ（XPC/補助アプリ）上でモジュールをロードし、`request` を IPC で中継。  
- **Rosetta 依存の強制はしない**（ホストを Rosetta で再起動させないのが原則）。

## 9. セキュリティ・署名・ロード先制限
- アプリは **公証/署名**済みを前提。モジュールは基本的に **アプリ内（又はユーザ領域）**からのみ読み込み。  
- サンドボックス想定時は **XPC サービス**にモジュールロードを委譲可能。  
- 外部パスや隔離属性のあるバイナリは **読み込みを拒否**し、ユーザに移動/許可を促す。

## 10. タイムアウト・エラー処理
- `load(u)`/`unload`：各 10 秒、`request`：**既定 10 秒**（設定可能）。  
- タイムアウト時は **モジュールをアンロード**し、再ロードを試行。連続失敗で無効化。  
- 代表エラー：`NoEntryPoint` / `BadArch` / `SignatureInvalid` / `Timeout` / `ProtocolError`。

## 11. ログと計測
- ログ：`subsystem=jp.ourin.usl`、イベント `open/close/request/timeout/ipc_fallback`。  
- 計測：平均応答時間・タイムアウト率・クラッシュ回数。

## 12. 互換性メモ（Windows 由来との橋渡し）
- `load` の第1引数は **モジュールのディレクトリパス**。YAYA/AYA 等の辞書配置はここを基準に解決。  
- `yaya.dll` 等の **名称差**は USL が吸収（名称正規化）。  
- **SJIS辞書**は USL で UTF‑8 化（内部）して SHIORI に渡す。

---

## 付録A. USL/1.0M 要求仕様チェックリスト
- [ ] `dlopen` / `dlsym` で `request` を解決できる  
- [ ] `loadu` があれば UTF‑8 パスで初期化、なければ `load`（CP932）  
- [ ] `GET/NOTIFY` の応答差を処理（`Value` の有無）  
- [ ] タイムアウト設定を持ち、未応答時に OOP フォールバックが可能  
- [ ] arm64/x86_64 の **両対応**（Universal 推奨、OOP で代替可）  
- [ ] SJIS/UTF‑8 受理・内部 UTF‑8 正規化  
- [ ] CRLF/最終空行の自動付与/検査

## 付録B. サンプル構成（典型的な YAYA ゴースト）
```
MyGhost/
  ghost/master/
    descript.txt
    yaya.dylib         ; macOS 版 YAYA（例名）
    yaya.txt           ; 設定
    dic/...
```
`descript.txt: shiori,yaya.dylib` を想定。Windows 版は `yaya.dll`。USL の名称正規化で差を吸収。

---

## 変更履歴
- 2025-07-28 (JST): 初版（USL/1.0M）。
