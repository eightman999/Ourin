# FMO機能について

このドキュメントでは、Windows向けゲームやゴーストで利用されているFMO(Forged Memory Object)をmacOS上で再現するための実装方針を説明します。

## 目的
- 名前付き共有メモリを用いてプロセス間で64KBのデータ領域を共有する
- 名前付きセマフォを利用して排他制御を行う
- ninix仕様に準拠した起動判定を実装する

## ninix仕様準拠について

本実装はninix/ninix-kagariのFMO仕様に準拠しています。

### 起動判定方法
POSIX環境では `shm_open('/ninix', O_RDWR, 0)` が成功するかで他のベースウェアが起動しているかを判定します。

- 成功 → 既に他のベースウェアが起動中
- 失敗(errno == ENOENT) → 起動していない
- その他のエラー → 権限不足など

### 使用するリソース名
ninixとの互換性のため、以下の名前を使用します：

- 共有メモリ名: `/ninix`
- セマフォ名: `/ninix_mutex`

### FMO内容
共有メモリには以下の構造でデータを格納します：

```c
struct shm_t {
    uint32_t size;      // データサイズ（先頭4バイト）
    sem_t sem;          // セマフォ（POSIX環境）
    char buf[PATH_MAX]; // UNIXソケットがあるディレクトリのパス
};
```

ninixではFMOはベースウェアの情報ではなく、ベースウェアの情報を取得できるUNIXソケットがあるディレクトリを保持します。パスは末尾が `/` で終わります（例：`/home/user/.ninix/sock/`）。

## 主要クラス

### `FmoMutex`
- 名前付きセマフォをラップしたMutexクラス
- `lock()` と `unlock()` で排他制御を行います
- `createNew` パラメータで新規作成モードと既存オープンモードを切り替え可能
- 作成者のみが `cleanup()` 時に `sem_unlink` を実行します

### `FmoSharedMemory`
- POSIX共有メモリをSwiftから扱うためのラッパー
- `shm_open` 後に `shm_unlink` を行い、最後のクローズで自動削除されるエフェメラル運用を採用
- 先頭4バイトにデータサイズ、末尾にNUL終端を書き込みます
- `createNew` パラメータで新規作成モードと既存オープンモードを切り替え可能
- 作成者のみが `cleanup()` 時に `shm_unlink` を実行します（ただしエフェメラルモードでは作成直後に既にunlink済み）

### `FmoManager`
- 上記2つをまとめて初期化し、アプリケーション起動時に使用します
- `isAnotherInstanceRunning()` 静的メソッドで他のベースウェアの起動判定が可能

## 使用例

### 起動判定と初期化
```swift
// 1. まず他のベースウェアが起動しているか確認
if FmoManager.isAnotherInstanceRunning(sharedName: "/ninix") {
    NSLog("Another baseware instance is already running")
    exit(1)
}

// 2. 起動していなければFMOリソースを作成
do {
    let manager = try FmoManager(mutexName: "/ninix_mutex", sharedName: "/ninix")
    // 使用...
} catch {
    NSLog("FMO initialization failed: \(error)")
}
```

### データの読み書き
```swift
try manager.memory.write(data, mutex: manager.mutex)
let received = try manager.memory.read(mutex: manager.mutex)
```

### クリーンアップ
アプリケーション終了時には `cleanup()` を呼び、共有メモリとセマフォを解放します：

```swift
manager.cleanup()
```

## 実装の流れ

1. **起動判定**: `FmoManager.isAnotherInstanceRunning()` で他インスタンスの存在を確認
2. **FMO作成**: 他インスタンスがなければ `FmoManager(mutexName:sharedName:)` で初期化
3. **データ共有**: mutex で保護しながら共有メモリにデータを読み書き
4. **クリーンアップ**: 終了時に `cleanup()` でリソース解放

## エラーハンドリング

- `FmoError.alreadyRunning`: セマフォまたは共有メモリが既に存在する（他インスタンス起動中）
- `FmoError.systemError(String)`: システムエラー（権限不足、リソース不足など）

