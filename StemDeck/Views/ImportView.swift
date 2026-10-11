// Views/ImportView.swift — macOS 13 compatible, improved contrast
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var appState: AppState

    @State private var urlText        = ""
    @State private var droppedFile: URL? = nil
    @State private var isDragging     = false
    @State private var isProcessing   = false
    @State private var errorMessage: String? = nil
    @State private var showFilePicker = false
    @State private var showLogs       = false
    @State private var showConverter  = false

    private var canProcess: Bool {
        !isProcessing && (!urlText.isEmpty || droppedFile != nil) && appState.backendReady
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            Spacer()
            mainForm
            Spacer()
        }
        .background(Color("BackgroundPrimary"))
        .onChange(of: droppedFile) { url in
            if url != nil { urlText = "" }
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result {
                droppedFile = url; urlText = ""
            }
        }
        .sheet(isPresented: $showLogs) { LogsView() }
        .sheet(isPresented: $showConverter) { ConverterView() }
    }

    // MARK: - Nav bar
    private var navBar: some View {
        HStack(spacing: 12) {
            // Logo
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic")
                    .font(.title3).foregroundStyle(.purple.gradient)
                Text("StemMac")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
            }
            Spacer()

            // Backend status pill
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.backendReady ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(appState.backendReady ? "Backend prêt" : "Démarrage…")
                    .font(.caption)
                    .foregroundColor(appState.backendReady ? Color(white: 0.75) : .orange)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .cornerRadius(20)

            // Library
            Button { appState.screen = .library } label: {
                Image(systemName: "books.vertical.fill")
                    .foregroundColor(Color(white: 0.65))
            }.buttonStyle(.plain)

            // Converter
            Button { showConverter = true } label: {
                Image(systemName: "arrow.triangle.2.circlepath.circle")
                    .foregroundColor(Color(white: 0.65))
            }
            .buttonStyle(.plain)
            .help("Convertisseur audio (M4A → MP3…)")

            // Logs
            Button { showLogs = true } label: {
                Image(systemName: "terminal")
                    .foregroundColor(Color(white: 0.65))
            }.buttonStyle(.plain)

            // Settings
            Button { appState.showSettings = true } label: {
                Image(systemName: "gear")
                    .foregroundColor(Color(white: 0.65))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Color("BackgroundSecondary"))
    }

    // MARK: - Main form
    private var mainForm: some View {
        VStack(spacing: 32) {

            // Drop zone
            DropZone(droppedFile: $droppedFile, isDragging: $isDragging)
                .frame(maxWidth: 540, minHeight: 150)

            // Divider
            HStack {
                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
                Text("ou")
                    .font(.caption).foregroundColor(.white.opacity(0.80))
                    .padding(.horizontal, 14)
                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
            }
            .frame(maxWidth: 540)

            // YouTube URL
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundColor(Color(white: 0.55))
                TextField("Coller une URL YouTube…", text: $urlText)
                    .textFieldStyle(.plain).font(.callout)
                    .foregroundColor(.white)
                    .onSubmit { processIfReady() }
                if !urlText.isEmpty {
                    Button { urlText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.80))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.white.opacity(0.07))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.14), lineWidth: 1))
            .frame(maxWidth: 540)

            // Stem chips
            VStack(alignment: .leading, spacing: 10) {
                Text("PISTES À EXTRAIRE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(white: 0.55))
                    .tracking(1.2)
                HStack(spacing: 8) {
                    ForEach(StemKind.processable) { kind in
                        StemChip(kind: kind,
                                 isSelected: appState.selectedStems.contains(kind)) {
                            appState.toggleStem(kind)
                        }
                    }
                }
            }
            .frame(maxWidth: 540, alignment: .leading)

            // Error
            if let err = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                    Text(err).font(.callout).foregroundColor(Color.red.opacity(0.9))
                }
                .frame(maxWidth: 540, alignment: .leading)
            }

            // Process button
            Button(action: processIfReady) {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView().progressViewStyle(.circular)
                            .scaleEffect(0.7).tint(.white)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text(isProcessing ? "Traitement…" : "Extraire les pistes")
                        .font(.callout.weight(.semibold))
                }
                .frame(minWidth: 220)
                .padding(.vertical, 14).padding(.horizontal, 32)
                .background(
                    Group {
                        if canProcess {
                            LinearGradient(
                                colors: [.purple, Color(red: 0.6, green: 0.2, blue: 0.9)],
                                startPoint: .leading, endPoint: .trailing)
                        } else {
                            Color.white.opacity(0.10)
                        }
                    })
                .foregroundColor(canProcess ? .white : Color(white: 0.45))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(!canProcess)

            // Backend waiting hint
            if !appState.backendReady {
                HStack(spacing: 6) {
                    ProgressView().progressViewStyle(.circular).scaleEffect(0.6)
                    Text("En attente du backend Python…")
                        .font(.caption).foregroundColor(.orange)
                }
            }

            // Credit
            HStack(spacing: 4) {
                Text("Propulsé par")
                    .font(.caption2).foregroundColor(Color(white: 0.30))
                Link("stemdeckapp/stemdeck",
                     destination: URL(string: "https://github.com/stemdeckapp/stemdeck")!)
                    .font(.caption2).foregroundColor(Color(white: 0.38))
                Text("· Apache 2.0")
                    .font(.caption2).foregroundColor(Color(white: 0.28))
            }
        }
        .padding(.horizontal, 40).padding(.vertical, 32)
    }

    // MARK: - Process
    /// Formats acceptés tels quels par le backend (app/api/jobs.py → _ALLOWED_EXTS).
    private static let backendFormats: Set<String> = ["mp3", "wav", "flac", "mp4", "m4a", "ogg", "opus"]

    private func processIfReady() {
        guard canProcess else { return }
        errorMessage = nil; isProcessing = true

        Task {
            var tempFile: URL? = nil
            defer { if let t = tempFile { try? FileManager.default.removeItem(at: t) } }
            do {
                let stems = StemKind.processable.filter { appState.selectedStems.contains($0) }
                let jobId: String
                if let fileURL = droppedFile {
                    var uploadURL = fileURL
                    // AIFF, ALAC, WMA… : conversion locale en FLAC (sans perte) avant l'envoi
                    if !Self.backendFormats.contains(fileURL.pathExtension.lowercased()) {
                        AppLogger.shared.log("Conversion en FLAC : \(fileURL.lastPathComponent)", level: .info)
                        uploadURL = try await Self.convertToFlac(fileURL)
                        tempFile = uploadURL
                    }
                    AppLogger.shared.log("Envoi du fichier : \(fileURL.lastPathComponent)", level: .info)
                    jobId = try await BackendService.shared.uploadJob(fileURL: uploadURL, stems: stems)
                } else {
                    AppLogger.shared.log("Traitement de l'URL : \(urlText)", level: .info)
                    jobId = try await BackendService.shared.createJob(url: urlText, stems: stems)
                }
                AppLogger.shared.log("Job créé : \(jobId)", level: .ok)
                appState.currentJob  = StemJob(id: jobId,
                                               title: droppedFile?.deletingPathExtension().lastPathComponent ?? urlText)
                appState.jobProgress = JobProgress(message: "En file d'attente…")
                appState.screen      = .processing
                isProcessing         = false
                startListening(jobId: jobId)
            } catch {
                let msg = error.localizedDescription
                AppLogger.shared.log("Échec de création du job : \(msg)", level: .error)
                errorMessage = msg
                isProcessing = false
            }
        }
    }

    private static func convertToFlac(_ source: URL) async throws -> URL {
        guard let ffmpeg = PythonRuntimeService.ffmpegPath() else {
            throw BackendError(message: "Format non pris en charge et FFmpeg introuvable pour le convertir.")
        }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".flac")
        try? FileManager.default.removeItem(at: dest)
        _ = try await Task.detached(priority: .userInitiated) {
            try PythonRuntimeService.run(ffmpeg, ["-y", "-hide_banner", "-loglevel", "error",
                                                  "-i", source.path, "-vn", "-c:a", "flac", dest.path])
        }.value
        return dest
    }

    private func startListening(jobId: String) {
        let url = BackendService.shared.baseURL
            .appendingPathComponent("api/jobs/\(jobId)/events")
        let client = SSEClient(url: url)

        client.onEvent = { event in
            appState.jobProgress = JobProgress(
                phase:        event.phase,
                percent:      event.progress,
                message:      event.message,
                isComplete:   event.status == .done,
                isFailed:     event.status.isFailure,
                errorMessage: event.error)
            appState.currentJob = event.job

            switch event.status {
            case .done:
                appState.screen = .studio
            case .error:
                errorMessage = (event.error ?? "La séparation a échoué.")
                    + "\n\nConsulte les Logs (⬛) pour l'erreur complète."
                appState.screen = .importing
            case .cancelled, .stopped:
                appState.screen = .importing
            default:
                break
            }
        }
        client.onComplete = {
            // Flux terminé (ou coupé) : on relit l'état réel du job
            guard appState.screen == .processing else { return }
            Task {
                guard let job = try? await BackendService.shared.fetchJob(id: jobId) else { return }
                appState.currentJob = job
                switch job.status {
                case .done:
                    appState.screen = .studio
                case .error:
                    errorMessage = job.errorMessage ?? "La séparation a échoué."
                    appState.screen = .importing
                case .cancelled, .stopped:
                    appState.screen = .importing
                default:
                    // Toujours en cours (flux coupé) : on se reconnecte
                    startListening(jobId: jobId)
                }
            }
        }
        client.onError = { error in
            AppLogger.shared.log("SSE : \(error.localizedDescription)", level: .warn)
        }
        client.start()
    }
}

