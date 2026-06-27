# FMO機能について

このドキュメントでは、Ourin の FMO（Forged Memory Object）の実装方針を説明します。

## 概要

Ourin の FMO は Windows の名前付き FileMapping API の完全互換ではなく、POSIX 共有メモリによる**意味的互換**です。
外部ツールが現在起動中のゴースト一覧・名前・パス・surface 等を取得できることを目的としています。
Windows 向け FMO 直接読込ツールとのバイナリ/OS API 互換は対象外で、Ourin が保証する互換境界は
`EXECUTE GetFMO` と `id.key\x01value\r\n` 形式のテキストビューです。

## 共有メモリ名

| リソース | 名前 |
|---|---|
| 共有メモリ | `/ourin_fmo` |
| セマフォ（排他制御） | `/ourin_fmo_mutex` |

## FMO レコード形式

SSP 互換の形式を採用しています:

```
id.key\x01value\r\n
```

- `\x01` は ASCII SOH（Start of Heading, U+0001）
- 改行は CRLF（`\r\n`）
- `id` は 0 から始まるゴーストのインデックス番号

### フィールド一覧

| キー | 説明 | 例 |
|---|---|---|
| `name` | ゴーストの sakura 名 | `Emily4` |
| `keroname` | kero の名前 | `Teddy` |
| `fullname` | descript 由来のゴーストフルネーム | `Emily/Phase4` |
| `ghostname` | descript / ディレクトリ由来のゴースト名 | `emily4` |
| `path` | ゴーストディレクトリのパス | `/Users/.../ghost/emily4` |
| `ghostpath` | ゴーストのインストールパス | `/Users/.../ghost/emily4` |
| `sakura.surface` | sakura の現在サーフェス ID | `0` |
| `kero.surface` | kero の現在サーフェス ID | `10` |
| `hwnd` | sakura 側の Ourin ウィンドウ識別子 | `1001` |
| `kerohwnd` | kero 側の Ourin ウィンドウ識別子 | `1002` |
| `hwndlist` | このゴーストに属するウィンドウ識別子の一覧 | `1001,1002` |
| `module.state` | ゴーストモジュール状態 | `running` |
| `shell` | 現在のシェル名（Ourin 拡張） | `master` |
| `balloon` | 現在のバルーン名（Ourin 拡張） | `default` |

### 出力例

```
0.name\x01Emily4\r\n
0.keroname\x01Teddy\r\n
0.fullname\x01Emily/Phase4\r\n
0.ghostname\x01emily4\r\n
0.path\x01/Users/user/Library/.../ghost/emily4\r\n
0.ghostpath\x01/Users/user/Library/.../ghost/emily4\r\n
0.sakura.surface\x010\r\n
0.kero.surface\x0110\r\n
0.hwnd\x011001\r\n
0.kerohwnd\x011002\r\n
0.hwndlist\x011001,1002\r\n
0.module.state\x01running\r\n
0.shell\x01master\r\n
0.balloon\x01default\r\n
```

## macOS 独自制約と Windows との差異

### FileMapping 名は互換しない
Windows/SSP の名前付き FileMapping をそのまま公開するものではありません。macOS では POSIX 共有メモリ
`/ourin_fmo` とセマフォ `/ourin_fmo_mutex` を使います。Windows 向け外部ツールが Win32 API で
FMO を直接読むことはできません。

### hwnd は Win32 HWND ではない
`hwnd` / `kerohwnd` / `hwndlist` は Windows のウィンドウハンドルではありません。Ourin では
`NSWindow.windowNumber` を優先し、取得できない場合はゴースト/スコープから安定ハッシュを生成した
**非ゼロの Ourin 内部ウィンドウ識別子**を返します。この値は同一 Ourin 実行中の識別・SSTP 対象解決用であり、
Win32 HWND として dereference できません。

### パス形式
パスは macOS のネイティブ形式（POSIX パス）です。Windows のバックスラッシュ区切りやドライブレター形式ではありません。

### 共有メモリの寿命
- Windows: 名前付き FileMapping は全ハンドルが閉じると自動削除
- Ourin: POSIX 共有メモリはプロセス生存中は名前を保持し、正常終了時に `shm_unlink` / `sem_unlink` で削除
- クラッシュ後に残った共有メモリは、次回起動時に安全に上書き・初期化されます

