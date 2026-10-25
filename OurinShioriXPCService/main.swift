import Foundation
import Darwin

@objc protocol OurinShioriXPC {
    func load(_ bundlePath: String, loadDirectory: String, shiori2Compatibility: Bool, withReply reply: @escaping (Bool, String?) -> Void)
    func ping(withReply reply: @escaping () -> Void)
    func load(_ bundlePath: String, withReply reply: @escaping (Bool, String?) -> Void)
    func execute(_ request: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func unload(withReply reply: @escaping () -> Void)
    func load(_ bundlePath: String, shiori2Compatibility: Bool, withReply reply: @escaping (Bool, String?) -> Void)
    func execute(_ request: Data, bundlePath: String, shiori2Compatibility: Bool, withReply reply: @escaping (Data?, String?) -> Void)
    func unload(_ bundlePath: String, shiori2Compatibility: Bool, withReply reply: @escaping () -> Void)
    func execute(_ request: Data, bundlePath: String, withReply reply: @escaping (Data?, String?) -> Void)
}

private enum WireEncoding {
    static func charset(in data: Data, default defaultValue: String = "UTF-8") -> String {
        let header = String(data: data.prefix(8192), encoding: .isoLatin1) ?? ""
        for line in header.components(separatedBy: .newlines) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            if line[..<separator].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Charset") == .orderedSame {
                return line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return defaultValue
    }

    static func encoding(for charset: String) -> String.Encoding {
        switch charset.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "shift_jis", "shiftjis", "windows_31j", "cp932", "ms932", "sjis", "x_sjis": return .shiftJIS
        case "euc_jp", "eucjp": return .japaneseEUC
        case "iso_2022_jp", "jis": return .iso2022JP
        default: return .utf8
        }
    }
}

private final class ShioriSession: NSObject, OurinShioriXPC {
    private let queue = DispatchQueue(label: "jp.ourin.shiori.session")
    private var module: NativeShioriModule?
    private let watchdogTimeout: TimeInterval = 5

    func ping(withReply reply: @escaping () -> Void) { reply() }

    func load(_ bundlePath: String, withReply reply: @escaping (Bool, String?) -> Void) {
        load(bundlePath, loadDirectory: URL(fileURLWithPath: bundlePath).deletingLastPathComponent().path, shiori2Compatibility: true, withReply: reply)
    }

    func load(_ bundlePath: String, loadDirectory: String, shiori2Compatibility: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        runWithWatchdog {
            self.module?.unload()
            self.module = nil
            do {
                let url = URL(fileURLWithPath: bundlePath).standardizedFileURL
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw NSError(domain: "OurinShioriXPC", code: 5, userInfo: [NSLocalizedDescriptionKey: "Module not found: \(url.path)"])
                }
                self.module = try NativeShioriModule(url: url, loadDirectory: URL(fileURLWithPath: loadDirectory))
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func load(_ bundlePath: String, shiori2Compatibility: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        // SHIORI/2.x変換はクライアント側adapterが担当する。サービスは接続単位のraw moduleを保持する。
        load(bundlePath, withReply: reply)
    }

    func execute(_ request: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        runWithWatchdog {
            guard let module = self.module else { reply(nil, "SHIORI module is not loaded"); return }
            guard let response = module.request(request) else { reply(nil, "SHIORI request failed"); return }
            reply(response, nil)
        }
    }

    func unload(withReply reply: @escaping () -> Void) {
        runWithWatchdog {
            self.module?.unload()
            self.module = nil
            reply()
        }
    }

    func execute(_ request: Data, bundlePath: String, shiori2Compatibility: Bool, withReply reply: @escaping (Data?, String?) -> Void) {
        // XpcBackendは接続確立時に同じbundlePathをload済み。
        execute(request, withReply: reply)
    }

    func unload(_ bundlePath: String, shiori2Compatibility: Bool, withReply reply: @escaping () -> Void) {
        unload(withReply: reply)
    }

    func execute(_ request: Data, bundlePath: String, withReply reply: @escaping (Data?, String?) -> Void) {
        load(bundlePath) { ok, error in
            guard ok else { reply(nil, error); return }
            self.execute(request, withReply: reply)
        }
    }

    func invalidate() {
        queue.async {
            self.module?.unload()
            self.module = nil
        }
    }

    private func runWithWatchdog(_ operation: @escaping () -> Void) {
        let state = WatchdogState()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + watchdogTimeout) {
            if state.markTimedOutIfRunning() { _exit(124) }
        }
        queue.async {
            operation()
            state.markFinished()
        }
    }
}

private final class WatchdogState {
    private let lock = NSLock()
    private var running = true

    func markFinished() {
        lock.lock(); running = false; lock.unlock()
    }

    func markTimedOutIfRunning() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard running else { return false }
        running = false
        return true
    }
}

private final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let session = ShioriSession()
        connection.exportedInterface = NSXPCInterface(with: OurinShioriXPC.self)
        connection.exportedObject = session
        connection.invalidationHandler = { session.invalidate() }
        connection.interruptionHandler = { session.invalidate() }
        connection.resume()
        return true
    }
}

private let delegate = ServiceDelegate()
private let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
