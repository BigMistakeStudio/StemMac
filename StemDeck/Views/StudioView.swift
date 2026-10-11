// Views/StudioView.swift — macOS 13 compatible
import SwiftUI
import AVFoundation
import AppKit

struct StudioView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var player = AudioPlayerService.shared

    @State private var stemTracks:    [StemTrack] = []
    @State private var isLoadingStems = true
    @State private var loadError:     String? = nil
    @State private var keyMonitor:    Any?    = nil

    var body: some View {
        VStack(spacing: 0) {
            StudioTopBar(
                title: appState.currentJob?.title ?? "StemMac",
                stemTracks: stemTracks,
                jobId: appState.currentJob?.id ?? ""
            ) { saveAndReturn() }

            if isLoadingStems {
                loadingView
            } else if let err = loadError {
                errorView(err)
            } else {
                mainContent
            }
        }
        .background(Color("BackgroundPrimary"))
        .task { await loadAllStems() }
        .onAppear  { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: - Loading / error
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().progressViewStyle(.circular).scaleEffect(1.2)
            Text("Téléchargement des pistes…").font(.callout).foregroundColor(.secondary)
            Spacer()
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle).foregroundColor(.red)
            Text(msg).foregroundColor(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Button("Retour") { appState.resetForNewJob() }
                .buttonStyle(.borderedProminent).tint(.purple)
            Spacer()
        }
    }

    // MARK: - Main content
    private var mainContent: some View {
        VStack(spacing: 0) {
            if let analysis = appState.currentJob?.analysis {
                AnalysisBar(analysis: analysis)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    RulerView(
                        duration: player.duration,
                        playheadPosition: $player.currentTime,
                        loopStart: $player.loopStart,
                        loopEnd: $player.loopEnd,
                        loopEnabled: $player.loopEnabled,
                        zoomLevel: $appState.zoomLevel)
                    .frame(height: 32)

                    ForEach(stemTracks) { track in
                        StemTrackRow(track: track, player: player,
                                     zoomLevel: appState.zoomLevel)
                        Divider().background(Color.white.opacity(0.05))
                    }
                }
            }

            TransportView(player: player, duration: player.duration,
                          zoomLevel: $appState.zoomLevel)
                .background(Color("BackgroundSecondary"))
        }
    }

    // MARK: - Load stems
    private func loadAllStems() async {
        guard let job = appState.currentJob else { return }
        isLoadingStems = true
        loadError = nil
        var loaded: [StemTrack] = []

        // Pistes annoncées par le backend (stems[]), sinon on essaie toutes les pistes possibles
        let announced = job.stems.map(\.kind)
        let stemsToTry: [StemKind] = announced.isEmpty
            ? [.vocals, .drums, .bass, .guitar, .piano, .other, .original]
            : announced
        for kind in stemsToTry {
            if let url = try? await BackendService.shared.downloadStem(jobId: job.id, stem: kind) {
                let stemFile = StemFile(id: "\(job.id)-\(kind.rawValue)",
                                       kind: kind,
                                       fileName: "\(kind.rawValue).wav",
                                       durationSeconds: nil)
                let track = StemTrack(stemFile: stemFile, audioURL: url)
                loaded.append(track)
                print("[StemDeck] ✅ Piste téléchargée: \(kind.rawValue)")
            }
        }

        if loaded.isEmpty {
            isLoadingStems = false
            loadError = "Aucune piste trouvée. Vérifiez les logs."
            return
        }

        await AudioPlayerService.shared.loadStems(loaded)
        stemTracks     = loaded
        isLoadingStems = false

        // Render waveforms: capture URL on MainActor, render on background
        for track in loaded {
            guard let url = track.audioURL else { continue }
            let capturedURL  = url
            let capturedKind = track.kind.rawValue
            let capturedTrack = track
            Task.detached(priority: .utility) {
                let samples = await WaveformRenderer.render(url: capturedURL)
                print("[StemDeck] 🎵 Waveform \(capturedKind): \(samples.count) pts, max=\(samples.max() ?? 0)")
                await MainActor.run { capturedTrack.waveformSamples = samples }
            }
        }
    }

    // MARK: - Keyboard (NSEvent, macOS 13)
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.charactersIgnoringModifiers {
            case " ": player.isPlaying ? player.pause() : player.play(); return nil
            case "[": player.skipBackward(); return nil
            case "]": player.skipForward();  return nil
            case "l": player.loopEnabled.toggle(); return nil
            case "i": player.loopStart = player.currentTime; return nil
            case "o": player.loopEnd   = player.currentTime; return nil
            case "+": appState.zoomLevel = min(appState.zoomLevel * 1.5, 32); return nil
            case "-": appState.zoomLevel = max(appState.zoomLevel / 1.5, 0.5); return nil
            default:  return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private func saveAndReturn() {
        player.stop()
        if let job = appState.currentJob,
           !appState.libraryJobs.contains(where: { $0.id == job.id }) {
            appState.libraryJobs.insert(job, at: 0)
        }
        appState.resetForNewJob()
    }
}

