import Foundation
import Darwin

// ProcessKiller: Kills other Ourin instances and stray yaya_core processes at startup.
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

    static func killOtherOurinAndYaya() {
        let selfPid = getpid()
        let selfPath = pathFor(pid: selfPid) ?? ""
        let isOurinSelf = selfPath.contains("Ourin.app")

        var killedPids: [pid_t] = []
        for pid in listAllPIDs() {
            if pid == selfPid { continue }
            guard let path = pathFor(pid: pid) else { continue }
            // Match other Ourin apps
            if path.contains("Ourin.app") {
                // Avoid killing unrelated helper inside our own bundle path if it belongs to us
                if isOurinSelf {
                    // Different process ID and same app bundle name → treat as another instance
                    NSLog("[ProcessKiller] Killing other Ourin pid=\(pid) path=\(path)")
                    terminateThenKill(pid: pid)
                    killedPids.append(pid)
                }
                continue
            }
            // Match yaya_core helper
            if path.hasSuffix("/yaya_core") || (path as NSString).lastPathComponent == "yaya_core" {
                NSLog("[ProcessKiller] Killing stray yaya_core pid=\(pid) path=\(path)")
                terminateThenKill(pid: pid)
                killedPids.append(pid)
            }
        }
        if killedPids.isEmpty {
            NSLog("[ProcessKiller] No other Ourin/yaya_core processes found to kill")
        }
    }
}
