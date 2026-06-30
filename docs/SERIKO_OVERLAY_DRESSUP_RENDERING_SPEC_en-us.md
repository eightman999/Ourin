# SERIKO Overlay & Dressup Rendering Specification

**Status:** Implementation Spec  
**Updated:** 2025-03-09  
**Target:** Ourin (macOS 10.15+ / Universal 2)  
**Scope:** SERIKO Animation Surface overlay composition and dressup parts rendering

---

## 1. Overview

The SERIKO animation system is a mechanism to composite ghost display using multiple Surface layers. This specification implements the following features:

- **Surface Overlay**: Display multiple surfaces layered on top of a base surface
- **Dressup Parts**: Display user-worn accessories (hair ornaments, ribbons, etc.)
- **Z-order Management**: Control layering order between overlays
- **Animation**: Pattern animation for overlays

---

## 2. Existing Implementation Verification

### 2.1 CharacterViewModel (GhostManager.swift:10-62)

Existing properties:
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

Existing implementation:
- `AnimationDefinition`, `AnimationPattern` data structures
- `ActiveAnimation` class (animation playback management)
- `onAnimationUpdate` callback (pattern update)
- `onAnimationComplete` callback (animation completion)
- Metal setup complete (not yet in use)

### 2.3 CharacterView (CharacterView.swift)

Current implementation:
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

## 3. Implementation Plan

### 3.1 Surface Overlay Rendering

**Purpose**: Render `CharacterViewModel.overlays` array in CharacterView

**File**: `Ourin/Ghost/CharacterView.swift` (major extension)

**Implementation**:
1. Add overlay layer on top of base surface
2. Z-order management
3. Apply offset coordinates
4. Apply opacity (alpha)

**Code Changes**:
```swift
struct CharacterView: View {
    @ObservedObject var viewModel: CharacterViewModel
    var onDragDropEvent: ((ShioriEvent) -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Base surface
            if let baseImage = viewModel.image {
                Image(nsImage: baseImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }

            // Overlay layers (sorted by Z-order)
            ForEach(viewModel.overlays.sorted { $0.id < $1.id }) { overlay in
                OverlayView(overlay: overlay)
                    .offset(x: overlay.offset.x, y: overlay.offset.y)
            }

            // Dressup parts
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

        // Drag and drop overlay
        if let onEvent = onDragDropEvent {
            DragDropView(onEvent: onEvent)
        }
    }
}
```

### 3.2 OverlayView Implementation

**Purpose**: Display individual Surface overlay

**File**: New file `Ourin/Ghost/OverlayView.swift`

**Implementation**:
- NSImage rendering
- Opacity application
- Frame size setting

**Code**:
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

### 3.3 Dressup Parts Rendering

**Purpose**: Display dressup via `\![bind,category,part,value]` command

**Data Structure**: Add to CharacterViewModel

