import Foundation

enum Log {
    static var verbose: Bool {
        // Temporarily enabled for debugging backslash issue
        return true
        // Off by default; enable by setting defaults key "OurinVerboseLogging" = true
        // return UserDefaults.standard.bool(forKey: "OurinVerboseLogging")
    }

    static func info(_ message: String) {
        NSLog(message)
    }

    static func debug(_ message: String) {
        if verbose { NSLog(message) }
    }
}
