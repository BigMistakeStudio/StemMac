// Models/Stem.swift
// Represents one Demucs stem track in the DAW mixer

import SwiftUI
import AVFoundation

// MARK: - Stem kinds (htdemucs_6s)
enum StemKind: String, CaseIterable, Codable, Identifiable {
    case vocals
    case drums
    case bass
    case guitar
    case piano
    case other
    case original  // complement stem (subset mode only)
    case mix       // downloaded mix

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vocals:   return "Voix"
        case .drums:    return "Batterie"
        case .bass:     return "Basse"
        case .guitar:   return "Guitare"
        case .piano:    return "Piano"
        case .other:    return "Autres (sax, cordes…)"
        case .original: return "Original"
        case .mix:      return "Mix"
        }
    }

    var icon: String {
        switch self {
        case .vocals:   return "mic.fill"
        case .drums:    return "waveform"
        case .bass:     return "music.note"
        case .guitar:   return "guitars.fill"
        case .piano:    return "pianokeys"
        case .other:    return "music.note.list"
        case .original: return "music.quarternote.3"
        case .mix:      return "slider.horizontal.3"
        }
    }

    var color: Color {
        switch self {
        case .vocals:   return Color(hex: "#C084FC")   // purple
        case .drums:    return Color(hex: "#F97316")   // orange
        case .bass:     return Color(hex: "#22D3EE")   // cyan
        case .guitar:   return Color(hex: "#4ADE80")   // green
        case .piano:    return Color(hex: "#FBBF24")   // amber
        case .other:    return Color(hex: "#94A3B8")   // slate
        case .original: return Color(hex: "#60A5FA")   // blue
        case .mix:      return Color(hex: "#A3E635")   // lime
        }
    }

    static var processable: [StemKind] {
        [.vocals, .drums, .bass, .guitar, .piano, .other]
    }
}

// MARK: - Stem file (from backend /stems/{name}.wav)
struct StemFile: Identifiable, Codable, Equatable {
    let id: String
    let kind: StemKind
    let fileName: String
    let durationSeconds: Double?

    var localURL: URL? = nil          // downloaded to disk

    enum CodingKeys: String, CodingKey {
        case id, kind, fileName = "file_name", durationSeconds = "duration"
    }
}

// MARK: - Per-stem mixer state (in-memory, not persisted)
@MainActor
final class StemTrack: ObservableObject, Identifiable {
    let id: String
    let kind: StemKind
    let stemFile: StemFile
    var audioURL: URL?

    @Published var volume: Float = 1.0    // linear, 0–1.5
    @Published var isMuted = false
    @Published var isSolo = false
    @Published var isMonitor = false      // solo-only (clears others)
    @Published var vuLevel: Float = 0     // RMS post-gain, -inf → 0 dBFS
    @Published var peakLevel: Float = 0
    @Published var waveformSamples: [Float] = []
    @Published var isLoadingWaveform = false

    var gainDb: Float { 20 * log10(max(volume, 0.0001)) }

    init(stemFile: StemFile, audioURL: URL? = nil) {
        self.id = stemFile.id
        self.kind = stemFile.kind
        self.stemFile = stemFile
        self.audioURL = audioURL
    }
}

// MARK: - Color hex helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
    }
}
