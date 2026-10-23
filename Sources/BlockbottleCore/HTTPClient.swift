import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPClient: Sendable {
    func data(from url: URL) async throws -> Data
    /// Downloads to a temporary file and returns its location.
    func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}

public enum HTTPError: Error, Equatable {
    case badStatus(Int)
}

public final class URLSessionHTTPClient: NSObject, HTTPClient, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [Int: (progress: @Sendable (Double) -> Void, cont: CheckedContinuation<URL, Error>)] = [:]
    private var session: URLSession!

    public override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    private func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("Blockbottle", forHTTPHeaderField: "User-Agent")
        if url.host == "api.github.com" { r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        return r
    }

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: request(url))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.badStatus(http.statusCode)
        }
        return data
    }

    public func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let task = session.downloadTask(with: request(url))
            lock.lock(); handlers[task.taskIdentifier] = (progress, cont); lock.unlock()
            task.resume()
        }
    }

    private func take(_ id: Int) -> (progress: @Sendable (Double) -> Void, cont: CheckedContinuation<URL, Error>)? {
        lock.lock(); defer { lock.unlock() }
        return handlers.removeValue(forKey: id)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        lock.lock(); let h = handlers[downloadTask.taskIdentifier]; lock.unlock()
        h?.progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let h = take(downloadTask.taskIdentifier) else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            h.cont.resume(throwing: HTTPError.badStatus(http.statusCode))
            return
        }
        // The system deletes `location` when this returns, so move it first.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("bb-dl-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            h.cont.resume(returning: kept)
        } catch {
            h.cont.resume(throwing: error)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, let h = take(task.taskIdentifier) { h.cont.resume(throwing: error) }
    }
}
