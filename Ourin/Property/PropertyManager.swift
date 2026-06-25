import Foundation
import AppKit
import CoreGraphics
import IOKit.ps

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
        let calendarSkins = CalendarRegistry.shared.installedSkins()
        let calendarPlugins = CalendarRegistry.shared.installedPlugins()
        register("ghostlist", provider: GhostPropertyProvider(mode: .ghostlist, ghosts: ghosts, activeIndices: active))
        register("activeghostlist", provider: GhostPropertyProvider(mode: .activeghostlist, ghosts: ghosts, activeIndices: active))
        register("currentghost", provider: GhostPropertyProvider(mode: .currentghost, ghosts: ghosts, activeIndices: active))
        register("balloonlist", provider: BalloonPropertyProvider(mode: .balloonlist, balloons: balloons))
        register("currentghost.balloon", provider: BalloonPropertyProvider(mode: .currentBalloon))
        register("headlinelist", provider: HeadlinePropertyProvider(headlines: headlines))
        register("pluginlist", provider: PluginPropertyProvider(plugins: plugins))
        register("calendarskinlist", provider: CalendarSkinPropertyProvider(skins: calendarSkins))
        register("calendarpluginlist", provider: CalendarPluginPropertyProvider(plugins: calendarPlugins))
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
            let values = registry.allMetas.map {
                PropertyPlugin(
                    name: $0.name,
                    path: $0.compatibilityPath,
                    id: $0.id,
                    craftmanw: $0.craftman ?? "",
                    craftmanurl: $0.craftmanURL ?? "",
                    filename: $0.filename,
                    native: $0.isNative,
                    localizedMessages: $0.localizedMessages,
                    executablePath: $0.executablePath,
                    packagePath: $0.packagePath
                )
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

    /// 登録済みプロバイダのうち、key のドット接頭辞として最長一致するものを解決する。
    /// 例: `currentghost.balloon.scope(0).num` は `currentghost`(短) より
    /// `currentghost.balloon`(長) を優先し、残り `scope(0).num` をプロバイダへ渡す。
    /// （旧実装は最初のドットだけで分割していたため `currentghost.balloon` 登録が
    ///  到達不能な dead code になっていた。）
    private func resolveProvider(_ lowerKey: String) -> (prefix: String, provider: PropertyProvider, rest: String)? {
        let parts = lowerKey.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        var idx = parts.count - 1
        while idx >= 1 {
            let prefix = parts[0..<idx].joined(separator: ".")
            if let provider = providers[prefix] {
                let rest = parts[idx...].joined(separator: ".")
                return (prefix, provider, rest)
            }
            idx -= 1
        }
        return nil
    }

    public func set(_ key: String, value: String) -> Bool {
        let lower = key.lowercased()
        guard let (_, provider, rest) = resolveProvider(lower) else { return false }
        let didSet = provider.set(key: rest, value: value)
        if didSet {
            invalidateCache()
        }
        return didSet
    }

    /// 動的に値が変わる名前空間はキャッシュしない（system.second / system.cursor.pos 等が
    /// 初回取得値で固定されるのを防ぐ）。
    private static let uncachedPrefixes: Set<String> = ["system"]

    public func get(_ key: String) -> String? {
        let lower = key.lowercased()
        let firstSegment = lower.split(separator: ".", maxSplits: 1).first.map(String.init) ?? lower
        let cacheable = !Self.uncachedPrefixes.contains(firstSegment)

        if cacheable {
            if let cached = valueCache[lower] {
                return cached
            }
            if missingValueCache.contains(lower) {
                return nil
            }
        }
        guard let (_, provider, rest) = resolveProvider(lower) else {
            if cacheable { missingValueCache.insert(lower) }
            return nil
        }
        let value = provider.get(key: rest)
        if cacheable {
            if let value {
                valueCache[lower] = value
            } else {
                missingValueCache.insert(lower)
            }
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
        case "os.version": return sysctlString("kern.osrelease")
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
        // 仕様(PROPERTY/1.0M)準拠の phyt/phya を正式キーとし、英語別名も互換のため受理
        case "memory.phyt", "memory.physical": return sysctlInt64("hw.memsize").map { String($0 / 1024 / 1024) }
        case "memory.phya", "memory.available": return memoryAvailable().map { String($0) }
        case "memory.load":
            if let total = sysctlInt64("hw.memsize"), let avail = memoryAvailable() {
                let used = Double(total / 1024 / 1024 - Int64(avail))
                let load = used / Double(total / 1024 / 1024) * 100
                return String(Int(load))
            }
            return nil
        case "os.build": return sysctlString("kern.osversion")
        case "os.arch": return sysctlString("hw.machine")
        case "os.locale": return Locale.current.identifier
        case "os.timezone.offset": return String(TimeZone.current.secondsFromGMT() / 60)
        case "os.uptime": return String(Int(ProcessInfo.processInfo.systemUptime))
        case "os.unixtime": return String(Int(Date().timeIntervalSince1970))
        case "os.idletime": return String(Int(systemIdleSeconds()))
        case "monitor.count": return String(NSScreen.screens.count)
        case "theme.app.mode", "theme.os.mode": return appearanceMode()
        case "dnd.mode": return "0"   // macOS の Focus 状態は公開 API で取得不可
        case "power.source": return powerSource()
        case "power.battery.percent": return batteryPercent().map { String($0) }
        case "power.battery.flag": return powerSource() == "battery" ? "1" : "0"
        case "network.status": return primaryIPv4() != nil ? "online" : "offline"
        case "network.ipaddress": return primaryIPv4() ?? ""
        case "disk.count": return String(mountedVolumes().count)
        case let k where k.hasPrefix("monitor.index("): return monitorProperty(k)
        case let k where k.hasPrefix("disk.index("): return diskProperty(k)
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
        // 使用率はアイドルを除いた割合。idle を分子に含めると常に 100% になる
        return (deltaUser + deltaSystem + deltaNice) / total * 100
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

    // MARK: - 追加: monitor / disk / theme / power / network / os.*

    private func appearanceMode() -> String {
        let name = NSApp?.effectiveAppearance.name.rawValue ?? ""
        return name.lowercased().contains("dark") ? "dark" : "light"
    }

    private func systemIdleSeconds() -> Double {
        let anyType = CGEventType(rawValue: ~UInt32(0)) ?? .null
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyType)
    }

    private func monitorProperty(_ key: String) -> String? {
        guard let lp = key.firstIndex(of: "("), let rp = key.firstIndex(of: ")"),
              let idx = Int(key[key.index(after: lp)..<rp]),
              NSScreen.screens.indices.contains(idx) else { return nil }
        let screen = NSScreen.screens[idx]
        let field = key[key.index(after: rp)...].drop(while: { $0 == "." }).lowercased()
        let f = screen.frame, w = screen.visibleFrame
        switch field {
        case "rect": return "\(Int(f.minX)),\(Int(f.minY)),\(Int(f.maxX)),\(Int(f.maxY))"
        case "work": return "\(Int(w.minX)),\(Int(w.minY)),\(Int(w.maxX)),\(Int(w.maxY))"
        case "dpi": return String(Int(screen.backingScaleFactor * 72))
        case "primary": return idx == 0 ? "1" : "0"
        default: return nil
        }
    }

    private func mountedVolumes() -> [URL] {
        return FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                     options: [.skipHiddenVolumes]) ?? []
    }

    private func diskProperty(_ key: String) -> String? {
        guard let lp = key.firstIndex(of: "("), let rp = key.firstIndex(of: ")"),
              let idx = Int(key[key.index(after: lp)..<rp]) else { return nil }
        let vols = mountedVolumes()
        guard vols.indices.contains(idx) else { return nil }
        let url = vols[idx]
        let field = key[key.index(after: rp)...].drop(while: { $0 == "." }).lowercased()
        switch field {
        case "mountpoint": return url.path
        case "total", "free":
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
               let n = attrs[field == "total" ? .systemSize : .systemFreeSize] as? NSNumber {
                return String(n.int64Value / 1024 / 1024)
            }
            return nil
        default: return nil
        }
    }

    private func powerDescription() -> [String: Any]? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let src = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any]
        else { return nil }
        return desc
    }

    private func powerSource() -> String {
        guard let d = powerDescription(),
              let state = d[kIOPSPowerSourceStateKey as String] as? String else { return "ac" }
        return state == (kIOPSACPowerValue as String) ? "ac" : "battery"
    }

    private func batteryPercent() -> Int? {
        guard let d = powerDescription(),
              let cur = d[kIOPSCurrentCapacityKey as String] as? Int,
              let mx = d[kIOPSMaxCapacityKey as String] as? Int, mx > 0 else { return nil }
        return Int((Double(cur) / Double(mx)) * 100)
    }

    private func primaryIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var fallback: String?
        var ptr = ifaddr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(bitPattern: cur.pointee.ifa_flags)
            guard (flags & IFF_LOOPBACK) == 0, (flags & IFF_UP) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            let name = String(cString: cur.pointee.ifa_name)
            if name == "en0" { return ip }   // 物理/Wi-Fi を優先
            if fallback == nil { fallback = ip }
        }
        return fallback
    }
}
