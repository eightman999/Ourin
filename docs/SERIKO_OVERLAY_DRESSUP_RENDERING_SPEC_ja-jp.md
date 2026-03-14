# SERIKOオーバーレイ・着せ替えレンダリング仕様書

**Status:** Implementation Spec  
**Updated:** 2025-03-09  
**Target:** Ourin (macOS 10.15+ / Universal 2)  
**Scope:** SERIKOアニメーションのSurfaceオーバーレイ合成と着せ替えパーツのレンダリング

---

## 1. 概要

SERIKOアニメーションシステムは、ghostの表示を複数のSurfaceレイヤーで合成する仕組みです。本仕様では、以下の機能を実装します：

- **Surfaceオーバーレイ**: ベースサーフェスの上に複数のサーフェスを重ねて表示
- **着せ替えパーツ**: ユーザーが着せるアクセサリー（髪飾り、リボンなど）を表示
- **Z-order管理**: オーバーレイ同士の重ね順序を制御
- **アニメーション**: オーバーレイのパターンアニメーション

---

## 2. 既存実装の確認

### 2.1 CharacterViewModel (GhostManager.swift:10-62)

既存プロパティ:
```swift
class CharacterViewModel: ObservableObject {
    @Published var image: NSImage?
    @Published var scaleX: Double = 1.0
    @Published var scaleY: Double = 1.0
    @Published var alpha: Double = 1.0
    @Published var position: CGPoint? = nil
    @Published var alignment: DesktopAlignment = .free
    @Published var repaintLocked: Bool = false
    @Published var currentBalloonID: Int = 0

    // Surface compositing
    @Published var overlays: [SurfaceOverlay] = []

    // Effects and filters
    var activeEffects: [EffectConfig] = []
    var activeFilters: [FilterConfig] = []

    // Dressup bindings
    var dressupBindings: [String: [String: String]] = [:]

    // Text animations
    var textAnimations: [TextAnimationConfig] = []

    struct SurfaceOverlay: Identifiable {
        let id: Int
        let image: NSImage
        var offset: CGPoint = .zero
        var alpha: Double = 1.0
    }

    enum DesktopAlignment {
        case free, top, bottom, left, right
    }
}
```

### 2.2 AnimationEngine (AnimationEngine.swift)

既存実装:
- `AnimationDefinition`, `AnimationPattern` データ構造
- `ActiveAnimation` クラス（アニメーション再生管理）
- `onAnimationUpdate` コールバック（パターン更新時）
- `onAnimationComplete` コールバック（アニメーション完了時）
- Metalセットアップ済み（まだ未使用）

### 2.3 CharacterView (CharacterView.swift)

現在の実装:
```swift
struct CharacterView: View {
    @ObservedObject var viewModel: CharacterViewModel
    
    var body: some View {
        ZStack {
            if let image = viewModel.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(x: viewModel.scaleX, y: viewModel.scaleY)
                    .opacity(viewModel.alpha)
                    .contentShape(Rectangle())
            }
        }
    }
}
```

---

## 3. 実装計画

### 3.1 Surfaceオーバーレイレンダリング

**目的**: `CharacterViewModel.overlays` 配列をCharacterViewでレンダリング

**ファイル**: `Ourin/Ghost/CharacterView.swift`（大規模拡張）

**実装内容**:
1. ベースサーフェスの上にオーバーレイレイヤーを追加
2. Z-orderによる重ね順序管理
3. オフセット座標の適用
4. 透明度（alpha）の適用

**変更コード**:
```swift
struct CharacterView: View {
    @ObservedObject var viewModel: CharacterViewModel
    var onDragDropEvent: ((ShioriEvent) -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // ベースサーフェス
            if let baseImage = viewModel.image {
                Image(nsImage: baseImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }

            // オーバーレイレイヤー（Z-order順にソート）
            ForEach(viewModel.overlays.sorted { $0.id < $1.id }) { overlay in
                OverlayView(overlay: overlay)
                    .offset(x: overlay.offset.x, y: overlay.offset.y)
            }

            // 着せ替えパーツ
            ForEach(viewModel.dressupParts) { part in
                DressupPartView(part: part)
            }
        }
        .scaleEffect(x: viewModel.scaleX, y: viewModel.scaleY)
        .opacity(viewModel.alpha)
        .allowsHitTesting(!viewModel.repaintLocked)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    handleTap(at: value.location)
                }
        )

        // Drag and dropオーバーレイ
        if let onEvent = onDragDropEvent {
            DragDropView(onEvent: onEvent)
        }
    }
}
```

### 3.2 OverlayViewの実装

**目的**: 個々のSurfaceオーバーレイを表示

**ファイル**: 新規作成 `Ourin/Ghost/OverlayView.swift`

**実装内容**:
- NSImageのレンダリング
- 透明度の適用
- フレームサイズの設定

