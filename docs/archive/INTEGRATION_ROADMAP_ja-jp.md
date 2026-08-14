# 統合ロードマップ

**最終更新**: 2026年3月15日
**状態**: アクティブ
**目的**: 既存のスタブ実装を機能させるための詳細な統合計画

---

# エグゼクティブサマリー

## 現状

すべての主要コンポーネントはコードファイルとして実装されていますが、ほとんどはシステムの他の部分と**統合されていません**。このロードマップは、適切な統合作業を通じてこれらのスタブを機能させることに焦点を当てています。

## 統合の哲学

**スタブを機能させる** - 新しいコンポーネントを作成するのではなく、既存のものを統合する。

**統合を新機能より優先** - 最初にエンドツーエンドの機能に集中する。

**早く頻繁にテストする** - 各ステップで統合を検証する。

---

# 統合フェーズ

## フェーズ1: SAORI機能化

### 概要

既存のSAORIシステムをYAYA Coreと統合し、ゴーストがSAORIモジュールをロード・実行できるようにする。

### 前提条件

- ✅ SaoriLoader.swift存在（macOS ネイティブ .dylib ロード）
- ✅ SaoriProtocol.swift存在（SAORI/1.0 プロトコル）
- ✅ SaoriRegistry.swift存在（モジュール検出）
- ✅ SaoriManager.swift存在（統一API）
- ✅ YAYA Core VM は LOADLIB/UNLOADLIB/REQUESTLIB スタブを保有
- ✅ YayaAdapter.swift存在（SHIORI アダプター）

### 統合タスク

#### タスク1.1: VM.cpp プラグイン操作実装

**ファイル**: `yaya_core/src/VM.cpp`

**現在の状態**: LOADLIB/UNLOADLIB/REQUESTLIBは互換性値を返すスタブ実装。

**必要な変更**:

```cpp
// VM.cpp内で、スタブ実装を置き換え:
Value VM::loadlib(const std::string& module) {
    // 互換性値を返す代わりに:
    // return Value(1); // スタブ
    
    // ホストにプラグイン操作を送出:
    nlohmann::json request;
    request["cmd"] = "plugin";
    request["operation"] = "saori_load";
    request["module"] = module;
    
    nlohmann::json response = sendToHost(request);
    return Value(response["result"].get<int>());
}

Value VM::unloadlib(int handle) {
    nlohmann::json request;
    request["cmd"] = "plugin";
    request["operation"] = "saori_unload";
    request["handle"] = handle;
    
    nlohmann::json response = sendToHost(request);
    return Value(response["result"].get<int>());
}

Value VM::requestlib(int handle, const std::string& text) {
    nlohmann::json request;
    request["cmd"] = "plugin";
    request["operation"] = "saori_request";
    request["handle"] = handle;
    request["text"] = text;
    
    nlohmann::json response = sendToHost(request);
    return Value(response["result"].get<std::string>());
}
```

**テスト**:
- OnBootでLOADLIBを呼び出すテストゴーストを作成
- YayaCoreが "host_op" JSON を受け取ることを確認
- YayaAdapterがリクエストを処理することを確認

**依存関係**: なし

**推定作業時間**: 2～3時間

---

#### タスク1.2: YayaCore.cpp pluginOperation() 実装

**ファイル**: `yaya_core/src/YayaCore.cpp`

**現在の状態**: pluginOperation()は存在しないか、スタブ。

**必要な変更**:

```cpp
// YayaCore クラスに追加:
void YayaCore::handlePluginOperation(const nlohmann::json& request) {
    std::string operation = request["operation"].get<std::string>();
    
    if (operation == "saori_load") {
        // ロードロジック
    } else if (operation == "saori_unload") {
        // アンロードロジック
    } else if (operation == "saori_request") {
        // リクエストロジック
    }
}

// processCommand()にケースを追加:
if (cmd == "plugin") {
    handlePluginOperation(data);
}
```

**テスト**:
- VM が "host_op" を送出したときに pluginOperation が呼ばれることを確認
- 操作が正しく解析されることを確認

**依存関係**: タスク1.1

**推定作業時間**: 1～2時間

---

#### タスク1.3: YayaAdapter.handleSaoriRequest() 実装

**ファイル**: `Ourin/Yaya/YayaAdapter.swift`

**現在の状態**: handleSaoriRequest()は存在しないか、SaoriManager に委譲しない。

**必要な変更**:

```swift
extension YayaAdapter {
    func handleSaoriRequest(operation: String, payload: [String: Any]) async throws -> [String: Any] {
        switch operation {
        case "saori_load":
            guard let moduleName = payload["module"] as? String else {
                throw YayaAdapterError.invalidPayload
            }
            let handle = try await saoriManager.loadModule(moduleName)
            return ["result": handle]
            
        case "saori_unload":
            guard let handle = payload["handle"] as? Int else {
                throw YayaAdapterError.invalidPayload
            }
            try await saoriManager.unloadModule(handle: handle)
            return ["result": 0]
            
        case "saori_request":
            guard let handle = payload["handle"] as? Int,
                  let text = payload["text"] as? String else {
                throw YayaAdapterError.invalidPayload
            }
            let response = try await saoriManager.request(handle: handle, text: text)
            return ["result": response]
            
        default:
            throw YayaAdapterError.unknownOperation
        }
    }
    
    func handlePluginOperation(_ request: [String: Any]) async throws -> [String: Any] {
        guard let operation = request["operation"] as? String else {
            throw YayaAdapterError.invalidPayload
        }
        return try await handleSaoriRequest(operation: operation, payload: request)
    }
}
```

**テスト**:
- テスト用 .dylib SAORI モジュールを作成
- YAYA スクリプトからモジュールをロード
- リクエストを送信し応答を確認
- モジュールをアンロード

**依存関係**: タスク1.2

**推定作業時間**: 2～3時間

---

#### タスク1.4: テスト用サンプルSAORIモジュール作成

**ファイル**: `Samples/SimpleSaori/SimpleSaori.swift`

**目的**: SAORI ロード・実行テスト。

**実装**:

```swift
import Foundation

// SAORI モジュール関数
@_cdecl("request")
func request(_ text: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
    let message = String(cString: text)
    let response = "Echo: \(message)"
    return strdup(response)
}

@_cdecl("load")
func load(_ directory: UnsafePointer<CChar>) -> Int32 {
    print("SAORI loaded from: \(String(cString: directory))")
    return 1
}

@_cdecl("unload")
func unload() -> Int32 {
    print("SAORI unloaded")
    return 1
}
```

**テスト**:
- .dylib にコンパイル
- テストゴーストからロード
- load/unload/request が動作することを確認

**依存関係**: タスク1.3

**推定作業時間**: 1～2時間

---

### フェーズ1成功基準

- [ ] LOADLIB が .dylib モジュールを正常にロード
- [ ] REQUESTLIB がリクエストを送信して応答を受け取る
- [ ] UNLOADLIB がモジュールをアンロード
- [ ] 統合テストが成功
- [ ] サンプルSAORIモジュールがエンドツーエンドで動作
- [ ] SAORIブロッカーなし（ID-001、ID-002 解決）

### ロールバック計画

統合が失敗した場合:
1. YayaAdapter 変更を revert
2. VM.cpp スタブが互換性値を返すままに
3. 統合が失敗した理由をドキュメント化

---

## フェーズ2: SSTP統合完成

### 概要

実際のBridgeToSHIORIを実装し、外部SSTP通信を有効にする。

### 前提条件

- ✅ SSTPDispatcher.swift存在（すべてのSSTPメソッドを解析）
- ✅ SSTPResponse.swift存在（ワイヤーフォーマット生成）
- ✅ ShioriHost存在（SHIORI/3.0M実装）
- ⚠️ BridgeToSHIORI はモック/スタブ

### 統合タスク

#### タスク2.1: 実際のBridgeToSHIORI実装

**ファイル**: `Ourin/SSTP/BridgeToSHIORI.swift`（作成が必要な可能性）

**現在の状態**: BridgeToSHIORI.handle() はスタブ。

**必要な変更**:

```swift
import Foundation

class BridgeToSHIORI {
    private let shioriHost: ShioriHost
    private let ghostManager: GhostManager
    
    init(shioriHost: ShioriHost, ghostManager: GhostManager) {
        self.shioriHost = shioriHost
        self.ghostManager = ghostManager
    }
    
    func handle(
        method: String,
        event: String,
        references: [String],
        headers: [String: String]
    ) async -> [String: String] {
        // SHIORI リクエストを構築
        var shioriRequest: [String: String] = [:]
        shioriRequest["ID"] = event
        shioriRequest["Charset"] = headers["Charset"] ?? "UTF-8"
        
        // References を追加
        for (index, value) in references.enumerated() {
            shioriRequest["Reference\(index)"] = value
        }
        
        // 関連ヘッダーを追加
        if let sender = headers["Sender"] {
            shioriRequest["Sender"] = sender
        }
        if let senderType = headers["SenderType"] {
            shioriRequest["SenderType"] = senderType
        }
        
        // SHIORI に送信
        do {
            let shioriResponse = try await shioriHost.request(shioriRequest)
            return shioriResponse
        } catch {
            // エラー応答を返す
            return [
                "Status": "500",
                "Charset": "UTF-8",
                "Value": "SHIORI request failed: \(error.localizedDescription)"
            ]
        }
    }
}
```

**テスト**:
- 外部アプリから SSTP リクエストをモック
- BridgeToSHIORI が ShioriHost を呼び出すことを確認
- 応答が正しくフォーマットされることを確認

**依存関係**: なし

**推定作業時間**: 3～4時間

