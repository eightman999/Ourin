# Integration Roadmap / 統合ロードマップ

**Last Updated**: 2026-03-15  
**Status**: Active  
**Purpose**: Detailed integration plan for making existing stub implementations functional / 既存のスタブ実装を機能させるための詳細な統合計画

---

# Executive Summary / エグゼクティブサマリー

## Current Situation / 現状

All major components are implemented as code files, but most are **not integrated** with the rest of the system. This roadmap focuses on making these stubs functional through proper integration work.

すべての主要コンポーネントはコードファイルとして実装されていますが、ほとんどはシステムの他の部分と**統合されていません**。このロードマップは、適切な統合作業を通じてこれらのスタブを機能させることに焦点を当てています。

## Integration Philosophy / 統合の哲学

**Make stubs functional** - Don't create new components; integrate existing ones.

**スタブを機能させる** - 新しいコンポーネントを作成するのではなく、既存のものを統合する。

**Integration over new features** - Focus on end-to-end functionality first.

**統合を新機能より優先** - 最初にエンドツーエンドの機能に集中する。

**Test early and often** - Verify integration at each step.

**早く頻繁にテストする** - 各ステップで統合を検証する。

---

# Integration Phases / 統合フェーズ

## Phase 1: Make SAORI Functional / SAORI機能化

### Overview / 概要

Integrate the existing SAORI system with YAYA Core so ghosts can load and execute SAORI modules.

既存のSAORIシステムをYAYA Coreと統合し、ゴーストがSAORIモジュールをロード・実行できるようにする。

### Prerequisites / 前提条件

- ✅ SaoriLoader.swift exists (macOS native .dylib loading)
- ✅ SaoriProtocol.swift exists (SAORI/1.0 protocol)
- ✅ SaoriRegistry.swift exists (module discovery)
- ✅ SaoriManager.swift exists (unified API)
- ✅ YAYA Core VM has LOADLIB/UNLOADLIB/REQUESTLIB stubs
- ✅ YayaAdapter.swift exists (SHIORI adapter)

### Integration Tasks / 統合タスク

#### Task 1.1: Implement VM.cpp Plugin Operations / VM.cppプラグイン操作実装

**File**: `yaya_core/src/VM.cpp`

**Current State**: LOADLIB/UNLOADLIB/REQUESTLIB are stub implementations returning compatibility values.

**Required Changes**:

```cpp
// In VM.cpp, replace stub implementations:
Value VM::loadlib(const std::string& module) {
    // Instead of returning compatibility value:
    // return Value(1); // Stub
    
    // Emit plugin operation to host:
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

**Testing**:
- Create test ghost that calls LOADLIB in OnBoot
- Verify YayaCore receives "host_op" JSON
- Verify YayaAdapter processes the request

**Dependencies**: None

**Estimated Effort**: 2-3 hours

---

#### Task 1.2: Implement YayaCore.cpp pluginOperation() / YayaCore.cpp pluginOperation()実装

**File**: `yaya_core/src/YayaCore.cpp`

**Current State**: pluginOperation() doesn't exist or is a stub.

**Required Changes**:

```cpp
// Add to YayaCore class:
void YayaCore::handlePluginOperation(const nlohmann::json& request) {
    std::string operation = request["operation"].get<std::string>();
    
    if (operation == "saori_load") {
        // Load logic
    } else if (operation == "saori_unload") {
        // Unload logic
    } else if (operation == "saori_request") {
        // Request logic
    }
}

