import Foundation
import Network
import Darwin

/// SNTP 応答から得たサーバ時刻とローカル時刻の差。
struct SNTPMeasurement: Equatable {
    let server: String
    let serverDate: Date
    let localDate: Date
    let offset: TimeInterval

    var offsetMilliseconds: Int {
        Int((offset * 1_000).rounded())
    }
}

/// システム時計補正が拒否または失敗した理由。
enum SNTPClockAdjustmentError: Error, Equatable, CustomStringConvertible {
    case permissionDenied
    case systemFailure(Int32)

    var description: String {
        switch self {
        case .permissionDenied:
            return "システム時計を変更する権限がありません"
        case .systemFailure(let code):
            return "システム時計の変更に失敗しました (errno=\(code))"
        }
    }
}

/// SNTP で得た時刻を macOS のシステム時計へ反映する境界。
///
/// `settimeofday` はプロセスが持つ権限の範囲でのみ成功する。sudo 等の
/// 外部プロセスを起動して権限を迂回することはせず、OS の拒否をそのまま
/// 呼び出し元へ返して `OnSNTPFailure` へつなげる。
enum SNTPClockAdjuster {
    typealias Setter = (Date) -> Result<Void, SNTPClockAdjustmentError>

    static func adjust(to date: Date) -> Result<Void, SNTPClockAdjustmentError> {
        var value = timeValue(for: date)
        let returnCode = settimeofday(&value, nil)
        return result(for: returnCode, errorCode: returnCode == -1 ? Darwin.errno : 0)
    }

    /// `Date` を `settimeofday` 用の秒・マイクロ秒へ変換する。
    static func timeValue(for date: Date) -> timeval {
        var seconds = date.timeIntervalSince1970.rounded(.down)
        var microseconds = ((date.timeIntervalSince1970 - seconds) * 1_000_000).rounded()

        if microseconds >= 1_000_000 {
            seconds += 1
            microseconds -= 1_000_000
        } else if microseconds < 0 {
            seconds -= 1
            microseconds += 1_000_000
        }

        return timeval(tv_sec: Int(seconds), tv_usec: Int32(microseconds))
    }

    /// システムコール結果の分類を純粋関数として公開し、失敗経路をテスト可能にする。
    static func result(
        for returnCode: Int32,
        errorCode: Int32
    ) -> Result<Void, SNTPClockAdjustmentError> {
        guard returnCode == 0 else {
            if errorCode == EPERM || errorCode == EACCES {
                return .failure(.permissionDenied)
            }
            return .failure(.systemFailure(errorCode))
        }
        return .success(())
    }
}

enum SNTPClientError: Error, Equatable, CustomStringConvertible {
    case invalidPacket
    case invalidServerResponse
    case timeout
    case connection(String)

    var description: String {
        switch self {
        case .invalidPacket:
            return "SNTPパケットが不正です"
        case .invalidServerResponse:
            return "SNTPサーバ応答が不正です"
        case .timeout:
            return "SNTPサーバがタイムアウトしました"
        case .connection(let message):
            return message
        }
    }
}

/// NTP の 48 バイト要求・応答を扱う小さなプロトコル層。
enum SNTPPacket {
    static let unixEpochOffset: TimeInterval = 2_208_988_800
    static let packetLength = 48
    static let transmitTimestampOffset = 40

    /// NTP v4 client request を生成する。
    static func request(transmitDate: Date) -> Data {
        var bytes = [UInt8](repeating: 0, count: packetLength)
        // LI=0, VN=4, Mode=3 (client)
        bytes[0] = 0x23
        writeTimestamp(transmitDate, into: &bytes, at: transmitTimestampOffset)
        return Data(bytes)
    }

    /// NTP v4 server response を検証し、往復遅延を考慮した時刻差を返す。
    ///
    /// NTP の四時刻 (t1=送信, t2=サーバ受信, t3=サーバ送信, t4=受信)
    /// から offset = ((t2-t1)+(t3-t4))/2 を計算する。
    static func decode(
        _ data: Data,
        server: String,
        sentAt: Date,
        receivedAt: Date
    ) throws -> SNTPMeasurement {
        guard data.count >= packetLength else { throw SNTPClientError.invalidPacket }
        let bytes = [UInt8](data)
        let mode = bytes[0] & 0x07
        let version = (bytes[0] >> 3) & 0x07
        guard mode == 4, version >= 3 else { throw SNTPClientError.invalidServerResponse }
        guard bytes[1] != 0 else { throw SNTPClientError.invalidServerResponse }

        guard let originate = readTimestamp(from: bytes, at: 24),
              let serverReceive = readTimestamp(from: bytes, at: 32),
              let serverTransmit = readTimestamp(from: bytes, at: 40) else {
            throw SNTPClientError.invalidServerResponse
        }

        // 応答の originate timestamp は要求の transmit timestamp の写し。
        // 浮動小数点化による丸め誤差を許容して照合する。
        guard abs(originate.timeIntervalSince(sentAt)) < 0.002 else {
            throw SNTPClientError.invalidServerResponse
        }

        let offset = ((serverReceive.timeIntervalSince(sentAt)
                       + serverTransmit.timeIntervalSince(receivedAt)) / 2.0)
        let adjustedServerDate = receivedAt.addingTimeInterval(offset)
        return SNTPMeasurement(
            server: server,
            serverDate: adjustedServerDate,
            localDate: receivedAt,
            offset: offset
        )
    }

