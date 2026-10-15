import AppKit
import Foundation
import Darwin

/// 起動・終了時のプロセス整理。
///
/// SSP 互換の単一インスタンス: 既に稼働中の Ourin があれば、新しく起動した側がそれを前面に出して
/// 自分が終了する（他の Ourin を強制終了しない）。以前は起動時・終了時に、パスに "Ourin.app" を含む
/// 全プロセス（利用者の Ourin、XCTest ホスト、自バンドル内の XPC ヘルパー）と全 yaya_core を
/// 強制終了しており、並行実行中のテストや他インスタンスの SHIORI まで巻き込んでいた。
/// yaya_core は親を失った孤児（クラッシュ等の残留）と自分の子だけを片付ける。
enum ProcessKiller {
    private static func listAllPIDs() -> [pid_t] {
        let type = Int32(PROC_ALL_PIDS)
        // First call with zero buffer to obtain size
        var needed = proc_listpids(UInt32(type), 0, nil, 0)
        if needed <= 0 { return [] }
        let count = Int(needed) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: count)
        needed = proc_listpids(UInt32(type), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        if needed <= 0 { return [] }
        let n = Int(needed) / MemoryLayout<pid_t>.size
        return Array(pids.prefix(n)).filter { $0 > 0 }
    }

    private static func pathFor(pid: pid_t) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is a C macro not always visible to Swift; 4096 is the documented size.
        let pathBufSize = 4096
        var buf = [CChar](repeating: 0, count: pathBufSize)
        let ret = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard ret > 0 else { return nil }
        return String(cString: buf)
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    /// プロセスの argv と環境変数（KERN_PROCARGS2、同一ユーザーのみ読める）。読めなければ nil。
    private static func argumentsAndEnvironment(of pid: pid_t) -> [String]? {
        var argmax: Int32 = 0
        var argmaxSize = MemoryLayout<Int32>.size
        var argmaxMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argmaxMib, 2, &argmax, &argmaxSize, nil, 0) == 0, argmax > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(argmax))
        var size = buffer.count
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        // 先頭 4 バイトは argc、続いて実行パス・NUL 埋め・argv・環境変数が NUL 区切りで並ぶ
        return buffer[MemoryLayout<Int32>.size..<size]
            .split(separator: 0, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    private static func isRunning(pid: pid_t) -> Bool {
        return kill(pid, 0) == 0
    }

    private static func terminateThenKill(pid: pid_t) {
        // Try SIGTERM first
        _ = kill(pid, SIGTERM)
        // Wait up to 0.5s for graceful exit
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline {
            if !isRunning(pid: pid) { return }
            usleep(50_000)
        }
        // Force kill
        _ = kill(pid, SIGKILL)
    }

    /// Ourin 本体の実行ファイルか（自バンドル内の XPC ヘルパー等は含めない）。
    static func isOurinMainExecutable(path: String) -> Bool {
        path.hasSuffix("/Ourin.app/Contents/MacOS/Ourin")
    }

    /// XCTest のテストホストとして起動された Ourin か（環境変数で判定）。
    static func isTestHost(argumentsAndEnvironment: [String]) -> Bool {
        argumentsAndEnvironment.contains {
            $0.hasPrefix("XCTestConfigurationFilePath=") || $0.hasPrefix("XCTestSessionIdentifier=") || $0.hasPrefix("XCTestBundlePath=")
        }
    }

    private static func isYaya(path: String) -> Bool {
        (path as NSString).lastPathComponent == "yaya_core"
    }

    /// 自分以外に稼働中の Ourin 本体（テストホストは除く）。
    static func otherRunningOurinInstances() -> [pid_t] {
        let selfPid = getpid()
        return listAllPIDs().filter { pid in
            guard pid != selfPid,
                  let path = pathFor(pid: pid),
                  isOurinMainExecutable(path: path) else { return false }
            // 環境が読めない場合は安全側（稼働中の Ourin とみなす）
            return !isTestHost(argumentsAndEnvironment: argumentsAndEnvironment(of: pid) ?? [])
        }
    }

    static func hasOtherOurinInstance() -> Bool {
        !otherRunningOurinInstances().isEmpty
    }

    /// 既に稼働中の Ourin を前面に出す。前面化できた場合 true。
    @discardableResult
    static func activateOtherInstance() -> Bool {
        for pid in otherRunningOurinInstances() {
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.activate()
                NSLog("[ProcessKiller] Activated running Ourin pid=\(pid)")
                return true
            }
        }
        return false
    }

    /// 親を失った（ppid=1）yaya_core だけを終了する。稼働中の他 Ourin の SHIORI には触れない。
    static func killOrphanedYaya() {
        for pid in listAllPIDs() {
            guard let path = pathFor(pid: pid), isYaya(path: path), parentPID(of: pid) == 1 else { continue }
            NSLog("[ProcessKiller] Killing orphaned yaya_core pid=\(pid) path=\(path)")
            terminateThenKill(pid: pid)
        }
    }

    /// 自分が起動した yaya_core（子プロセス）と孤児だけを終了する（終了時の後始末）。
    static func killOwnAndOrphanedYaya() {
        let selfPid = getpid()
        for pid in listAllPIDs() {
            guard let path = pathFor(pid: pid), isYaya(path: path),
                  let ppid = parentPID(of: pid), ppid == selfPid || ppid == 1 else { continue }
            NSLog("[ProcessKiller] Killing yaya_core pid=\(pid) ppid=\(ppid)")
            terminateThenKill(pid: pid)
        }
    }
}
