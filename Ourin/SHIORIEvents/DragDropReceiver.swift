// DragDropReceiver.swift
// ドラッグ＆ドロップされたデータを受け取り SHIORI イベントに変換
// DEPRECATED: This implementation is deprecated in favor of DragDropView.swift
// which properly integrates with SwiftUI using NSViewRepresentable.
// This file is kept for backward compatibility only.

import AppKit
import UniformTypeIdentifiers

@available(*, deprecated, message: "Use DragDropView instead for SwiftUI integration")
final class DragDropReceiver: NSView {
    static let shared = DragDropReceiver()
    private var onEvent: ((ShioriEvent)->Void)?

    private override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .string])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// ドロップ受付を有効化し、最前面ビューへ自身を追加する
    /// WARNING: This method is deprecated and should not be used with NSHostingController
    @available(*, deprecated, message: "This causes view hierarchy issues with NSHostingController. Use DragDropView in SwiftUI instead.")
    func activate(_ onEvent: @escaping (ShioriEvent)->Void) {
        self.onEvent = onEvent
        if self.superview == nil {
            // キーウィンドウがあればその上にオーバーレイとして配置
            if let win = NSApp.windows.first {
                self.frame = win.contentView?.bounds ?? .zero
                self.autoresizingMask = [.width, .height]
                win.contentView?.addSubview(self, positioned: .above, relativeTo: nil)
            }
        }
    }

    /// ドラッグ開始時は常にコピー操作を許可する
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    /// ドロップされたデータ種別を判別して適切なイベントを発火する
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let items = pb.pasteboardItems {
            // ファイル URL の取り出し
            var urls: [String] = []
            var narFiles: [URL] = []
            for it in items {
                if let u = it.string(forType: .fileURL), let url = URL(string: u) {
                    urls.append(u)
                    // .nar ファイルをチェック
                    if url.pathExtension.lowercased() == "nar" {
                        narFiles.append(url)
                    }
                }
            }

            // .nar ファイルが含まれている場合はアプリの標準ファイル開処理に委譲
            if !narFiles.isEmpty {
                for narUrl in narFiles {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.application(NSApp, open: [narUrl])
                    }
                }
                return true
            }

            // .nar 以外のファイルは従来通り SHIORI イベントとして処理
            if !urls.isEmpty {
                onEvent?(ShioriEvent(id: .OnFileDrop, params: Dictionary(uniqueKeysWithValues: urls.enumerated().map{ ("Reference\($0.offset)", $0.element) } )))
                return true
            }

            // URL 文字列
            for it in items {
                if let u = it.string(forType: .URL) {
                    onEvent?(ShioriEvent(id: .OnURLDrop, params: ["Reference0": u]))
                    return true
                }
            }
            // プレーンテキスト
            for it in items {
                if let s = it.string(forType: .string) {
                    onEvent?(ShioriEvent(id: .OnTextDrop, params: ["Reference0": s]))
                    return true
                }
            }
        }
        return false
    }
}