---

#### タスク2.2: SSTPDispatcher を実際のブリッジに接続

**ファイル**: `Ourin/SSTP/SSTPDispatcher.swift`

**現在の状態**: routeToShiori() はスタブ BridgeToSHIORI を呼び出す。

**必要な変更**:

```swift
class SSTPDispatcher {
    private let bridgeToSHIORI: BridgeToSHIORI
    
    init(bridgeToSHIORI: BridgeToSHIORI) {
        self.bridgeToSHIORI = bridgeToSHIORI
    }
    
    private func routeToShiori(
        request: SSTPRequest,
        method: String,
        event: String
    ) async -> SSTPResponse {
        // References を抽出
        var references: [String] = []
        
        // Reference0..N ヘッダーを追加
        var index = 0
        while let ref = request.headers["Reference\(index)"] {
            references.append(ref)
            index += 1
        }
        
        // 特定のメソッド用に Sentence/Command を追加
        if method == "communicate", let sentence = request.headers["Sentence"] {
            references.append(sentence)
        }
        
        // 実際のブリッジを呼び出す
        let shioriResponse = await bridgeToSHIORI.handle(
            method: method,
            event: event,
            references: references,
            headers: request.headers
        )
        
        // SSTP 応答に変換
        return mapShioriResponse(shioriResponse, originalRequest: request)
    }
    
    private func mapShioriResponse(
        _ response: [String: String],
        originalRequest: SSTPRequest
    ) -> SSTPResponse {
        var sstpResponse = SSTPResponse()
        
        // ステータスをマップ
        if let status = response["Status"] {
            sstpResponse.statusCode = status
        }
        
        // ヘッダーをマップ
        if let script = response["Value"] {
            sstpResponse.headers["Script"] = script
        }
        
        // 他のヘッダーを保持
        for (key, value) in response {
            if key != "Status" && key != "Value" {
                sstpResponse.headers[key] = value
            }
        }
        
        // パススルーを保持
        if let passThru = originalRequest.headers["X-SSTP-PassThru"] {
            sstpResponse.headers["X-SSTP-PassThru"] = passThru
        }
        
        return sstpResponse
    }
}
```

**テスト**:
- SSTP SEND リクエストを送信
- SHIORI が OnChoose イベントを受け取ることを確認
- SHIORI 応答が SSTP に変換されることを確認
- すべてのSSTPメソッドをテスト（SEND、NOTIFY、COMMUNICATE、EXECUTE、GIVE、INSTALL）

**依存関係**: タスク2.1

**推定作業時間**: 2～3時間

---

#### タスク2.3: エンドツーエンドSSTPテスト

**目的**: 外部アプリが SSTP 経由で通信できることを確認。

**テストケース**:

1. **基本通信**
   - SSTP SEND リクエストを送信
   - スクリプト付き SSTP 応答を受け取る
   - SHIORI イベントがトリガーされたことを確認

2. **イベント解決**
   - イベント ヘッダーオーバーライドでテスト
   - 各メソッドのデフォルト イベント マッピングをテスト

3. **ヘッダー伝搬**
   - Sender、SenderType、Charset が SHIORI に渡されることを確認
   - X-SSTP-PassThru が保持されることを確認

4. **エラー処理**
   - 無効なゴースト（OnChoose イベントなし）でテスト
   - ネットワークエラーでテスト
   - 適切なステータスコードを確認

**依存関係**: タスク2.2

**推定作業時間**: 2～3時間

---

### フェーズ2成功基準

- [ ] 外部アプリが SSTP リクエストを送信可能
- [ ] リクエストが SHIORI システムに到達
- [ ] SHIORI がリクエストを処理して応答を生成
- [ ] 応答が外部アプリに返される
- [ ] すべてのSSTPメソッドが動作（SEND、NOTIFY、COMMUNICATE、EXECUTE、GIVE、INSTALL）
- [ ] 統合テストが成功
- [ ] SSTPブロッカーなし（ID-003 解決）

### ロールバック計画

統合が失敗した場合:
1. スタブ BridgeToSHIORI を維持
2. 統合が失敗した理由をドキュメント化
3. 代替案: 直接 YAYA-to-SSTP ブリッジを実装（SHIORI をバイパス）

---

## フェーズ3: SERIKOエグゼキューター統合

### 概要

SerikoExecutor を GhostManager と SakuraScriptEngine に接続し、アニメーションコマンドを機能させる。

### 前提条件

- ✅ SerikoParser.swift存在（完全なSERIKO/2.0 パーサー）
- ✅ SerikoExecutor.swift存在（アニメーション実行エンジン）
- ✅ GhostManager存在（ゴースト状態管理）
- ⚠️ SerikoExecutor が GhostManager に接続されていない
- ⚠️ SakuraScriptEngine アニメーションコマンドはスタブ

### 統合タスク

