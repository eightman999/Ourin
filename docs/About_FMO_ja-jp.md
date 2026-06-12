# FMO機能について

このドキュメントでは、Ourin の FMO（Forged Memory Object）の実装方針を説明します。

## 概要

Ourin の FMO は Windows の名前付き FileMapping API の完全互換ではなく、POSIX 共有メモリによる**意味的互換**です。
外部ツールが現在起動中のゴースト一覧・名前・パス・shell・balloon・surface 等を取得できることを目的としています。

## 共有メモリ名

| リソース | 名前 |
|---|---|
| 共有メモリ | `/ourin_fmo` |
| セマフォ（排他制御） | `/ourin_fmo_mutex` |

## FMO レコード形式

SSP 互換の形式を採用しています:

```
(id).(key)\x01(value)\r\n
```

- `\x01` は ASCII SOH（Start of Heading, U+0001）
- 改行は CRLF（`\r\n`）
- `id` は 0 から始まるゴーストのインデックス番号

### フィールド一覧

| キー | 説明 | 例 |
|---|---|---|
| `name` | ゴーストの sakura 名 | `Emily4` |
| `keroname` | kero の名前 | `Teddy` |
| `path` | ゴーストディレクトリのパス | `/Users/.../ghost/emily4` |
| `shell` | 現在のシェル名 | `master` |
| `balloon` | 現在のバルーン名 | `default` |
| `sakura.surface` | sakura の現在サーフェス ID | `0` |
| `kero.surface` | kero の現在サーフェス ID | `10` |
| `hwnd` | ウィンドウハンドル（ダミー値） | `0` |

### 出力例

```
0.name\x01Emily4\r\n
0.keroname\x01Teddy\r\n
0.path\x01/Users/user/Library/.../ghost/emily4\r\n
0.shell\x01master\r\n
0.balloon\x01default\r\n
0.sakura.surface\x010\r\n
0.kero.surface\x0110\r\n
0.hwnd\x010\r\n
```

## Windows との差異

### hwnd はダミー値
`hwnd` は Windows のウィンドウハンドルに相当しますが、macOS では意味を持たないため常に `0` を返します。

### パス形式
パスは macOS のネイティブ形式（POSIX パス）です。Windows のバックスラッシュ区切りやドライブレター形式ではありません。

### 共有メモリの寿命
- Windows: 名前付き FileMapping は全ハンドルが閉じると自動削除
- Ourin: POSIX 共有メモリはプロセス生存中は名前を保持し、正常終了時に `shm_unlink` / `sem_unlink` で削除
- クラッシュ後に残った共有メモリは、次回起動時に安全に上書き・初期化されます

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
- `writeSnapshot(records:)`: 共有メモリへスナップショットを書き込む
- `isAnotherInstanceRunning()`: 共有メモリの存在で他インスタンスの起動を判定
- `cleanup()`: 正常終了時に共有メモリとセマフォを解放

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
