// Views/LogsView.swift
// In-app log viewer for debugging.
import SwiftUI

struct LogsView: View {
    @ObservedObject private var logger = AppLogger.shared
    @Environment(\.dismiss) var dismiss
    @State private var filterText  = ""
    @State private var autoScroll  = true
    @State private var selectedLevel: LogEntry.LogLevel? = nil

    private var filtered: [LogEntry] {
        logger.entries.filter { entry in
            let levelOK = selectedLevel == nil || entry.level == selectedLevel
            let textOK  = filterText.isEmpty ||
                entry.message.localizedCaseInsensitiveContains(filterText)
            return levelOK && textOK
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 10) {
                Image(systemName: "terminal").foregroundColor(.purple)
                Text("Logs").font(.headline.weight(.semibold)).foregroundColor(.white)
                Spacer()

                // Level filter
                HStack(spacing: 4) {
                    ForEach([LogEntry.LogLevel.error, .warn, .ok, .info, .debug], id: \.rawValue) { lvl in
                        Button(lvl.rawValue) {
                            selectedLevel = (selectedLevel == lvl) ? nil : lvl
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(selectedLevel == lvl
                                    ? Color.purple.opacity(0.35)
                                    : Color.white.opacity(0.07))
                        .cornerRadius(5)
                        .buttonStyle(.plain)
                    }
                }

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.caption).foregroundColor(Color(white: 0.60))

                Button { logger.clear() } label: {
                    Label("Vider", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain).foregroundColor(.red.opacity(0.8))

                Button {
                    let text = logger.fullText
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copier", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain).foregroundColor(Color(white: 0.60))

                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain).foregroundColor(Color(white: 0.50))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color("BackgroundSecondary"))

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(Color(white: 0.45))
                TextField("Filtrer…", text: $filterText)
                    .textFieldStyle(.plain).font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                if !filterText.isEmpty {
                    Button { filterText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(white: 0.45))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.black.opacity(0.3))

            Divider().background(Color.white.opacity(0.08))

            // Log list
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.badge.checkmark")
                        .font(.largeTitle).foregroundColor(Color(white: 0.30))
                    Text("Aucun log")
                        .font(.callout).foregroundColor(Color(white: 0.35))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(filtered) { entry in
                                LogRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                    }
                    .background(Color.black.opacity(0.4))
                    .onChange(of: filtered.count) { _ in
                        if autoScroll, let last = filtered.last {
                            withAnimation(.none) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            // Status bar
            HStack {
                Text("\(filtered.count) entrée(s)")
                    .font(.caption2).foregroundColor(Color(white: 0.40))
                Spacer()
                if let last = logger.entries.last {
                    Text("Dernier : \(last.date.formatted(date: .omitted, time: .standard))")
                        .font(.caption2).foregroundColor(Color(white: 0.35))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Color("BackgroundSecondary"))
        }
        .background(Color(red: 0.06, green: 0.07, blue: 0.09))
        .frame(minWidth: 700, minHeight: 440)
    }
}

// MARK: - Log row
private struct LogRow: View {
    let entry: LogEntry

    private var rowColor: Color {
        switch entry.level {
        case .error: return Color.red.opacity(0.10)
        case .warn:  return Color.orange.opacity(0.07)
        default:     return Color.clear
        }
    }

    private var textColor: Color {
        switch entry.level {
        case .error: return Color(red: 1, green: 0.45, blue: 0.45)
        case .warn:  return Color(red: 1, green: 0.75, blue: 0.35)
        case .ok:    return Color(red: 0.45, green: 0.95, blue: 0.55)
        case .debug: return Color(white: 0.50)
        default:     return Color(white: 0.78)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Timestamp
            Text(DateFormatter.logFormatter.string(from: entry.date))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(white: 0.38))
                .frame(width: 76, alignment: .leading)
            // Level icon
            Text(entry.level.rawValue)
                .font(.system(size: 10))
                .frame(width: 18)
            // Message
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(textColor)
                .lineLimit(6)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(rowColor)
        .cornerRadius(3)
    }
}

private extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()
}
