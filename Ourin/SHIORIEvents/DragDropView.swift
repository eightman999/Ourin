// DragDropView.swift
// SwiftUI wrapper for DragDropReceiver
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// SwiftUI-compatible wrapper for the DragDropReceiver NSView
struct DragDropView: NSViewRepresentable {
    let scopeID: Int
    let onEvent: (ShioriEvent) -> Void

    func makeNSView(context: Context) -> DragDropReceiverView {
        let view = DragDropReceiverView()
        view.scopeID = scopeID
        view.onEvent = onEvent
        return view
    }

    func updateNSView(_ nsView: DragDropReceiverView, context: Context) {
        nsView.scopeID = scopeID
        nsView.onEvent = onEvent
    }
}

/// Internal NSView that handles drag and drop operations
final class DragDropReceiverView: NSView {
    var scopeID: Int = 0
    var onEvent: ((ShioriEvent) -> Void)?

    private static let multiValueSeparator = "\u{01}"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    /// 標準D&Dイベントの Reference 値を作る（パス・スコープ・MIMEの順）。
    static func fileDropReferences(for urls: [URL], scopeID: Int) -> [String: String] {
        [
            "filePath": urls.map(\.path).joined(separator: multiValueSeparator),
            "scopeID": String(scopeID),
            "mimeType": urls.map(mimeType(for:)).joined(separator: multiValueSeparator)
        ]
    }

    private static func mimeType(for url: URL) -> String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return "inode/directory"
        }
        return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
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
            var fileURLs: [URL] = []
            var narFiles: [URL] = []
            for it in items {
                if let u = it.string(forType: .fileURL), let url = URL(string: u) {
                    urls.append(u)
                    fileURLs.append(url)
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
                var fileURLsForDrop: [URL] = []
                var dirPaths: [String] = []
                for url in fileURLs {
                    let path = url.path
                    var isDir: ObjCBool = false
                    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                    if exists && isDir.boolValue {
                        dirPaths.append(path)
                    } else {
                        fileURLsForDrop.append(url)
                    }
                }

                // 旧仕様の互換イベント（複数ファイルを Reference0.. に列挙）
                let legacyParams = Dictionary(uniqueKeysWithValues: urls.enumerated().map { ("Reference\($0.offset)", $0.element) })
                onEvent?(ShioriEvent(id: .OnDragDrop, params: legacyParams))
                onEvent?(ShioriEvent(id: .OnFileDropped, params: legacyParams))

                // 標準D&Dイベント: 複数パス／MIMEはバイト値1区切り、Reference1はスコープ番号。
                if !fileURLsForDrop.isEmpty {
                    let standardRefs = Self.fileDropReferences(for: fileURLsForDrop, scopeID: scopeID)
                    onEvent?(ShioriEvent(id: .OnFileDrop, refs: standardRefs))
                    onEvent?(ShioriEvent(id: .OnFileDropEx, refs: standardRefs))
                    onEvent?(ShioriEvent(id: .OnFileDrop2, refs: standardRefs))
                }
                if !dirPaths.isEmpty {
                    // OnDirectoryDrop: Reference0=ディレクトリパス、Reference1=スコープ番号
                    onEvent?(ShioriEvent(id: .OnDirectoryDrop, refs: [
                        "dirPath": dirPaths.joined(separator: Self.multiValueSeparator),
                        "scopeID": String(scopeID)
                    ]))
                }
                return true
            }

            // URL strings
            for it in items {
                if let u = it.string(forType: .URL) {
                    onEvent?(ShioriEvent(id: .OnURLDropping, refs: ["url": u]))
                    onEvent?(ShioriEvent(id: .OnURLDropped, refs: ["url": u]))
                    onEvent?(ShioriEvent(id: .OnURLDrop, refs: ["url": u]))
                    return true
                }
            }

            // Plain text
            for it in items {
                if let s = it.string(forType: .string) {
                    onEvent?(ShioriEvent(id: .OnTextDrop, refs: ["text": s]))
                    return true
                }
            }
        }
        onEvent?(ShioriEvent(id: .OnURLDropFailure, refs: ["filePath": "unsupported_payload"]))
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
                onEvent?(ShioriEvent(id: .OnURLDragDropping, refs: ["url": urlString]))
            }
        }
        if !fileURLs.isEmpty {
            let params = Dictionary(uniqueKeysWithValues: fileURLs.enumerated().map { ("Reference\($0.offset)", $0.element) })
            onEvent?(ShioriEvent(id: .OnFileDropping, params: params))
        }
    }
}