// In processCommand(), add case:
if (cmd == "plugin") {
    handlePluginOperation(data);
}
```

**Testing**:
- Verify pluginOperation is called when VM emits "host_op"
- Verify operation is parsed correctly

**Dependencies**: Task 1.1

**Estimated Effort**: 1-2 hours

---

#### Task 1.3: Implement YayaAdapter.handleSaoriRequest() / YayaAdapter.handleSaoriRequest()実装

**File**: `Ourin/Yaya/YayaAdapter.swift`

**Current State**: handleSaoriRequest() doesn't exist or doesn't delegate to SaoriManager.

**Required Changes**:

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

**Testing**:
- Create test .dylib SAORI module
- Load module from YAYA script
- Send request and verify response
- Unload module

**Dependencies**: Task 1.2

**Estimated Effort**: 2-3 hours

---

#### Task 1.4: Create Sample SAORI Module for Testing / テスト用サンプルSAORIモジュール作成

**File**: `Samples/SimpleSaori/SimpleSaori.swift`

**Purpose**: Test SAORI loading and execution.

**Implementation**:

```swift
import Foundation

// SAORI module functions
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

**Testing**:
- Compile to .dylib
- Load from test ghost
- Verify load/unload/request work

**Dependencies**: Task 1.3

**Estimated Effort**: 1-2 hours

---

### Phase 1 Success Criteria / フェーズ1成功基準

- [ ] LOADLIB successfully loads .dylib module
- [ ] REQUESTLIB sends request and receives response
- [ ] UNLOADLIB unloads module
- [ ] Integration tests pass
- [ ] Sample SAORI module works end-to-end
- [ ] No SAORI blockers remain (ID-001, ID-002 resolved)

### Rollback Plan / ロールバック計画

If integration fails:
1. Revert YayaAdapter changes
2. Keep VM.cpp stubs returning compatibility values
3. Document why integration failed

---

## Phase 2: Complete SSTP Integration / SSTP統合完成

### Overview / 概要

Implement real BridgeToSHIORI to enable external SSTP communication.

実際のBridgeToSHIORIを実装し、外部SSTP通信を有効にする。

### Prerequisites / 前提条件

- ✅ SSTPDispatcher.swift exists (parses all SSTP methods)
- ✅ SSTPResponse.swift exists (wire format generation)
- ✅ ShioriHost exists (SHIORI/3.0M implementation)
- ⚠️ BridgeToSHIORI is mocked/stub

### Integration Tasks / 統合タスク

#### Task 2.1: Implement Real BridgeToSHIORI / 実際のBridgeToSHIORI実装

**File**: `Ourin/SSTP/BridgeToSHIORI.swift` (may need to be created)

**Current State**: BridgeToSHIORI.handle() is a stub.

**Required Changes**:

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
        // Build SHIORI request
        var shioriRequest: [String: String] = [:]
        shioriRequest["ID"] = event
        shioriRequest["Charset"] = headers["Charset"] ?? "UTF-8"
        
        // Add references
        for (index, value) in references.enumerated() {
            shioriRequest["Reference\(index)"] = value
        }
        
        // Add relevant headers
        if let sender = headers["Sender"] {
            shioriRequest["Sender"] = sender
        }
        if let senderType = headers["SenderType"] {
            shioriRequest["SenderType"] = senderType
        }
        
        // Send to SHIORI
        do {
            let shioriResponse = try await shioriHost.request(shioriRequest)
            return shioriResponse
        } catch {
            // Return error response
            return [
                "Status": "500",
                "Charset": "UTF-8",
                "Value": "SHIORI request failed: \(error.localizedDescription)"
            ]
        }
    }
}
```

**Testing**:
- Mock SSTP request from external app
- Verify BridgeToSHIORI calls ShioriHost
- Verify response is correctly formatted

**Dependencies**: None

**Estimated Effort**: 3-4 hours

---

#### Task 2.2: Connect SSTPDispatcher to Real Bridge / SSTPDispatcherを実際のブリッジに接続

**File**: `Ourin/SSTP/SSTPDispatcher.swift`

**Current State**: routeToShiori() calls stub BridgeToSHIORI.

**Required Changes**:

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
        // Extract references
        var references: [String] = []
        
        // Add Reference0..N headers
        var index = 0
        while let ref = request.headers["Reference\(index)"] {
            references.append(ref)
            index += 1
        }
        
        // Add Sentence/Command for specific methods
        if method == "communicate", let sentence = request.headers["Sentence"] {
            references.append(sentence)
        }
        
        // Call real bridge
        let shioriResponse = await bridgeToSHIORI.handle(
            method: method,
            event: event,
            references: references,
            headers: request.headers
        )
        
        // Convert to SSTP response
        return mapShioriResponse(shioriResponse, originalRequest: request)
    }
    
    private func mapShioriResponse(
        _ response: [String: String],
        originalRequest: SSTPRequest
    ) -> SSTPResponse {
        var sstpResponse = SSTPResponse()
        
        // Map status
        if let status = response["Status"] {
            sstpResponse.statusCode = status
        }
        
        // Map headers
        if let script = response["Value"] {
            sstpResponse.headers["Script"] = script
        }
        
        // Preserve other headers
        for (key, value) in response {
            if key != "Status" && key != "Value" {
                sstpResponse.headers[key] = value
            }
        }
        
        // Preserve pass-through
        if let passThru = originalRequest.headers["X-SSTP-PassThru"] {
            sstpResponse.headers["X-SSTP-PassThru"] = passThru
        }
        
        return sstpResponse
    }
}
```

