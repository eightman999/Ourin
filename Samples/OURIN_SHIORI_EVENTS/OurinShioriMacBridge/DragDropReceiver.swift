// DragDropReceiver.swift
import AppKit
import UniformTypeIdentifiers

final class DragDropReceiver: NSView {
    static let shared = DragDropReceiver()
    private var onEvent: ((ShioriEvent)->Void)?

    private override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .string])
    }
    required init?(coder: NSCoder) { fatalError() }

    func activate(_ onEvent: @escaping (ShioriEvent)->Void) {
        self.onEvent = onEvent
        if self.superview == nil {
            // Install as overlay in key window if available
            if let win = NSApp.windows.first {
                self.frame = win.contentView?.bounds ?? .zero
                self.autoresizingMask = [.width, .height]
                win.contentView?.addSubview(self, positioned: .above, relativeTo: nil)
            }
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let items = pb.pasteboardItems {
            // file-url
            var urls: [String] = []
            for it in items {
                if let u = it.string(forType: .fileURL) { urls.append(u) }
            }
            if !urls.isEmpty {
                onEvent?(ShioriEvent(id: "OnFileDrop", params: Dictionary(uniqueKeysWithValues: urls.enumerated().map{ ("Reference\($0.offset)", $0.element) } )))
                return true
            }
            // url
            for it in items {
                if let u = it.string(forType: .URL) {
                    onEvent?(ShioriEvent(id: "OnURLDrop", params: ["Reference0": u]))
                    return true
                }
            }
            // plain text
            for it in items {
                if let s = it.string(forType: .string) {
                    onEvent?(ShioriEvent(id: "OnTextDrop", params: ["Reference0": s]))
                    return true
                }
            }
        }
        return false
    }
}
