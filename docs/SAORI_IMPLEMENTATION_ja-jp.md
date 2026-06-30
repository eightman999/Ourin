# Ourin における SAORI 実装

## スコープ

Ourin は `Ourin/SaoriHost/` の SAORI/1.0 ホスト側サポートを実装し、YAYA ランタイム呼び出しにブリッジしています。

主要ファイル：

- `SaoriLoader.swift`
- `SaoriProtocol.swift`
- `SaoriRegistry.swift`
- `SaoriManager.swift`
- `YayaAdapter.swift` (ブリッジ)
- `yaya_core/src/VM.cpp`, `yaya_core/src/YayaCore.cpp` (プラグイン操作)

## モジュールロード (`SaoriLoader`)

`SaoriLoader` は `dlopen/dlsym/dlclose` で動的ロードを処理します：

- シンボルバリアントを解決：
  - `request` / `saori_request`
  - `load` / `saori_load`
  - `unload` / `saori_unload`
- 利用可能な場合 `load(directory)` を呼び出し
- バイナリリクエストペイロードを `request(...)` に送信
- 設定文字セット (UTF-8 フォールバック) で応答をデコード

エラーケースは `SaoriLoaderError` で表示されます。

## プロトコルハンドリング (`SaoriProtocol`)

`SaoriProtocol` は以下を提供します：

- SAORI リクエストパーサー
- SAORI レスポンスパーサー/ビルダー
- 文字セット変換ヘルパー

サポートされるエンコーディング：

- UTF-8
- Shift-JIS ファミリーエイリアス (`sjis`, `cp932`, `windows-31j`, ...)
- EUC-JP
- ISO-2022-JP

## 検出とキャッシュ (`SaoriRegistry`)

`SaoriRegistry` は以下を管理します：

- 検索パス
- ゴーストルート下の `.saori` 検出
- モジュール名の正規化 (`foo`, `foo.dylib`, `libfoo.dylib`, ...)
- ローダーキャッシュとアンロードライフサイクル

デフォルト検索ロケーションにはアプリリソースとユーザー Application Support が含まれます。

## 統合 API (`SaoriManager`)

`SaoriManager` は単一エントリーポイントを提供します：

- モジュールの検出/ロード/アンロード
- 文字セット付きリクエストテキストの送信
- プラグイン操作の処理：
  - `saori_load`
  - `saori_unload`
  - `saori_request`

## YAYA ブリッジパス

実行時チェーン：

1. YAYA スクリプトが `LOADLIB` / `UNLOADLIB` / `REQUESTLIB` を呼び出し
2. `VM.cpp` が `pluginOperation(...)` に転送
3. `YayaCore.cpp` がホスト操作 JSON (`host_op`) を発行
4. `YayaAdapter.swift` が `host_op=plugin` を受信
5. `YayaAdapter.handlePluginOperation(...)` が `SaoriManager` に委譲
6. 結果 JSON が `yaya_core` に戻される

`YayaAdapter` はヘルパー `handleSaoriRequest(...)` も公開します。

## テストと サンプル

テスト：

- `OurinTests/SaoriProtocolTests.swift`
- `OurinTests/SaoriRegistryTests.swift`

サンプル：

- `Samples/SimpleSaori/CppSimpleSaori`
- `Samples/SimpleSaori/SwiftSimpleSaori`

両方のサンプルモジュールは `load/unload/request` を実装しています。

## 現在のステータス

**ステータス**: 統合完了（コアパス）/ 2026-03-15

主要な SAORI コンポーネントは、VM → YayaCore → YayaAdapter → SaoriManager パス経由で YAYA ランタイムに統合されました。

### 実装済みコンポーネント
- ✅ **SaoriLoader.swift** - dlopen/dlsym での macOS ネイティブ .dylib ロード
- ✅ **SaoriProtocol.swift** - SAORI/1.0 リクエスト/レスポンスパース
- ✅ **SaoriRegistry.swift** - モジュール検出とキャッシング
- ✅ **SaoriManager.swift** - SAORI 操作用の統合 API
- ✅ **テストファイル** - SaoriProtocolTests.swift、SaoriRegistryTests.swift

### 統合ステータス
- ✅ **VM.cpp** - LOADLIB/UNLOADLIB/REQUESTLIB が pluginOperation ブリッジを呼び出し
- ✅ **YayaCore.cpp** - pluginOperation が handlePluginOperation で検証経由でルーティング
- ✅ **YayaAdapter.swift** - handlePluginOperation / handleSaoriRequest が SaoriManager に委譲
- ✅ **操作パス** - YAYA スクリプトが SAORI モジュールをロード/リクエスト/アンロード可能

### ブロック中の問題
- ✅ **ID-001**: 解決済み
- ✅ **ID-002**: 解決済み

### 統合実施記録

フェーズ 1 の統合作業は完了し、コードとテストで追跡されています：

1. ✅ **VM.cpp ブリッジパス** (タスク 1.1 完了)
2. ✅ **YayaCore プラグイン操作ルーティング** (タスク 1.2 完了)
3. ✅ **YayaAdapter SAORI ブリッジ配線** (タスク 1.3 完了)
4. ✅ **サンプル + スモークカバレッジ** (タスク 1.4-1.5 完了)

### 成功基準
- [x] LOADLIB が .dylib モジュールを正常にロード
- [x] REQUESTLIB がリクエストを送信して応答を受信
- [x] UNLOADLIB がモジュールをアンロード
- [x] 統合スモークテストが成功
- [x] SAORI ブロッカーが残存しない (ID-001、ID-002 解決済み)

---

## 現在の制限

- SAORI モジュール ABI の差異は共通シンボルエイリアスのみで処理されます。
- レスポンスメモリの所有権はモジュール動作に依存します。モジュールは SAORI 規約に従うべきです。
- 拡張 SAORI セキュリティポリシーはまだ完全には形式化されていません (将来の強化項目)。
- エンドツーエンドゴースト動作検証は、より広い実ゴーストカバレッジのため進行中です。