**Testing**:
- Send SSTP SEND request
- Verify SHIORI receives OnChoose event
- Verify SHIORI response is converted to SSTP
- Test all SSTP methods (SEND, NOTIFY, COMMUNICATE, EXECUTE, GIVE, INSTALL)

**Dependencies**: Task 2.1

**Estimated Effort**: 2-3 hours

---

#### Task 2.3: End-to-End SSTP Testing / エンドツーエンドSSTPテスト

**Purpose**: Verify external apps can communicate via SSTP.

**Test Cases**:

1. **Basic Communication**
   - Send SSTP SEND request
   - Receive SSTP response with script
   - Verify SHIORI event was triggered

2. **Event Resolution**
   - Test with Event header override
   - Test default event mapping for each method

3. **Header Propagation**
   - Verify Sender, SenderType, Charset are passed to SHIORI
   - Verify X-SSTP-PassThru is preserved

4. **Error Handling**
   - Test with invalid ghost (no OnChoose event)
   - Test with network errors
   - Verify appropriate status codes

**Dependencies**: Task 2.2

**Estimated Effort**: 2-3 hours

---

### Phase 2 Success Criteria / フェーズ2成功基準

- [ ] External app can send SSTP request
- [ ] Request reaches SHIORI system
- [ ] SHIORI processes request and generates response
- [ ] Response returned to external app
- [ ] All SSTP methods work (SEND, NOTIFY, COMMUNICATE, EXECUTE, GIVE, INSTALL)
- [ ] Integration tests pass
- [ ] No SSTP blockers remain (ID-003 resolved)

### Rollback Plan / ロールバック計画

If integration fails:
1. Keep stub BridgeToSHIORI
2. Document why integration failed
3. Alternative: Implement direct YAYA-to-SSTP bridge (bypass SHIORI)

---

## Phase 3: Integrate SERIKO Executor / SERIKOエグゼキューター統合

### Overview / 概要

Wire SerikoExecutor to GhostManager and SakuraScriptEngine so animation commands work.

SerikoExecutorをGhostManagerとSakuraScriptEngineに接続し、アニメーションコマンドを機能させる。

### Prerequisites / 前提条件

- ✅ SerikoParser.swift exists (complete SERIKO/2.0 parser)
- ✅ SerikoExecutor.swift exists (animation execution engine)
- ✅ GhostManager exists (ghost state management)
- ⚠️ SerikoExecutor not connected to GhostManager
- ⚠️ SakuraScriptEngine animation commands are stubs

### Integration Tasks / 統合タスク

#### Task 3.1: Wire SerikoExecutor to GhostManager / SerikoExecutorをGhostManagerに接続