#### タスク3.1: SerikoExecutor を GhostManager に接続

**ファイル**: `Ourin/Ghost/GhostManager+Animation.swift`（拡張が必要な可能性）

**現在の状態**: GhostManager はアニメーションハンドラーを持つが、SerikoExecutor コールバックが接続されていない。

**必要な変更**:

```swift
extension GhostManager {
    // setupAnimationExecutor内で:
    private func setupAnimationExecutor() {
        serikoExecutor.onMethodInvoked = { [weak self] method in
            guard let self = self else { return }
            self.handleSerikoMethod(method)
        }
        
        serikoExecutor.onPatternExecuted = { [weak self] pattern in
            guard let self = self else { return }
            self.handleSerikoPattern(pattern)
        }
        
        serikoExecutor.onAnimationFinished = { [weak self] animationId in
            guard let self = self else { return }
            self.handleAnimationFinished(animationId)
        }
    }
    
    private func handleSerikoMethod(_ method: SerikoMethod) {
        switch method {
        case .overlay(let surfaceId, let overlayId, let x, let y):
            handleSurfaceOverlay(surfaceId: surfaceId, overlayId: overlayId, x: x, y: y)
            
        case .overlayFast(let surfaceId, let overlayId, let x, let y):
            handleSurfaceOverlayFast(surfaceId: surfaceId, overlayId: overlayId, x: x, y: y)
            
        case .base(let surfaceId, let baseId):
            handleAnimAddBase(surfaceId: surfaceId, baseId: baseId)
            
        case .move(let surfaceId, let x, let y, let time):
            handleAnimAddMove(surfaceId: surfaceId, x: x, y: y, time: time)
            
        case .reduce(let surfaceId, let amount):
            // リダクション処理
            
        case .replace(let surfaceId, let replacementId):
            handleSurfaceOverlay(surfaceId: surfaceId, overlayId: replacementId, x: 0, y: 0, replace: true)
            
        case .start(let animationId):
            serikoExecutor.executeAnimation(id: animationId)
            
        case .alternativeStart(let animationId):
            serikoExecutor.executeAnimation(id: animationId)
            
        case .stop(let animationId):
            serikoExecutor.stopAnimation(id: animationId)
            
        case .asis:
            // 現在の状態を維持
        }
    }
    
    private func handleSerikoPattern(_ pattern: SerikoPattern) {
        // パターンに基づいてサーフェスを更新
        // これは描画エンジン実装に依存
    }
    
    private func handleAnimationFinished(_ animationId: Int) {
        // 関心者に通知
        // SakuraScript \__w[animation, animationId] 完了をトリガーする可能性
    }
}
```

**テスト**:
- surfaces.txt でアニメーション付きゴーストをロード
- アニメーションが正常に解析されることを確認
- SerikoExecutor に登録すること
- アニメーション実行してコールバック発火を確認

**依存関係**: なし

**推定作業時間**: 3～4時間

---

#### タスク3.2: SakuraScript アニメーションコマンド実装

**ファイル**: `Ourin/SakuraScript/SakuraScriptEngine.swift`

**現在の状態**: アニメーション コマンドはスタブ。

**必要な変更**:

```swift
extension SakuraScriptEngine {
    private func handleAnimCommand(arguments: [String]) {
        guard arguments.count >= 1 else { return }
        
        let command = arguments[0]
        
        switch command {
        case "clear":
            handleAnimClear(arguments: Array(arguments.dropFirst()))
            
        case "pause":
            handleAnimPause(arguments: Array(arguments.dropFirst()))
            
        case "resume":
            handleAnimResume(arguments: Array(arguments.dropFirst()))
            
        case "offset":
            handleAnimOffset(arguments: Array(arguments.dropFirst()))
            
        case "add":
            handleAnimAdd(arguments: Array(arguments.dropFirst()))
            
        case "stop":
            handleAnimStop(arguments: Array(arguments.dropFirst()))
            
        default:
            // 不明なアニメーション コマンド
            break
        }
    }
    
    private func handleAnimClear(arguments: [String]) {
        // サーフェスのすべてのアニメーションをクリア
        // IDが指定されている場合、特定のアニメーションをクリア
        // serikoExecutor.stopAllAnimations()
        // または serikoExecutor.stopAnimation(id: animationId)
    }
    
    private func handleAnimPause(arguments: [String]) {
        // アニメーションを一時停止
        guard arguments.count >= 1, let animationId = Int(arguments[0]) else { return }
        serikoExecutor.pauseAnimation(id: animationId)
    }
    
    private func handleAnimResume(arguments: [String]) {
        // アニメーションを再開
        guard arguments.count >= 1, let animationId = Int(arguments[0]) else { return }
        serikoExecutor.resumeAnimation(id: animationId)
    }
    
    private func handleAnimOffset(arguments: [String]) {
        // アニメーション タイミングをオフセット
        guard arguments.count >= 2,
              let animationId = Int(arguments[0]),
              let offset = Int(arguments[1]) else { return }
        serikoExecutor.offsetAnimation(id: animationId, offset: offset)
    }
    
    private func handleAnimAdd(arguments: [String]) {
        // アニメーション パターンを追加
        guard arguments.count >= 1 else { return }
        
        let method = arguments[0]
        let args = Array(arguments.dropFirst())
        
        // メソッド タイプに基づいて解析
        // 次のいずれでも: overlay、base、move、text など
        // これは複雑なSERIKO構文の解析が必要
        // 当面、基本的なoverlayを実装
        if method == "overlay", args.count >= 3,
           let surfaceId = Int(args[0]),
           let overlayId = Int(args[1]),
           let x = Int(args[2]),
           let y = Int(args[3]) {
            // アニメーションにoverlayパターンを追加
            // serikoExecutor.addPattern(...)
        }
    }
    
    private func handleAnimStop(arguments: [String]) {
        // アニメーションを停止
        guard arguments.count >= 1, let animationId = Int(arguments[0]) else { return }
        serikoExecutor.stopAnimation(id: animationId)
    }
    
    private func handleWaitForAnimation(arguments: [String]) {
        // アニメーション完了まで待つ
        guard arguments.count >= 1, let animationId = Int(arguments[0]) else { return }
        // アニメーション完了のためのコールバックを登録
        // 完了時、スクリプト実行を継続
    }
}
```