    private static func writeTimestamp(_ date: Date, into bytes: inout [UInt8], at offset: Int) {
        let seconds = max(0, date.timeIntervalSince1970 + unixEpochOffset)
        let wholeSeconds = UInt64(seconds)
        let fraction = UInt64((seconds - Double(wholeSeconds)) * 4_294_967_296.0)
        writeUInt32(UInt32(truncatingIfNeeded: wholeSeconds), into: &bytes, at: offset)
        writeUInt32(UInt32(truncatingIfNeeded: fraction), into: &bytes, at: offset + 4)
    }

    private static func readTimestamp(from bytes: [UInt8], at offset: Int) -> Date? {
        guard offset >= 0, offset + 8 <= bytes.count else { return nil }
        let seconds = UInt64(readUInt32(from: bytes, at: offset))
        let fraction = UInt64(readUInt32(from: bytes, at: offset + 4))
        guard seconds != 0 else { return nil }
        let unixSeconds = Double(seconds) - unixEpochOffset
        let fractionalSeconds = Double(fraction) / 4_294_967_296.0
        return Date(timeIntervalSince1970: unixSeconds + fractionalSeconds)
    }

    private static func writeUInt32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8((value >> 24) & 0xff)
        bytes[offset + 1] = UInt8((value >> 16) & 0xff)
        bytes[offset + 2] = UInt8((value >> 8) & 0xff)
        bytes[offset + 3] = UInt8(value & 0xff)
    }

    private static func readUInt32(from bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }
}

/// Network.framework を使った実 SNTP クライアント。
final class SNTPClient {
    private let queue = DispatchQueue(label: "jp.ourin.sntp", qos: .utility)

    func query(
        server: String = "pool.ntp.org",
        timeout: TimeInterval = 5,
        completion: @escaping (Result<SNTPMeasurement, Error>) -> Void
    ) {
        guard let port = NWEndpoint.Port(rawValue: 123) else {
            completion(.failure(SNTPClientError.connection("SNTPポートを作成できません")))
            return
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(server),
            port: port,
            using: .udp
        )
        let state = State(connection: connection, server: server, timeout: timeout, completion: completion)
        state.start(on: queue)
    }

    private final class State {
        let connection: NWConnection
        let server: String
        let timeout: TimeInterval
        let completion: (Result<SNTPMeasurement, Error>) -> Void
        var sentAt: Date?
        var finished = false

        init(
            connection: NWConnection,
            server: String,
            timeout: TimeInterval,
            completion: @escaping (Result<SNTPMeasurement, Error>) -> Void
        ) {
            self.connection = connection
            self.server = server
            self.timeout = timeout
            self.completion = completion
        }

        func start(on queue: DispatchQueue) {
            connection.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    sendRequest()
                case .failed(let error):
                    finish(.failure(SNTPClientError.connection(error.localizedDescription)))
                case .cancelled:
                    finish(.failure(SNTPClientError.connection("SNTP接続がキャンセルされました")))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + max(0.1, timeout)) { [self] in
                finish(.failure(SNTPClientError.timeout))
            }
        }

        private func sendRequest() {
            guard !finished else { return }
            let date = Date()
            sentAt = date
            let request = SNTPPacket.request(transmitDate: date)
            connection.send(content: request, completion: .contentProcessed { [self] error in
                guard let error else {
                    receiveResponse()
                    return
                }
                finish(.failure(SNTPClientError.connection(error.localizedDescription)))
            })
        }

        private func receiveResponse() {
            connection.receiveMessage { [self] data, _, _, error in
                guard !finished else { return }
                if let error {
                    finish(.failure(SNTPClientError.connection(error.localizedDescription)))
                    return
                }
                guard let data, let sentAt else {
                    finish(.failure(SNTPClientError.invalidPacket))
                    return
                }
                do {
                    let measurement = try SNTPPacket.decode(
                        data,
                        server: server,
                        sentAt: sentAt,
                        receivedAt: Date()
                    )
                    finish(.success(measurement))
                } catch {
                    finish(.failure(error))
                }
            }
        }

        private func finish(_ result: Result<SNTPMeasurement, Error>) {
            guard !finished else { return }
            finished = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            completion(result)
        }
    }
}