## 互換ビュー

### FMO テキストビュー
`FmoManager.buildSnapshot(records:)` は `id.key\x01value\r\n` の SSP 風テキストを生成します。
SSTP `EXECUTE GetFMO` の応答と POSIX 共有メモリの本文は同じテキストビューを使います。

### 構造化ビュー
`FmoCompatibilityView.parse(_:)` と `FmoManager.buildCompatibilityView(records:)` は、FMO テキストを
`id` ごとの field 辞書として読むための Ourin 内部 API です。テスト、診断 UI、macOS 側ブリッジはこのビューを使い、
POSIX 共有メモリ実体や Windows API の違いに依存しないようにします。

### POSIX 共有メモリビュー
共有メモリ上では、先頭 4 バイトの `uint32_t` に UTF-8 本文長、その後に FMO テキスト、末尾に NUL を格納します。
これは Ourin の macOS 実装詳細であり、Windows FMO のメモリオブジェクト形式そのものではありません。

## 外部アプリからのアクセス方法

### 推奨: SSTP EXECUTE GetFMO
macOS 外部アプリからは、SSTP プロトコル経由で `EXECUTE` メソッドの `GetFMO` コマンドを使うことを推奨します。
共有メモリの直接アクセスよりも安全で、セキュリティレベルの制御（`local` のみ許可）も適用されます。

```
EXECUTE SSTP/1.4
Sender: MyApp
Command: GetFMO
SecurityLevel: local
Charset: UTF-8

```

### 直接アクセス: POSIX 共有メモリ
`shm_open("/ourin_fmo", O_RDWR, 0)` で共有メモリを開き、先頭 4 バイトの `uint32_t` でデータサイズを読み取り、その後にUTF-8 テキストとして FMO レコードを読み出せます。排他制御には `/ourin_fmo_mutex` セマフォを使用してください。

## 更新タイミング

FMO は以下のタイミングで更新されます:

- ゴースト起動時（OnBoot 完了後）
- ゴースト終了時
- シェル変更時（OnShellChanged）
- バルーン変更時（OnBalloonChange）
- サーフェス変更時（OnSurfaceChange）

## 主要クラス

### `FmoManager`
- FMO 全体の管理クラス
- `buildSnapshot(records:)`: SSP 風レコード形式の文字列を生成（static）
- `buildCompatibilityView(records:)`: 同じレコードを構造化互換ビューとして生成（static）
- `writeSnapshot(records:)`: 共有メモリへスナップショットを書き込む
- `isAnotherInstanceRunning()`: 共有メモリの存在で他インスタンスの起動を判定
- `cleanup()`: 正常終了時に共有メモリとセマフォを解放

### `FmoCompatibilityView`
- `id.key\x01value\r\n` 形式の FMO テキストを `id` ごとの `fields` に変換する内部ビュー
- 不正行は無視し、`id` 昇順で entries を返す

### `FmoSharedMemory`
- POSIX 共有メモリのラッパー
- プロセス生存中は共有メモリ名を保持（作成直後の unlink は行わない）
- 先頭 4 バイトにデータサイズ、末尾に NUL 終端を書き込む
- クラッシュ後の残留共有メモリは `O_CREAT` で安全に上書きされる

### `FmoMutex`
- 名前付きセマフォのラッパー
- クラッシュ後の残留セマフォは自動的に `sem_unlink` → 再作成される

### `FmoBridge.c / .h`
- Swift から POSIX API を呼び出すための C ラッパー関数群

## 実装ファイル

- `Ourin/FMO/FmoManager.swift`: FMO 管理クラス・スナップショット生成
- `Ourin/FMO/FmoSharedMemory.swift`: 共有メモリラッパー
- `Ourin/FMO/FmoMutex.swift`: Mutex ラッパー
- `Ourin/FMO/FmoError.swift`: エラー定義
- `Ourin/FMO/FmoBridge.c`: C ブリッジ実装
- `Ourin/FMO/FmoBridge.h`: C ブリッジヘッダー