**テスト**:
- \![anim,clear] コマンドを実行
- \![anim,pause,ID] コマンドを実行
- \![anim,resume,ID] コマンドを実行
- \![anim,offset,ID,offset] コマンドを実行
- \![anim,add,...] コマンドを実行
- \![anim,stop,ID] コマンドを実行
- \__w[animation,ID] 待機コマンドを実行
- アニメーションが正しく再生されることを確認

**依存関係**: タスク3.1

**推定作業時間**: 4～5時間

---

#### タスク3.3: アニメーション再生テスト

**テストケース**:

1. **基本アニメーション**
   - シンプルなoverlayアニメーション付きゴーストをロード
   - SakuraScript 経由でアニメーションをトリガー
   - 画面でアニメーション再生を確認

2. **アニメーション制御**
   - アニメーションを一時停止
   - アニメーションを再開
   - アニメーション タイミングをオフセット
   - アニメーションを停止

3. **複数アニメーション**
   - 複数アニメーションを同時に実行
   - 干渉しないことを確認

4. **アニメーション イベント**
   - yen-e アニメーションをトリガー
   - トーク アニメーションをトリガー
   - bind アニメーションをトリガー

**注意**: Dressup機能はビルド失敗のため延期（ID-005）。フェーズ4以降で対応予定。

**依存関係**: タスク3.2

**推定作業時間**: 3～4時間

---

### フェーズ3成功基準

- [ ] SerikoExecutor が GhostManager に接続
- [ ] アニメーション コマンドが正しく実行
- [ ] アニメーション画面再生
- [ ] Pause/resume/offset 動作
- [ ] 複数アニメーション同時実行可能
- [ ] 統合テスト成功
- [ ] 重大SERIKO ブロッカー解決（ID-004、ID-006）
- [ ] 注記: ID-005（dressup）は後のフェーズに延期

### ロールバック計画

統合が失敗した場合:
1. スタブ アニメーション コマンドを維持
2. どのアニメーションが動作するかをドキュメント化
3. 代替アニメーション システム検討（例：SpriteKit ベース）

---

## フェーズ4: SakuraScript実行完成

### 概要

不足しているコマンド実装を実装し、90%以上のコマンド実行率を達成する。

### 前提条件

- ✅ SakuraScriptEngine.swift存在（包括的解析）
- ✅ 34コマンド完全実装
- ⚠️ 18コマンド部分実装
- ❌ 26コマンド未実装

### 統合タスク

#### タスク4.1: テキスト フォーマット実行実装

**ファイル**: `Ourin/SakuraScript/SakuraScriptEngine.swift`

**現在の状態**: テキスト フォーマット コマンド（\f[...]）解析済みだが実行されない。

**必要な変更**:

```swift
private func handleTextFormatting(arguments: [String]) {
    guard arguments.count >= 1 else { return }
    
    let tag = arguments[0]
    
    switch tag {
    case "font":
        handleFontChange(arguments: Array(arguments.dropFirst()))
        
    case "size":
        handleSizeChange(arguments: Array(arguments.dropFirst()))
        
    case "bold":
        handleBoldToggle()
        
    case "italic":
        handleItalicToggle()
        
    case "color":
        handleColorChange(arguments: Array(arguments.dropFirst()))
        
    // ... その他フォーマット タグ
    }
}

private func handleFontChange(arguments: [String]) {
    guard let fontName = arguments.first else { return }
    // 次のテキスト用に現在フォントを更新
    currentFont = fontName
}

private func handleSizeChange(arguments: [String]) {
    guard let fontSize = Int(arguments.first ?? "12") else { return }
    // 現在フォント サイズを更新
    currentFontSize = fontSize
}

private func handleBoldToggle() {
    isBold = !isBold
}

private func handleItalicToggle() {
    isItalic = !isItalic
}

private func handleColorChange(arguments: [String]) {
    // 色を解析（RGB、名前付き色など）
    // 現在テキスト色を更新
    if arguments.count >= 3,
       let r = Int(arguments[0]),
       let g = Int(arguments[1]),
       let b = Int(arguments[2]) {
        currentTextColor = Color(r: r, g: g, b: b)
    }
}
```

**テスト**:
- 様々なフォーマット タグをテスト
- レンダリングがフォーマットを正しく適用することを確認
- ネストされたフォーマットをテスト

**依存関係**: なし

**推定作業時間**: 3～4時間

---

#### タスク4.2: ゴースト/シェル/バルーン切り替え実装

**ファイル**: `Ourin/SakuraScript/SakuraScriptEngine.swift` および `Ourin/Ghost/GhostManager.swift`

**現在の状態**: 切り替えコマンド未実装。

**必要な変更**:

```swift
// SakuraScriptEngine内:
private func handleSurfaceCommand(arguments: [String]) {
    // \s[ID] - サーフェス切り替え
    guard arguments.count >= 1, let surfaceId = Int(arguments[0]) else { return }
    
    Task {
        await ghostManager.switchSurface(to: surfaceId)
    }
}

private func handleScopeCommand(arguments: [String]) {
    // \0、\1、\2... - キャラクター スコープ切り替え
    guard arguments.count >= 1, let scopeId = Int(arguments[0]) else { return }
    currentScope = scopeId
}

// GhostManager内:
func switchSurface(to surfaceId: Int) async {
    // 現在のサーフェスを更新
    currentSurfaceId = surfaceId
    
    // サーフェス イメージをロード
    // 表示を更新
    
    // 新しいサーフェスのSERIKO アニメーションをトリガー
    serikoExecutor.executeSurfaceAnimations(surfaceId: surfaceId)
}

func switchShell(to shellId: String) async {
    // 新しいシェルをロード
    // サーフェス定義を更新
    // アニメーションを再ロード
}

func switchBalloon(to balloonId: String) async {
    // 新しいバルーンをロード
    // テキスト レンダリングを更新
}
```

**テスト**:
- 異なるサーフェス間で切り替え
- イメージが正しく更新されることを確認
- 新しいサーフェスのアニメーション再生を確認
- シェルとバルーン切り替え

**依存関係**: タスク4.1

**推定作業時間**: 4～5時間

---

#### タスク4.3: ダイアログ コマンド実装

**ファイル**: `Ourin/SakuraScript/SakuraScriptEngine.swift`

**現在の状態**: ダイアログ コマンド未実装。

**必要な変更**:

```swift
private func handleDialogCommand(arguments: [String]) {
    guard arguments.count >= 1 else { return }
    
    let dialogType = arguments[0]
    
    switch dialogType {
    case "inputbox":
        handleInputBox(arguments: Array(arguments.dropFirst()))
        
    case "openfile":
        handleOpenFileDialog(arguments: Array(arguments.dropFirst()))
        
    case "savefile":
        handleSaveFileDialog(arguments: Array(arguments.dropFirst()))
        
    case "date":
        handleDatePicker(arguments: Array(arguments.dropFirst()))
        
    // ... その他ダイアログ タイプ
    }
}

private func handleInputBox(arguments: [String]) {
    let title = arguments.first ?? "Input"
    let defaultValue = arguments.count > 1 ? arguments[1] : ""
    
    // macOS 入力ダイアログを表示
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = ""
    alert.alertStyle = .informational
    
    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    input.stringValue = defaultValue
    alert.accessoryView = input
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    
    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
        let result = input.stringValue
        // スクリプトがアクセスできるように結果を保存
        dialogResult = result
        dialogResultAvailable = true
    }
}

private func handleOpenFileDialog(arguments: [String]) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    
    let response = panel.runModal()
    if response == .OK, let url = panel.url {
        dialogResult = url.path
        dialogResultAvailable = true
    }
}

// その他ダイアログ タイプの同様の実装
```

**テスト**:
- 各ダイアログ タイプをテスト
- 結果がスクリプトからアクセス可能であることを確認
- キャンセル操作をテスト

**依存関係**: タスク4.2

**推定作業時間**: 5～6時間

---

#### タスク4.4: 不正なコマンド セマンティクス修正

**ファイル**: `Ourin/SakuraScript/SakuraScriptEngine.swift`

**修正する問題**:

