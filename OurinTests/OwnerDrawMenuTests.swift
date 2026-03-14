@testable import Ourin
import XCTest

class OwnerDrawMenuTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BridgeToSHIORI.reset()
    }
    
    override func tearDown() {
        super.tearDown()
        BridgeToSHIORI.reset()
    }
    
    func testMenuConfigParsing() {
        BridgeToSHIORI.setResource("menu.background.bitmap.filename", value: "/tmp/bg.png")
        BridgeToSHIORI.setResource("menu.foreground.bitmap.filename", value: "/tmp/fg.png")
        BridgeToSHIORI.setResource("menu.sidebar.bitmap.filename", value: "/tmp/sidebar.png")
        BridgeToSHIORI.setResource("menu.background.color.r", value: "255")
        BridgeToSHIORI.setResource("menu.background.color.g", value: "0")
        BridgeToSHIORI.setResource("menu.background.color.b", value: "0")
        BridgeToSHIORI.setResource("menu.foreground.color.r", value: "0")
        BridgeToSHIORI.setResource("menu.foreground.color.g", value: "0")
        BridgeToSHIORI.setResource("menu.foreground.color.b", value: "255")
        
        let config = ResourceBridge.shared.ownerDrawMenuConfig()
        
        XCTAssertEqual(config.backgroundColor.redComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(config.foregroundColor.blueComponent, 1.0, accuracy: 0.01)
    }
    
    func testMenuItemCreation() {
        BridgeToSHIORI.setResource("inforootbutton.caption", value: "Ghost Info")
        BridgeToSHIORI.setResource("inforootbutton.visible", value: "1")
        
        let items = ResourceBridge.shared.menuItems()
        
        XCTAssertTrue(items.contains { $0.caption == "Ghost Info" })
    }
    
    func testShortcutParsing() {
        BridgeToSHIORI.setResource("quitbutton.caption", value: "Exit (&Q)")
        
        let items = ResourceBridge.shared.menuItems()
        
        let quitItem = items.first { $0.caption == "Exit Q" }
        XCTAssertNotNil(quitItem)
        XCTAssertEqual(quitItem?.shortcut, "Q")
    }
    
    func testVisibleProperty() {
        BridgeToSHIORI.setResource("vanishbutton.caption", value: "Vanish")
        BridgeToSHIORI.setResource("vanishbutton.visible", value: "0")
        
        let items = ResourceBridge.shared.menuItems()
        
        XCTAssertFalse(items.contains { $0.caption == "Vanish" })
    }
    
    func testMenuItemWithShortcut() {
        BridgeToSHIORI.setResource("configurationbutton.caption", value: "Settings (&S)")
        BridgeToSHIORI.setResource("configurationbutton.visible", value: "1")
        
        let items = ResourceBridge.shared.menuItems()
        
        let settingsItem = items.first { $0.caption == "Settings S" }
        XCTAssertNotNil(settingsItem)
        XCTAssertEqual(settingsItem?.shortcut, "S")
    }
    
    func testMenuAlignment() {
        BridgeToSHIORI.setResource("menu.background.alignment", value: "lefttop")
        BridgeToSHIORI.setResource("menu.foreground.alignment", value: "rightbottom")
        BridgeToSHIORI.setResource("menu.sidebar.alignment", value: "leftbottom")
        
        let config = ResourceBridge.shared.ownerDrawMenuConfig()
        
        XCTAssertEqual(config.backgroundAlignment, .leftTop)
        XCTAssertEqual(config.foregroundAlignment, .rightBottom)
        XCTAssertEqual(config.sidebarAlignment, .leftBottom)
    }
    
    func testSeparatorColor() {
        BridgeToSHIORI.setResource("menu.separator.color.r", value: "128")
        BridgeToSHIORI.setResource("menu.separator.color.g", value: "128")
        BridgeToSHIORI.setResource("menu.separator.color.b", value: "128")
        
        let config = ResourceBridge.shared.ownerDrawMenuConfig()
        
        XCTAssertEqual(config.separatorColor.redComponent, 0.5, accuracy: 0.01)
        XCTAssertEqual(config.separatorColor.greenComponent, 0.5, accuracy: 0.01)
        XCTAssertEqual(config.separatorColor.blueComponent, 0.5, accuracy: 0.01)
    }
    
    func testDisabledColor() {
        BridgeToSHIORI.setResource("menu.disable.font.color.r", value: "64")
        BridgeToSHIORI.setResource("menu.disable.font.color.g", value: "64")
        BridgeToSHIORI.setResource("menu.disable.font.color.b", value: "64")
        
        let config = ResourceBridge.shared.ownerDrawMenuConfig()
        
        XCTAssertEqual(config.disabledColor.redComponent, 64.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(config.disabledColor.greenComponent, 64.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(config.disabledColor.blueComponent, 64.0 / 255.0, accuracy: 0.01)
    }
}