// MARK: - Stem chip
struct StemChip: View {
    let kind: StemKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: kind.icon).font(.caption)
                Text(kind.displayName).font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isSelected ? kind.color.opacity(0.22) : Color.white.opacity(0.06))
            .foregroundColor(isSelected ? kind.color : Color(white: 0.60))
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20)
                .stroke(isSelected ? kind.color.opacity(0.7) : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Drop zone
struct DropZone: View {
    @Binding var droppedFile: URL?
    @Binding var isDragging: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(isDragging
                      ? Color.purple.opacity(0.12)
                      : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.5,
                                               dash: isDragging ? [] : [8, 5]))
                        .foregroundColor(isDragging
                                         ? Color.purple.opacity(0.8)
                                         : Color.white.opacity(0.18))
                )

            VStack(spacing: 14) {
                if let url = droppedFile {
                    Image(systemName: "music.note")
                        .font(.system(size: 38)).foregroundStyle(.purple.gradient)
                    Text(url.lastPathComponent)
                        .font(.callout.weight(.semibold)).foregroundColor(.white)
                    Button("Changer de fichier") { droppedFile = nil }
                        .buttonStyle(.plain).font(.caption)
                        .foregroundColor(Color(white: 0.55))
                } else {
                    Image(systemName: "arrow.down.to.line.circle")
                        .font(.system(size: 38))
                        .foregroundColor(isDragging ? .purple : Color(white: 0.45))
                    Text("Déposer un fichier MP3 / WAV")
                        .font(.callout)
                        .foregroundColor(isDragging ? .purple : Color(white: 0.50))
                    Text("ou cliquer pour parcourir")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.38))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if droppedFile == nil {
                // Open file picker via AppState trigger would be cleaner,
                // but for simplicity use NSOpenPanel directly
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.audio]
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK { droppedFile = panel.url }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            providers.first?.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async { droppedFile = url }
                }
            }
            return true
        }
    }
}