**File**: `Ourin/Ghost/GhostManager+Animation.swift` (may need enhancement)

**Current State**: GhostManager has animation handlers but SerikoExecutor callbacks not connected.

**Required Changes**:

```swift
extension GhostManager {
    // In setupAnimationExecutor:
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
            // Handle reduction
            
        case .replace(let surfaceId, let replacementId):
            handleSurfaceOverlay(surfaceId: surfaceId, overlayId: replacementId, x: 0, y: 0, replace: true)
            
        case .start(let animationId):
            serikoExecutor.executeAnimation(id: animationId)
            
        case .alternativeStart(let animationId):
            serikoExecutor.executeAnimation(id: animationId)
            
        case .stop(let animationId):
            serikoExecutor.stopAnimation(id: animationId)
            
        case .asis:
            // Keep current state
        }
    }
    
    private func handleSerikoPattern(_ pattern: SerikoPattern) {
        // Update surface based on pattern
        // This depends on rendering engine implementation
    }
    
    private func handleAnimationFinished(_ animationId: Int) {
        // Notify interested parties
        // Could trigger SakuraScript \__w[animation, animationId] completion
    }
}
```

**Testing**:
- Load ghost with animations in surfaces.txt
- Parse animations successfully
- Register with SerikoExecutor
- Execute animation and verify callbacks fire

**Dependencies**: None

**Estimated Effort**: 3-4 hours

---

#### Task 3.2: Implement SakuraScript Animation Commands / SakuraScriptアニメーションコマンド実装

**File**: `Ourin/SakuraScript/SakuraScriptEngine.swift`

**Current State**: Animation commands are stubs.

