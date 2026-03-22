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
                let params = Dictionary(uniqueKeysWithValues: urls.enumerated().map { ("Reference\($0.offset)", $0.element) })
                onEvent?(ShioriEvent(id: .OnDragDrop, params: params))
                onEvent?(ShioriEvent(id: .OnFileDropped, params: params))
                onEvent?(ShioriEvent(id: .OnFileDrop, params: params))
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
