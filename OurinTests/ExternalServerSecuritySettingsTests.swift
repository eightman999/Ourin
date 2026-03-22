import Foundation
import Testing
@testable import Ourin

struct ExternalServerSecuritySettingsTests {
    @Test
    func defaultsAreSecure() throws {
        let suiteName = "ExternalServerSecuritySettingsTests.defaults.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let settings = ExternalServerSecuritySettings.load(defaults: suite)
        #expect(settings.allowTCP == false)
        #expect(settings.allowHTTP == false)
        #expect(settings.allowExternalSecurityLevel == false)
        #expect(settings.allowXPC == true)
    }

    @Test
    func saveAndLoadRoundTrip() throws {
        let suiteName = "ExternalServerSecuritySettingsTests.roundtrip.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let saved = ExternalServerSecuritySettings(
            allowTCP: true,
            allowHTTP: true,
            allowExternalSecurityLevel: true,
            allowXPC: false,
            maxPayloadSize: 256 * 1024,
            timeoutSeconds: 12
        )
        saved.save(defaults: suite)
        let loaded = ExternalServerSecuritySettings.load(defaults: suite)
        #expect(loaded == saved)
    }

    @Test
    func mappingToServerConfigIsConsistent() throws {
        let settings = ExternalServerSecuritySettings(
            allowTCP: true,
            allowHTTP: false,
            allowExternalSecurityLevel: false,
            allowXPC: true,
            maxPayloadSize: 200000,
            timeoutSeconds: 9
        )
        let config = settings.asServerConfig()
        #expect(config.enableTCP == true)
        #expect(config.enableHTTP == false)
        #expect(config.enableXPC == true)
        #expect(config.securityLocalOnly == true)
        #expect(config.maxPayloadSize == 200000)
        #expect(config.timeout == 9)
    }

    @Test
    func sandboxDisablesNetworkListenersWithoutEntitlement() throws {
        let originalSandbox = RuntimeSecurityCapabilities.sandboxDetector
        let originalNetwork = RuntimeSecurityCapabilities.incomingNetworkEntitlementDetector
        defer {
            RuntimeSecurityCapabilities.sandboxDetector = originalSandbox
            RuntimeSecurityCapabilities.incomingNetworkEntitlementDetector = originalNetwork
        }
        RuntimeSecurityCapabilities.sandboxDetector = { true }
        RuntimeSecurityCapabilities.incomingNetworkEntitlementDetector = { false }

        let settings = ExternalServerSecuritySettings(
            allowTCP: true,
            allowHTTP: true,
            allowExternalSecurityLevel: true,
            allowXPC: true,
            maxPayloadSize: 200000,
            timeoutSeconds: 9
        )
        let config = settings.asServerConfig()
        #expect(config.enableTCP == false)
        #expect(config.enableHTTP == false)
        #expect(config.enableXPC == true)
    }

    @Test
    func sandboxKeepsNetworkWhenServerEntitlementPresent() throws {
        let originalSandbox = RuntimeSecurityCapabilities.sandboxDetector
        let originalNetwork = RuntimeSecurityCapabilities.incomingNetworkEntitlementDetector
        defer {
            RuntimeSecurityCapabilities.sandboxDetector = originalSandbox
            RuntimeSecurityCapabilities.incomingNetworkEntitlementDetector = originalNetwork
        }
        RuntimeSecurityCapabilities.sandboxDetector = { true }
        RuntimeSecurityCapabilities.incomingNetworkEntitlementDetector = { true }

        let settings = ExternalServerSecuritySettings(
            allowTCP: true,
            allowHTTP: true,
            allowExternalSecurityLevel: false,
            allowXPC: true,
            maxPayloadSize: 200000,
            timeoutSeconds: 9
        )
        let config = settings.asServerConfig()
        #expect(config.enableTCP == true)
        #expect(config.enableHTTP == true)
        #expect(config.securityLocalOnly == true)
    }
}
