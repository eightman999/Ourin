import Foundation
import AppKit
import Darwin

/// OnNotifyUserInfo の Reference0..3。
struct SystemUserInfo: Equatable {
    let addressName: String
    let fullName: String
    let birthday: String
    let gender: String

    var parameters: [String: String] {
        [
            "Reference0": addressName,
            "Reference1": fullName,
            "Reference2": birthday,
            "Reference3": gender
        ]
    }
}

/// OnNotifyOSInfo の Reference0..3。
struct SystemOSInfo: Equatable {
    let system: String
    let version: String
    let displayName: String
    let cpuType: String
    let clockMHz: String
    let cpuAdditionalInfo: String
    let physicalMemoryKB: UInt64
    let virtualMemoryKB: UInt64
    let uptimeMinutes: Int

    var parameters: [String: String] {
        [
            // UKADOC: system, version, display name (comma separated).
            "Reference0": [system, version, displayName].map(Self.csvField).joined(separator: ","),
            // UKADOC: CPU type, clock MHz, additional information (comma separated).
            "Reference1": [cpuType, clockMHz, cpuAdditionalInfo].map(Self.csvField).joined(separator: ","),
            // UKADOC: physical and virtual memory in KB (comma separated).
            "Reference2": "\(physicalMemoryKB),\(virtualMemoryKB)",
            "Reference3": String(uptimeMinutes)
        ]
    }

    private static func csvField(_ value: String) -> String {
        // Reference values are comma-delimited by the SHIORI event definition.
        // Keep the field valid if an OS/CPU display name contains a comma.
        value.replacingOccurrences(of: ",", with: " ")
    }
}

/// OnNotifyInternationalInfo の Reference0..3。
struct SystemInternationalInfo: Equatable {
    let utcOffsetMinutes: Int
    let daylightSavingTime: Bool
    let countryCode: String
    let languageCode: String

    var parameters: [String: String] {
        [
            "Reference0": String(utcOffsetMinutes),
            "Reference1": daylightSavingTime ? "1" : "0",
            "Reference2": countryCode,
            "Reference3": languageCode
        ]
    }
}

/// OnLanguageChange の Reference0..3。
struct SystemLanguageInfo: Equatable {
    let languageName: String
    let languageID: String
    let resourcePath: String
    let helpURL: String

    /// OnLanguageChange の仕様テーブルへ渡す意味ラベル。
    var references: [String: String] {
        [
            "languageName": languageName,
            "languageID": languageID,
            "resourcePath": resourcePath,
            "helpURL": helpURL
        ]
    }

    var parameters: [String: String] {
        EventReferenceTable.params(forEvent: "OnLanguageChange", refs: references)
    }
}

/// OS の実データから Notify イベントの Reference 値を組み立てる。
///
/// 値を取得できない OS 情報は空欄のまま返す。固定値で補完して実在しない
/// 環境情報を通知することはしない（OnNotifyUserInfo の gender は仕様上の
/// 未定義値 `undef` を使用する）。
enum SystemNotificationData {

    static func currentUserInfo(addressName: String? = nil) -> SystemUserInfo {
        let loginName = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        let systemFullName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredAddress = addressName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let fullName = systemFullName.isEmpty ? loginName : systemFullName
        let resolvedAddress = configuredAddress.isEmpty
            ? (fullName.isEmpty ? loginName : fullName)
            : configuredAddress

        return SystemUserInfo(
            addressName: resolvedAddress,
            fullName: fullName,
            birthday: "",
            gender: "undef"
        )
    }

    static func currentOSInfo() -> SystemOSInfo {
        let versionInfo = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(versionInfo.majorVersion).\(versionInfo.minorVersion).\(versionInfo.patchVersion)"
        let displayName = ProcessInfo.processInfo.operatingSystemVersionString

        let cpuType = sysctlString("machdep.cpu.brand_string")
            ?? sysctlString("hw.machine")
            ?? ""
        let frequencyHz = sysctlUInt64("hw.cpufrequency")
            ?? sysctlUInt64("hw.cpufrequency_max")
            ?? 0
        let clockMHz = frequencyHz > 0 ? String(frequencyHz / 1_000_000) : ""
        let processorCount = max(ProcessInfo.processInfo.activeProcessorCount, 0)
        let cpuAdditionalInfo = processorCount > 0 ? "\(processorCount) cores" : ""

        let physicalBytes = sysctlUInt64("hw.memsize") ?? ProcessInfo.processInfo.physicalMemory
        let swapBytes = swapTotalBytes() ?? 0

        return SystemOSInfo(
            system: "macOS",
            version: version,
            displayName: displayName,
            cpuType: cpuType,
            clockMHz: clockMHz,
            cpuAdditionalInfo: cpuAdditionalInfo,
            physicalMemoryKB: physicalBytes / 1024,
            virtualMemoryKB: (physicalBytes + swapBytes) / 1024,
            uptimeMinutes: max(Int(ProcessInfo.processInfo.systemUptime / 60), 0)
        )
    }

    /// NSFontManager が返すフォントファミリーを Reference* 用に正規化する。
    static func normalizedFontNames(_ names: [String]) -> [String] {
        Array(Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func currentFontNames() -> [String] {
        normalizedFontNames(NSFontManager.shared.availableFontFamilies)
    }

    static func fontParameters(_ names: [String]) -> [String: String] {
        normalizedFontNames(names).enumerated().reduce(into: [:]) { result, entry in
            result["Reference\(entry.offset)"] = entry.element
        }
    }

    static func currentInternationalInfo() -> SystemInternationalInfo {
        let timeZone = TimeZone.current
        // UKADOC defines the sign as UTC-relative: east/ahead of UTC is negative.
        let utcOffsetMinutes = -(timeZone.secondsFromGMT() / 60)
        let country = (Locale.current.regionCode ?? "").uppercased()
        let language = (Locale.current.languageCode ?? "").lowercased()

        return SystemInternationalInfo(
            utcOffsetMinutes: utcOffsetMinutes,
            daylightSavingTime: timeZone.isDaylightSavingTime(),
            countryCode: country,
            languageCode: language
        )
    }

    static func currentLanguageInfo(bundle: Bundle = .main) -> SystemLanguageInfo {
        let languageID = (Locale.current.languageCode ?? "").lowercased()
        let languageName = languageID.isEmpty
            ? ""
            : (Locale.current.localizedString(forLanguageCode: languageID) ?? languageID)
        let resourcePath = languageID.isEmpty
            ? ""
            : (bundle.path(forResource: languageID, ofType: "lproj") ?? "")

        return SystemLanguageInfo(
            languageName: languageName,
            languageID: languageID,
            resourcePath: resourcePath,
            helpURL: ""
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    private static func swapTotalBytes() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return usage.xsu_total
    }
}