1. **\6 コマンド**: メニュー テキストを設定する必要があるが、正しく実装されていない
2. **\7 コマンド**: メニュー選択を実行する必要があるが、実装されていない
3. **\- コマンド**: コメント/区切り文字である必要があるが、実装されていない

**必要な変更**:

```swift
private func handleMenuCommand(arguments: [String]) {
    // \6[text] - メニュー テキストを設定
    guard arguments.count >= 1 else { return }
    let menuText = arguments[0]
    
    // メニュー項目リストに追加
    menuItems.append(menuText)
}

private func handleChoiceCommand(arguments: [String]) {
    // \7[index] - メニュー選択を実行
    guard arguments.count >= 1, let index = Int(arguments[0]) else { return }
    
    // インデックス別に選択を実行
    if index >= 0 && index < menuItems.count {
        // 選択されたメニュー項目でchoiceイベントをトリガー
        let selectedItem = menuItems[index]
        // これは OnChoiceSelect または同様のイベントをトリガー
    }
}

private func handleSeparatorCommand() {
    // \- - コメント/区切り文字
    // レンダリング観点からはno-op
    // 処理をスキップするだけ
}
```

**テスト**:
- メニュー機能をテスト
- 選択が正しく実行されることを確認
- 区切り文字をテスト

**依存関係**: タスク4.3

**推定作業時間**: 2～3時間

---

### フェーズ4成功基準

- [ ] テキスト フォーマット コマンドが機能（90%+ の \f タグ）
- [ ] ゴースト/シェル/バルーン切り替えが機能
- [ ] すべてのダイアログ コマンドが機能
- [ ] メニュー コマンド（\6、\7）が正しく機能
- [ ] 90%以上のコマンド実行率を達成
- [ ] 統合テスト成功
- [ ] 重大SakuraScript ブロッカー解決（ID-006、ID-007）

### ロールバック計画

統合が失敗した場合:
1. 部分実装済みコマンドを維持
2. どのコマンドが動作するかをドキュメント化
3. ゴーストが最も一般的に使用するコマンドを優先化

---

## フェーズ5: 統合テストと文書化

### 概要

実際のゴーストでのエンドツーエンドテスト、パフォーマンスプロファイリング、ドキュメント更新。

### 前提条件

- ✅ 全フェーズ前が完了
- ✅ 重大ブロッカーなし

### 統合タスク

#### タスク5.1: エンドツーエンドゴースト テスト

**テスト ゴースト**:

1. **Emily4**（複雑なYAYAゴースト）
   - 正常にロード
   - ブート シーケンス動作
   - 基本 対話動作
   - SAORI使用（存在する場合）
   - アニメーション再生

2. **シンプル テスト ゴースト**
   - 最小限の機能
   - デバッグが容易

3. **商用ゴースト**（入手可能な場合）
   - 実世界での使用をテスト

**テスト シナリオ**:

1. **ブート シーケンス**
   - OnBoot イベント発火
   - 初期サーフェス表示
   - 初期スクリプト実行

2. **対話**
   - クリック イベント機能
   - メニュー選択機能
   - 選択が正しいイベントを発火

3. **SSTP通信**
   - 外部アプリがリクエスト送信可能
   - ゴースト正しく応答

4. **SAORI使用**
   - ゴースト SAORIモジュール ロード可能
   - モジュール正しく実行

5. **アニメーション**
   - 対話でアニメーション再生
   - アニメーション一時停止/再開正しく機能

**依存関係**: 全フェーズ前

**推定作業時間**: 8～12時間

---

#### タスク5.2: パフォーマンス プロファイリング

**測定指標**:

1. **ゴースト ロード時間**
   - 目標: 一般的なゴースト < 2秒

2. **スクリプト実行**
   - 目標: 一般的なイベント応答 < 100ms

3. **SSTP応答時間**
   - 目標: < 200ms

4. **アニメーション フレーム レート**
   - 目標: スムーズ再生 60fps

5. **メモリ使用量**
   - 目標: 一般的なゴースト < 200MB

**ツール**:
- Instruments（macOS プロファイラー）
- カスタム ロギング

**依存関係**: タスク5.1

**推定作業時間**: 4～6時間

---

#### タスク5.3: ドキュメント更新

**更新するドキュメント**:

1. **IMPLEMENTATION_STATUS_SUMMARY.md**
   - ステータス行列を100%に更新
   - すべてのブロッカーを解決済みにマーク

2. **コンポーネント 実装ドキュメント**
   - SAORI_IMPLEMENTATION.md - 統合済みにマーク
   - SERIKO_IMPLEMENTATION.md - 統合済みにマーク
   - SSTP_DISPATCHER_GUIDE.md - 統合済みにマーク

3. **SUPPORTED_SAKURA_SCRIPT.md**
   - 実装ステータスを更新
   - 90%以上が実行済みにマーク

4. **移行ガイド作成**
   - 既存 Windows ゴースト向け
   - 非互換性をドキュメント化