**Required Changes**:

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
            // Unknown animation command
            break
        }
    }
    
    private func handleAnimClear(arguments: [String]) {
        // Clear all animations for surface
        // If ID provided, clear specific animation
        // serikoExecutor.stopAllAnimations()
        // or serikoExecutor.stopAnimation(id: animationId)
    }
    
    private func handleAnimPause(arguments: [String]) {
        // Pause animation
        guard arguments.count >= 1, let animationId = Int(arguments[0]) else { return }
        serikoExecutor.pauseAnimation(id: animationId)
    }
    
    private func handleAnimResume(arguments: [String]) {
        // Resume animation
        guard arguments.count >= 1, let animationId = Int(arguments[0]) else { return }
        serikoExecutor.resumeAnimation(id: animationId)
    }
    
    private func handleAnimOffset(arguments: [String]) {
        // Offset animation timing
        guard arguments.count >= 2,
              let animationId = Int(arguments[0]),
              let offset = Int(arguments[1]) else { return }
        serikoExecutor.offsetAnimation(id: animationId, offset: offset)
    }
    
    private func handleAnimAdd(arguments: [String]) {
        // Add animation pattern
        guard arguments.count >= 1 else { return }
        
        let method = arguments[0]
        let args = Array(arguments.dropFirst())
        
        // Parse based on method type
        // Could be: overlay, base, move, text, etc.
        // This requires parsing complex SERIKO syntax
        // For now, implement basic overlay
        if method == "overlay", args.count >= 3,
           let surfaceId = Int(args[0]),
           let overlayId = Int(args[1]),
           let x = Int(args[2]),
           let y = Int(args[3]) {
            // Add overlay pattern to animation
            // serikoExecutor.addPattern(...)
        }
    }
    
    private func handleAnimStop(arguments: [String]) {
        // Stop animation
        guard arguments.count >= 1, let animationId = Int(arguments[0]) else { return }
        serikoExecutor.stopAnimation(id: animationId)
    }
    
    private func handleWaitForAnimation(arguments: [String]) {
        // Wait for animation to complete
        guard arguments.count >= 1, let animationId = Int(arguments[0]) else { return }
        // Register callback for animation completion
        // When complete, continue script execution
    }
}
```

**Testing**:
- Execute \![anim,clear] command
- Execute \![anim,pause,ID] command
- Execute \![anim,resume,ID] command
- Execute \![anim,offset,ID,offset] command
- Execute \![anim,add,...] command
- Execute \![anim,stop,ID] command
- Execute \__w[animation,ID] wait command
- Verify animations play correctly

**Dependencies**: Task 3.1

**Estimated Effort**: 4-5 hours

---

#### Task 3.3: Test Animation Playback / アニメーション再生テスト

**Test Cases**:

1. **Basic Animation**
   - Load ghost with simple overlay animation
   - Trigger animation via SakuraScript
   - Verify animation plays on screen

2. **Animation Control**
   - Pause animation
   - Resume animation
   - Offset animation timing
   - Stop animation

3. **Multiple Animations**
   - Run multiple animations concurrently
   - Verify they don't interfere

4. **Animation Events**
   - Trigger yen-e animations
   - Trigger talk animations
   - Trigger bind animations

**Note**: Dressup functionality deferred due to build failures (ID-005). Will be addressed in Phase 4 or later.

**Dependencies**: Task 3.2

**Estimated Effort**: 3-4 hours

---

### Phase 3 Success Criteria / フェーズ3成功基準

- [ ] SerikoExecutor connected to GhostManager
- [ ] Animation commands execute correctly
- [ ] Animations play on screen
- [ ] Pause/resume/offset work
- [ ] Multiple animations can run concurrently
- [ ] Integration tests pass
- [ ] Critical SERIKO blockers resolved (ID-004, ID-006)
- [ ] Note: ID-005 (dressup) deferred to later phase

### Rollback Plan / ロールバック計画

If integration fails:
1. Keep stub animation commands
2. Document which animations work vs don't
3. Consider alternative animation system (e.g., SpriteKit-based)

---

## Phase 4: Complete SakuraScript Execution / SakuraScript実行完成

### Overview / 概要

Implement missing command execution to achieve 90%+ command execution rate.

不足しているコマンド実装を実装し、90%以上のコマンド実行率を達成する。

### Prerequisites / 前提条件

- ✅ SakuraScriptEngine.swift exists (comprehensive parsing)
- ✅ 34 commands fully implemented
- ⚠️ 18 commands partially implemented
- ❌ 26 commands not implemented

### Integration Tasks / 統合タスク

#### Task 4.1: Implement Text Formatting Execution / テキストフォーマット実行

**File**: `Ourin/SakuraScript/SakuraScriptEngine.swift`

**Current State**: Text formatting commands (\f[...]) parsed but not executed.

**Required Changes**:

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
        
    // ... more formatting tags
    }
}

private func handleFontChange(arguments: [String]) {
    guard let fontName = arguments.first else { return }
    // Update current font for subsequent text
    currentFont = fontName
}

private func handleSizeChange(arguments: [String]) {
    guard let fontSize = Int(arguments.first ?? "12") else { return }
    // Update current font size
    currentFontSize = fontSize
}

private func handleBoldToggle() {
    isBold = !isBold
}

private func handleItalicToggle() {
    isItalic = !isItalic
}

private func handleColorChange(arguments: [String]) {
    // Parse color (RGB, named color, etc.)
    // Update current text color
    if arguments.count >= 3,
       let r = Int(arguments[0]),
       let g = Int(arguments[1]),
       let b = Int(arguments[2]) {
        currentTextColor = Color(r: r, g: g, b: b)
    }
}
```

**Testing**:
- Test various formatting tags
- Verify rendering applies formatting correctly
- Test nested formatting

**Dependencies**: None

**Estimated Effort**: 3-4 hours

---

#### Task 4.2: Implement Ghost/Shell/Balloon Switching / ゴースト/シェル/バルーン切り替え実装

**File**: `Ourin/SakuraScript/SakuraScriptEngine.swift` and `Ourin/Ghost/GhostManager.swift`

