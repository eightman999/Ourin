import Testing
@testable import Ourin

struct NarInstallTests {
    @Test
    func parseInstallTxt() throws {
        let raw = "type,ghost\ndirectory,foo" 
        let manifest = try InstallTxtParser.parse(raw)
        #expect(manifest.type == "ghost")
        #expect(manifest.directory == "foo")
    }
}
