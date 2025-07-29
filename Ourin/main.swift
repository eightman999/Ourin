import AppKit
import SwiftUI

if #available(macOS 11.0, *) {
    OurinApp.main()
} else {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    app.run()
}
