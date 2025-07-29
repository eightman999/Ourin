import os.log

#if swift(>=5.5)
@available(macOS 11.0, *)
private typealias ModernLogger = Logger
#endif

struct CompatLogger {
    private let subsystem: String
    private let category: String
    #if swift(>=5.5)
    @available(macOS 11.0, *)
    private var logger: ModernLogger
    private var oslog: OSLog?
    #else
    private var logger: OSLog
    #endif

    init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
        if #available(macOS 11.0, *) {
            #if swift(>=5.5)
            self.logger = ModernLogger(subsystem: subsystem, category: category)
            self.oslog = nil
            #endif
        } else {
            #if swift(>=5.5)
            self.logger = Logger(subsystem: subsystem, category: category) // will not be used
            self.oslog = OSLog(subsystem: subsystem, category: category)
            #else
            self.logger = OSLog(subsystem: subsystem, category: category)
            #endif
        }
    }

    func info(_ message: String) {
        if #available(macOS 11.0, *) {
            #if swift(>=5.5)
            logger.info("\(message, privacy: .public)")
            #endif
        } else {
            #if swift(>=5.5)
            os_log("%{public}@", log: oslog ?? .default, type: .info, message)
            #else
            os_log("%{public}@", log: logger, type: .info, message)
            #endif
        }
    }

    func debug(_ message: String) {
        if #available(macOS 11.0, *) {
            #if swift(>=5.5)
            logger.debug("\(message, privacy: .public)")
            #endif
        } else {
            #if swift(>=5.5)
            os_log("%{public}@", log: oslog ?? .default, type: .debug, message)
            #else
            os_log("%{public}@", log: logger, type: .debug, message)
            #endif
        }
    }

    func warning(_ message: String) {
        if #available(macOS 11.0, *) {
            #if swift(>=5.5)
            logger.warning("\(message, privacy: .public)")
            #endif
        } else {
            #if swift(>=5.5)
            os_log("%{public}@", log: oslog ?? .default, type: .error, message)
            #else
            os_log("%{public}@", log: logger, type: .error, message)
            #endif
        }
    }

    func fault(_ message: String) {
        if #available(macOS 11.0, *) {
            #if swift(>=5.5)
            logger.fault("\(message, privacy: .public)")
            #endif
        } else {
            #if swift(>=5.5)
            os_log("%{public}@", log: oslog ?? .default, type: .fault, message)
            #else
            os_log("%{public}@", log: logger, type: .fault, message)
            #endif
        }
    }
}