**コード**:
```swift
import SwiftUI
import AppKit

/// View for rendering a single surface overlay
struct OverlayView: View {
    let overlay: CharacterViewModel.SurfaceOverlay

    var body: some View {
        if !overlay.image.isValid {
            EmptyView()
        } else {
            Image(nsImage: overlay.image)
                .resizable()
                .opacity(overlay.alpha)
        }
    }
}

extension NSImage {
    var isValid: Bool {
        return size.width > 0 && size.height > 0
    }
}
```

### 3.3 着せ替えパーツレンダリング

**目的**: `\![bind,category,part,value]` コマンドによる着せ替えを表示

**データ構造**: CharacterViewModelに追加

**追加プロパティ**:
```swift
class CharacterViewModel: ObservableObject {
    // 既存プロパティ...

    // 着せ替えパーツ（新規追加）
    @Published var dressupParts: [DressupPart] = []
}

struct DressupPart: Identifiable {
    let id = UUID()
    let category: String
    let partName: String
    let image: NSImage
    let frame: CGRect
    var zOrder: Int = 0
    var isEnabled: Bool = true
}
```

**DressupViewの実装**:

**ファイル**: 新規作成 `Ourin/Ghost/DressupPartView.swift`

```swift
import SwiftUI
import AppKit

/// View for rendering a dressup part
struct DressupPartView: View {
    let part: DressupPart

    var body: some View {
        if part.isEnabled {
            Image(nsImage: part.image)
                .resizable()
                .frame(width: part.frame.width, height: part.frame.height)
                .position(x: part.frame.midX, y: part.frame.midY)
        } else {
            EmptyView()
        }
    }
}
```

### 3.4 着せ替え管理拡張

**目的**: GhostManagerで着せ替えコマンドを処理

**ファイル**: 新規作成 `Ourin/Ghost/GhostManager+Dressup.swift`

**実装内容**:
```swift
import Foundation
import AppKit

// MARK: - Dressup Management

extension GhostManager {

    // MARK: - Dressup Data Structures

    struct DressupInfo {
        let category: String
        let partName: String
        let imagePaths: [Int: String]  // Surface ID -> Image path
        let frame: CGRect
        let defaultPart: String? = nil
    }

    var dressupInfos: [String: [String: DressupInfo]] = [:]  // category -> part -> info

    // MARK: - Load Dressup Configuration

    /// Load dressup configuration from shell directory
    func loadDressupConfiguration() {
        guard let shellPath = loadShellPath() else { return }

        let descriptPath = shellPath.appendingPathComponent("descript.txt")
        guard FileManager.default.fileExists(atPath: descriptPath.path) else {
            Log.info("[GhostManager] descript.txt not found at: \(descriptPath.path)")
            return
        }

        // Parse descript.txt for dressup bindings
        if let content = try? String(contentsOf: descriptPath, encoding: .utf8) {
            parseDressupFromDescript(content)
        } else if let content = try? String(contentsOf: descriptPath, encoding: .shiftJIS) {
            parseDressupFromDescript(content)
        }
    }

    private func parseDressupFromDescript(_ content: String) {
        dressupInfos.removeAll()

        let lines = content.components(separatedBy: .newlines)
        var currentCategory: String?
        var currentPart: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Parse category binding
            if trimmed.hasPrefix("sakura.bind.") {
                let parts = trimmed.replacingOccurrences(of: "sakura.bind.", with: "").split(separator: ".")
                if parts.count >= 3 {
                    let category = String(parts[0])
                    let part = String(parts[1])
                    let value = parts[2].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }

                    // Initialize category dictionary if needed
                    if dressupInfos[category] == nil {
                        dressupInfos[category] = [:]
                    }

                    // Store binding info
                    if dressupInfos[category]![part] == nil {
                        dressupInfos[category]![part] = DressupInfo(
                            category: category,
                            partName: part,
                            imagePaths: [:],
                            frame: .zero
                        )
                    }
                }
            }
        }
    }

    // MARK: - Apply Dressup Bindings

    /// Apply current dressup bindings to view models
    func applyDressupBindings() {
        for (scopeID, viewModel) in characterViewModels {
            var parts: [DressupPart] = []
            var zOrder = 0

            for (category, bindings) in viewModel.dressupBindings {
                for (partName, isEnabled) in bindings {
                    guard isEnabled == "1" || isEnabled == "true" else { continue }

                    guard let info = dressupInfos[category]?[partName] else { continue }

                    // Load image for current surface
                    let currentSurfaceID = viewModel.currentBalloonID  // TODO: Track actual surface ID
                    if let imagePath = info.imagePaths[currentSurfaceID],
                       let image = loadDressupImage(at: imagePath) {

                        let part = DressupPart(
                            category: category,
                            partName: partName,
                            image: image,
                            frame: info.frame,
                            zOrder: zOrder
                        )
                        parts.append(part)
                        zOrder += 1
                    }
                }
            }

            viewModel.dressupParts = parts.sorted { $0.zOrder < $1.zOrder }
        }
    }

    private func loadDressupImage(at path: String) -> NSImage? {
        // Resolve relative path from ghost master directory
        let ghostMasterPath = ghostURL.appendingPathComponent("ghost/master")
        let resolvedPath = path.hasPrefix("/") ? URL(fileURLWithPath: path) : ghostMasterPath.appendingPathComponent(path)

        return NSImage(contentsOf: resolvedPath)
    }

    // MARK: - Handle Dressup Commands

    /// Handle \![bind,category,part,value] command
    func handleBindCommand(category: String, part: String?, value: String?) {
        guard let viewModel = characterViewModels[currentScope] else { return }

        // Initialize category dictionary if needed
        if viewModel.dressupBindings[category] == nil {
            viewModel.dressupBindings[category] = [:]
        }

        if let part = part {
            // Set specific part
            if let value = value {
                // Set value (1/0/true/false)
                let normalizedValue = value.lowercased()
                let isEnabled = normalizedValue == "1" || normalizedValue == "true"
                viewModel.dressupBindings[category]![part] = isEnabled ? "1" : "0"
            } else {
                // Toggle
                if let currentValue = viewModel.dressupBindings[category]?[part] {
                    let currentEnabled = currentValue == "1"
                    viewModel.dressupBindings[category]![part] = currentEnabled ? "0" : "1"
                }
            }
        } else {
            // Clear all parts in category
            viewModel.dressupBindings[category]?.removeAll()
        }

        // Trigger OnDressupChanged event
        EventBridge.shared.notifyCustom(
            eventName: "OnDressupChanged",
            sender: "SakuraScript"
        )

        // Apply bindings
        applyDressupBindings()

        // Trigger OnNotifyDressupInfo event
        EventBridge.shared.notifyCustom(
            eventName: "OnNotifyDressupInfo",
            sender: "SakuraScript"
        )
    }
}
```