**Current State**: Switching commands not implemented.

**Required Changes**:

```swift
// In SakuraScriptEngine:
private func handleSurfaceCommand(arguments: [String]) {
    // \s[ID] - Switch surface
    guard arguments.count >= 1, let surfaceId = Int(arguments[0]) else { return }
    
    Task {
        await ghostManager.switchSurface(to: surfaceId)
    }
}

private func handleScopeCommand(arguments: [String]) {
    // \0, \1, \2... - Switch character scope
    guard arguments.count >= 1, let scopeId = Int(arguments[0]) else { return }
    currentScope = scopeId
}

// In GhostManager:
func switchSurface(to surfaceId: Int) async {
    // Update current surface
    currentSurfaceId = surfaceId
    
    // Load surface images
    // Update display
    
    // Trigger SERIKO animations for new surface
    serikoExecutor.executeSurfaceAnimations(surfaceId: surfaceId)
}

func switchShell(to shellId: String) async {
    // Load new shell
    // Update surface definitions
    // Reload animations
}

func switchBalloon(to balloonId: String) async {
    // Load new balloon
    // Update text rendering
}
```

**Testing**:
- Switch between different surfaces
- Verify images update correctly
- Verify animations play for new surface
- Switch shells and balloons

**Dependencies**: Task 4.1

**Estimated Effort**: 4-5 hours

---

#### Task 4.3: Implement Dialog Commands / ダイアログコマンド実装

**File**: `Ourin/SakuraScript/SakuraScriptEngine.swift`

**Current State**: Dialog commands not implemented.

**Required Changes**:

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
        
    // ... more dialog types
    }
}

