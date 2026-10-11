// Services/BackendService.swift
// Client REST aligné sur stemdeckapp/stemdeck v0.20.0.
//
// POST   /api/jobs                       JSON {url, stems} ou multipart {file, stems=<JSON>} → {job_id}
// GET    /api/jobs                       bibliothèque (jobs terminés, hors corbeille)
// GET    /api/jobs/{id}                  état complet
// GET    /api/jobs/{id}/events           SSE
// POST   /api/jobs/{id}/cancel           annuler
// POST   /api/jobs/{id}/trash            mettre à la corbeille
// DELETE /api/jobs/{id}                  supprimer définitivement
// GET    /api/jobs/{id}/stems/{name}.wav piste
// GET    /api/health                     {status, version, ffmpeg_configured, …}

import Foundation

// MARK: - Erreurs
struct BackendError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct APIErrorDetail: Decodable {
    let detail: AnyCodableString?
}

// FastAPI : `detail` peut être une chaîne ou une liste d'erreurs
private struct AnyCodableString: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            value = s
        } else if let arr = try? c.decode([[String: AnyDecodable]].self) {
            value = arr.compactMap { $0["msg"]?.string }.joined(separator: "; ")
        } else {
            value = "Erreur inconnue"
        }
    }
}

private struct AnyDecodable: Decodable {
    let string: String?
    init(from decoder: Decoder) throws {
        string = try? decoder.singleValueContainer().decode(String.self)
    }
}

// MARK: - Santé du backend
struct BackendHealth: Decodable {
    let status: String
    let version: String?
    let ffmpegConfigured: Bool?
    let demucsDevice: String?
    enum CodingKeys: String, CodingKey {
        case status, version
        case ffmpegConfigured = "ffmpeg_configured"
        case demucsDevice     = "demucs_device"
    }
}

// MARK: - BackendService
final class BackendService: ObservableObject {

    static let shared = BackendService()

