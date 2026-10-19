import Foundation
import AppKit
import Darwin

/// ゴミ箱全体の集計値。トップレベル項目数と配下を含む割当サイズを保持する。
struct RecycleBinSnapshot: Equatable {
    let count: Int
    let size: Int64
}

/// macOSのTrashを読み取り専用で監視し、OnRecycleBinStatusUpdateを発火する。
///
/// ホームの `.Trash` だけでなく、接続中ボリュームの `.Trashes/<uid>` も
/// 集計する。Finderからの操作も、Ourinの `emptyrecyclebin` も同じ状態差分として
/// 扱うため、イベントのReference値が経路によって不一致にならない。
final class RecycleBinObserver {
    static let shared = RecycleBinObserver()
    private init() {}

    private var sources: [URL: DispatchSourceFileSystemObject] = [:]
    private var mountTokens: [NSObjectProtocol] = []
    private var handler: ((ShioriEvent) -> Void)?
    private var lastSnapshot: RecycleBinSnapshot?
    private var refreshWorkItem: DispatchWorkItem?

    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        stop()
        self.handler = handler
        installSources()
        let center = NSWorkspace.shared.notificationCenter
        mountTokens.append(center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleSourceRefresh()
        })
        mountTokens.append(center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleSourceRefresh()
        })

        let initial = readSnapshot()
        lastSnapshot = initial
        emit(snapshot: initial, previous: nil, initial: true)
    }

    func stop() {
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        for source in sources.values {
            source.cancel()
        }
        sources.removeAll()
        let center = NSWorkspace.shared.notificationCenter
        for token in mountTokens {
            center.removeObserver(token)
        }
        mountTokens.removeAll()
        handler = nil
        lastSnapshot = nil
    }

    /// Re-read immediately after a baseware command changes Trash. The vnode
    /// callback normally catches this as well; deduplication against
    /// `lastSnapshot` makes the explicit refresh safe and deterministic.
    func refreshNow() {
        emitIfChanged()
    }

    /// Testable, read-only aggregation entry point.
    static func snapshot(at directories: [URL]) -> RecycleBinSnapshot {
        var count = 0
        var size: Int64 = 0
        for directory in directories {
            let partial = snapshot(at: directory)
            count += partial.count
            size += partial.size
        }
        return RecycleBinSnapshot(count: count, size: size)
    }

    /// Aggregate one Trash directory. A missing Trash directory is an empty
    /// directory from the user's point of view, so it contributes zero.
    static func snapshot(at directory: URL) -> RecycleBinSnapshot {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return RecycleBinSnapshot(count: 0, size: 0)
        }

        var totalSize: Int64 = 0
        for item in items {
            if let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey]) {
                totalSize += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                if values.isDirectory == true,
                   let descendants = FileManager.default.enumerator(
                       at: item,
                       includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                       options: [.skipsHiddenFiles]
                   ) {
                    for case let descendant as URL in descendants {
                        if let child = try? descendant.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]) {
                            totalSize += Int64(child.totalFileAllocatedSize ?? child.fileSize ?? 0)
                        }
                    }
                }
            }
        }
        return RecycleBinSnapshot(count: items.count, size: totalSize)
    }

    private func installSources() {
        let directories = trashDirectories()
        for directory in directories {
            let descriptor = open(directory.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .extend, .attrib, .link, .revoke],
                queue: .main
            )
            source.setEventHandler { [weak self, weak source] in
                guard let self else { return }
                let flags = source?.data ?? []
                self.emitIfChanged()
                if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
                    self.scheduleSourceRefresh()
                }
            }
            source.setCancelHandler {
                close(descriptor)
            }
            sources[directory] = source
            source.resume()
        }
    }

    private func scheduleSourceRefresh() {
        refreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refreshWorkItem = nil
            self.refreshSources()
        }
        refreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func refreshSources() {
        for source in sources.values {
            source.cancel()
        }
        sources.removeAll()
        installSources()
        emitIfChanged()
    }

    private func emitIfChanged() {
        let current = readSnapshot()
        guard current != lastSnapshot else { return }
        let previous = lastSnapshot
        lastSnapshot = current
        emit(snapshot: current, previous: previous, initial: false)
    }

    private func emit(snapshot: RecycleBinSnapshot,
                      previous: RecycleBinSnapshot?,
                      initial: Bool) {
        let refs = [
            "count": String(snapshot.count),
            "size": String(snapshot.size),
            "countDelta": String(snapshot.count - (previous?.count ?? snapshot.count)),
            "sizeDelta": String(snapshot.size - (previous?.size ?? snapshot.size)),
            // OnRecycleBinStatusUpdate Reference4 is defined as always 1;
            // it is not the success flag used by OnRecycleBinEmpty.
            "success": "1",
            "ghostName": ""
        ]
        handler?(ShioriEvent(
            id: .OnRecycleBinStatusUpdate,
            refs: refs,
            delivery: initial ? .notify : .get,
            ignoreResponseScript: initial
        ))
    }

    private func readSnapshot() -> RecycleBinSnapshot {
        Self.snapshot(at: trashDirectories())
    }

    private func trashDirectories() -> [URL] {
        var paths = Set<URL>()
        let homeTrash = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".Trash", isDirectory: true)
        paths.insert(homeTrash)

        let uid = String(geteuid())
        let fileManager = FileManager.default
        let volumes = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) ?? []
        for volume in volumes {
            let volumeTrash = volume
                .appendingPathComponent(".Trashes", isDirectory: true)
                .appendingPathComponent(uid, isDirectory: true)
            if fileManager.fileExists(atPath: volumeTrash.path) {
                paths.insert(volumeTrash)
            }
        }
        return paths.sorted { $0.path < $1.path }
    }
}
