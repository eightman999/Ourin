import Darwin
import Foundation

// MARK: - clipcopy（SatisKia 氏作）

/// クリップボードに文字列をコピーする。Argument0 の `\n` を改行にする（`\\n` と書けば `\n` のまま）。戻り値なし（204）。
final class CompatClipcopyModule: CompatSaoriModule {
    init(environment: CompatSaoriEnvironment) {}

    func execute(_ arguments: [String], charset: String) -> CompatSaoriResult {
        guard let text = arguments.first else { return .badRequest }
        return CompatSaoriHooks.writeClipboard(Self.unescape(text)) ? .noContent : .internalError
    }

    static func unescape(_ text: String) -> String {
        var output = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            if characters[index] == "\\", index + 2 < characters.count, characters[index + 1] == "\\", characters[index + 2] == "n" {
                output += "\\n"
                index += 3
            } else if characters[index] == "\\", index + 1 < characters.count, characters[index + 1] == "n" {
                output += "\n"
                index += 2
            } else {
                output.append(characters[index])
                index += 1
            }
        }
        return output
    }
}

// MARK: - textcopy（橋本孔明氏作。CSaori の textcopy2 と同じ動き）

/// クリップボードに文字列をコピーする。Argument1 が 0 以外なら、コピーした文字列を Result に返す（それ以外は 204）。
/// Argument2 があれば、その文字列を改行に置き換えてからコピーする（textcopy2 の拡張）。
final class CompatTextcopyModule: CompatSaoriModule {
    init(environment: CompatSaoriEnvironment) {}

    func execute(_ arguments: [String], charset: String) -> CompatSaoriResult {
        guard let text = arguments.first, !text.isEmpty else { return .badRequest }
        var copied = text
        if arguments.count >= 3, !arguments[2].isEmpty {
            copied = copied.replacingOccurrences(of: arguments[2], with: "\n")
        }
        guard CompatSaoriHooks.writeClipboard(copied) else { return .internalError }
        if arguments.count >= 2, CompatSaoriHost.leadingInteger(arguments[1]) != 0 {
            return .ok(text)
        }
        return .noContent
    }
}

// MARK: - saori_ip（CSaori Project）

/// GetLocalIP（この Mac の IPv4 アドレス）/ GetInternetIP（外から見た IP アドレス）/ GetLocalHostname（ホスト名）。
/// 関数名は大文字小文字を区別せず、先頭が一致すればよい（原作どおり）。
final class CompatSaoriIPModule: CompatSaoriModule {
    /// 原作が外から見た IP アドレスを問い合わせる先。
    static let internetIPURL = URL(string: "http://usada.sakura.vg/ip.php")!

    init(environment: CompatSaoriEnvironment) {}

    func execute(_ arguments: [String], charset: String) -> CompatSaoriResult {
        guard let command = arguments.first?.lowercased() else { return .badRequest }
        if command.hasPrefix("getlocalip") {
            return Self.localIPv4().map { .ok($0) } ?? .internalError
        }
        if command.hasPrefix("getinternetip") {
            guard let reply = CompatSaoriHooks.fetch(Self.internetIPURL),
                  let text = String(data: reply.data, encoding: .utf8) ?? String(data: reply.data, encoding: .isoLatin1) else {
                return .internalError
            }
            let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return address.isEmpty ? .internalError : .ok(address)
        }
        if command.hasPrefix("getlocalhostname") {
            var buffer = [CChar](repeating: 0, count: 256)
            guard gethostname(&buffer, buffer.count) == 0 else { return .internalError }
            return .ok(String(cString: buffer))
        }
        return .badRequest
    }

    /// 動いているインターフェースの最初の IPv4（ループバック以外。en0 を優先）。
    static func localIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var candidates: [(name: String, address: String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            candidates.append((String(cString: entry.pointee.ifa_name), String(cString: host)))
        }
        return (candidates.first { $0.name == "en0" } ?? candidates.first)?.address
    }
}

// MARK: - cpuusage（りゅう氏作）

/// get で、過去 1 秒間の平均 CPU 使用率（0〜100 の整数）を返す。
final class CompatCPUUsageModule: CompatSaoriModule {
    init(environment: CompatSaoriEnvironment) {
        CompatCPUUsage.shared.start()
    }

    func execute(_ arguments: [String], charset: String) -> CompatSaoriResult {
        guard arguments.first?.lowercased() == "get" else { return .badRequest }
        return .ok(String(CompatCPUUsage.shared.averageOverLastSecond()))
    }
}

/// CPU 使用率。0.5 秒ごとに全 CPU の累積の時間を記録し、1 秒前との差から求める。
final class CompatCPUUsage {
    static let shared = CompatCPUUsage()

    private struct Sample {
        var time: TimeInterval
        var busy: UInt64
        var total: UInt64
    }

