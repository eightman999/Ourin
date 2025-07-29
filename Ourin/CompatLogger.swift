import os.log

struct CompatLogger {
    private let subsystem: String
    private let category: String
    private let oslog: OSLog
    private var modern: Any?

    init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
        self.oslog = OSLog(subsystem: subsystem, category: category)
        if #available(macOS 11.0, *) {
            self.modern = Logger(subsystem: subsystem, category: category)
        } else {
            self.modern = nil
        }
    }

    func info(_ message: String) {
        if #available(macOS 11.0, *), let log = modern as? Logger {
            log.info("\(message)")
        } else {
            os_log("%{public}@", log: oslog, type: .info, message)
        }
    }

    func debug(_ message: String) {
        if #available(macOS 11.0, *), let log = modern as? Logger {
            log.debug("\(message)")
        } else {
            os_log("%{public}@", log: oslog, type: .debug, message)
        }
    }

    func warning(_ message: String) {
        if #available(macOS 11.0, *), let log = modern as? Logger {
            log.warning("\(message)")
        } else {
            os_log("%{public}@", log: oslog, type: .error, message)
        }
    }

    func fault(_ message: String) {
        if #available(macOS 11.0, *), let log = modern as? Logger {
            log.fault("\(message)")
        } else {
            os_log("%{public}@", log: oslog, type: .fault, message)
        }
    }
}