起動判定を先に行うことで、不必要な `alreadyRunning` エラーを回避できます。

## 技術的な詳細

### C Bridge関数
Swift から POSIX API を呼び出すために以下のブリッジ関数を実装しています（`FmoBridge.c/h`）：

#### 共有メモリ操作
- `fmo_open_shared()`: 共有メモリを新規作成
- `fmo_open_existing_shared()`: 既存の共有メモリを開く
- `fmo_map()`: メモリマッピング
- `fmo_munmap()`: マッピング解除
- `fmo_shm_unlink()`: 共有メモリ削除

#### セマフォ操作
- `fmo_sem_open()`: セマフォを開く/作成
- `fmo_sem_wait()`: ロック取得
- `fmo_sem_post()`: ロック解放
- `fmo_sem_close()`: セマフォクローズ
- `fmo_sem_unlink()`: セマフォ削除

#### 起動判定
- `fmo_check_running()`: ninix仕様に基づく起動判定
  - `shm_open(name, O_RDWR, 0)` で既存の共有メモリを開けるか試行
  - 戻り値: 1=起動中, 0=未起動, -1=エラー

### 注意事項

- **32/64bit非互換**: 32bitと64bitプロセス間ではFMOをやり取りできません
- **権限**: サンドボックス環境では共有メモリやセマフォへのアクセスが制限される場合があります
- **リソース名**: ninix互換性のため `/ninix` と `/ninix_mutex` を使用しますが、必要に応じて変更可能です
- **エフェメラル運用**: 共有メモリは作成直後に `shm_unlink` され、全プロセスがクローズすると自動削除されます

## 実装状況（Implementation Status）

**更新日:** 2025-10-20

### Ourin における実装

- [x] **完全実装済み**: FMO システムは完全に実装され、動作確認済み
- [x] **起動判定**: `FmoManager.isAnotherInstanceRunning()` による ninix 仕様準拠の起動判定
- [x] **共有メモリ管理**: `FmoSharedMemory` による POSIX 共有メモリの管理
- [x] **排他制御**: `FmoMutex` による名前付きセマフォの実装
- [x] **C ブリッジ**: POSIX API へのブリッジ関数群（`FmoBridge.c/h`）
- [x] **エフェメラル運用**: 共有メモリの自動削除機能
- [x] **エラーハンドリング**: `FmoError` による適切なエラー処理

### 実装済みの機能

1. **POSIX 共有メモリ**
   - `shm_open()` による共有メモリの作成/オープン
   - `mmap()` によるメモリマッピング
   - `shm_unlink()` による自動削除

2. **名前付きセマフォ**
   - `sem_open()` によるセマフォの作成/オープン
   - `sem_wait()`/`sem_post()` による排他制御
   - `sem_unlink()` による削除

3. **ninix 互換起動判定**
   - `/ninix` 共有メモリの存在確認
   - `O_RDWR` モードでの既存メモリオープン試行
   - errno に基づくエラー判定

4. **Swift インターフェース**
   - `FmoManager`: 全体管理クラス
   - `FmoSharedMemory`: 共有メモリラッパー
   - `FmoMutex`: セマフォラッパー
   - `FmoError`: エラー型定義

### 実装ファイル

- `Ourin/FMO/FmoManager.swift`: FMO 管理クラス
- `Ourin/FMO/FmoSharedMemory.swift`: 共有メモリラッパー
- `Ourin/FMO/FmoMutex.swift`: Mutex ラッパー
- `Ourin/FMO/FmoError.swift`: エラー定義
- `Ourin/FMO/FmoBridge.c`: C ブリッジ実装
- `Ourin/FMO/FmoBridge.h`: C ブリッジヘッダ

### 動作確認

- ✅ 単一インスタンス起動制御
- ✅ 複数インスタンス起動時のエラー検出
- ✅ 共有メモリへの読み書き
- ✅ セマフォによる排他制御
- ✅ プロセス終了時のリソース解放