**New Properties**:
```swift
class CharacterViewModel: ObservableObject {
    // Existing properties...

    // Dressup parts (new)
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

**DressupView Implementation**:

**File**: New file `Ourin/Ghost/DressupPartView.swift`

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

### 3.4 Dressup Management Extension

**Purpose**: Handle dressup commands in GhostManager

**File**: New file `Ourin/Ghost/GhostManager+Dressup.swift`

**Implementation**:
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

## 4. SakuraScript Command Support

### 4.1 Animation Commands

| Command | Implementation Status | Handler |
|---------|----------|----------|
| `\i[ID]` | ✅ Existing | `playAnimation(id: id, wait: false)` |
| `\i[ID,wait]` | ✅ Existing | `playAnimation(id: id, wait: true)` |
| `\![anim,clear,ID]` | ⚠️ Not Implemented | `GhostManager.handleAnimClear(id:)` |
| `\![anim,pause,ID]` | ⚠️ Not Implemented | `GhostManager.handleAnimPause(id:)` |
| `\![anim,resume,ID]` | ⚠️ Not Implemented | `GhostManager.handleAnimResume(id:)` |
| `\![anim,offset,ID,x,y]` | ⚠️ Not Implemented | `GhostManager.handleAnimOffset(id:x:y:)` |
| `\![anim,stop]` | ⚠️ Not Implemented | `GhostManager.handleAnimStop()` |
| `\![anim,add,overlay,ID]` | ⚠️ Not Implemented | `GhostManager.handleAnimAddOverlay(id:)` |
| `\![anim,add,overlayfast,ID]` | ⚠️ Not Implemented | `GhostManager.handleAnimAddOverlayFast(id:)` |
| `\![anim,add,base,ID]` | ⚠️ Not Implemented | `GhostManager.handleAnimAddBase(id:)` |
| `\![anim,add,move,x,y]` | ⚠️ Not Implemented | `GhostManager.handleAnimAddMove(x:y:)` |
| `\![anim,add,overlay,ID,x,y]` | ⚠️ Not Implemented | `GhostManager.handleAnimAddOverlayAt(id:x:y:)` |
| `\_w[animation,ID]` | ⚠️ Not Implemented | `GhostManager.handleWaitForAnimation(id:)` |

### 4.2 Dressup Commands

| Command | Implementation Status | Handler |
|---------|----------|----------|
| `\![bind,category,part,1]` | ⚠️ Data Stored | `handleBindCommand(category:part:value: "1")` |
| `\![bind,category,part,0]` | ⚠️ Data Stored | `handleBindCommand(category:part:value: "0")` |
| `\![bind,category,,0]` | ⚠️ Not Implemented | `handleBindCommand(category:part:nil:value: "0")` |
| `\![bind,category,part]` | ⚠️ Data Stored | `handleBindCommand(category:part:value:nil)` |

---

## 5. Implementation Tasks

### Task 1: CharacterViewModel Extension
- [ ] Add `DressupPart` structure
- [ ] Add `dressupParts: [DressupPart]` property

### Task 2: CharacterView Extension
- [ ] Add overlay layer (`ForEach` with sorted overlays)
- [ ] Add dressup parts layer (`ForEach` with dressupParts)
- [ ] Implement Z-order sorting

### Task 3: OverlayView Creation
- [ ] Create new file `Ourin/Ghost/OverlayView.swift`
- [ ] Implement single overlay rendering

### Task 4: DressupPartView Creation
- [ ] Create new file `Ourin/Ghost/DressupPartView.swift`
- [ ] Implement single dressup part rendering

### Task 5: GhostManager+Animation Extension
- [ ] Implement `handleAnimClear(id:)`
- [ ] Implement `handleAnimPause(id:)`
- [ ] Implement `handleAnimResume(id:)`
- [ ] Implement `handleAnimOffset(id:x:y:)`
- [ ] Implement `handleAnimStop()`
- [ ] Implement `handleAnimAddOverlay(id:)`
- [ ] Implement `handleAnimAddOverlayFast(id:)`
- [ ] Implement `handleAnimAddBase(id:)`
- [ ] Implement `handleAnimAddMove(x:y:)`
- [ ] Implement `handleAnimAddOverlayAt(id:x:y:)`
- [ ] Implement `handleWaitForAnimation(id:)`

### Task 6: GhostManager+Dressup Creation
- [ ] Create new file `Ourin/Ghost/GhostManager+Dressup.swift`
- [ ] Add `DressupInfo` structure
- [ ] Add `dressupInfos` property
- [ ] Implement `loadDressupConfiguration()`
- [ ] Implement `parseDressupFromDescript()`
- [ ] Implement `applyDressupBindings()`
- [ ] Implement `handleBindCommand()`

---

## 6. Dependencies

```
Task 1 (CharacterViewModel Extension)
    ↓
Task 2 (CharacterView Extension) ← Task 3 (OverlayView)
                         ← Task 4 (DressupPartView)
    ↓
Task 6 (GhostManager+Dressup Creation)
    ↓
Task 5 (GhostManager+Animation Extension)
```

---

## 7. Test Plan

### Test 1: Overlay Rendering
- [ ] Display base surface
- [ ] Display single overlay
- [ ] Display multiple overlays
- [ ] Correct Z-order with multiple overlays
- [ ] Offset coordinate application
- [ ] Opacity application

### Test 2: Dressup Rendering
- [ ] Display single dressup part
- [ ] Display multiple dressup parts
- [ ] Category-based part management
- [ ] Enable/disable state switching
- [ ] Z-order layering

### Test 3: Animation
- [ ] `\i[ID]` animation playback
- [ ] `\i[ID,wait]` completion wait
- [ ] `\![anim,clear,ID]` stop
- [ ] `\![anim,pause,ID]` pause
- [ ] `\![anim,resume,ID]` resume
- [ ] `\![anim,offset,ID,x,y]` offset
- [ ] `\![anim,stop]` stop all

### Test 4: Dressup Commands
- [ ] `\![bind,head,ribbon,1]` wear
- [ ] `\![bind,head,ribbon,0]` remove
- [ ] `\![bind,head,ribbon]` toggle
- [ ] `\![bind,arm,,0]` clear category
- [ ] `OnDressupChanged` event trigger
- [ ] `OnNotifyDressupInfo` event trigger

---

## 8. Known Limitations

1. **Metal Not Used**: Metal setup complete in AnimationEngine but still CPU-based rendering
2. **Surface ID Tracking Not Implemented**: Currently assumes fixed surface 0. Actual surface ID tracking needed
3. **Dressup Path Resolution Not Implemented**: `DressupInfo.imagePaths` still empty. Parsing from surfaces.txt needed
4. **Frame Information Not Implemented**: Dressup parts frame (position/size) defaults to zero

---

## 9. Future Enhancements

1. **GPU Acceleration**: Leverage Metal for overlay compositing
2. **Animation Blending**: Smooth transitions between patterns
3. **Dressup Animation**: Animation effects during dressup
4. **Dressup Presets**: Save/load multiple part combinations

---

## 10. References

- [SAKURASCRIPT_FULL_1.0M_PATCHED_en-us.md](./SAKURASCRIPT_FULL_1.0M_PATCHED_en-us.md)
- [SURFACES specification](https://ssp.shillest.net/ukadoc/manual/list_surface.html)
- SERIKO specification (UKADOC)
