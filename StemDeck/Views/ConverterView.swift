// Views/ConverterView.swift
// M4A (and any audio format) → MP3 / WAV converter
// Uses ffmpeg from the venv or Homebrew

import SwiftUI
import UniformTypeIdentifiers

struct ConverterView: View {
    @State private var inputFiles:   [URL]           = []
    @State private var outputFormat: ExportFormat    = .mp3
    @State private var outputDir:    URL?            = nil
    @State private var isConverting  = false
    @State private var results:      [ConvertResult] = []
    @State private var isDragging    = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.title3).foregroundStyle(.orange.gradient)
                Text("Convertisseur Audio")
                    .font(.headline.weight(.semibold)).foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Color("BackgroundSecondary"))

            ScrollView {
                VStack(spacing: 20) {

                    // Drop zone
                    dropZone
                        .frame(maxWidth: .infinity, minHeight: 120)

                    // File list
                    if !inputFiles.isEmpty {
                        fileList
                    }

                    // Options row
                    HStack(spacing: 16) {
                        // Format
                        VStack(alignment: .leading, spacing: 6) {
                            Text("FORMAT DE SORTIE")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(white: 0.50)).tracking(1)
                            Picker("", selection: $outputFormat) {
                                ForEach(ExportFormat.allCases) { fmt in
                                    Text(fmt.rawValue).tag(fmt)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }

                        // Output folder
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DOSSIER DE SORTIE")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(white: 0.50)).tracking(1)
                            Button {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.prompt = "Choisir"
                                if panel.runModal() == .OK { outputDir = panel.url }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.orange)
                                    Text(outputDir?.lastPathComponent ?? "Même dossier")
                                        .font(.callout)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color.white.opacity(0.07))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        // Convert button
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(" ").font(.system(size: 10))  // spacer
                            Button(action: convert) {
                                HStack(spacing: 6) {
                                    if isConverting {
                                        ProgressView().progressViewStyle(.circular)
                                            .scaleEffect(0.65).tint(.white)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    Text(isConverting ? "Conversion…" : "Convertir")
                                        .font(.callout.weight(.semibold))
                                }
                                .padding(.horizontal, 20).padding(.vertical, 9)
                                .background(inputFiles.isEmpty || isConverting
                                            ? Color.gray.opacity(0.3)
                                            : Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(inputFiles.isEmpty || isConverting)
                        }
                    }
                    .padding(.horizontal, 4)

                    // Results
                    if !results.isEmpty {
                        resultsList
                    }
                }
                .padding(20)
            }
        }
        .background(Color("BackgroundPrimary"))
        .frame(minWidth: 560, minHeight: 400)
    }

    // MARK: - Drop zone
    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(isDragging ? Color.orange.opacity(0.10) : Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.5, dash: isDragging ? [] : [7, 5]))
                    .foregroundColor(isDragging ? .orange : Color.white.opacity(0.16)))

            VStack(spacing: 10) {
                Image(systemName: "arrow.down.to.line.circle")
                    .font(.system(size: 32))
                    .foregroundColor(isDragging ? .orange : Color(white: 0.42))
                Text("Déposer des fichiers audio ici")
                    .font(.callout).foregroundColor(isDragging ? .orange : Color(white: 0.48))
                Text("M4A, MP3, WAV, FLAC, AIF, OGG…")
                    .font(.caption).foregroundColor(Color(white: 0.35))
                Button("ou cliquer pour parcourir") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.allowedContentTypes = [.audio]
                    if panel.runModal() == .OK {
                        addFiles(panel.urls)
                    }
                }
                .buttonStyle(.plain).font(.caption.weight(.medium))
                .foregroundColor(.orange)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            for p in providers {
                p.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async { addFiles([url]) }
                    }
                }
            }
            return true
        }
    }

    // MARK: - File list
    private var fileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(inputFiles.count) fichier(s)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(white: 0.55))
                Spacer()
                Button("Tout effacer") { inputFiles.removeAll(); results.removeAll() }
                    .buttonStyle(.plain).font(.caption).foregroundColor(.red.opacity(0.7))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(0.04))

            ForEach(inputFiles, id: \.self) { url in
                HStack(spacing: 10) {
                    Image(systemName: audioIcon(for: url.pathExtension))
                        .foregroundColor(.orange).font(.caption)
                    Text(url.lastPathComponent).font(.caption).foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(url.pathExtension.uppercased()).font(.system(size: 9))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.20))
                        .foregroundColor(.orange).cornerRadius(4)
                    Button { inputFiles.removeAll { $0 == url } } label: {
                        Image(systemName: "xmark").font(.system(size: 9))
                            .foregroundColor(Color(white: 0.40))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.white.opacity(0.02))
            }
        }
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Results list
    private var resultsList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Résultats").font(.caption.weight(.semibold))
                    .foregroundColor(Color(white: 0.55))
                Spacer()
                Button("Effacer") { results.removeAll() }
                    .buttonStyle(.plain).font(.caption).foregroundColor(Color(white: 0.40))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(0.04))

            ForEach(results) { result in
                HStack(spacing: 10) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red).font(.caption)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.fileName).font(.caption).foregroundColor(.white)
                        if !result.success {
                            Text(result.error ?? "Erreur").font(.caption2)
                                .foregroundColor(.red.opacity(0.8))
                        }
                    }
                    Spacer()
                    if result.success, let dest = result.destURL {
                        Button {
                            NSWorkspace.shared.selectFile(dest.path,
                                inFileViewerRootedAtPath: dest.deletingLastPathComponent().path)
                        } label: {
                            Image(systemName: "folder.fill").font(.caption)
                                .foregroundColor(Color(white: 0.50))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.white.opacity(0.02))
            }
        }
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Logic
    private func addFiles(_ urls: [URL]) {
        let supported = ["m4a","mp3","wav","flac","aif","aiff","ogg","opus","wma","aac"]
        let new = urls.filter {
            supported.contains($0.pathExtension.lowercased()) &&
            !inputFiles.contains($0)
        }
        inputFiles.append(contentsOf: new)
    }

    private func convert() {
        guard !inputFiles.isEmpty else { return }
        isConverting = true
        results = []

        Task {
            for url in inputFiles {
                let dir = outputDir ?? url.deletingLastPathComponent()
                let name = url.deletingPathExtension().lastPathComponent
                    + "." + outputFormat.fileExtension
                let dest = dir.appendingPathComponent(name)

                do {
                    try await ExportService.shared.convert(source: url,
                                                           to: outputFormat,
                                                           destURL: dest)
                    results.append(ConvertResult(fileName: url.lastPathComponent,
                                                 success: true, destURL: dest))
                } catch {
                    results.append(ConvertResult(fileName: url.lastPathComponent,
                                                 success: false,
                                                 error: error.localizedDescription))
                }
            }
            isConverting = false
            // Clear input on full success
            if results.allSatisfy(\.success) { inputFiles.removeAll() }
        }
    }

    private func audioIcon(for ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "music.note"
        case "wav": return "waveform"
        case "m4a": return "applelogo"
        case "flac": return "hifispeaker.fill"
        default:    return "music.quarternote.3"
        }
    }
}

// MARK: - Result model
struct ConvertResult: Identifiable {
    let id      = UUID()
    let fileName: String
    let success: Bool
    var destURL:  URL?   = nil
    var error:    String? = nil
}
