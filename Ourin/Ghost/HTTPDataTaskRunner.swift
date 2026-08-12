import Foundation

/// URLSession の受信データを、完了まで保持したまま逐次通知する実行器。
///
/// `URLSession.shared.dataTask(with:completionHandler:)` は完了時にしか
/// データを返さないため、HTTP の progress/streaming イベントには使えない。
/// このクラスは delegate の寿命も自分で保持し、受信チャンクと累積データを
/// 同時に呼び出し側へ渡す。
final class HTTPDataTaskRunner: NSObject, URLSessionDataDelegate {
    typealias DataHandler = (_ chunk: Data, _ accumulated: Data, _ response: HTTPURLResponse?) -> Void
    typealias CompletionHandler = (_ data: Data, _ response: HTTPURLResponse?, _ metrics: URLSessionTaskMetrics?, _ error: Error?) -> Void

    private let request: URLRequest
    private let onData: DataHandler
    private let onComplete: CompletionHandler
    private var session: URLSession?
    private(set) var task: URLSessionDataTask?
    private var receivedData = Data()
    private var response: HTTPURLResponse?
    private var metrics: URLSessionTaskMetrics?
    private var didComplete = false

    init(request: URLRequest, onData: @escaping DataHandler, onComplete: @escaping CompletionHandler) {
        self.request = request
        self.onData = onData
        self.onComplete = onComplete
        super.init()
    }

    func start() {
        guard session == nil else { return }
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response as? HTTPURLResponse
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
        onData(data, receivedData, response)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        self.metrics = metrics
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !didComplete else { return }
        didComplete = true
        let finalResponse = response ?? task.response as? HTTPURLResponse
        onComplete(receivedData, finalResponse, metrics, error)
        session.finishTasksAndInvalidate()
        self.session = nil
    }
}
