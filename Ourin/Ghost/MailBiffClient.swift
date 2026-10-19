import Foundation
import AppKit

struct MailBiffResult: Equatable {
    let unreadCount: Int
    let unreadBytes: Int
    let senderAndSubject: String
    let topResult: String
}

enum MailBiffClientError: Error, Equatable, CustomStringConvertible {
    case unavailable(String)
    case invalidResult

    var description: String {
        switch self {
        case .unavailable(let message): return message
        case .invalidResult: return "Mail のBIFF結果を解釈できません"
        }
    }
}

/// macOS Mail の未読メールを Apple Event 経由で取得する。
/// Mail が起動しているかどうかではなく、実際の未読件数を取得できた場合だけ成功とする。
final class MailBiffClient {
    func query(account: String?, completion: @escaping (Result<MailBiffResult, Error>) -> Void) {
        let script = Self.appleScript(account: account)
        DispatchQueue.global(qos: .utility).async {
            guard let appleScript = NSAppleScript(source: script) else {
                completion(.failure(MailBiffClientError.unavailable("Mail AppleScript を作成できません")))
                return
            }

            var errorInfo: NSDictionary?
            let descriptor = appleScript.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = (errorInfo[NSAppleScript.errorMessage] as? String)
                    ?? "Mail へのアクセスが拒否されました"
                completion(.failure(MailBiffClientError.unavailable(message)))
                return
            }

            guard let result = Self.parse(descriptor) else {
                completion(.failure(MailBiffClientError.invalidResult))
                return
            }
            completion(.success(result))
        }
    }

    static func appleScript(account: String?) -> String {
        let escapedAccount = (account ?? "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Mail"
            set accountName to "\(escapedAccount)"
            set unreadCount to 0
            set unreadBytes to 0
            set senderAndSubject to ""
            set topResult to ""
            repeat with theAccount in accounts
                if accountName is "" or (name of theAccount as text) is accountName then
                    repeat with theMailbox in (mailboxes of theAccount)
                        try
                            repeat with theMessage in (messages of theMailbox whose read status is false)
                                set unreadCount to unreadCount + 1
                                try
                                    set unreadBytes to unreadBytes + (size of theMessage as integer)
                                end try
                                try
                                    set senderAndSubject to senderAndSubject & (sender of theMessage as text) & character id 1 & (subject of theMessage as text) & character id 1
                                end try
                                try
                                    set topResult to topResult & (all headers of theMessage as text) & character id 2
                                end try
                            end repeat
                        end try
                    end repeat
                end if
            end repeat
            return {unreadCount, unreadBytes, senderAndSubject, topResult}
        end tell
        """
    }

    /// AppleScript の list descriptor を純粋な値へ変換する。
    static func parse(_ descriptor: NSAppleEventDescriptor) -> MailBiffResult? {
        guard descriptor.numberOfItems >= 2,
              let countDescriptor = descriptor.atIndex(1),
              let bytesDescriptor = descriptor.atIndex(2) else {
            return nil
        }
        let unreadCount = max(0, Int(countDescriptor.int32Value))
        let unreadBytes = max(0, Int(bytesDescriptor.int32Value))
        let senderAndSubject = descriptor.atIndex(3)?.stringValue ?? ""
        let topResult = descriptor.atIndex(4)?.stringValue ?? ""
        return MailBiffResult(
            unreadCount: unreadCount,
            unreadBytes: unreadBytes,
            senderAndSubject: senderAndSubject,
            topResult: topResult
        )
    }
}
