import Foundation
import AppKit

/// `system.*` プロパティを提供する。
final class SystemPropertyProvider: PropertyProvider {
    func get(key: String) -> String? {
        switch key {
        case "year":
            return String(Calendar.current.component(.year, from: Date()))
        case "month":
            return String(Calendar.current.component(.month, from: Date()))
        case "day":
            return String(Calendar.current.component(.day, from: Date()))
        case "hour":
            return String(Calendar.current.component(.hour, from: Date()))
        case "minute":
            return String(Calendar.current.component(.minute, from: Date()))
        case "second":
            return String(Calendar.current.component(.second, from: Date()))
        case "millisecond":
            let ms = Int((Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000)
            return String(ms)
        case "dayofweek":
            // Sunday=0
            let n = Calendar.current.component(.weekday, from: Date()) - 1
            return String(n)
        case "cursor.pos":
            return cursorPos()
        default:
            break
        }
        if key.hasPrefix("os.") {
            let sub = String(key.dropFirst(3))
            return os(sub)
        } else if key.hasPrefix("cpu.") {
            let sub = String(key.dropFirst(4))
            return cpu(sub)
        } else if key.hasPrefix("memory.") {
            let sub = String(key.dropFirst(7))
            return memory(sub)
        }
        return nil
    }

    /// マウスの現在位置を合成矩形の左上基準で返す。
    private func cursorPos() -> String {
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let p = NSEvent.mouseLocation
        let x = Int(p.x - union.minX)
        let y = Int(union.maxY - p.y)
        return "\(x),\(y)"
    }

    // MARK: - OS
    /// OS 関連プロパティの取得
    private func os(_ key: String) -> String? {
        switch key {
        case "type":
            return "macOS"
        case "name":
            let v = ProcessInfo.processInfo.operatingSystemVersion
            let suffix = v.patchVersion == 0 ? "" : ".\(v.patchVersion)"
            return "macOS \(v.majorVersion).\(v.minorVersion)\(suffix)"
        case "version":
            return sysctlString("kern.osrelease")
        case "build":
            return sysctlString("kern.osversion")
        case "parenttype":
            return isRunningUnderRosetta() ? "Rosetta 2" : nil
        case "parentname":
            if isRunningUnderRosetta() {
                let v = ProcessInfo.processInfo.operatingSystemVersion
                let suffix = v.patchVersion == 0 ? "" : ".\(v.patchVersion)"
                return "macOS \(v.majorVersion).\(v.minorVersion)\(suffix)"
            }
            return nil
        default:
            return nil
        }
    }

    // MARK: - CPU
    /// CPU 関連プロパティの取得
    private var lastCPULoad: host_cpu_load_info = host_cpu_load_info()
    private var lastLoadTime: Date = Date()

    private func cpu(_ key: String) -> String? {
        switch key {
        case "num":
            return sysctlInt("hw.ncpu").map { String($0) }
        case "vendor":
            return sysctlString("machdep.cpu.vendor") ?? "Apple"
        case "name":
            return sysctlString("machdep.cpu.brand_string")
        case "clock":
            return sysctlInt("hw.cpufrequency").map { String($0) }
        case "features":
            return sysctlString("machdep.cpu.features")
        case "load":
            return cpuLoad().map { String(Int($0)) }
        default:
            return nil
        }
    }

    /// CPU 使用率を計算
    private func cpuLoad() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let deltaUser = Double(info.cpu_ticks.0 - lastCPULoad.cpu_ticks.0)
        let deltaSystem = Double(info.cpu_ticks.1 - lastCPULoad.cpu_ticks.1)
        let deltaIdle = Double(info.cpu_ticks.2 - lastCPULoad.cpu_ticks.2)
        let deltaNice = Double(info.cpu_ticks.3 - lastCPULoad.cpu_ticks.3)
        let total = deltaUser + deltaSystem + deltaIdle + deltaNice
        lastCPULoad = info
        guard total > 0 else { return nil }
        return (deltaUser + deltaSystem + deltaNice) / total * 100
    }

    // MARK: - Memory
    /// メモリ関連プロパティの取得
    private func memory(_ key: String) -> String? {
        switch key {
        case "phyt":
            return sysctlInt64("hw.memsize").map { String($0 / 1024 / 1024) }
        case "phya":
            let avail = memoryAvailable()
            return avail.map { String($0) }
        case "load":
            if let total = sysctlInt64("hw.memsize"), let avail = memoryAvailable() {
                let used = Double(total / 1024 / 1024 - Int64(avail))
                let load = used / Double(total / 1024 / 1024) * 100
                return String(Int(load))
            }
            return nil
        default:
            return nil
        }
    }

    /// 空きメモリ量(MB)を取得
    private func memoryAvailable() -> Int? {
        var info = vm_statistics64()
        var count = HOST_VM_INFO64_COUNT
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let free = Int(info.free_count + info.inactive_count) * Int(vm_page_size) / (1024 * 1024)
        return free
    }

    // MARK: - Helpers
    /// sysctl から文字列を取得
    private func sysctlString(_ name: String) -> String? {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        if sysctlbyname(name, &buf, &size, nil, 0) == 0 {
            return String(cString: buf)
        }
        return nil
    }

    /// sysctl から整数値を取得
    private func sysctlInt(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    /// sysctl から 64bit 整数を取得
    private func sysctlInt64(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    /// Rosetta 2 下での実行判定
    private func isRunningUnderRosetta() -> Bool {
        var flag: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("sysctl.proc_translated", &flag, &size, nil, 0) != 0 {
            return false
        }
        return flag == 1
    }
}
