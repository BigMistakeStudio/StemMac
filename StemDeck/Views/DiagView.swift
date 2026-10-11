// Views/DiagView.swift — Diagnostic interactif
import SwiftUI
import Darwin

struct DiagView: View {
    @State private var log = ""
    @State private var running = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "stethoscope").foregroundColor(.orange)
                Text("Diagnostic").font(.headline).foregroundColor(.white)
                Spacer()
                Button("Diagnostic") { Task { await runDiag() } }
                    .buttonStyle(.borderedProminent).tint(.orange)
                    .disabled(running)
                Button("Test YouTube") { Task { await runYouTubeTest() } }
                    .buttonStyle(.borderedProminent).tint(.blue)
                    .disabled(running)
            }
            .padding(14).background(Color("BackgroundSecondary"))

            ScrollViewReader { proxy in
                ScrollView {
                    Text(log.isEmpty ? "Appuie sur Lancer…" : log)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(log.isEmpty ? .secondary : .green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).id("end")
                }
                .background(Color.black.opacity(0.6))
                .onChange(of: log) { _ in
                    withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 400)
        .background(Color("BackgroundPrimary"))
    }

    func add(_ line: String) {
        DispatchQueue.main.async { log += line + "\n" }
        print("[Diag] \(line)")
    }

    func runYouTubeTest() async {
        running = true
        log = ""
        add("=== Test YouTube Backend ===\n")
        let testURL = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
        add("POST /api/jobs url=\(testURL)\n")
        guard let url = URL(string: "http://127.0.0.1:8000/api/jobs") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "url": testURL, "stems": ["vocals"]
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let resp = String(data: data, encoding: .utf8) else {
            add("❌ Backend inaccessible"); running = false; return
        }
        add("Réponse: \(resp)")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobId = json["job_id"] as? String else {
            add("❌ Pas de job_id"); running = false; return
        }
        add("\nJob: \(jobId) — attente 30s…")
        // Poll every 2s for 30s
        for i in 1...15 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let jobURL = URL(string: "http://127.0.0.1:8000/api/jobs/\(jobId)")!
            if let (jobData, _) = try? await URLSession.shared.data(from: jobURL),
               let jobStr = String(data: jobData, encoding: .utf8) {
                add("[\(i*2)s] \(jobStr.prefix(300))")
                if jobStr.contains("\"done\"") || jobStr.contains("\"error\"") { break }
            }
        }
        add("\n=== Fin du test ===")
        running = false
    }

    func runDiag() async {
        running = true
        log = ""
        add("=== Diagnostic StemMac ===\n")

        // 1. Find ffmpeg
        add("── ffmpeg ──────────────────────────────")
        let ffmpegPaths = [
            PythonRuntimeService.shared.ffmpegBinURL.path,
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
        ]
        var foundFFmpeg: String? = nil
        for p in ffmpegPaths {
            let exists = access(p, X_OK) == 0
            add("  \(exists ? "✅" : "❌") \(p)")
            if exists && foundFFmpeg == nil { foundFFmpeg = p }
        }
        // which ffmpeg
        let whichOut = shell("/usr/bin/which", ["ffmpeg"])
        add("  which ffmpeg → \(whichOut.isEmpty ? "❌ introuvable" : whichOut)")
        if foundFFmpeg == nil && !whichOut.isEmpty { foundFFmpeg = whichOut }

        // 2. ffmpeg version
        if let ff = foundFFmpeg {
            let ver = shell(ff, ["-version"])
            let firstLine = ver.components(separatedBy: "\n").first ?? ""
            add("  version: \(firstLine)")
        } else {
            add("  ❌ ffmpeg ABSENT — installer via: brew install ffmpeg")
        }

        // 2b. ffprobe (requis par le backend pour lire la durée)
        if let fp = PythonRuntimeService.ffprobePath() {
            let ver = shell(fp, ["-version"]).components(separatedBy: "\n").first ?? ""
            add("  ✅ ffprobe: \(fp)")
            add("  version: \(ver)")
        } else {
            add("  ❌ ffprobe ABSENT — installer via: brew install ffmpeg")
        }

        // 3. Test M4A → MP3 conversion
        add("\n── Test conversion M4A → MP3 ──────────────")
        if let ff = foundFFmpeg {
            // Create a tiny test WAV with silence using ffmpeg itself
            let tmp = FileManager.default.temporaryDirectory
            let src = tmp.appendingPathComponent("test_stemdeck.wav")
            let dst = tmp.appendingPathComponent("test_stemdeck.mp3")
            // Generate 1s silence WAV
            let gen = shell(ff, [
                "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono",
                "-t", "1", src.path
            ])
            if FileManager.default.fileExists(atPath: src.path) {
                add("  ✅ Fichier test créé: \(src.path)")
                let conv = shellFull(ff, [
                    "-y", "-i", src.path,
                    "-codec:a", "libmp3lame", "-qscale:a", "2",
                    dst.path
                ])
                if FileManager.default.fileExists(atPath: dst.path) {
                    let size = (try? FileManager.default.attributesOfItem(atPath: dst.path)[.size] as? Int) ?? 0
                    add("  ✅ MP3 créé: \(dst.path) (\(size) bytes)")
                } else {
                    add("  ❌ Conversion échouée:")
                    add("  " + conv.suffix(500).description)
                }
            } else {
                add("  ❌ Impossible de créer le fichier test: \(gen.suffix(200))")
            }
        } else {
            add("  ⏭ Skipped (ffmpeg absent)")
        }

        // 4. yt-dlp
        add("\n── yt-dlp ──────────────────────────────────")
        let ytdlpPaths = [
            PythonRuntimeService.shared.repoURL.appendingPathComponent(".venv/bin/yt-dlp").path,
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
        ]
        var foundYtdlp: String? = nil
        for p in ytdlpPaths {
            let exists = access(p, X_OK) == 0
            add("  \(exists ? "✅" : "❌") \(p)")
            if exists && foundYtdlp == nil { foundYtdlp = p }
        }
        let whichYt = shell("/usr/bin/which", ["yt-dlp"])
        add("  which yt-dlp → \(whichYt.isEmpty ? "❌ introuvable" : whichYt)")
        if foundYtdlp == nil && !whichYt.isEmpty { foundYtdlp = whichYt }

        if let yt = foundYtdlp {
            let ver = shell(yt, ["--version"])
            add("  version: \(ver.trimmingCharacters(in: .whitespacesAndNewlines))")
            // Test with a short public video
            add("  Test téléchargement YouTube (vidéo courte)…")
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("yt_test_stemdeck.%(ext)s")
            let result = shellFull(yt, [
                "--no-playlist",
                "--format", "bestaudio[ext=m4a]/bestaudio/best",
                "--output", tmp.path,
                "--extractor-args", "youtube:player_client=ios,web",
                "--max-filesize", "10m",
                "--no-part",
                "https://www.youtube.com/watch?v=jNQXAC9IVRw"  // "Me at the zoo" — 19s
            ])
            add("  Sortie yt-dlp:")
            for line in result.components(separatedBy: "\n").filter({ !$0.isEmpty }) {
                add("    \(line)")
            }
        } else {
            add("  ❌ yt-dlp ABSENT")
        }

        // 5. Composants installés
        add("\n── Composants ──────────────────────────────")
        let rt = PythonRuntimeService.shared
        add("  Backend actif : \(rt.manifest.backendTag ?? "aucun") → \(rt.repoURL.path)")
        add("  Données       : \(rt.dataDirURL.path)")
        add("  Bibliothèque  : \(rt.jobsDirURL.path)")
        await rt.refreshStatus(checkRemote: true)
        for c in await MainActor.run(body: { rt.components }) {
            add("  \(c.state == .ok ? "✅" : "⚠️") \(c.id.title): \(c.installed ?? "—")"
                + (c.latest.map { " (dernière : \($0))" } ?? ""))
        }

        // 6. Backend log file
        add("\n── Logs backend (dernières lignes) ─────────")
        let logPath = PythonRuntimeService.shared.appSupportURL
            .appendingPathComponent("backend.log")
        if let logContent = try? String(contentsOf: logPath) {
            let lines = logContent.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let lastLines = lines.suffix(30)
            for line in lastLines { add("  \(line)") }
        } else {
            add("  (pas de log backend)")
        }

        // 7. Backend ping
        add("\n── Backend uvicorn ─────────────────────────")
        if let h = await BackendService.shared.health() {
            add("  ✅ http://127.0.0.1:8000 → moteur StemDeck \(h.version ?? "?")")
            add("     ffmpeg configuré : \(h.ffmpegConfigured == true ? "oui" : "non") · Demucs : \(h.demucsDevice ?? "?")")
        } else {
            add("  ❌ http://127.0.0.1:8000 → NON ACCESSIBLE")
        }


        add("\n=== Fin du diagnostic ===")
        running = false
    }

    @discardableResult
    func shell(_ exe: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = Pipe()
        try? p.run(); p.waitUntilExit()
        return (String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                       encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func shellFull(_ exe: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                      encoding: .utf8) ?? ""
    }
}
