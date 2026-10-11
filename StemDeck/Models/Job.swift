// Models/Job.swift
// Modèles alignés sur l'API de stemdeckapp/stemdeck v0.20.0 (Job.to_state()).

import Foundation

// MARK: - Réponse de création (POST /api/jobs → {"job_id": "..."})
struct JobCreateResponse: Codable {
    let jobId: String
    enum CodingKeys: String, CodingKey { case jobId = "job_id" }
}

// MARK: - Job complet (GET /api/jobs/{id}, GET /api/jobs, événements SSE)
struct StemJob: Identifiable, Codable, Equatable {
    let id: String
    var status:       JobStatus
    var progress:     Double          // 0…1
    var stage:        String          // message d'étape du backend
    var stems:        [StemFile]
    var analysis:     SongAnalysis?
    var title:        String
    var createdAt:    Date
    var error:        String?
    var errorDetail:  String?
    var favorite:     Bool

    enum CodingKeys: String, CodingKey {
        case id = "job_id"
        case status, progress, stage, stems, title, error, favorite
        case createdAt   = "created_at"
        case errorDetail = "error_detail"
        // champs d'analyse, à plat dans to_state()
        case bpm, key, scale
        case keyConfidence = "key_confidence"
        case lufs
        case peakDb = "peak_db"
        // ancien format
        case analysis
    }

    init(id: String, status: JobStatus = .queued, stems: [StemFile] = [],
         analysis: SongAnalysis? = nil, title: String = "Sans titre",
         createdAt: Date = Date()) {
        self.id = id; self.status = status; self.stems = stems
        self.analysis = analysis; self.title = title; self.createdAt = createdAt
        self.progress = 0; self.stage = ""; self.error = nil; self.errorDetail = nil
        self.favorite = false
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self, forKey: .id)
        status      = (try? c.decode(JobStatus.self, forKey: .status)) ?? .queued
        progress    = (try? c.decode(Double.self, forKey: .progress)) ?? 0
        stage       = (try? c.decode(String.self, forKey: .stage)) ?? ""
        title       = (try? c.decode(String.self, forKey: .title)) ?? "Sans titre"
        error       = try? c.decode(String.self, forKey: .error)
        errorDetail = try? c.decode(String.self, forKey: .errorDetail)
        favorite    = (try? c.decode(Bool.self, forKey: .favorite)) ?? false

        // created_at : timestamp Unix (float) — ou ISO 8601 pour l'ancien format
        if let ts = try? c.decode(Double.self, forKey: .createdAt) {
            createdAt = Date(timeIntervalSince1970: ts)
        } else if let raw = try? c.decode(String.self, forKey: .createdAt),
                  let d = ISO8601DateFormatter().date(from: raw) {
            createdAt = d
        } else {
            createdAt = Date()
        }

        // stems : [{"name": "vocals", "url": "/api/jobs/<id>/stems/vocals.wav"}]
        let jobId = id
        if let refs = try? c.decode([StemRef].self, forKey: .stems) {
            stems = refs.compactMap { ref in
                guard let kind = StemKind(rawValue: ref.name) else { return nil }
                return StemFile(id: "\(jobId)-\(ref.name)", kind: kind,
                                fileName: "\(ref.name).wav", durationSeconds: nil)
            }
        } else {
            stems = []
        }

        // analyse
        if let legacy = try? c.decode(SongAnalysis.self, forKey: .analysis) {
            analysis = legacy
        } else {
            let a = SongAnalysis(
                bpm:            try? c.decode(Double.self, forKey: .bpm),
                key:            try? c.decode(String.self, forKey: .key),
                scale:          try? c.decode(String.self, forKey: .scale),
                keyConfidence:  try? c.decode(Double.self, forKey: .keyConfidence),
                integratedLufs: try? c.decode(Double.self, forKey: .lufs),
                samplePeakDb:   try? c.decode(Double.self, forKey: .peakDb))
            analysis = a.isEmpty ? nil : a
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(status, forKey: .status)
        try c.encode(progress, forKey: .progress)
        try c.encode(stage, forKey: .stage)
        try c.encode(title, forKey: .title)
        try c.encode(createdAt.timeIntervalSince1970, forKey: .createdAt)
        try c.encodeIfPresent(error, forKey: .error)
        try c.encodeIfPresent(analysis, forKey: .analysis)
        try c.encode(favorite, forKey: .favorite)
    }

    /// Message d'erreur lisible (le backend fournit `error` court + `error_detail`).
    var errorMessage: String? {
        switch (error, errorDetail) {
        case let (e?, d?) where !d.isEmpty && d != e: return "\(e)\n\(d)"
        case let (e?, _): return e
        case let (nil, d?): return d
        default: return nil
        }
    }
}

private struct StemRef: Decodable {
    let name: String
}

// MARK: - Statut (app/core/models.py → JobStatus)
enum JobStatus: String, Codable {
    case queued, downloading, analyzing, separating, processing
    case done, error, cancelled, stopped
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "pending":           self = .queued       // anciens noms
        case "uploading":         self = .downloading
        case "mixing":            self = .processing
        case "failed":            self = .error
        default:                  self = JobStatus(rawValue: raw) ?? .unknown
        }
    }

    var isFinished: Bool { [.done, .error, .cancelled, .stopped].contains(self) }
    var isFailure:  Bool { self == .error }

    var localizedLabel: String {
        switch self {
        case .queued:      return "En file d'attente…"
        case .downloading: return "Téléchargement…"
        case .analyzing:   return "Analyse…"
        case .separating:  return "Séparation des pistes…"
        case .processing:  return "Finalisation…"
        case .done:        return "Terminé"
        case .error:       return "Échec"
        case .cancelled:   return "Annulé"
        case .stopped:     return "Arrêté"
        case .unknown:     return "Traitement…"
        }
    }
}

// MARK: - Demande de création (URL)
struct CreateJobRequest: Encodable {
    let url:   String
    let stems: [String]
}

// MARK: - Analyse
struct SongAnalysis: Codable, Equatable {
    let bpm:            Double?
    let key:            String?
    let scale:          String?
    let keyConfidence:  Double?
    let integratedLufs: Double?
    let samplePeakDb:   Double?

    enum CodingKeys: String, CodingKey {
        case bpm, key, scale
        case keyConfidence  = "key_confidence"
        case integratedLufs = "integrated_lufs"
        case samplePeakDb   = "sample_peak_db"
    }

    var isEmpty: Bool { bpm == nil && key == nil && integratedLufs == nil }

    var keyDisplay:  String {
        guard let k = key else { return "—" }
        return scale.map { "\(k) \($0)" } ?? k
    }
    var bpmDisplay:  String { guard let b = bpm else { return "—" }; return String(format: "%.1f BPM", b) }
    var lufsDisplay: String { guard let l = integratedLufs else { return "—" }; return String(format: "%.1f LUFS", l) }
}