5. **CLAUDE.md更新**
   - 新しい統合ステータスを反映
   - 必要に応じてビルド/テスト 指示を更新

**依存関係**: タスク5.2

**推定作業時間**: 4～6時間

---

### フェーズ5成功基準

- [ ] Emily4 ゴースト エンドツーエンド動作
- [ ] パフォーマンス指標が目標を達成
- [ ] すべてのドキュメント更新
- [ ] 移行ガイド作成
- [ ] 本番準備状態を達成

### ロールバック計画

重大問題が見つかった場合:
1. 問題を明確にドキュメント化
2. 可能な場合は回避策を提供
3. 将来の修正計画
4. 既知問題付き「ベータ」としてリリース

---

# 統合依存関係グラフ

```
フェーズ1: SAORI統合
  ├── タスク1.1: VM.cpp プラグイン操作
  ├── タスク1.2: YayaCore.cpp pluginOperation()
  ├── タスク1.3: YayaAdapter.handleSaoriRequest()
  └── タスク1.4: サンプルSAORIモジュール作成
       ↓ 必須

フェーズ2: SSTP統合
  ├── タスク2.1: BridgeToSHIORI実装
  ├── タスク2.2: SSTPDispatcher接続
  └── タスク2.3: エンドツーエンド テスト
       ↓ 有効化

フェーズ3: SERIKO統合
  ├── タスク3.1: SerikoExecutor を GhostManager に接続
  ├── タスク3.2: アニメーション コマンド実装
  └── タスク3.3: アニメーション再生テスト
       ↓ 拡張

フェーズ4: SakuraScript完成
  ├── タスク4.1: テキスト フォーマット
  ├── タスク4.2: ゴースト/シェル/バルーン切り替え
  ├── タスク4.3: ダイアログ コマンド
  └── タスク4.4: コマンド セマンティクス修正
       ↓ 有効化

フェーズ5: テストと文書化
  ├── タスク5.1: エンドツーエンド ゴースト テスト
  ├── タスク5.2: パフォーマンス プロファイリング
  └── タスク5.3: ドキュメント更新
```

---

# ロールバック戦略

## 一般的なロールバック原則

1. **バージョン管理**: すべての変更がブランチにコミットされ、簡単にrevert可能
2. **フィーチャー フラグ**: 問題が発生した場合、特定の統合を無効化可能
3. **グレースフル デグラデーション**: 一部機能が失敗してもシステム動作

## フェーズ別ロールバック計画

### フェーズ1ロールバック
- YayaAdapter 変更をrevert
- VM.cpp スタブを維持
- SAORI統合が失敗した理由をドキュメント化

### フェーズ2ロールバック
- スタブ BridgeToSHIORI を維持
- 代替案として直接 YAYA-to-SSTP ブリッジを実装

### フェーズ3ロールバック
- スタブ アニメーション コマンドを維持
- 代替アニメーション システム検討

### フェーズ4ロールバック
- 部分実装済みコマンドを維持
- どのコマンドが動作するかをドキュメント化

### フェーズ5ロールバック
- 既知問題付き「ベータ」としてリリース
- 回避策をドキュメント化

---

# 成功指標

## 統合完了指標

- [ ] すべてのコンポーネント統合（100%）
- [ ] すべての重大ブロッカー解決（100%）
- [ ] すべての統合テスト成功（100%）
- [ ] Emily4 ゴースト動作（100%）

## 機能指標

- [ ] SAORIモジュール ロード・実行（100%）
- [ ] SSTP外部通信動作（100%）
- [ ] SERIKO アニメーション再生（90%以上）
- [ ] SakuraScript コマンド実行（90%以上）

## パフォーマンス指標

- [ ] ゴースト ロード時間 < 2秒
- [ ] スクリプト実行 < 100ms
- [ ] SSTP応答時間 < 200ms
- [ ] アニメーション フレーム レート 60fps
- [ ] メモリ使用量 < 200MB

---

# 関連ドキュメント

- **IMPLEMENTATION_STATUS_SUMMARY.md**: 現在のステータス行列とブロッカー リスト
- **BLOCKER_TRACKER.md**: 詳細なブロッカー情報と回避策
- **COPILOT_AUTO_PROMPT.md**: 実装作業のタスク構造
- **コンポーネント 実装ドキュメント**: SAORI_IMPLEMENTATION.md、SERIKO_IMPLEMENTATION.md、SSTP_DISPATCHER_GUIDE.md
- **yaya_core/IMPLEMENTATION_STATUS.md**: YAYA Core ステータス

---

# 変更ログ

## 2026年3月15日
- ドキュメント作成
- 5つの統合フェーズ定義
- 各フェーズの詳細タスク追加
- 成功基準とロールバック計画追加
- 統合依存関係グラフ追加

---

**保守者**: 開発チーム
**更新頻度**: 必要に応じて更新
**バージョン**: 1.0
