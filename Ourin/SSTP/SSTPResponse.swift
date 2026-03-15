import Foundation

public struct SSTPResponse: Equatable {
    public var version: String
    public var statusCode: Int
    public var statusMessage: String
    public var headers: [String: String]

    public init(
        version: String = "SSTP/1.4",
        statusCode: Int,
        statusMessage: String? = nil,
        headers: [String: String] = [:]
    ) {
        self.version = version
        self.statusCode = statusCode
        self.statusMessage = statusMessage ?? Self.defaultStatusMessage(for: statusCode)
        self.headers = headers
    }

    public mutating func setScript(_ script: String?) {
        if let script, !script.isEmpty {
            headers["Script"] = script
        } else {
            headers.removeValue(forKey: "Script")
        }
    }

    public mutating func setData(_ data: String?) {
        if let data, !data.isEmpty {
            headers["Data"] = data
        } else {
            headers.removeValue(forKey: "Data")
        }
    }

    public mutating func setPassThru(_ passThru: String?) {
        if let passThru, !passThru.isEmpty {
            headers["X-SSTP-PassThru"] = passThru
        } else {
            headers.removeValue(forKey: "X-SSTP-PassThru")
        }
    }

    public func toWireFormat() -> String {
        var lines = ["\(version) \(statusCode) \(statusMessage)"]
        for key in headerOutputOrder() {
            if let value = headers[key], !value.isEmpty {
                lines.append("\(key): \(value)")
            }
        }
        lines.append("")
        lines.append("")
        return lines.joined(separator: "\r\n")
    }

    public static func defaultStatusMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 204: return "No Content"
        case 210: return "Break"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 420: return "Refuse"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 503: return "Service Unavailable"
        case 505: return "HTTP Version Not Supported"
        case 512: return "Invisible"
        default: return "Status"
        }
    }

    private func headerOutputOrder() -> [String] {
        var order = ["Charset", "Sender", "Script", "Data", "X-SSTP-PassThru"]
        let others = headers.keys
            .filter { !order.contains($0) }
            .sorted()
        order.append(contentsOf: others)
        return order
    }
}

