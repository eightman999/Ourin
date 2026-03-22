import Foundation
import AppKit

public final class PropertyManager {
    private var providers: [String: PropertyProvider] = [:]
    private var valueCache: [String: String] = [:]
    private var missingValueCache: Set<String> = []
    public static let shared = PropertyManager()

    init() {
        registerDefaultProviders()
    }

    private func registerDefaultProviders() {
        register("system", provider: SystemPropertyProvider())
        register("baseware", provider: BasewarePropertyProvider())
        let ghosts = discoverDefaultGhosts()
        let active = ghosts.isEmpty ? [] : [0]
        let balloons = discoverDefaultBalloons()
        let headlines = discoverDefaultHeadlines()
        let plugins = discoverDefaultPlugins()
        register("ghostlist", provider: GhostPropertyProvider(mode: .ghostlist, ghosts: ghosts, activeIndices: active))
        register("activeghostlist", provider: GhostPropertyProvider(mode: .activeghostlist, ghosts: ghosts, activeIndices: active))
        register("currentghost", provider: GhostPropertyProvider(mode: .currentghost, ghosts: ghosts, activeIndices: active))
        register("balloonlist", provider: BalloonPropertyProvider(mode: .balloonlist, balloons: balloons))
        register("currentghost.balloon", provider: BalloonPropertyProvider(mode: .currentBalloon))
        register("headlinelist", provider: HeadlinePropertyProvider(headlines: headlines))
        register("pluginlist", provider: PluginPropertyProvider(plugins: plugins))
        register("history", provider: HistoryPropertyProvider())
        register("rateofuselist", provider: RateOfUsePropertyProvider())
    }

