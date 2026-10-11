// Services/ExportService.swift
// Converts any audio format (M4A, WAV, MP3, FLAC…) using ffmpeg.

import Foundation
import AVFoundation
import Darwin

enum ExportFormat: String, CaseIterable, Identifiable {
    case wav = "WAV"
    case mp3 = "MP3"
    var id: String { rawValue }
    var fileExtension: String { rawValue.lowercased() }
}

final class ExportService {

    static let shared = ExportService()

    // ── Public API ────────────────────────────────────────────────────────────

    func convert(source: URL, to format: ExportFormat, destURL: URL) async throws {
        guard let ffmpeg = findFFmpeg() else {
            throw ExportError.ffmpegNotFound
        }
        try await runFFmpeg(ffmpeg, source: source, format: format, dest: destURL)
    }

    // Backwards-compat alias (old callers used sourceWAV:)
    func convert(sourceWAV: URL, to format: ExportFormat, destURL: URL) async throws {
        try await convert(source: sourceWAV, to: format, destURL: destURL)
    }

    // ── Find ffmpeg ───────────────────────────────────────────────────────────

    func findFFmpeg() -> String? {
        // Delegate to PythonRuntimeService which uses access() syscall
        if let path = PythonRuntimeService.ffmpegPath() {
            print("[ExportService] ✅ ffmpeg: \(path)")
            return path
        }
        print("[ExportService] ❌ ffmpeg introuvable — installer via: brew install ffmpeg")
        return nil
    }

    // ── Run ffmpeg ────────────────────────────────────────────────────────────

    private func runFFmpeg(_ ffmpeg: String, source: URL,
                            format: ExportFormat, dest: URL) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                // Build args based on output format
                var args: [String] = [
                    "-y",            // overwrite output
                    "-i", source.path
                ]
                switch format {
                case .mp3:
                    args += [
                        "-vn",                    // no video
                        "-codec:a", "libmp3lame", // MP3 encoder
                        "-qscale:a", "2",         // VBR ~190 kbps
                        "-ar", "44100",
                    ]
                case .wav:
                    args += [
                        "-vn",
                        "-acodec", "pcm_s16le",   // standard 16-bit WAV
                        "-ar", "44100",
                    ]
                }
                args.append(dest.path)

                let p = Process()
                p.executableURL = URL(fileURLWithPath: ffmpeg)
                p.arguments = args
                let errPipe = Pipe()
                p.standardError  = errPipe
                p.standardOutput = Pipe() // discard stdout

                do {
                    try p.run(); p.waitUntilExit()
                    let errOut = String(
                        data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8) ?? ""
                    if p.terminationStatus == 0 {
                        print("[ExportService] ✅ Converted \(source.lastPathComponent) → \(dest.lastPathComponent)")
                        cont.resume()
                    } else {
                        print("[ExportService] ❌ ffmpeg error:\n\(errOut.suffix(400))")
                        cont.resume(throwing: ExportError.ffmpegFailed(
                            errOut.suffix(300).description))
                    }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

// ── Errors ────────────────────────────────────────────────────────────────────
enum ExportError: Error, LocalizedError {
    case ffmpegNotFound
    case ffmpegFailed(String)
    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "ffmpeg introuvable. Installez-le via Homebrew :\nbrew install ffmpeg"
        case .ffmpegFailed(let msg):
            return "ffmpeg a échoué :\n\(msg)"
        }
    }
}