    var baseURL: URL = URL(string: "http://127.0.0.1:8000")!

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 300      // l'upload attend le probe de durée
        cfg.timeoutIntervalForResource = 3600
        return URLSession(configuration: cfg)
    }()

    private func api(_ path: String) -> URL { baseURL.appendingPathComponent("api/" + path) }

    // MARK: POST /api/jobs (URL YouTube / SoundCloud)
    func createJob(url: String, stems: [StemKind]) async throws -> String {
        var req = URLRequest(url: api("jobs"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            CreateJobRequest(url: url, stems: stems.map(\.rawValue)))
        let (data, resp) = try await session.data(for: req)
        try checkHTTP(resp, data: data)
        return try JSONDecoder().decode(JobCreateResponse.self, from: data).jobId
    }

    // MARK: POST /api/jobs (fichier — multipart, envoyé depuis le disque)
    func uploadJob(fileURL: URL, stems: [StemKind]) async throws -> String {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

        let boundary = "StemDeck-\(UUID().uuidString)"
        let body = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).multipart")
        defer { try? FileManager.default.removeItem(at: body) }
        try writeMultipart(to: body, boundary: boundary, fileURL: fileURL,
                           // Le backend lit UN champ `stems` contenant une liste JSON
                           stemsJSON: String(data: try JSONEncoder().encode(stems.map(\.rawValue)),
                                             encoding: .utf8) ?? "[]")

        var req = URLRequest(url: api("jobs"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await session.upload(for: req, fromFile: body)
        try checkHTTP(resp, data: data)
        return try JSONDecoder().decode(JobCreateResponse.self, from: data).jobId
    }

    // MARK: GET /api/jobs/{id}
    func fetchJob(id: String) async throws -> StemJob {
        let (data, resp) = try await session.data(from: api("jobs/\(id)"))
        try checkHTTP(resp, data: data)
        return try JSONDecoder().decode(StemJob.self, from: data)
    }

    // MARK: GET /api/jobs — bibliothèque (plus récents d'abord)
    func listJobs() async throws -> [StemJob] {
        let (data, resp) = try await session.data(from: api("jobs"))
        try checkHTTP(resp, data: data)
        return try JSONDecoder().decode([StemJob].self, from: data)
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: POST /api/jobs/{id}/cancel
    func cancelJob(id: String) async throws {
        var req = URLRequest(url: api("jobs/\(id)/cancel"))
        req.httpMethod = "POST"
        let (data, resp) = try await session.data(for: req)
        try checkHTTP(resp, data: data)
    }

    // MARK: POST /api/jobs/{id}/trash
    func trashJob(id: String) async throws {
        var req = URLRequest(url: api("jobs/\(id)/trash"))
        req.httpMethod = "POST"
        let (data, resp) = try await session.data(for: req)
        try checkHTTP(resp, data: data)
    }

    // MARK: DELETE /api/jobs/{id}
    func deleteJob(id: String) async throws {
        var req = URLRequest(url: api("jobs/\(id)"))
        req.httpMethod = "DELETE"
        let (data, resp) = try await session.data(for: req)
        try checkHTTP(resp, data: data)
    }

    // MARK: Piste WAV (nil si absente pour ce job)
    func downloadStem(jobId: String, stem: StemKind) async throws -> URL? {
        let dest = stemCacheURL(jobId: jobId, name: "\(stem.rawValue).wav")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        do {
            let (tmp, resp) = try await session.download(from: api("jobs/\(jobId)/stems/\(stem.rawValue).wav"))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                try? FileManager.default.removeItem(at: tmp)
                return nil
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            return dest
        } catch {
            print("[StemDeck] Piste \(stem.rawValue) indisponible : \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: mix.wav (présent quand un sous-ensemble de pistes a été demandé)
    func downloadMix(jobId: String) async throws -> URL {
        let dest = stemCacheURL(jobId: jobId, name: "mix.wav")
        let (tmp, resp) = try await session.download(from: api("jobs/\(jobId)/stems/mix.wav"))
        try checkHTTP(resp, data: nil)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    // MARK: Santé
    func health() async -> BackendHealth? {
        var req = URLRequest(url: api("health"))
        req.timeoutInterval = 3
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(BackendHealth.self, from: data)
    }

    func ping() async -> Bool {
        guard let h = await health() else { return false }
        await MainActor.run { PythonRuntimeService.shared.runningVersion = h.version }
        return h.status == "ok"
    }

    // MARK: - Utilitaires
    private func checkHTTP(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode >= 400 else { return }
        var msg = "HTTP \(http.statusCode)"
        if let data {
            if let api = try? JSONDecoder().decode(APIErrorDetail.self, from: data),
               let detail = api.detail?.value {
                msg = detail
            } else if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                msg = String(raw.prefix(300))
            }
        }
        print("[StemDeck] ❌ Backend \(http.statusCode): \(msg)")
        throw BackendError(message: msg)
    }

    private func writeMultipart(to dest: URL, boundary: String, fileURL: URL, stemsJSON: String) throws {
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let out = try FileHandle(forWritingTo: dest)
        defer { try? out.close() }
        func write(_ s: String) { out.write(Data(s.utf8)) }

        write("--\(boundary)\r\n")
        write("Content-Disposition: form-data; name=\"stems\"\r\n\r\n")
        write("\(stemsJSON)\r\n")

        let name = fileURL.lastPathComponent.replacingOccurrences(of: "\"", with: "'")
        write("--\(boundary)\r\n")
        write("Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n")
        write("Content-Type: \(mimeType(for: fileURL.pathExtension))\r\n\r\n")
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            out.write(chunk)
        }
        write("\r\n--\(boundary)--\r\n")
    }

    private func stemCacheURL(jobId: String, name: String) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StemDeck/\(jobId)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "wav":        return "audio/wav"
        case "mp3":        return "audio/mpeg"
        case "m4a", "mp4": return "audio/mp4"
        case "flac":       return "audio/flac"
        case "ogg":        return "audio/ogg"
        case "opus":       return "audio/opus"
        default:           return "application/octet-stream"
        }
    }
}