private func handleInputBox(arguments: [String]) {
    let title = arguments.first ?? "Input"
    let defaultValue = arguments.count > 1 ? arguments[1] : ""
    
    // Show macOS input dialog
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
        // Store result for script to access
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

// Similar implementations for other dialog types
```

**Testing**:
- Test each dialog type
- Verify result is accessible to script
- Test cancel operations

**Dependencies**: Task 4.2

**Estimated Effort**: 5-6 hours

---

#### Task 4.4: Fix Incorrect Command Semantics / 不正なコマンドセマンティクス修正

**File**: `Ourin/SakuraScript/SakuraScriptEngine.swift`

**Issues to Fix**:

1. **\6 command**: Should set menu text, not implemented correctly
2. **\7 command**: Should execute menu choice, not implemented
3. **\- command**: Should be comment/separator, not implemented

**Required Changes**:

```swift
private func handleMenuCommand(arguments: [String]) {
    // \6[text] - Set menu text
    guard arguments.count >= 1 else { return }
    let menuText = arguments[0]
    
    // Add to menu items list
    menuItems.append(menuText)
}

private func handleChoiceCommand(arguments: [String]) {
    // \7[index] - Execute menu choice
    guard arguments.count >= 1, let index = Int(arguments[0]) else { return }
    
    // Execute choice by index
    if index >= 0 && index < menuItems.count {
        // Trigger choice event with selected menu item
        let selectedItem = menuItems[index]
        // This should trigger OnChoiceSelect or similar
    }
}

private func handleSeparatorCommand() {
    // \- - Comment/separator
    // This is a no-op in terms of rendering
    // Just skip processing
}
```

**Testing**:
- Test menu functionality
- Verify choices execute correctly
- Test separators

**Dependencies**: Task 4.3

**Estimated Effort**: 2-3 hours

---

### Phase 4 Success Criteria / フェーズ4成功基準

- [ ] Text formatting commands work (90%+ of \f tags)
- [ ] Ghost/shell/balloon switching works
- [ ] All dialog commands work
- [ ] Menu commands (\6, \7) work correctly
- [ ] 90%+ command execution rate achieved
- [ ] Integration tests pass
- [ ] Critical SakuraScript blockers resolved (ID-006, ID-007)

### Rollback Plan / ロールバック計画

If integration fails:
1. Keep partially implemented commands
2. Document which commands work vs don't
3. Prioritize commands most commonly used by ghosts

---

## Phase 5: Integration Testing & Documentation / 統合テストと文書化

### Overview / 概要

End-to-end testing with real ghosts, performance profiling, and documentation updates.

実際のゴーストでのエンドツーエンドテスト、パフォーマンスプロファイリング、ドキュメント更新。

### Prerequisites / 前提条件

- ✅ All previous phases complete
- ✅ No critical blockers remaining

### Integration Tasks / 統合タスク

#### Task 5.1: End-to-End Ghost Testing / エンドツーエンドゴーストテスト

**Test Ghosts**:

1. **Emily4** (complex YAYA ghost)
   - Load successfully
   - Boot sequence works
   - Basic interaction works
   - SAORI usage (if any)
   - Animation playback

2. **Simple Test Ghost**
   - Minimal functionality
   - Easy to debug

3. **Commercial Ghost** (if available)
   - Test real-world usage

**Test Scenarios**:

1. **Boot Sequence**
   - OnBoot event fires
   - Initial surface displays
   - Initial script executes

2. **Interaction**
   - Click events work
   - Menu choices work
   - Choices fire correct events

3. **SSTP Communication**
   - External apps can send requests
   - Ghost responds correctly

4. **SAORI Usage**
   - Ghost can load SAORI modules
   - Modules execute correctly

5. **Animation**
   - Animations play on interaction
   - Animations pause/resume correctly

**Dependencies**: All previous phases

**Estimated Effort**: 8-12 hours

---

#### Task 5.2: Performance Profiling / パフォーマンスプロファイリング

**Metrics to Measure**:

1. **Ghost Load Time**
   - Target: < 2 seconds for typical ghost

2. **Script Execution**
   - Target: < 100ms for typical event response

3. **SSTP Response Time**
   - Target: < 200ms

4. **Animation Frame Rate**
   - Target: 60fps smooth playback

5. **Memory Usage**
   - Target: < 200MB for typical ghost

**Tools**:
- Instruments (macOS profiler)
- Custom logging

**Dependencies**: Task 5.1

**Estimated Effort**: 4-6 hours

---

#### Task 5.3: Update Documentation / ドキュメント更新

**Documents to Update**:

1. **IMPLEMENTATION_STATUS_SUMMARY.md**
   - Update status matrix to 100%
   - Mark all blockers as resolved

2. **Component Implementation Docs**
   - SAORI_IMPLEMENTATION.md - Mark as integrated
   - SERIKO_IMPLEMENTATION.md - Mark as integrated
   - SSTP_DISPATCHER_GUIDE.md - Mark as integrated

3. **SUPPORTED_SAKURA_SCRIPT.md**
   - Update implementation status
   - Mark 90%+ as executed

4. **Create Migration Guide**
   - For existing Windows ghosts
   - Document any incompatibilities

5. **Update CLAUDE.md**
   - Reflect new integration status
   - Update build/test instructions if needed

**Dependencies**: Task 5.2

**Estimated Effort**: 4-6 hours

---

### Phase 5 Success Criteria / フェーズ5成功基準

- [ ] Emily4 ghost works end-to-end
- [ ] Performance metrics meet targets
- [ ] All documentation updated
- [ ] Migration guide created
- [ ] Production-ready state achieved

### Rollback Plan / ロールバック計画

If critical issues found:
1. Document issues clearly
2. Provide workarounds if possible
3. Plan for future fixes
4. Release as "beta" with known issues

---

# Integration Dependencies Graph / 統合依存関係グラフ

```
Phase 1: SAORI Integration
  ├── Task 1.1: VM.cpp plugin operations
  ├── Task 1.2: YayaCore.cpp pluginOperation()
  ├── Task 1.3: YayaAdapter.handleSaoriRequest()
  └── Task 1.4: Create sample SAORI module
       ↓ Required for / 必須

Phase 2: SSTP Integration
  ├── Task 2.1: Implement BridgeToSHIORI
  ├── Task 2.2: Connect SSTPDispatcher
  └── Task 2.3: End-to-end testing
       ↓ Enables / 有効化

Phase 3: SERIKO Integration
  ├── Task 3.1: Wire SerikoExecutor to GhostManager
  ├── Task 3.2: Implement animation commands
  └── Task 3.3: Test animation playback
       ↓ Enhances / 拡張

Phase 4: SakuraScript Completion
  ├── Task 4.1: Text formatting
  ├── Task 4.2: Ghost/shell/balloon switching
  ├── Task 4.3: Dialog commands
  └── Task 4.4: Fix command semantics
       ↓ Enables / 有効化

Phase 5: Testing & Documentation
  ├── Task 5.1: End-to-end ghost testing
  ├── Task 5.2: Performance profiling
  └── Task 5.3: Documentation updates
```

---

# Rollback Strategies / ロールバック戦略

## General Rollback Principles / 一般的なロールバック原則

1. **Version Control**: All changes committed in branches, easy to revert
2. **Feature Flags**: Can disable specific integrations if they cause issues
3. **Graceful Degradation**: System should work even if some features fail

## Phase-Specific Rollback Plans / フェーズ別ロールバック計画

### Phase 1 Rollback / フェーズ1ロールバック
- Revert YayaAdapter changes
- Keep VM.cpp stubs
- Document why SAORI integration failed

### Phase 2 Rollback / フェーズ2ロールバック
- Keep stub BridgeToSHIORI
- Implement direct YAYA-to-SSTP bridge as alternative

### Phase 3 Rollback / フェーズ3ロールバック
- Keep stub animation commands
- Consider alternative animation system

### Phase 4 Rollback / フェーズ4ロールバック
- Keep partially implemented commands
- Document which commands work vs don't

### Phase 5 Rollback / フェーズ5ロールバック
- Release as "beta" with known issues
- Document workarounds

---

# Success Metrics / 成功指標

## Integration Completion Metrics / 統合完了指標

- [ ] All components integrated (100%)
- [ ] All critical blockers resolved (100%)
- [ ] All integration tests pass (100%)
- [ ] Emily4 ghost works (100%)

## Functional Metrics / 機能指標

- [ ] SAORI modules load and execute (100%)
- [ ] SSTP external communication works (100%)
- [ ] SERIKO animations play (90%+)
- [ ] SakuraScript commands execute (90%+)

## Performance Metrics / パフォーマンス指標

- [ ] Ghost load time < 2 seconds
- [ ] Script execution < 100ms
- [ ] SSTP response time < 200ms
- [ ] Animation frame rate 60fps
- [ ] Memory usage < 200MB

---

# Related Documents / 関連ドキュメント

- **IMPLEMENTATION_STATUS_SUMMARY.md**: Current status matrix and blocker list
- **BLOCKER_TRACKER.md**: Detailed blocker information with workarounds
- **COPILOT_AUTO_PROMPT.md**: Task structure for implementation work
- **Component Implementation Docs**: SAORI_IMPLEMENTATION.md, SERIKO_IMPLEMENTATION.md, SSTP_DISPATCHER_GUIDE.md
- **yaya_core/IMPLEMENTATION_STATUS.md**: YAYA Core status

---

# Change Log / 変更ログ

## 2026-03-15
- Created document / ドキュメント作成
- Defined 5 integration phases / 5つの統合フェーズ定義
- Added detailed tasks for each phase / 各フェーズの詳細タスク追加
- Added success criteria and rollback plans / 成功基準とロールバック計画追加
- Added integration dependencies graph / 統合依存関係グラフ追加

---

**Maintainer**: Development Team  
**Update Frequency**: As needed / 必要に応じて更新  
**Version**: 1.0
