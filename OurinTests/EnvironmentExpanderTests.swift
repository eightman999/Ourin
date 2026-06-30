import Testing
@testable import Ourin

@Suite(.serialized)
struct EnvironmentExpanderTests {
    @Test
    func lastGhostNameExpandsFromStaticContext() {
        let mgr = PropertyManager()
        let expander = EnvironmentExpander(propertyManager: mgr)
        EnvironmentExpander.lastInstalledGhostName = "TestGhost"
        EnvironmentExpander.lastInstalledObjectName = "TestObject"
        defer {
            EnvironmentExpander.lastInstalledGhostName = nil
            EnvironmentExpander.lastInstalledObjectName = nil
        }
        #expect(expander.expand(text: "installed: %lastghostname") == "installed: TestGhost")
        #expect(expander.expand(text: "object: %lastobjectname") == "object: TestObject")
    }

    @Test
    func lastGhostNameEmptyWhenUnset() {
        let mgr = PropertyManager()
        let expander = EnvironmentExpander(propertyManager: mgr)
        EnvironmentExpander.lastInstalledGhostName = nil
        #expect(expander.expand(text: "%lastghostname") == "")
    }
}