---

## 4. SakuraScriptコマンド対応

### 4.1 アニメーションコマンド

| コマンド | 実装状況 | ハンドラー |
|---------|----------|----------|
| `\i[ID]` | ✅ 既存 | `playAnimation(id: id, wait: false)` |
| `\i[ID,wait]` | ✅ 既存 | `playAnimation(id: id, wait: true)` |
| `\![anim,clear,ID]` | ⚠️ 未実装 | `GhostManager.handleAnimClear(id:)` |
| `\![anim,pause,ID]` | ⚠️ 未実装 | `GhostManager.handleAnimPause(id:)` |
| `\![anim,resume,ID]` | ⚠️ 未実装 | `GhostManager.handleAnimResume(id:)` |
| `\![anim,offset,ID,x,y]` | ⚠️ 未実装 | `GhostManager.handleAnimOffset(id:x:y:)` |
| `\![anim,stop]` | ⚠️ 未実装 | `GhostManager.handleAnimStop()` |
| `\![anim,add,overlay,ID]` | ⚠️ 未実装 | `GhostManager.handleAnimAddOverlay(id:)` |
| `\![anim,add,overlayfast,ID]` | ⚠️ 未実装 | `GhostManager.handleAnimAddOverlayFast(id:)` |
| `\![anim,add,base,ID]` | ⚠️ 未実装 | `GhostManager.handleAnimAddBase(id:)` |
| `\![anim,add,move,x,y]` | ⚠️ 未実装 | `GhostManager.handleAnimAddMove(x:y:)` |
| `\![anim,add,overlay,ID,x,y]` | ⚠️ 未実装 | `GhostManager.handleAnimAddOverlayAt(id:x:y:)` |
| `\_w[animation,ID]` | ⚠️ 未実装 | `GhostManager.handleWaitForAnimation(id:)` |

### 4.2 着せ替えコマンド

| コマンド | 実装状況 | ハンドラー |
|---------|----------|----------|
| `\![bind,category,part,1]` | ⚠️ データ格納済み | `handleBindCommand(category:part:value: "1")` |
| `\![bind,category,part,0]` | ⚠️ データ格納済み | `handleBindCommand(category:part:value: "0")` |
| `\![bind,category,,0]` | ⚠️ 未実装 | `handleBindCommand(category:part:nil:value: "0")` |
| `\![bind,category,part]` | ⚠️ データ格納済み | `handleBindCommand(category:part:value:nil)` |

---

## 5. 実装タスク

### タスク1: CharacterViewModel拡張
- [ ] `DressupPart` 構造体追加
- [ ] `dressupParts: [DressupPart]` プロパティ追加

