// Services/MixExportService.swift
// Exports the current mix respecting mutes, solos and volumes.
// All @MainActor data is captured before crossing into background threads.

import AVFoundation
import Foundation

// Plain struct to carry track data across actor boundaries — Sendable safe
struct TrackSnapshot: Sendable {
    let url:    URL
    let volume: Float
}

final class MixExportService {

    static let shared = MixExportService()

    /// Call from MainActor context — captures track state, then mixes on a bg thread.
    @MainActor func exportMix(tracks: [StemTrack],
                   format: ExportFormat,
                   destURL: URL) async throws {

        // --- Capture all @MainActor data here, on MainActor ---
        let anySolo = tracks.contains { $0.isSolo }
        let snapshots: [TrackSnapshot] = tracks.compactMap { track in
            guard !track.isMuted,
                  let url = track.audioURL else { return nil }
            if anySolo && !track.isSolo { return nil }
            return TrackSnapshot(url: url, volume: track.volume)
        }

        guard !snapshots.isEmpty else { throw MixError.noActiveTracks }

        // Single track — just convert
        if snapshots.count == 1 {
            try await ExportService.shared.convert(source: snapshots[0].url,
                                                   to: format,
                                                   destURL: destURL)
            return
        }

        // Multiple tracks — mix with ffmpeg on background thread
        guard let ffmpeg = ExportService.shared.findFFmpeg() else {
            throw ExportError.ffmpegNotFound
        }

        // All data is now plain Sendable structs — safe to cross into Task.detached
        let capturedSnapshots = snapshots
        let capturedFormat    = format
        let capturedDest      = destURL

        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.runFFmpegMix(ffmpeg: ffmpeg,
                                          snapshots: capturedSnapshots,
                                          format: capturedFormat,
                                          dest: capturedDest)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // Pure static — no actor isolation needed
    private static func runFFmpegMix(ffmpeg: String,
                                      snapshots: [TrackSnapshot],
                                      format: ExportFormat,
                                      dest: URL) throws {
        var args = ["-y"]

        // Input files
        for s in snapshots { args += ["-i", s.url.path] }

        // Filter graph: volume per track → amix
        var filterParts: [String] = []
        for (i, s) in snapshots.enumerated() {
            let vol = String(format: "%.3f", s.volume)
            filterParts.append("[\(i):a]volume=\(vol)[a\(i)]")
        }
        let inputs = (0..<snapshots.count).map { "[a\($0)]" }.joined()
        filterParts.append(
            "\(inputs)amix=inputs=\(snapshots.count):duration=longest:normalize=0[out]"
        )

        args += ["-filter_complex", filterParts.joined(separator: ";"),
                 "-map", "[out]", "-ac", "2"]

        switch format {
        case .mp3: args += ["-codec:a", "libmp3lame", "-qscale:a", "2"]
        case .wav: args += ["-acodec", "pcm_s16le", "-ar", "44100"]
        }
        args.append(dest.path)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments     = args
        let errPipe = Pipe()
        p.standardError  = errPipe
        p.standardOutput = Pipe()

        print("[MixExport] \(args.joined(separator: " "))")
        try p.run(); p.waitUntilExit()

        if p.terminationStatus != 0 {
            let errOut = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8) ?? ""
            throw ExportError.ffmpegFailed(errOut.suffix(300).description)
        }
    }
}

enum MixError: Error, LocalizedError {
    case noActiveTracks
    var errorDescription: String? {
        "Aucune piste active. Activez au moins une piste avant d'exporter."
    }
}