// MARK: - Studio top bar
struct StudioTopBar: View {
    let title:      String
    let stemTracks: [StemTrack]
    let jobId:      String
    let onBack:     () -> Void
    @EnvironmentObject var appState: AppState

    @State private var exportFormat: ExportFormat = .wav
    @State private var isExporting   = false
    @State private var exportError:  String? = nil
    @State private var showExportMenu = false

    // Sanitise title for use as folder/filename
    private var safeTitle: String {
        title.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: " -_")).inverted)
             .joined()
             .trimmingCharacters(in: .whitespaces)
             .replacingOccurrences(of: "  ", with: " ")
             .prefix(60).description
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Label("Nouveau", systemImage: "chevron.left").font(.callout)
            }
            .buttonStyle(.plain).foregroundColor(.secondary)

            Text(title).font(.callout.weight(.semibold))
                .foregroundColor(.white).lineLimit(1)
            Spacer()

            // Format picker
            Picker("", selection: $exportFormat) {
                ForEach(ExportFormat.allCases) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
            .labelsHidden()

            // Export menu button
            Menu {
                // Option 1: export each active stem in its own file
                Button {
                    Task { await exportPistesSepaees() }
                } label: {
                    Label("Exporter les pistes séparées", systemImage: "square.stack.3d.up")
                }

                Divider()

                // Option 2: mix = sum of all UN-muted tracks → single file
                let activeTracks = stemTracks.filter { !$0.isMuted }
                let mutedNames   = stemTracks.filter  { $0.isMuted  }.map(\.kind.displayName)
                let mixLabel = mutedNames.isEmpty
                    ? "Exporter le mix complet"
                    : "Exporter sans \(mutedNames.joined(separator: ", "))"

                Button {
                    Task { await exportMix() }
                } label: {
                    Label(mixLabel, systemImage: "waveform.path")
                }
                .disabled(activeTracks.isEmpty)

            } label: {
                HStack(spacing: 5) {
                    if isExporting {
                        ProgressView().progressViewStyle(.circular)
                            .scaleEffect(0.6).tint(.white)
                    } else {
                        Image(systemName: "arrow.down.to.line")
                    }
                    Text(isExporting ? "Export…" : "Exporter ↓")
                        .font(.caption.weight(.medium))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.purple)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(isExporting)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color("BackgroundSecondary"))
        .alert("Erreur d'export", isPresented: .constant(exportError != nil)) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: - Export pistes séparées
    // Crée un dossier au nom de la musique et y exporte chaque piste active
    private func exportPistesSepaees() async {
        let activeTracks = stemTracks.filter { !$0.isMuted }
        guard !activeTracks.isEmpty else { return }
        isExporting = true
        defer { isExporting = false }

        let panel = NSOpenPanel()
        panel.title          = "Choisir où sauvegarder"
        panel.message        = "Un sous-dossier « \(safeTitle) » sera créé à cet endroit."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt         = "Choisir"
        guard panel.runModal() == .OK, let base = panel.url else { return }

        // Create named subfolder
        let folder = base.appendingPathComponent(safeTitle)
        do {
            try FileManager.default.createDirectory(at: folder,
                withIntermediateDirectories: true)
        } catch {
            exportError = "Impossible de créer le dossier : \(error.localizedDescription)"
            return
        }

        for track in activeTracks {
            guard let srcURL = track.audioURL else { continue }
            let destURL = folder.appendingPathComponent(
                track.kind.displayName + "." + exportFormat.fileExtension)
            do {
                try await ExportService.shared.convert(source: srcURL,
                                                       to: exportFormat,
                                                       destURL: destURL)
            } catch {
                exportError = error.localizedDescription
                return
            }
        }

        // Reveal folder in Finder
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }

    // MARK: - Export mix via MixExportService
    private func exportMix() async {
        let mutedNames = stemTracks.filter { $0.isMuted }.map(\.kind.displayName)
        let anySolo    = stemTracks.contains { $0.isSolo }
        let mixName: String
        if anySolo {
            let soloNames = stemTracks.filter { $0.isSolo }.map(\.kind.displayName)
            mixName = safeTitle + " (\(soloNames.joined(separator: "+")))"
        } else if mutedNames.isEmpty {
            mixName = safeTitle + " (mix)"
        } else {
            mixName = safeTitle + " (sans \(mutedNames.joined(separator: ", ")))"
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = mixName + "." + exportFormat.fileExtension
        panel.title = "Exporter le mix"
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        isExporting = true
        defer { isExporting = false }

        do {
            try await MixExportService.shared.exportMix(
                tracks: stemTracks,
                format: exportFormat,
                destURL: destURL)
            NSWorkspace.shared.selectFile(destURL.path,
                inFileViewerRootedAtPath: destURL.deletingLastPathComponent().path)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

// MARK: - Analysis bar
struct AnalysisBar: View {
    let analysis: SongAnalysis
    var body: some View {
        HStack(spacing: 20) {
            AnalysisBadge(icon: "metronome.fill",      label: "BPM",      value: analysis.bpmDisplay)
            AnalysisBadge(icon: "music.quarternote.3", label: "Tonalité", value: analysis.keyDisplay)
            AnalysisBadge(icon: "speaker.wave.3.fill", label: "LUFS",     value: analysis.lufsDisplay)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
    }
}

struct AnalysisBadge: View {
    let icon: String; let label: String; let value: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundColor(.purple)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 9)).foregroundColor(.secondary)
                    .textCase(.uppercase).tracking(0.5)
                Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Ruler
struct RulerView: View {
    let duration: Double
    @Binding var playheadPosition: Double
    @Binding var loopStart: Double
    @Binding var loopEnd: Double
    @Binding var loopEnabled: Bool
    @Binding var zoomLevel: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color("BackgroundSecondary")
                if loopEnabled && loopEnd > loopStart {
                    let sx = CGFloat(loopStart / max(duration, 1)) * geo.size.width
                    let ex = CGFloat(loopEnd   / max(duration, 1)) * geo.size.width
                    Rectangle().fill(Color.purple.opacity(0.2))
                        .frame(width: ex - sx).offset(x: sx)
                }
                Canvas { ctx, size in
                    let step = stepInterval(for: duration, width: Double(size.width))
                    var t = 0.0
                    while t <= duration {
                        let x = CGFloat(t / max(duration, 1)) * size.width
                        ctx.stroke(Path { p in
                            p.move(to: .init(x: x, y: size.height - 10))
                            p.addLine(to: .init(x: x, y: size.height))
                        }, with: .color(.white.opacity(0.2)), lineWidth: 1)
                        t += step
                    }
                }
                let phX = CGFloat(playheadPosition / max(duration, 1)) * geo.size.width
                Rectangle().fill(Color.yellow).frame(width: 2).offset(x: phX - 1)
                Color.clear
                    .gesture(DragGesture(minimumDistance: 4).onChanged { val in
                        let t  = Double(val.startLocation.x / geo.size.width) * duration
                        let t2 = Double(val.location.x      / geo.size.width) * duration
                        loopStart = min(t, t2); loopEnd = max(t, t2)
                    }.onEnded { _ in loopEnabled = true })
            }
        }
        .frame(height: 32)
    }

    private func stepInterval(for duration: Double, width: Double) -> Double {
        let raw  = duration / max(width / 60, 1)
        let mags = [1, 2, 5, 10, 15, 30, 60, 120, 300]
        return Double(mags.first { Double($0) >= raw } ?? mags.last!)
    }
}

// MARK: - Stem track row
struct StemTrackRow: View {
    @ObservedObject var track: StemTrack
    let player: AudioPlayerService
    let zoomLevel: Double

    var body: some View {
        HStack(spacing: 0) {
            // Controls panel
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: track.kind.icon).font(.caption)
                        .foregroundColor(track.kind.color)
                    Text(track.kind.displayName)
                        .font(.caption.weight(.semibold)).foregroundColor(.white)
                }
                HStack(spacing: 4) {
                    MiniButton("M", active: track.isMuted,    color: .orange) {
                        player.setMute(!track.isMuted, forTrack: track.id)
                    }
                    MiniButton("S", active: track.isSolo,     color: .yellow) {
                        player.setSolo(!track.isSolo, forTrack: track.id)
                    }
                    MiniButton("Mon", active: track.isMonitor, color: .cyan) {
                        player.setMonitor(!track.isMonitor, forTrack: track.id)
                    }
                }
                Slider(value: Binding(
                    get: { Double(track.volume) },
                    set: { track.volume = Float($0)
                           player.setVolume(Float($0), forTrack: track.id) }
                ), in: 0...1.5).tint(track.kind.color).frame(width: 140)
            }
            .frame(width: 180).padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.white.opacity(0.03))

            // VU meter
            VUMeterView(level: track.vuLevel, peak: track.peakLevel, color: track.kind.color)
                .frame(width: 12).padding(.horizontal, 4)

            // Waveform — use .id() to force redraw when samples arrive
            WaveformView(
                samples: track.waveformSamples,
                color: track.kind.color,
                isMuted: track.isMuted,
                playheadPosition: player.currentTime,
                duration: player.duration,
                loopStart: player.loopStart,
                loopEnd: player.loopEnd,
                loopEnabled: player.loopEnabled,
                zoomLevel: zoomLevel)
            .frame(maxWidth: .infinity).frame(height: 80)
            .background(Color.white.opacity(0.02))
            // CRITICAL: force SwiftUI to recreate Canvas when sample count changes
            .id("waveform-\(track.kind.rawValue)-\(track.waveformSamples.count)")
        }
        .frame(height: 100)
        .opacity(track.isMuted ? 0.45 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: track.isMuted)
    }
}

// MARK: - Mini button
struct MiniButton: View {
    let label: String; let active: Bool; let color: Color; let action: () -> Void
    init(_ l: String, active: Bool, color: Color, action: @escaping () -> Void) {
        label = l; self.active = active; self.color = color; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(active ? color : Color.white.opacity(0.08))
                .foregroundColor(active ? .black : .secondary).cornerRadius(3)
        }.buttonStyle(.plain)
    }
}