    private var samples: [Sample] = []
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "jp.ourin.compat.cpuusage", qos: .utility)

    func start() {
        lock.lock(); defer { lock.unlock() }
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: 0.5)
        source.setEventHandler { [weak self] in self?.record() }
        source.resume()
        timer = source
    }

    private func record() {
        guard let sample = Self.sample() else { return }
        lock.lock(); defer { lock.unlock() }
        samples.append(sample)
        samples.removeAll { sample.time - $0.time > 3 }
    }

    /// 過去 1 秒間の平均（記録が足りなければ、いま 0.2 秒だけ測る）。
    func averageOverLastSecond() -> Int {
        guard let now = Self.sample() else { return 0 }
        lock.lock()
        let reference = samples.last { now.time - $0.time >= 0.95 } ?? samples.first { now.time - $0.time >= 0.2 }
        lock.unlock()
        if let reference { return Self.percent(from: reference, to: now) }
        Thread.sleep(forTimeInterval: 0.2)
        guard let later = Self.sample() else { return 0 }
        return Self.percent(from: now, to: later)
    }

    private static func percent(from old: Sample, to new: Sample) -> Int {
        let total = new.total &- old.total
        guard total > 0, new.total >= old.total else { return 0 }
        let busy = new.busy &- old.busy
        return min(100, max(0, Int((Double(busy) * 100 / Double(total)).rounded())))
    }

    private static func sample() -> Sample? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let user = UInt64(load.cpu_ticks.0), system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2), nice = UInt64(load.cpu_ticks.3)
        return Sample(time: ProcessInfo.processInfo.systemUptime, busy: user + system + nice, total: user + system + idle + nice)
    }
}

// MARK: - houchi（りゅう氏作。放置器）

/// load すると、ユーザーが PC を操作していない間、1 分ごとに OnHouchi（Reference0 = 連続放置時間（分））をゴーストへ送る。
/// 関数は無い（呼ばれても 204）。Direct SSTP（ゴーストなし）では何もしない。
final class CompatHouchiModule: CompatSaoriModule {
    private let deliver: ((String, [String]) -> Void)?
    private var timer: DispatchSourceTimer?
    private var lastNotifiedMinutes = 0
    private let lock = NSLock()

    init(environment: CompatSaoriEnvironment) {
        deliver = environment.hasGhost ? environment.deliverEvent : nil
        guard deliver != nil else { return }
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        source.schedule(deadline: .now() + 5, repeating: 5)
        source.setEventHandler { [weak self] in self?.poll() }
        source.resume()
        timer = source
    }

    func execute(_ arguments: [String], charset: String) -> CompatSaoriResult { .noContent }

    /// 放置時間を確かめ、1 分を越えるたびに通知する。操作があれば数え直す。
    func poll() {
        let minutes = Int(CompatSaoriHooks.idleSeconds() / 60)
        lock.lock()
        let notify = minutes >= 1 && minutes > lastNotifiedMinutes
        lastNotifiedMinutes = minutes >= 1 ? max(lastNotifiedMinutes, minutes) : 0
        lock.unlock()
        if notify { deliver?("OnHouchi", [String(minutes)]) }
    }

    func unload() {
        timer?.cancel()
        timer = nil
    }
}

// MARK: - saori_cpuid（七瀬いーうぃ氏作。CCPUID の拡張も一部）

/// CPU・メモリ・OS の情報を返す。Argument1 が数値の 0 なら返さない（204）。
/// CCPUID のように Argument1 以降にも取得情報コードを並べると、それぞれの値が Value0 から順に入る（Value0 は Argument0 の値）。
final class CompatSaoriCPUIDModule: CompatSaoriModule {
    init(environment: CompatSaoriEnvironment) {}

    func execute(_ arguments: [String], charset: String) -> CompatSaoriResult {
        guard let first = arguments.first else { return .noContent }
        // Argument1 が数値なら「返す / 返さない」の指定（原作）、そうでなければ追加の取得情報コード（CCPUID）。
        var keys = [first]
        if arguments.count >= 2 {
            let flag = arguments[1].trimmingCharacters(in: .whitespaces)
            if let number = Int(flag) {
                if number == 0 { return .noContent }
            } else {
                keys += arguments.dropFirst()
            }
        }
        let values = keys.map { Self.value(for: $0) }
        guard let result = values.first ?? nil else {
            return CompatSaoriResult(status: 400, result: "param error", error: "param error")
        }
        return .ok(result, values: keys.count > 1 ? values.map { $0 ?? "param error" } : [])
    }

