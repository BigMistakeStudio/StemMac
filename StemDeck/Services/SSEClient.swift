// Services/SSEClient.swift
// Client Server-Sent Events pour GET /api/jobs/{id}/events.
// Chaque événement est un instantané complet du job (Job.to_state() côté backend).

import Foundation

// MARK: - Événement
struct SSEJobEvent {
    let job:      StemJob
    var status:   JobStatus { job.status }
    var phase:    String    { job.status.localizedLabel }
    var progress: Double    { job.progress }
    var message:  String    { job.stage.isEmpty ? job.status.localizedLabel : job.stage }
    var error:    String?   { job.errorMessage }
}

// MARK: - Client
final class SSEClient: NSObject {

    private let url: URL
    private var task: URLSessionDataTask?
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 60 * 60    // flux long (keepalive toutes les ~15 s)
        cfg.timeoutIntervalForResource = 4 * 60 * 60
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()
    private var buffer = ""
    private var finished = false
    var onEvent:    ((SSEJobEvent) -> Void)?
    var onError:    ((Error) -> Void)?
    var onComplete: (() -> Void)?

    init(url: URL) { self.url = url }

    func start() {
        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        task = session.dataTask(with: req)
        task?.resume()
    }

    func stop() {
        task?.cancel()
        task = nil
        session.invalidateAndCancel()
    }

    // MARK: Parsing
    private func parseSSE(_ text: String) {
        buffer += text.replacingOccurrences(of: "\r\n", with: "\n")
        while let range = buffer.range(of: "\n\n") {
            let block = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            handleBlock(block)
        }
    }

    private func handleBlock(_ block: String) {
        let dataLines = block.components(separatedBy: "\n")
            .filter { $0.hasPrefix("data:") }
            .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        guard !dataLines.isEmpty,                       // ": keepalive" → ignoré
              let data = dataLines.joined(separator: "\n").data(using: .utf8) else { return }
        guard let job = try? JSONDecoder().decode(StemJob.self, from: data) else {
            print("[SSE] événement illisible: \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")
            return
        }
        let event = SSEJobEvent(job: job)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.finished else { return }
            self.onEvent?(event)
            if job.status.isFinished {
                self.finished = true
                self.onComplete?()
                self.stop()
            }
        }
    }
}

// MARK: - URLSessionDataDelegate
extension SSEClient: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let text = String(data: data, encoding: .utf8) { parseSSE(text) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.finished else { return }
            self.finished = true
            if let error, (error as NSError).code != NSURLErrorCancelled {
                self.onError?(error)
            }
            self.onComplete?()
        }
    }
}
