import Testing
@testable import Ourin

struct BalloonProgressTests {
    @Test func balloonNumberFieldsAreIndependentFromBooleanCompatibilityFlag() {
        let model = BalloonViewModel()
        #expect(model.balloonNumberVisible == false)
        model.balloonNumberFileName = "update.zip"
        model.balloonNumberCurrent = "3"
        model.balloonNumberMaximum = "10"
        model.balloonNumberVisible = true
        #expect(model.balloonNumberFileName == "update.zip")
        #expect(model.balloonNumberCurrent == "3")
        #expect(model.balloonNumberMaximum == "10")
    }
}
