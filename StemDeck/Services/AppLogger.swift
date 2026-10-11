// Services/AppLogger.swift
// Centralized in-memory log for debugging.
// Captures: backend stdout, API calls, errors, backend start/stop.

import Foundation
import Combine

struct LogEntry: Identifiable {
    let id      = UUID()
    let date:   Date
    let level:  LogLevel
    let message: String

    enum LogLevel: String {
        case info  = "ℹ️"
        case ok    = "✅"
        case warn  = "⚠️"
        case error = "❌"
        case debug = "🔍"
    }

    var formatted: String {
        let ts = DateFormatter.logFormatter.string(from: date)
        return "[\(ts)] \(level.rawValue) \(message)"
    }
}

private extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

final class AppLogger: ObservableObject {

    static let shared = AppLogger()

    @Published private(set) var entries: [LogEntry] = []
    private let maxEntries = 500
    private let queue = DispatchQueue(label: "com.stemdeck.logger")

    func log(_ message: String, level: LogEntry.LogLevel = .info) {
        let entry = LogEntry(date: Date(), level: level, message: message)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
        // Also print to Xcode console
        print(entry.formatted)
    }

    func clear() {
        DispatchQueue.main.async { self.entries.removeAll() }
    }

    var fullText: String {
        entries.map(\.formatted).joined(separator: "\n")
    }
}

// MARK: - Convenience global
func appLog(_ msg: String, level: LogEntry.LogLevel = .info) {
    AppLogger.shared.log(msg, level: level)
}