### タスク2: CharacterView拡張
- [ ] オーバーレイレイヤー追加（`ForEach` with sorted overlays）
- [ ] 着せ替えパーツレイヤー追加（`ForEach` with dressupParts）
- [ ] Z-orderでのソート実装

### タスク3: OverlayView作成
- [ ] 新規ファイル作成 `Ourin/Ghost/OverlayView.swift`
- [ ] 単一オーバーレイのレンダリング実装

### タスク4: DressupPartView作成
- [ ] 新規ファイル作成 `Ourin/Ghost/DressupPartView.swift`
- [ ] 単一着せ替えパーツのレンダリング実装

### タスク5: GhostManager+Animation拡張
- [ ] `handleAnimClear(id:)` 実装
- [ ] `handleAnimPause(id:)` 実装
- [ ] `handleAnimResume(id:)` 実装
- [ ] `handleAnimOffset(id:x:y:)` 実装
- [ ] `handleAnimStop()` 実装
- [ ] `handleAnimAddOverlay(id:)` 実装
- [ ] `handleAnimAddOverlayFast(id:)` 実装
- [ ] `handleAnimAddBase(id:)` 実装
- [ ] `handleAnimAddMove(x:y:)` 実装
- [ ] `handleAnimAddOverlayAt(id:x:y:)` 実装
- [ ] `handleWaitForAnimation(id:)` 実装

### タスク6: GhostManager+Dressup作成
- [ ] 新規ファイル作成 `Ourin/Ghost/GhostManager+Dressup.swift`
- [ ] `DressupInfo` 構造体追加
- [ ] `dressupInfos` プロパティ追加
- [ ] `loadDressupConfiguration()` 実装
- [ ] `parseDressupFromDescript()` 実装
- [ ] `applyDressupBindings()` 実装
- [ ] `handleBindCommand()` 実装

---

## 6. 依存関係

```
タスク1 (CharacterViewModel拡張)
    ↓
タスク2 (CharacterView拡張) ← タスク3 (OverlayView)
                         ← タスク4 (DressupPartView)
    ↓
タスク6 (GhostManager+Dressup作成)
    ↓
タスク5 (GhostManager+Animation拡張)
```

---

## 7. テスト計画

### テスト1: オーバーレイレンダリング
- [ ] ベースサーフェス表示
- [ ] 単一オーバーレイ表示
- [ ] 複数オーバーレイ表示
- [ ] Z-orderでの正確な重ね順序
- [ ] オフセット座標の適用
- [ ] 透明度の適用

### テスト2: 着せ替えレンダリング
- [ ] 単一着せ替えパーツ表示
- [ ] 複数着せ替えパーツ表示
- [ ] カテゴリ別のパーツ管理
- [ ] 有効/無効状態の切り替え
- [ ] Z-orderでの重ね順序

### テスト3: アニメーション
- [ ] `\i[ID]` によるアニメーション再生
- [ ] `\i[ID,wait]` による完了待ち
- [ ] `\![anim,clear,ID]` による停止
- [ ] `\![anim,pause,ID]` による一時停止
- [ ] `\![anim,resume,ID]` による再開
- [ ] `\![anim,offset,ID,x,y]` によるオフセット
- [ ] `\![anim,stop]` による全停止

### テスト4: 着せ替えコマンド
- [ ] `\![bind,head,ribbon,1]` による着衣
- [ ] `\![bind,head,ribbon,0]` による脱衣
- [ ] `\![bind,head,ribbon]` によるトグル
- [ ] `\![bind,arm,,0]` によるカテゴリ全解除
- [ ] `OnDressupChanged` イベント発火
- [ ] `OnNotifyDressupInfo` イベント発火

---

## 8. 既知の制限事項

1. **Metal未使用**: AnimationEngineでMetalセットアップ済みだが、まだCPUベースでレンダリング中
2. **Surface ID追跡未実装**: 現在は固定的なsurface 0を想定。実際のsurface ID追跡が必要
3. **着せ替えパス解決未実装**: `DressupInfo.imagePaths` は空のまま。surfaces.txtからのパースが必要
4. **フレーム情報未実装**: 着せ替えパーツのフレーム（位置・サイズ）はデフォルトでゼロ

---

## 9. 将来の拡張

1. **GPUアクセラレーション**: Metalを活用したオーバーレイ合成
2. **アニメーションブレンディング**: パターン間のスムーズな遷移
3. **着せ替えアニメーション**: 着せ替え時のアニメーション効果
4. **着せ替えプリセット**: 複数パーツの組み合わせを保存・読込

---

## 10. 参考文献

- [SAKURASCRIPT_FULL_1.0M_PATCHED_ja-jp.md](./SAKURASCRIPT_FULL_1.0M_PATCHED_ja-jp.md)
- [SURFACES specification](https://ssp.shillest.net/ukadoc/manual/list_surface.html)
- SERIKO specification (UKADOC)