    static func value(for key: String) -> String? {
        let info = CompatSystemInfo.self
        switch key {
        case "platform":
            return Bundle.main.executableURL?.lastPathComponent ?? ProcessInfo.processInfo.processName
        case "os.name": return "macOS"
        case "os.version":
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return "\(version.majorVersion).\(version.minorVersion)"
        case "os.build": return info.string("kern.osversion") ?? ""
        case "cpu.num": return String(info.int("hw.ncpu") ?? Int64(ProcessInfo.processInfo.processorCount))
        case "cpu.logicalprocessors": return String(ProcessInfo.processInfo.processorCount)
        case "cpu.vender", "cpu.vendor": return info.string("machdep.cpu.vendor") ?? (info.isAppleSilicon ? "Apple" : "")
        case "cpu.name": return info.string("machdep.cpu.brand_string") ?? ""
        case "cpu.ptype": return "0"
        case "cpu.family": return String(info.int("machdep.cpu.family") ?? info.int("hw.cpufamily") ?? 0)
        case "cpu.model": return String(info.int("machdep.cpu.model") ?? 0)
        case "cpu.stepping": return String(info.int("machdep.cpu.stepping") ?? 0)
        case "cpu.mmx": return info.ready("MMX")
        case "cpu.sse": return info.ready("SSE")
        case "cpu.sse2": return info.ready("SSE2")
        case "cpu.htt": return info.ready("HTT")
        case "cpu.tdn", "cpu.mmx+", "cpu.tdn+": return "Not Ready" // 3DNow! / MMX+ は AMD の古い拡張で、Mac の CPU には無い
        case "cpu.features": return info.cpuFeatures.joined(separator: " ")
        case "cpu.cache":
            let kb = { (name: String) in String((info.int(name) ?? 0) / 1024) }
            return [kb("hw.l1dcachesize"), kb("hw.l1icachesize"), kb("hw.l2cachesize"), kb("hw.l3cachesize")].joined(separator: " ")
        case "cpu.usage": return String(CompatCPUUsage.shared.averageOverLastSecond())
        case "cpu.vmguest": return (info.int("kern.hv_vmm_present") ?? 0) != 0 ? "Yes" : "No"
        case "cpu.clock": return String(Int((info.cpuFrequencyMHz).rounded()))
        case "cpu.clockex": return String(format: "%.3f", info.cpuFrequencyMHz)
        case "mem.os", "mem.phyt", "mem.phya", "mem.pagt", "mem.paga", "mem.virt", "mem.vira", "mem.viraex":
            return info.memory(key)
        default: return nil
        }
    }
}

/// sysctl・Mach からの情報。
enum CompatSystemInfo {
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func int(_ name: String) -> Int64? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        switch size {
        case 4:
            var value: Int32 = 0
            guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
            return Int64(value)
        case 8:
            var value: Int64 = 0
            guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
            return value
        default:
            return nil
        }
    }

    static var isAppleSilicon: Bool { (int("hw.optional.arm64") ?? 0) != 0 }

    /// Intel の CPU の機能（machdep.cpu.features / extfeatures / leaf7_features）。Apple シリコンでは空。
    static var cpuFeatures: [String] {
        ["machdep.cpu.features", "machdep.cpu.extfeatures", "machdep.cpu.leaf7_features"]
            .compactMap { string($0) }
            .flatMap { $0.split(separator: " ").map(String.init) }
    }

    static func ready(_ feature: String) -> String {
        cpuFeatures.contains(feature) ? "Ready" : "Not Ready"
    }

    /// クロック周波数（MHz）。Apple シリコンでは OS が出さないので 0。
    static var cpuFrequencyMHz: Double {
        Double(int("hw.cpufrequency") ?? int("hw.cpufrequency_max") ?? 0) / 1_000_000
    }

    /// メモリの情報（MB。mem.os は使用率の %）。ページファイルは物理メモリ＋スワップ、仮想メモリはこのプロセスのアドレス空間。
    static func memory(_ key: String) -> String {
        let megabyte: UInt64 = 1_048_576
        let total = UInt64(int("hw.memsize") ?? 0)
        let available = availablePhysicalMemory()
        let swap = swapUsage()
        let virtualTotal: UInt64 = 1 << 47 // 64 ビットのユーザー空間（128 TiB）
        switch key {
        case "mem.os":
            guard total > 0 else { return "0" }
            return String(Int((Double(total - min(total, available)) * 100 / Double(total)).rounded()))
        case "mem.phyt": return String(total / megabyte)
        case "mem.phya": return String(available / megabyte)
        case "mem.pagt": return String((total + swap.total) / megabyte)
        case "mem.paga": return String((available + swap.available) / megabyte)
        case "mem.virt": return String(virtualTotal / megabyte)
        case "mem.vira": return String((virtualTotal - min(virtualTotal, taskVirtualSize())) / megabyte)
        default: return "0" // mem.viraex（Windows の拡張仮想メモリ。Mac には無い）
        }
    }

    private static func availablePhysicalMemory() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return 0 }
        let pages = UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.purgeable_count) + UInt64(stats.speculative_count)
        return pages * UInt64(vm_kernel_page_size)
    }

    private static func swapUsage() -> (total: UInt64, available: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_total, usage.xsu_avail)
    }

    private static func taskVirtualSize() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? UInt64(info.virtual_size) : 0
    }
}
