import Foundation
import Security

enum RuntimeSecurityCapabilities {
    static var sandboxDetector: () -> Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let entitlement = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil)
        return (entitlement as? Bool) == true || (entitlement as? NSNumber)?.boolValue == true
    }

    static var incomingNetworkEntitlementDetector: () -> Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let entitlement = SecTaskCopyValueForEntitlement(task, "com.apple.security.network.server" as CFString, nil)
        return (entitlement as? Bool) == true || (entitlement as? NSNumber)?.boolValue == true
    }

    static func isSandboxed() -> Bool {
        sandboxDetector()
    }

    static func allowsIncomingNetworkServer() -> Bool {
        incomingNetworkEntitlementDetector()
    }
}

/// Persistent security and exposure settings for external SSTP listeners.
public struct ExternalServerSecuritySettings: Equatable {
    public static let allowTcpKey = "OurinExternalSSTPAllowTCP"
    public static let allowHttpKey = "OurinExternalSSTPAllowHTTP"
    public static let allowExternalSecurityLevelKey = "OurinExternalSSTPAllowExternalSecurityLevel"
    public static let allowXpcKey = "OurinExternalSSTPAllowXPC"
    public static let maxPayloadSizeKey = "OurinExternalSSTPMaxPayloadSize"
    public static let timeoutSecondsKey = "OurinExternalSSTPTimeoutSeconds"

    /// Network listener exposure. Default false to avoid unintended publishing.
    public var allowTCP: Bool
    public var allowHTTP: Bool
    /// Whether external SecurityLevel requests are accepted by router policy.
    public var allowExternalSecurityLevel: Bool
    /// XPC is local IPC; enabled by default.
    public var allowXPC: Bool
    public var maxPayloadSize: Int
    public var timeoutSeconds: TimeInterval

    public init(
        allowTCP: Bool = false,
        allowHTTP: Bool = false,
        allowExternalSecurityLevel: Bool = false,
        allowXPC: Bool = true,
        maxPayloadSize: Int = 1024 * 1024,
        timeoutSeconds: TimeInterval = 30
    ) {
        self.allowTCP = allowTCP
        self.allowHTTP = allowHTTP
        self.allowExternalSecurityLevel = allowExternalSecurityLevel
        self.allowXPC = allowXPC
        self.maxPayloadSize = max(8 * 1024, maxPayloadSize)
        self.timeoutSeconds = max(1, timeoutSeconds)
    }

    public static func load(defaults: UserDefaults = .standard) -> ExternalServerSecuritySettings {
        let hasTcp = defaults.object(forKey: allowTcpKey) != nil
        let hasHttp = defaults.object(forKey: allowHttpKey) != nil
        let hasExternal = defaults.object(forKey: allowExternalSecurityLevelKey) != nil
        let hasXpc = defaults.object(forKey: allowXpcKey) != nil
        let hasPayload = defaults.object(forKey: maxPayloadSizeKey) != nil
        let hasTimeout = defaults.object(forKey: timeoutSecondsKey) != nil

        return ExternalServerSecuritySettings(
            allowTCP: hasTcp ? defaults.bool(forKey: allowTcpKey) : false,
            allowHTTP: hasHttp ? defaults.bool(forKey: allowHttpKey) : false,
            allowExternalSecurityLevel: hasExternal ? defaults.bool(forKey: allowExternalSecurityLevelKey) : false,
            allowXPC: hasXpc ? defaults.bool(forKey: allowXpcKey) : true,
            maxPayloadSize: hasPayload ? defaults.integer(forKey: maxPayloadSizeKey) : 1024 * 1024,
            timeoutSeconds: hasTimeout ? defaults.double(forKey: timeoutSecondsKey) : 30
        )
    }

    public func save(defaults: UserDefaults = .standard) {
        defaults.set(allowTCP, forKey: Self.allowTcpKey)
        defaults.set(allowHTTP, forKey: Self.allowHttpKey)
        defaults.set(allowExternalSecurityLevel, forKey: Self.allowExternalSecurityLevelKey)
        defaults.set(allowXPC, forKey: Self.allowXpcKey)
        defaults.set(maxPayloadSize, forKey: Self.maxPayloadSizeKey)
        defaults.set(timeoutSeconds, forKey: Self.timeoutSecondsKey)
    }

    func asServerConfig() -> OurinExternalServer.Config {
        let allowIncomingNetwork = !RuntimeSecurityCapabilities.isSandboxed()
            || RuntimeSecurityCapabilities.allowsIncomingNetworkServer()
        return OurinExternalServer.Config(
            securityLocalOnly: !allowExternalSecurityLevel,
            maxPayloadSize: maxPayloadSize,
            timeout: timeoutSeconds,
            enableTCP: allowTCP && allowIncomingNetwork,
            enableHTTP: allowHTTP && allowIncomingNetwork,
            enableXPC: allowXPC
        )
    }
}