    private func discoverDefaultGhosts() -> [Ghost] {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return [Ghost(name: "DefaultGhost", path: "default")]
        }
        let installed = NarRegistry.shared.installedItems(ofType: "ghost")
            .map { Ghost(name: $0.name, path: $0.path.path) }
        if !installed.isEmpty {
            return installed
        }
        return [Ghost(name: "DefaultGhost", path: "default")]
    }

    private func discoverDefaultBalloons() -> [Balloon] {
        let installed = NarRegistry.shared.installedItems(ofType: "balloon")
            .map { Balloon(name: $0.name, path: $0.path.path) }
        if !installed.isEmpty {
            return installed
        }
        return []
    }

    private func discoverDefaultHeadlines() -> [Headline] {
        if let app = NSApp.delegate as? AppDelegate, let registry = app.headlineRegistry {
            let values = registry.metas.values.map {
                Headline(name: $0.name, path: $0.filename)
            }
            if !values.isEmpty {
                return values
            }
        }
        return []
    }

    private func discoverDefaultPlugins() -> [PropertyPlugin] {
        if let app = NSApp.delegate as? AppDelegate, let registry = app.pluginRegistry {
            let values = registry.metas.values.map {
                PropertyPlugin(name: $0.name, path: $0.filename, id: $0.id)
            }
            if !values.isEmpty {
                return values
            }
        }
        return []
    }

    public func expand(_ text: String) -> String {
        return expand(text, resolvingKeys: [], depth: 0)
    }

    public func set(_ key: String, value: String) -> Bool {
        let lower = key.lowercased()
        guard let dot = lower.firstIndex(of: ".") else { return false }
        let prefix = String(lower[..<dot])
        let rest = String(lower[lower.index(after: dot)...])
        guard let provider = providers[prefix] else { return false }
        let didSet = provider.set(key: rest, value: value)
        if didSet {
            invalidateCache()
        }
        return didSet
    }

    public func get(_ key: String) -> String? {
        let lower = key.lowercased()
        if let cached = valueCache[lower] {
            return cached
        }
        if missingValueCache.contains(lower) {
            return nil
        }
        guard let dot = lower.firstIndex(of: ".") else { return nil }
        let prefix = String(lower[..<dot])
        let rest = String(lower[lower.index(after: dot)...])
        guard let provider = providers[prefix] else { return nil }
        let value = provider.get(key: rest)
        if let value {
            valueCache[lower] = value
        } else {
            missingValueCache.insert(lower)
        }
        return value
    }

    public func register(_ prefix: String, provider: PropertyProvider) {
        providers[prefix.lowercased()] = provider
        invalidateCache()
    }

    public func getList(_ key: String, separator: Character = ",") -> [String]? {
        guard let raw = get(key) else { return nil }
        let values = raw
            .split(separator: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? [] : values
    }

    public func getDictionary(
        _ key: String,
        itemSeparator: Character = ",",
        keyValueSeparator: Character = ":"
    ) -> [String: String]? {
        guard let raw = get(key) else { return nil }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [:]
        }

        var result: [String: String] = [:]
        for item in raw.split(separator: itemSeparator) {
            let chunk = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chunk.isEmpty else { continue }
            guard let separatorIndex = chunk.firstIndex(of: keyValueSeparator) else { return nil }
            let k = String(chunk[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let v = String(chunk[chunk.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !k.isEmpty else { return nil }
            result[k] = v
        }
        return result
    }

    private func invalidateCache() {
        valueCache.removeAll()
        missingValueCache.removeAll()
    }

    private func expand(_ text: String, resolvingKeys: Set<String>, depth: Int) -> String {
        guard depth < 16 else { return text }
        let pattern = "%property\\[([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        guard !matches.isEmpty else { return result }

        for match in matches.reversed() {
            guard let keyRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range(at: 0), in: result) else {
                continue
            }

            let key = String(result[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedKey = key.lowercased()
            let replacement: String
            if resolvingKeys.contains(normalizedKey) {
                replacement = ""
            } else {
                let rawValue = get(key) ?? ""
                let nestedKeys = resolvingKeys.union([normalizedKey])
                replacement = expand(rawValue, resolvingKeys: nestedKeys, depth: depth + 1)
            }
            result.replaceSubrange(fullRange, with: replacement)
        }

        if result.contains("%property[") {
            return expand(result, resolvingKeys: resolvingKeys, depth: depth + 1)
        }
        return result
    }

    /// 全てのプロバイダーから書き込み可能なプロパティのリストを取得する。
    public func writableProperties() -> [(prefix: String, keys: [String])] {
        var result: [(prefix: String, keys: [String])] = []
        for (prefix, provider) in providers {
            let keys = provider.writableProperties()
            if !keys.isEmpty {
                result.append((prefix: prefix, keys: keys))
            }
        }
        return result
    }
}

final class SystemPropertyProvider: PropertyProvider {
    private var lastCPULoad: host_cpu_load_info = host_cpu_load_info()
    private var lastLoadTime: Date = Date()

    func get(key: String) -> String? {
        switch key.lowercased() {
        case "year": return String(Calendar.current.component(.year, from: Date()))
        case "month": return String(Calendar.current.component(.month, from: Date()))
        case "day": return String(Calendar.current.component(.day, from: Date()))
        case "hour": return String(Calendar.current.component(.hour, from: Date()))
        case "minute": return String(Calendar.current.component(.minute, from: Date()))
        case "second": return String(Calendar.current.component(.second, from: Date()))
        case "millisecond": return String(Int((Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000))
        case "dayofweek": let n = Calendar.current.component(.weekday, from: Date()); return String(n)
        case "cursor.pos": return cursorPos()
        case "os.type": return "macOS"
        case "os.name":
            let v = ProcessInfo.processInfo.operatingSystemVersion
            return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        case "os.version": return sysctlString("kern.osversion")
        case "os.parenttype": return isRunningUnderRosetta2() ? "Rosetta 2" : nil
        case "os.parentname":
            if isRunningUnderRosetta2() {
                let v = ProcessInfo.processInfo.operatingSystemVersion
                let suffix = v.patchVersion == 0 ? "" : ".\(v.patchVersion)"
                return "macOS \(v.majorVersion).\(v.minorVersion)\(suffix)"
            }
            return nil
        case "cpu.num": return sysctlInt("hw.ncpu").map { String($0) }
        case "cpu.vendor": return sysctlString("machdep.cpu.vendor") ?? "Apple"
        case "cpu.name": return sysctlString("machdep.cpu.brand_string")
        case "cpu.clock": return sysctlInt("hw.cpufrequency").map { String($0) }
        case "cpu.features": return sysctlString("machdep.cpu.features")
        case "cpu.load": return cpuLoad().map { String(Int($0)) }
        case "memory.physical": return sysctlInt64("hw.memsize").map { String($0 / 1024 / 1024) }
        case "memory.available": return memoryAvailable().map { String($0) }
        case "memory.load":
            if let total = sysctlInt64("hw.memsize"), let avail = memoryAvailable() {
                let used = Double(total / 1024 / 1024 - Int64(avail))
                let load = used / Double(total / 1024 / 1024) * 100
                return String(Int(load))
            }
            return nil
        default: return nil
        }
    }

    func set(key: String, value: String) -> Bool {
        return false
    }

    private func cursorPos() -> String {
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let p = NSEvent.mouseLocation
        let x = Int(p.x - union.minX)
        let y = Int(union.maxY - p.y)
        return "\(x),\(y)"
    }

    private func cpuLoad() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
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
        return (deltaUser + deltaSystem + deltaIdle + deltaNice) / total * 100
    }

    private func memoryAvailable() -> Int? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let free = Int(info.free_count + info.inactive_count) * Int(vm_page_size) / (1024 * 1024)
        return free
    }

    private func sysctlString(_ name: String) -> String? {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        if sysctlbyname(name, &buf, &size, nil, 0) == 0 {
            return String(cString: buf)
        }
        return nil
    }

    private func sysctlInt(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    private func sysctlInt64(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    private func isRunningUnderRosetta2() -> Bool {
        var flag: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("sysctl.proc_translated", &flag, &size, nil, 0) != 0 {
            return false
        }
        return flag == 1
    }
}
