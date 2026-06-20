// DragDropView.swift
// SwiftUI wrapper for DragDropReceiver
import SwiftUI
import AppKit

/// SwiftUI-compatible wrapper for the DragDropReceiver NSView
struct DragDropView: NSViewRepresentable {
    let onEvent: (ShioriEvent) -> Void

    func makeNSView(context: Context) -> DragDropReceiverView {
        let view = DragDropReceiverView()
        view.onEvent = onEvent
        return view
    }

    func updateNSView(_ nsView: DragDropReceiverView, context: Context) {
        nsView.onEvent = onEvent
    }
}

/// Internal NSView that handles drag and drop operations
final class DragDropReceiverView: NSView {
    var onEvent: ((ShioriEvent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Drag entered - always allow copy operation
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onEvent?(ShioriEvent(id: .OnDragEnter, params: [:]))
        emitDroppingEvent(from: sender.draggingPasteboard)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        emitDroppingEvent(from: sender.draggingPasteboard)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onEvent?(ShioriEvent(id: .OnDragLeave, params: [:]))
    }

    /// Handle the drop operation
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let items = pb.pasteboardItems {
            // Extract file URLs
            var urls: [String] = []
            var narFiles: [URL] = []
            for it in items {
                if let u = it.string(forType: .fileURL), let url = URL(string: u) {
                    urls.append(u)
                    // Check for .nar files
                    if url.pathExtension.lowercased() == "nar" {
                        narFiles.append(url)
                    }
                }
            }

            // If .nar files are present, delegate to the app's standard file opening mechanism
            if !narFiles.isEmpty {
                for narUrl in narFiles {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.application(NSApp, open: [narUrl])
                    }
                }
                return true
            }

            // For non-.nar files, process as SHIORI events
            if !urls.isEmpty {
                // ファイルとディレクトリのフルパスを分類する
                var filePaths: [String] = []
                var dirPaths: [String] = []
                for u in urls {
                    guard let url = URL(string: u) else { continue }
                    let path = url.path
                    var isDir: ObjCBool = false
                    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                    if exists && isDir.boolValue {
                        dirPaths.append(path)
                    } else {
                        filePaths.append(path)
                    }
                }

                // 旧仕様の互換イベント（複数ファイルを Reference0.. に列挙）
                let legacyParams = Dictionary(uniqueKeysWithValues: urls.enumerated().map { ("Reference\($0.offset)", $0.element) })
                onEvent?(ShioriEvent(id: .OnDragDrop, params: legacyParams))
                onEvent?(ShioriEvent(id: .OnFileDropped, params: legacyParams))

                // ドロップ座標（スクリーン上、左上原点）を算出する
                let screenPoint = self.window?.convertPoint(toScreen: sender.draggingLocation) ?? sender.draggingLocation
                let screenHeight = NSScreen.main?.frame.height ?? 0
                let dropX = Int(screenPoint.x)
                let dropY = Int(screenHeight - screenPoint.y)

                // 現行標準（UKADOC）: 複数パスはバイト値1（0x01）区切りで Reference0 にまとめる
                let delimiter = "\u{01}"
                if !filePaths.isEmpty {
                    let joined = filePaths.joined(separator: delimiter)
                    // OnFileDrop: Reference0=ファイルパス（0x01区切り）
                    onEvent?(ShioriEvent(id: .OnFileDrop, params: ["Reference0": joined]))
                    // OnFileDrop2: Reference0=ファイルパス（0x01区切り）, Reference1=X, Reference2=Y
                    onEvent?(ShioriEvent(id: .OnFileDrop2, params: [
                        "Reference0": joined,
                        "Reference1": String(dropX),
                        "Reference2": String(dropY)
                    ]))
                }
                if !dirPaths.isEmpty {
                    // OnDirectoryDrop: Reference0=ディレクトリパス（0x01区切り）
                    onEvent?(ShioriEvent(id: .OnDirectoryDrop, params: ["Reference0": dirPaths.joined(separator: delimiter)]))
                }
                return true
            }

            // URL strings
            for it in items {
                if let u = it.string(forType: .URL) {
                    onEvent?(ShioriEvent(id: .OnURLDropping, params: ["Reference0": u]))
                    onEvent?(ShioriEvent(id: .OnURLDropped, params: ["Reference0": u]))
                    onEvent?(ShioriEvent(id: .OnURLDrop, params: ["Reference0": u]))
                    return true
                }
            }

            // Plain text
            for it in items {
                if let s = it.string(forType: .string) {
                    onEvent?(ShioriEvent(id: .OnTextDrop, params: ["Reference0": s]))
                    return true
                }
            }
        }
        onEvent?(ShioriEvent(id: .OnURLDropFailure, params: ["Reference0": "unsupported_payload"]))
        return false
    }

    private func emitDroppingEvent(from pasteboard: NSPasteboard) {
        guard let items = pasteboard.pasteboardItems else { return }
        var fileURLs: [String] = []
        for item in items {
            if let fileURL = item.string(forType: .fileURL) {
                fileURLs.append(fileURL)
            }
            if let urlString = item.string(forType: .URL) {
                onEvent?(ShioriEvent(id: .OnURLDragDropping, params: ["Reference0": urlString]))
            }
        }
        if !fileURLs.isEmpty {
            let params = Dictionary(uniqueKeysWithValues: fileURLs.enumerated().map { ("Reference\($0.offset)", $0.element) })
            onEvent?(ShioriEvent(id: .OnFileDropping, params: params))
        }
    }
}
