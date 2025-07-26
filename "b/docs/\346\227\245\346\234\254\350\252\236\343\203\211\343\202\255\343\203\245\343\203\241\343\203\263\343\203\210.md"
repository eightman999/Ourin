# FMO機能について

このドキュメントでは、Windows向けゲームやゴーストで利用されているFMO(Forged Memory Object)をmacOS上で再現するための実装方針を説明します。

## 目的
- 名前付き共有メモリを用いてプロセス間で64KBのデータ領域を共有する
- 名前付きセマフォを利用して排他制御を行う
- 起動判定としてセマフォが既に存在するかどうかを確認する

## 主要クラス
- `FmoMutex`
  - 名前付きセマフォをラップしたMutexクラス
  - `lock()` と `unlock()` で排他制御を行います
- `FmoSharedMemory`
  - POSIX共有メモリをSwiftから扱うためのラッパー
  - `shm_open` 後に `shm_unlink` を行い、最後のクローズで自動削除されるエフェメラル運用を採用
  - 先頭4バイトにデータサイズ、末尾にNUL終端を書き込みます
- `FmoManager`
  - 上記2つをまとめて初期化し、アプリケーション起動時に使用します

## 使用例
```swift
let manager = try FmoManager()
try manager.memory.write(data, mutex: manager.mutex)
let received = try manager.memory.read(mutex: manager.mutex)
```

アプリケーション終了時には `cleanup()` を呼び、共有メモリとセマフォを解放します。
