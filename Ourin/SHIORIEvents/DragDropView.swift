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
    private static let genericItemType = NSPasteboard.PasteboardType(UTType.item.identifier)
    private static let genericDataType = NSPasteboard.PasteboardType(UTType.data.identifier)

    /// ファイル/URL/文字列以外のPasteboardも受け取り、OnOtherObject*へ分類する。
    /// public.item/public.data はmacOSのドラッグ提供元が独自UTIしか公開しない場合の
    /// 共通上位型として登録する。
    static let registeredDraggedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .string,
        genericItemType,
        genericDataType
    ]

    private static let knownPasteboardTypeIDs: Set<String> = [
        NSPasteboard.PasteboardType.fileURL.rawValue,
        NSPasteboard.PasteboardType.URL.rawValue,
        NSPasteboard.PasteboardType.string.rawValue,
        genericItemType.rawValue,
        genericDataType.rawValue
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(Self.registeredDraggedTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(Self.registeredDraggedTypes)
    }

    /// 標準D&Dイベントの Reference 値を作る（パス・スコープ・MIMEの順）。
    static func fileDropReferences(for urls: [URL], scopeID: Int) -> [String: String] {
        [
            "filePath": urls.map(\.path).joined(separator: multiValueSeparator),
            "scopeID": String(scopeID),
            "mimeType": urls.map(mimeType(for:)).joined(separator: multiValueSeparator)
        ]
    }

    /// OnFileDropping は MIME を持たないため、ホバー中の参照だけを作る。
    static func fileDroppingReferences(for urls: [URL], scopeID: Int) -> [String: String] {
        [
            "filePath": urls.map(\.path).joined(separator: multiValueSeparator),
            "scopeID": String(scopeID)
        ]
    }

    static func directoryDropReferences(for urls: [URL], scopeID: Int) -> [String: String] {
        [
            "dirPath": urls.map(\.path).joined(separator: multiValueSeparator),
            "scopeID": String(scopeID)
        ]
    }

    /// ファイル系イベントとディレクトリ系イベントを重複させないよう分類する。
    static func classifyFileURLs(_ urls: [URL]) -> (files: [URL], directories: [URL]) {
        var files: [URL] = []
        var directories: [URL] = []

        for url in urls {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if exists && isDirectory.boolValue {
                directories.append(url)
            } else {
                files.append(url)
            }
        }

        return (files, directories)
    }

    private static func mimeType(for url: URL) -> String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return "inode/directory"
        }
        return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    /// 非ファイルPasteboardを公式のOnOtherObject* Referenceへ変換する。
    /// macOSにはWindowsのShell Object IDに相当する共通値がないため、独自UTIを
    /// objectIDとして保持し、文字列表現が取れる場合はnameに使う。
    static func otherObjectDropReferences(
        for items: [NSPasteboardItem],
        scopeID: Int
    ) -> [String: String] {
        var names: [String] = []
        var objectIDs: [String] = []

        for item in items {
            let typeIDs = item.types.map(\.rawValue)
            let customTypeIDs = typeIDs.filter { !knownPasteboardTypeIDs.contains($0) }
            let objectID = customTypeIDs.first ?? typeIDs.first ?? "unknown"
            let name = customTypeIDs
                .compactMap { item.string(forType: NSPasteboard.PasteboardType($0)) }
                .first(where: { !$0.isEmpty })
                ?? item.string(forType: .string)
                ?? objectID
            names.append(name)
            objectIDs.append(objectID)
        }

        return [
            "scopeID": String(scopeID),
            "name": names.joined(separator: multiValueSeparator),
            "objectID": objectIDs.joined(separator: multiValueSeparator)
        ]
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
                    if let appDelegate = AppDelegate.resolve() {
                        appDelegate.application(NSApp, open: [narUrl])
                    }
                }
                return true
            }

            // For non-.nar files, process as SHIORI events
            if !urls.isEmpty {
                // ファイルとディレクトリのフルパスを分類する
                let classifiedURLs = Self.classifyFileURLs(fileURLs)

                // 旧仕様の互換イベント（複数ファイルを Reference0.. に列挙）
                let legacyParams = Dictionary(uniqueKeysWithValues: urls.enumerated().map { ("Reference\($0.offset)", $0.element) })
                onEvent?(ShioriEvent(id: .OnDragDrop, params: legacyParams))

                if !classifiedURLs.files.isEmpty {
                    let standardRefs = Self.fileDropReferences(for: classifiedURLs.files, scopeID: scopeID)
                    onEvent?(ShioriEvent(id: .OnFileDropped, refs: standardRefs))

                    // 標準D&Dイベント: 複数パス／MIMEはバイト値1区切り、Reference1はスコープ番号。
                    onEvent?(ShioriEvent(id: .OnFileDrop, refs: standardRefs))
                    onEvent?(ShioriEvent(id: .OnFileDropEx, refs: standardRefs))
                    onEvent?(ShioriEvent(id: .OnFileDrop2, refs: standardRefs))
                }

                if !classifiedURLs.directories.isEmpty {
                    onEvent?(ShioriEvent(id: .OnDirectoryDrop,
                                         refs: Self.directoryDropReferences(for: classifiedURLs.directories, scopeID: scopeID)))
                }
                return true
            }

            // URL strings. ここではダウンロードを開始していないため、
            // OnURLDropping/OnURLDropped/OnURLDropFailure は発火しない。
            // それらは実ダウンロード経路が開始・完了・失敗した箇所で送る。
            for it in items {
                if let u = it.string(forType: .URL) {
                    onEvent?(ShioriEvent(id: .OnURLDrop, refs: [
                        "url": u,
                        "scopeID": String(scopeID)
                    ]))
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

            // ファイル/URL/文字列でないPasteboardは、URL失敗ではなく
            // WindowsのShell Objectに相当する公式イベントへ渡す。
            onEvent?(ShioriEvent(
                id: .OnOtherObjectDropped,
                refs: Self.otherObjectDropReferences(for: items, scopeID: scopeID)
            ))
            return true
        }
        return false
    }

    private func emitDroppingEvent(from pasteboard: NSPasteboard) {
        guard let items = pasteboard.pasteboardItems else { return }
        var fileURLs: [String] = []
        var hasURL = false
        var hasString = false
        for item in items {
            if let fileURL = item.string(forType: .fileURL) {
                fileURLs.append(fileURL)
            }
            if let urlString = item.string(forType: .URL) {
                hasURL = true
                onEvent?(ShioriEvent(id: .OnURLDragDropping, refs: [
                    "url": urlString,
                    "scopeID": String(scopeID)
                ]))
            }
            if item.string(forType: .string) != nil {
                hasString = true
            }
        }
        if !fileURLs.isEmpty {
            let urls = fileURLs.compactMap(URL.init(string:))
            onEvent?(ShioriEvent(
                id: .OnFileDropping,
                refs: Self.fileDroppingReferences(for: urls, scopeID: scopeID)
            ))
        } else if !hasURL && !hasString {
            onEvent?(ShioriEvent(id: .OnOtherObjectDropping,
                                 refs: Self.otherObjectDropReferences(for: items, scopeID: scopeID)))
        }
    }
}
