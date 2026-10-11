// Services/PythonRuntimeService.swift
// Installation, gestion et mise à jour de TOUS les composants nécessaires au backend
// StemDeck (stemdeckapp/stemdeck), sans Homebrew ni Xcode CLT :
//
//   • FFmpeg + ffprobe   — builds statiques shaka-project (version + SHA256 épinglés,
//                          comme l'app officielle), evermeet en secours, Homebrew en dernier recours
//   • fpcalc             — Chromaprint (identification des morceaux, optionnel)
//   • QuickJS            — moteur JS pour le solveur YouTube de yt-dlp (optionnel)
//   • uv                 — gestionnaire Python (dernière release GitHub)
//   • Python 3.12        — installé et géré par uv
//   • Backend StemDeck   — dernière RELEASE GitHub (tag), installée côte à côte, bascule atomique
//   • Dépendances Python — `uv sync --frozen` : exactement les versions du uv.lock de la release
//   • yt-dlp             — mis à jour au-delà du lock (YouTube casse souvent les anciennes versions)
//   • Modèles IA         — pré-téléchargés via `python -m app.pipeline.warmup`
//
// Disposition sur disque (identique à l'app officielle pour data/ et les jobs) :
//   ~/Library/Application Support/StemDeck/
//       components.json           manifeste des versions installées
//       uv/uv                     binaire uv
//       python/                   CPython géré par uv
//       uv-cache/                 cache uv
//       backends/v0.20.0/         backend + .venv (une version par dossier)
//       data/                     STEMDECK_DATA_DIR (settings.json, models/, cache/, logs/)
//       data/ffmpeg/              ffmpeg, ffprobe, fpcalc (lus directement par le backend)
//       data/jsruntime/qjs        QuickJS (lu directement par le backend)
//       backend.log
//   ~/Documents/StemDeck/jobs/    bibliothèque (STEMDECK_DEFAULT_JOBS_DIR, comme l'app officielle)

import Foundation
import Darwin
import CryptoKit

// MARK: - Étapes affichées dans l'assistant de configuration
struct SetupStep {
    let icon:   String
    let title:  String
    let detail: String
}

let allSetupSteps: [SetupStep] = [
    SetupStep(icon: "waveform",             title: "FFmpeg",             detail: "Décodage / encodage audio (ffmpeg + ffprobe)"),
    SetupStep(icon: "wrench.and.screwdriver", title: "Outils audio",     detail: "Chromaprint (identification des morceaux)"),
    SetupStep(icon: "curlybraces",          title: "Moteur JavaScript",  detail: "QuickJS pour YouTube"),
    SetupStep(icon: "shippingbox",          title: "uv",                 detail: "Gestionnaire Python"),
    SetupStep(icon: "chevron.left.forwardslash.chevron.right", title: "Python", detail: "Python \(Pins.pythonVersion) géré par uv"),
    SetupStep(icon: "hammer",               title: "Outils de compilation", detail: "Optionnel — voix lead / chœurs (administrateur)"),
    SetupStep(icon: "arrow.down.circle",    title: "Moteur StemDeck",     detail: "Dernière version publiée + dépendances"),
    SetupStep(icon: "play.rectangle",       title: "yt-dlp",             detail: "Téléchargeur YouTube à jour"),
    SetupStep(icon: "brain",                title: "Modèles IA",         detail: "Demucs, rythme, sections, paroles"),
    SetupStep(icon: "play.circle.fill",     title: "Démarrage",          detail: "Lancement du serveur audio"),
]

// MARK: - Versions épinglées (mêmes binaires + SHA256 que l'app officielle StemDeck v0.20.0)
// Pour mettre à jour : changer la version ET tous les hashes ensemble.
enum Pins {
    static let backendRepo   = "stemdeckapp/stemdeck"
    static let pythonVersion = "3.12"

    // FFmpeg — shaka-project/static-ffmpeg-binaries (binaires bruts, par architecture)
    static let ffmpegVersion       = "8.1.2"
    static let shakaRelease        = "n8.1.2-1"
    static let shakaBase           = "https://github.com/shaka-project/static-ffmpeg-binaries/releases/download"
    static let shakaFFmpegArm64    = "e7b9fcd97f95f333512d6e8b8ac24d9dbc08f189f36047695499bd7b57214b22"
    static let shakaFFprobeArm64   = "ded4c698b8ff38d0bc1fd30fcc5e768dc46f58bc15a8dfd61f98615ba49cde5c"
    static let shakaFFmpegX64      = "62c87854d851f202fc4a29bdda0fe7b6ebcddd37b863482ce1bdc81151b03fe4"
    static let shakaFFprobeX64     = "d530823f480a3c7eb6334f18a00197d1e9f1070e86172b9aa89c4bf4022bd879"
    // Secours : evermeet.cx (x86_64, tourne sous Rosetta sur Apple Silicon)
    static let evermeetVersion     = "8.1.1"
    static let evermeetFFmpegZip   = "https://evermeet.cx/ffmpeg/ffmpeg-8.1.1.zip"
    static let evermeetFFprobeZip  = "https://evermeet.cx/ffmpeg/ffprobe-8.1.1.zip"
    static let evermeetFFmpegSha   = "4610988e2f54c243c50da73a09e4e2c36d9bb77546f9aa6c84cb328dcb1a98c1"
    static let evermeetFFprobeSha  = "aeade29dee3c3844e9bcc974f4ae4b29cc4f87994177d77003a8589fa531009e"

    // Chromaprint fpcalc (binaire universel)
    static let fpcalcVersion = "1.6.1"
    static let fpcalcURL     = "https://github.com/acoustid/chromaprint/releases/download/v1.6.1/chromaprint-fpcalc-1.6.1-macos-universal.tar.gz"
    static let fpcalcSha     = "240aeb5a8c8205af458e3625cb7487b826b711a999e491ef00111f3cebd76f00"

    // QuickJS-ng
    static let qjsVersion  = "0.16.2"
    static let qjsBase     = "https://github.com/quickjs-ng/quickjs/releases/download/v0.16.2"
    static let qjsArm64Sha = "f6200e9856c45578a5d42ac873a32f3f994b421e29df9f63b452d9c7145015fc"
    static let qjsX64Sha   = "4448991c0500dbe40c7b2f91ba39275995413aa4ee59db3b513b68350908a413"

    static var isArm64: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}

// MARK: - Manifeste des composants installés
struct InstallManifest: Codable {
    var backendTag:       String?   // ex. "v0.20.0"
    var ffmpegVersion:    String?   // version épinglée installée
    var fpcalcVersion:    String?
    var qjsVersion:       String?
    var modelsWarmedTag:  String?   // tag du backend pour lequel les modèles ont été préchargés
    var modelsFailed:     [String]?
    var skippedPackages:  [String]?  // paquets non installés faute de compilateur (ex. diffq)
    var lastUpdateCheck:  Date?
}

// MARK: - Composants (pour l'interface)
enum ComponentID: String, CaseIterable, Identifiable {
    case ffmpeg, fpcalc, jsRuntime, uv, python, compiler, backend, ytdlp, models
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ffmpeg:    return "FFmpeg + ffprobe"
        case .fpcalc:    return "Chromaprint (fpcalc)"
        case .jsRuntime: return "QuickJS"
        case .uv:        return "uv"
        case .python:    return "Python"
        case .compiler:  return "Outils de compilation"
        case .backend:   return "Moteur StemDeck"
        case .ytdlp:     return "yt-dlp"
        case .models:    return "Modèles IA"
        }
    }
    var subtitle: String {
        switch self {
        case .ffmpeg:    return "Lecture et conversion audio"
        case .fpcalc:    return "Identification des morceaux (optionnel)"
        case .jsRuntime: return "Solveur YouTube de yt-dlp (optionnel)"
        case .uv:        return "Gestionnaire Python"
        case .python:    return "Interpréteur géré par uv"
        case .compiler:  return "Outils Apple — requis pour la séparation voix lead / chœurs"
        case .backend:   return "stemdeckapp/stemdeck — dernière release"
        case .ytdlp:     return "Téléchargement YouTube / SoundCloud"
        case .models:    return "Demucs, rythme, sections, paroles"
        }
    }
    var icon: String {
        switch self {
        case .ffmpeg:    return "waveform"
        case .fpcalc:    return "wrench.and.screwdriver"
        case .jsRuntime: return "curlybraces"
        case .uv:        return "shippingbox"
        case .python:    return "chevron.left.forwardslash.chevron.right"
        case .compiler:  return "hammer"
        case .backend:   return "server.rack"
        case .ytdlp:     return "play.rectangle"
        case .models:    return "brain"
        }
    }
    var isOptional: Bool { [.fpcalc, .jsRuntime, .compiler, .models].contains(self) }
}

struct ComponentInfo: Identifiable, Equatable {
    enum State: Equatable {
        case unknown, checking, ok, missing, outdated, working, failed(String)
    }
    let id: ComponentID
    var installed: String? = nil
    var latest:    String? = nil
    var state:     State   = .unknown
}

// MARK: - PythonRuntimeService
final class PythonRuntimeService: ObservableObject {

    static let shared = PythonRuntimeService()

    @Published var isRunning:    Bool   = false
    @Published var setupLog:     String = ""
    @Published var components:   [ComponentInfo] = ComponentID.allCases.map { ComponentInfo(id: $0) }
    @Published var isBusy:       Bool   = false
    /// Une nouvelle version du backend est installée mais l'ancienne tourne encore.
    @Published var needsRestart: Bool   = false
    /// Version rapportée par /api/health du backend en cours.
    @Published var runningVersion: String? = nil

    private var backendProcess: Process?
    private var runningTag: String?
    private var port: Int = 8000
    private let opLock = NSLock()

    // MARK: Chemins
    var appSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StemDeck")
    }
    var manifestURL:   URL { appSupportURL.appendingPathComponent("components.json") }
    var uvBinURL:      URL { appSupportURL.appendingPathComponent("uv/uv") }
    var pythonDirURL:  URL { appSupportURL.appendingPathComponent("python") }
    var uvCacheURL:    URL { appSupportURL.appendingPathComponent("uv-cache") }
    var backendsURL:   URL { appSupportURL.appendingPathComponent("backends") }
    var dataDirURL:    URL { appSupportURL.appendingPathComponent("data") }
    var toolsDirURL:   URL { dataDirURL.appendingPathComponent("ffmpeg") }      // = FFMPEG_DIR du backend
    var jsRuntimeURL:  URL { dataDirURL.appendingPathComponent("jsruntime") }   // = JS_RUNTIME_DIR du backend
    var logFileURL:    URL { appSupportURL.appendingPathComponent("backend.log") }
    var jobsDirURL:    URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StemDeck/jobs")
    }

    var ffmpegBinURL:  URL { toolsDirURL.appendingPathComponent("ffmpeg") }
    var ffprobeBinURL: URL { toolsDirURL.appendingPathComponent("ffprobe") }
    var fpcalcBinURL:  URL { toolsDirURL.appendingPathComponent("fpcalc") }
    var qjsBinURL:     URL { jsRuntimeURL.appendingPathComponent("qjs") }

    /// Dossier du backend actif (dernière version installée avec succès).
    var repoURL: URL { backendURL(for: manifest.backendTag ?? "none") }
    func backendURL(for tag: String) -> URL { backendsURL.appendingPathComponent(tag) }
    var venvPythonURL: URL { repoURL.appendingPathComponent(".venv/bin/python") }

    // Anciennes installations (à migrer / nettoyer)
    private var legacyRepoURL:     URL { appSupportURL.appendingPathComponent("stemdeck") }
    private var legacySentinelURL: URL { appSupportURL.appendingPathComponent(".setup_complete") }
    private var legacyBinDirURL:   URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".stemdeck")
    }

    // MARK: Manifeste
    private(set) var manifest: InstallManifest = InstallManifest()

    private init() {
        // Le manifeste est écrit avec des dates ISO 8601 : il faut les relire de la même façon
        // (sinon le décodage échoue et l'app croit que rien n'est installé).
        if let data = try? Data(contentsOf: manifestURL) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            if let m = try? dec.decode(InstallManifest.self, from: data) {
                manifest = m
            } else if let m = try? JSONDecoder().decode(InstallManifest.self, from: data) {
                manifest = m
            }
        }
        recoverManifestIfNeeded()
    }

    /// Filet de sécurité : si le manifeste est absent ou illisible mais qu'un backend
    /// complet existe sur le disque, on le reprend au lieu de tout réinstaller.
    private func recoverManifestIfNeeded() {
        var changed = false
        if manifest.backendTag.map({ !isBackendReady($0) }) ?? true,
           let dirs = try? FileManager.default.contentsOfDirectory(atPath: backendsURL.path) {
            let ready = dirs.filter { isBackendReady($0) }
            if let best = ready.max(by: { Self.isNewer($1, than: $0) }) {
                manifest.backendTag = best
                changed = true
            }
        }
        if manifest.ffmpegVersion == nil,
           access(ffmpegBinURL.path, X_OK) == 0, access(ffprobeBinURL.path, X_OK) == 0 {
            manifest.ffmpegVersion = Pins.ffmpegVersion
            changed = true
        }
        if manifest.fpcalcVersion == nil, access(fpcalcBinURL.path, X_OK) == 0 {
            manifest.fpcalcVersion = Pins.fpcalcVersion; changed = true
        }
        if manifest.qjsVersion == nil, access(qjsBinURL.path, X_OK) == 0 {
            manifest.qjsVersion = Pins.qjsVersion; changed = true
        }
        if changed {
            saveManifest()
            print("[StemMac] Manifeste reconstruit depuis le disque (backend \(manifest.backendTag ?? "—"))")
        }
    }

    private func saveManifest() {
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(manifest) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    private func updateManifest(_ change: (inout InstallManifest) -> Void) {
        opLock.lock(); change(&manifest); opLock.unlock()
        saveManifest()
    }

    /// Prêt à démarrer : backend + venv + ffmpeg/ffprobe présents.
    var isInstalled: Bool {
        guard let tag = manifest.backendTag else { return false }
        return isBackendReady(tag) && ffmpegPath() != nil && ffprobePath() != nil
    }

    /// Une installation a déjà eu lieu (même incomplète) : on répare sans redemander.
    var hasPreviousInstall: Bool {
        manifest.backendTag != nil
            || FileManager.default.fileExists(atPath: backendsURL.path)
            || access(uvBinURL.path, X_OK) == 0
    }

    private func isBackendReady(_ tag: String) -> Bool {
        let dir = backendURL(for: tag)
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent(".stemdeck-ready").path)
            && access(dir.appendingPathComponent(".venv/bin/python").path, X_OK) == 0
    }

    // MARK: - Configuration complète (premier lancement / réparation)
    func runSetup(
        progressHandler: @escaping (String, String, Double) -> Void,
        completion:      @escaping (Bool, String?) -> Void
    ) {
        Task.detached(priority: .userInitiated) { [self] in
            func step(_ t: String, _ d: String, _ p: Double) {
                DispatchQueue.main.async { progressHandler(t, d, p) }
                self.printLog("[\(t)] \(d)")
            }
            setBusy(true)
            defer { setBusy(false) }
            do {
                try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
                migrateLegacyInstall()

                step("FFmpeg", "Vérification…", 0.02)
                try await ensureFFmpeg { step("FFmpeg", $0, 0.05) }
                step("FFmpeg", "✓ Prêt", 0.10)

                step("Outils audio", "Vérification…", 0.11)
                await ensureFpcalc { step("Outils audio", $0, 0.12) }
                step("Outils audio", "✓ Prêt", 0.14)

                step("Moteur JavaScript", "Vérification…", 0.15)
                await ensureQuickJS { step("Moteur JavaScript", $0, 0.16) }
                step("Moteur JavaScript", "✓ Prêt", 0.18)

                step("uv", "Vérification…", 0.19)
                try await ensureUv(update: false) { step("uv", $0, 0.20) }
                step("uv", "✓ Prêt", 0.24)

                step("Python", "Installation de Python \(Pins.pythonVersion)…", 0.25)
                try ensurePython { step("Python", $0, 0.27) }
                step("Python", "✓ Prêt", 0.30)

                step("Outils de compilation", "Vérification…", 0.305)
                // Optionnel : n'ouvre la fenêtre administrateur QUE si l'utilisateur l'a demandé.
                // Sans droits administrateur, StemMac s'installe et fonctionne quand même.
                let wantsTools = UserDefaults.standard.bool(forKey: Self.installCompilerKey)
                    && !UserDefaults.standard.bool(forKey: Self.compilerDeclinedKey)
                let compilerOK = ensureCompiler(interactive: wantsTools) {
                    step("Outils de compilation", $0, 0.307)
                }
                step("Outils de compilation", compilerOK ? "✓ Prêts" : "Non installés (optionnel)", 0.31)

                step("Moteur StemDeck", "Recherche de la dernière version…", 0.31)
                let tag = try await latestBackendTag()
                try await installBackend(tag: tag) { step("Moteur StemDeck", $0, 0.45) }
                step("Moteur StemDeck", "✓ \(tag) installé", 0.70)

                step("yt-dlp", "Mise à jour…", 0.71)
                await updateYtdlp { step("yt-dlp", $0, 0.72) }
                step("yt-dlp", "✓ Prêt", 0.74)

                step("Modèles IA", "Téléchargement (peut prendre plusieurs minutes)…", 0.75)
                warmupModels { step("Modèles IA", $0, 0.85) }
                step("Modèles IA", "✓ Prêts", 0.95)

                updateManifest { $0.lastUpdateCheck = Date() }
                step("Démarrage", "Configuration terminée ✓", 0.97)
                await refreshStatus(checkRemote: false)
                DispatchQueue.main.async { completion(true, nil) }
            } catch {
                printLog("❌ \(error.localizedDescription)")
                await refreshStatus(checkRemote: false)
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
            }
        }
    }

    // MARK: - Mises à jour (au démarrage, périodiquement, ou depuis les Réglages)
    /// Vérifie toutes les versions et met à jour ce qui est obsolète.
    /// Le dernier message envoyé contient « terminées ».
    func runUpdates(progressHandler: @escaping (String) -> Void) {
        guard manifest.backendTag != nil else { return }
        Task.detached(priority: .utility) { [self] in
            func log(_ msg: String) {
                printLog(msg)
                DispatchQueue.main.async { progressHandler(msg) }
            }
            guard tryBeginBusy() else { log("⏳ Une opération est déjà en cours"); return }
            defer { setBusy(false) }

            await refreshStatus(checkRemote: true)
            let snapshot = await MainActor.run { self.components }
            func state(_ id: ComponentID) -> ComponentInfo.State {
                snapshot.first { $0.id == id }?.state ?? .unknown
            }

            do {
                if state(.ffmpeg) != .ok {
                    log("🔄 FFmpeg…")
                    try await ensureFFmpeg { log("   \($0)") }
                }
                if state(.fpcalc) != .ok { await ensureFpcalc { log("   \($0)") } }
                if state(.jsRuntime) != .ok { await ensureQuickJS { log("   \($0)") } }
                if state(.uv) != .ok {
                    log("🔄 uv…")
                    try await ensureUv(update: true) { log("   \($0)") }
                }
                if state(.backend) != .ok || state(.python) != .ok {
                    let tag = try await latestBackendTag()
                    log("🔄 Moteur StemDeck \(tag)…")
                    try ensurePython { log("   \($0)") }
                    let incomplete = tag == manifest.backendTag && !(manifest.skippedPackages?.isEmpty ?? true)
                    if incomplete && isRunning {
                        log("ℹ️ Réinstallation complète au prochain arrêt du moteur")
                    } else {
                        try await installBackend(tag: tag, force: incomplete) { log("   \($0)") }
                    }
                    log("✅ Backend \(tag) installé")
                }
                if state(.ytdlp) != .ok || state(.backend) != .ok {
                    await updateYtdlp { log("   \($0)") }
                }
                if manifest.modelsWarmedTag != manifest.backendTag {
                    log("🔄 Modèles IA…")
                    warmupModels { log("   \($0)") }
                }
                updateManifest { $0.lastUpdateCheck = Date() }
            } catch {
                log("❌ \(error.localizedDescription)")
            }
            await refreshStatus(checkRemote: false)
            let restart = await MainActor.run { self.needsRestart }
            log(restart ? "✅ Mises à jour terminées — redémarrez le backend pour appliquer"
                        : "✅ Mises à jour terminées")
        }
    }

    /// Réinstalle / met à jour un seul composant.
    func repair(_ id: ComponentID, progressHandler: @escaping (String) -> Void = { _ in }) {
        Task.detached(priority: .userInitiated) { [self] in
            func log(_ msg: String) {
                printLog(msg)
                DispatchQueue.main.async { progressHandler(msg) }
            }
            guard tryBeginBusy() else { log("⏳ Une opération est déjà en cours"); return }
            defer { setBusy(false) }
            setState(id, .working)
            do {
                switch id {
                case .ffmpeg:
                    try? FileManager.default.removeItem(at: ffmpegBinURL)
                    try? FileManager.default.removeItem(at: ffprobeBinURL)
                    updateManifest { $0.ffmpegVersion = nil }
                    try await ensureFFmpeg(log)
                case .fpcalc:
                    try? FileManager.default.removeItem(at: fpcalcBinURL)
                    updateManifest { $0.fpcalcVersion = nil }
                    await ensureFpcalc(log)
                case .jsRuntime:
                    try? FileManager.default.removeItem(at: qjsBinURL)
                    updateManifest { $0.qjsVersion = nil }
                    await ensureQuickJS(log)
                case .uv:
                    try await ensureUv(update: true, log)
                case .python:
                    try ensurePython(log)
                    if let tag = manifest.backendTag {
                        try await installBackend(tag: tag, force: true, log)
                    }
                case .backend:
                    let tag = try await latestBackendTag()
                    let force = (tag == manifest.backendTag)   // même version → réinstallation propre
                    try await installBackend(tag: tag, force: force, log)
                    await updateYtdlp(log)
                case .compiler:
                    UserDefaults.standard.removeObject(forKey: Self.compilerDeclinedKey)
                    UserDefaults.standard.set(true, forKey: Self.installCompilerKey)
                    if ensureCompiler(interactive: true, log),
                       let tag = manifest.backendTag,
                       !(manifest.skippedPackages?.isEmpty ?? true) {
                        if isRunning && runningTag == tag {
                            log("ℹ️ Le moteur sera complété à la prochaine mise à jour (moteur en cours d'exécution)")
                        } else {
                            log("🔄 Réinstallation du moteur avec la séparation voix lead / chœurs…")
                            try await installBackend(tag: tag, force: true, log)
                        }
                    }
                case .ytdlp:
                    await updateYtdlp(log)
                case .models:
                    updateManifest { $0.modelsWarmedTag = nil }
                    warmupModels(log)
                }
                log("✅ \(id.title) : terminé")
            } catch {
                log("❌ \(id.title) : \(error.localizedDescription)")
            }
            await refreshStatus(checkRemote: id == .backend || id == .uv || id == .ytdlp)
        }
    }

    // MARK: - État des composants
    func refreshStatus(checkRemote: Bool) async {
        for id in ComponentID.allCases where currentState(id) != .working { setState(id, .checking) }

        // Versions distantes (best effort, en parallèle)
        var bl: String? = nil, ul: String? = nil, yl: String? = nil
        if checkRemote {
            bl = await latestGitHubTag(Pins.backendRepo)
            ul = await latestGitHubTag("astral-sh/uv")
            yl = await latestPyPIVersion("yt-dlp")
        }

        var infos: [ComponentID: ComponentInfo] = [:]

        // FFmpeg
        var ff = ComponentInfo(id: .ffmpeg, latest: Pins.ffmpegVersion)
        if let p = ffmpegPath(), ffprobePath() != nil {
            ff.installed = firstLine(of: (try? Self.run(p, ["-version"])) ?? "")
                .components(separatedBy: " ").dropFirst(2).first ?? "?"
            let ours = p == ffmpegBinURL.path
            ff.state = (!ours || manifest.ffmpegVersion == Pins.ffmpegVersion
                        || manifest.ffmpegVersion == Pins.evermeetVersion) ? .ok : .outdated
        } else { ff.state = .missing }
        infos[.ffmpeg] = ff

        // fpcalc
        var fp = ComponentInfo(id: .fpcalc, latest: Pins.fpcalcVersion)
        if access(fpcalcBinURL.path, X_OK) == 0 {
            fp.installed = manifest.fpcalcVersion ?? "?"
            fp.state = manifest.fpcalcVersion == Pins.fpcalcVersion ? .ok : .outdated
        } else if let sys = Self.which("fpcalc") {
            fp.installed = "système (\(sys))"; fp.state = .ok
        } else { fp.state = .missing }
        infos[.fpcalc] = fp

        // QuickJS
        var js = ComponentInfo(id: .jsRuntime, latest: Pins.qjsVersion)
        if access(qjsBinURL.path, X_OK) == 0 {
            js.installed = manifest.qjsVersion ?? "?"
            js.state = manifest.qjsVersion == Pins.qjsVersion ? .ok : .outdated
        } else { js.state = .missing }
        infos[.jsRuntime] = js

        // uv
        var uv = ComponentInfo(id: .uv, latest: ul)
        if access(uvBinURL.path, X_OK) == 0 {
            let out = (try? Self.run(uvBinURL.path, ["--version"])) ?? ""
            uv.installed = out.components(separatedBy: " ").dropFirst().first
            if let i = uv.installed, let l = ul, Self.isNewer(l, than: i) { uv.state = .outdated }
            else { uv.state = .ok }
        } else { uv.state = .missing }
        infos[.uv] = uv

        // Python + backend + yt-dlp (dans le venv du backend actif)
        var py = ComponentInfo(id: .python, latest: Pins.pythonVersion)
        var be = ComponentInfo(id: .backend, latest: bl)
        var yt = ComponentInfo(id: .ytdlp, latest: yl)
        if let tag = manifest.backendTag, isBackendReady(tag) {
            be.installed = (manifest.skippedPackages?.isEmpty ?? true)
                ? tag : "\(tag) (sans séparation voix lead / chœurs)"
            be.state = (bl.map { Self.isNewer($0, than: tag) } ?? false) ? .outdated : .ok
            // Installé sans diffq faute de compilateur, mais un compilateur est maintenant
            // disponible → « Mettre à jour » réinstalle avec la fonction complète.
            if !(manifest.skippedPackages?.isEmpty ?? true), usableCompilerEnv() != nil {
                be.state = .outdated
            }
            let pyOut = (try? Self.run(venvPythonURL.path, ["--version"])) ?? ""
            py.installed = pyOut.replacingOccurrences(of: "Python ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            py.state = (py.installed ?? "").hasPrefix(Pins.pythonVersion) ? .ok : .outdated
            let ytOut = (try? Self.run(venvPythonURL.path,
                ["-c", "import yt_dlp.version as v; print(v.__version__)"])) ?? ""
            yt.installed = ytOut.trimmingCharacters(in: .whitespacesAndNewlines)
            if yt.installed?.isEmpty ?? true { yt.installed = nil; yt.state = .missing }
            else if let l = yl, let i = yt.installed, Self.isNewer(l, than: i) { yt.state = .outdated }
            else { yt.state = .ok }
        } else {
            be.state = .missing; py.state = .missing; yt.state = .missing
        }
        infos[.python] = py; infos[.backend] = be; infos[.ytdlp] = yt

        // Modèles
        var mo = ComponentInfo(id: .models)
        if let warmed = manifest.modelsWarmedTag, warmed == manifest.backendTag {
            let failed = manifest.modelsFailed ?? []
            mo.installed = failed.isEmpty ? "préchargés" : "partiels (\(failed.joined(separator: ", ")))"
            mo.state = failed.isEmpty ? .ok : .outdated
        } else {
            mo.installed = "téléchargés au 1er usage"
            mo.state = .outdated
        }
        infos[.models] = mo

        // Outils de compilation
        var cc = ComponentInfo(id: .compiler)
        if usableCompilerEnv() != nil {
            cc.installed = FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
                && (try? Self.run("/usr/bin/xcode-select", ["-p"]))?.contains("Xcode.app") == true
                ? "Xcode" : "Command Line Tools"
            cc.state = .ok
        } else if FileManager.default.fileExists(atPath: "/Applications/Xcode.app") {
            cc.installed = "Xcode — licence non acceptée"
            cc.state = .outdated
        } else {
            cc.state = .missing
        }
        infos[.compiler] = cc

        let tagNow = manifest.backendTag
        await MainActor.run {
            for (i, c) in self.components.enumerated() {
                if c.state == .working { continue }
                if var n = infos[c.id] {
                    // conserver la dernière version connue si on n'a pas interrogé le réseau
                    if !checkRemote { n.latest = n.latest ?? c.latest }
                    self.components[i] = n
                }
            }
            self.needsRestart = self.isRunning && self.runningTag != nil && self.runningTag != tagNow
        }
    }

    private func currentState(_ id: ComponentID) -> ComponentInfo.State {
        if Thread.isMainThread { return components.first { $0.id == id }?.state ?? .unknown }
        return DispatchQueue.main.sync { components.first { $0.id == id }?.state ?? .unknown }
    }

    private func setState(_ id: ComponentID, _ state: ComponentInfo.State) {
        DispatchQueue.main.async {
            if let i = self.components.firstIndex(where: { $0.id == id }) {
                self.components[i].state = state
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        opLock.lock(); _busy = busy; opLock.unlock()
        DispatchQueue.main.async { self.isBusy = busy }
    }
    private var _busy = false
    private func tryBeginBusy() -> Bool {
        opLock.lock(); defer { opLock.unlock() }
        if _busy { return false }
        _busy = true
        DispatchQueue.main.async { self.isBusy = true }
        return true
    }

    // MARK: - FFmpeg + ffprobe
    private func ensureFFmpeg(_ log: (String) -> Void) async throws {
        let haveOurs = access(ffmpegBinURL.path, X_OK) == 0 && access(ffprobeBinURL.path, X_OK) == 0
        if haveOurs && (manifest.ffmpegVersion == Pins.ffmpegVersion
                        || manifest.ffmpegVersion == Pins.evermeetVersion) { return }
        try FileManager.default.createDirectory(at: toolsDirURL, withIntermediateDirectories: true)

        // 1. shaka-project (natif arm64 / x86_64)
        let arch = Pins.isArm64 ? "arm64" : "x64"
        let (ffSha, fpSha) = Pins.isArm64
            ? (Pins.shakaFFmpegArm64, Pins.shakaFFprobeArm64)
            : (Pins.shakaFFmpegX64, Pins.shakaFFprobeX64)
        log("Téléchargement FFmpeg \(Pins.ffmpegVersion) (\(arch))…")
        do {
            try await installRawBinary(
                url: "\(Pins.shakaBase)/\(Pins.shakaRelease)/ffmpeg-osx-\(arch)",
                sha256: ffSha, to: ffmpegBinURL)
            try await installRawBinary(
                url: "\(Pins.shakaBase)/\(Pins.shakaRelease)/ffprobe-osx-\(arch)",
                sha256: fpSha, to: ffprobeBinURL)
            updateManifest { $0.ffmpegVersion = Pins.ffmpegVersion }
            log("✅ FFmpeg \(Pins.ffmpegVersion) installé")
            return
        } catch {
            log("⚠️ Source principale indisponible (\(error.localizedDescription)) — essai evermeet.cx")
        }

        // 2. evermeet.cx (zip, x86_64)
        do {
            try await installZippedBinary(named: "ffmpeg", url: Pins.evermeetFFmpegZip,
                                          sha256: Pins.evermeetFFmpegSha, to: ffmpegBinURL)
            try await installZippedBinary(named: "ffprobe", url: Pins.evermeetFFprobeZip,
                                          sha256: Pins.evermeetFFprobeSha, to: ffprobeBinURL)
            updateManifest { $0.ffmpegVersion = Pins.evermeetVersion }
            log("✅ FFmpeg \(Pins.evermeetVersion) installé (evermeet)")
            return
        } catch {
            log("⚠️ evermeet.cx indisponible (\(error.localizedDescription))")
        }

        // 3. FFmpeg système (Homebrew / MacPorts) — utilisé via STEMDECK_FFMPEG/FFPROBE
        if ffmpegPath() != nil && ffprobePath() != nil {
            log("✅ FFmpeg système utilisé : \(ffmpegPath()!)")
            return
        }
        throw SetupError("FFmpeg n'a pas pu être téléchargé.\nVérifiez votre connexion internet, ou installez-le avec : brew install ffmpeg")
    }

    // MARK: - fpcalc (optionnel)
    private func ensureFpcalc(_ log: (String) -> Void) async {
        if access(fpcalcBinURL.path, X_OK) == 0 && manifest.fpcalcVersion == Pins.fpcalcVersion { return }
        do {
            try FileManager.default.createDirectory(at: toolsDirURL, withIntermediateDirectories: true)
            log("Téléchargement Chromaprint \(Pins.fpcalcVersion)…")
            try await installArchivedBinary(named: "fpcalc", url: Pins.fpcalcURL,
                                            sha256: Pins.fpcalcSha, to: fpcalcBinURL)
            updateManifest { $0.fpcalcVersion = Pins.fpcalcVersion }
            log("✅ fpcalc installé")
        } catch {
            log("⚠️ fpcalc non installé (identification des morceaux désactivée) : \(error.localizedDescription)")
        }
    }

    // MARK: - QuickJS (optionnel)
    private func ensureQuickJS(_ log: (String) -> Void) async {
        if access(qjsBinURL.path, X_OK) == 0 && manifest.qjsVersion == Pins.qjsVersion { return }
        do {
            try FileManager.default.createDirectory(at: jsRuntimeURL, withIntermediateDirectories: true)
            let asset = Pins.isArm64 ? "qjs-darwin-arm64" : "qjs-darwin-x86_64"
            log("Téléchargement QuickJS \(Pins.qjsVersion)…")
            try await installRawBinary(url: "\(Pins.qjsBase)/\(asset)",
                                       sha256: Pins.isArm64 ? Pins.qjsArm64Sha : Pins.qjsX64Sha,
                                       to: qjsBinURL, versionArgs: nil)
            updateManifest { $0.qjsVersion = Pins.qjsVersion }
            log("✅ QuickJS installé")
        } catch {
            log("⚠️ QuickJS non installé (certaines vidéos YouTube peuvent échouer) : \(error.localizedDescription)")
        }
    }

    // MARK: - uv
    private func ensureUv(update: Bool, _ log: (String) -> Void) async throws {
        let exists = access(uvBinURL.path, X_OK) == 0
        if exists && !update { return }

        let latest = await latestGitHubTag("astral-sh/uv")
        if exists, let latest {
            let out = (try? Self.run(uvBinURL.path, ["--version"])) ?? ""
            let current = out.components(separatedBy: " ").dropFirst().first ?? ""
            if !Self.isNewer(latest, than: current) { return }
            log("Mise à jour de uv \(current) → \(latest)…")
        } else {
            log("Téléchargement de uv…")
        }

        let platform = Pins.isArm64 ? "aarch64-apple-darwin" : "x86_64-apple-darwin"
        let urlStr = latest.map {
            "https://github.com/astral-sh/uv/releases/download/\($0)/uv-\(platform).tar.gz"
        } ?? "https://github.com/astral-sh/uv/releases/latest/download/uv-\(platform).tar.gz"

        let staged = uvBinURL.deletingLastPathComponent().appendingPathComponent("uv.new")
        do {
            try await installArchivedBinary(named: "uv", url: urlStr, sha256: nil, to: staged)
            try? FileManager.default.removeItem(at: uvBinURL)
            try FileManager.default.moveItem(at: staged, to: uvBinURL)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            if exists { log("⚠️ uv non mis à jour : \(error.localizedDescription)"); return }
            throw SetupError("Impossible de télécharger uv : \(error.localizedDescription)")
        }
        log("✅ uv \(latest ?? "") prêt")
    }

    // MARK: - Python (géré par uv)
    private func ensurePython(_ log: @escaping (String) -> Void) throws {
        try Self.run(uvBinURL.path, ["python", "install", Pins.pythonVersion],
                     env: uvEnv(), onLine: { log($0) })
    }

    // MARK: - Backend StemDeck (release GitHub)
    /// Dernière release publiée (pas `main`) : ex. "v0.20.0".
    func latestBackendTag() async throws -> String {
        if let tag = await latestGitHubTag(Pins.backendRepo) { return tag }
        if let current = manifest.backendTag { return current }
        throw SetupError("Impossible de déterminer la dernière version de StemDeck (GitHub inaccessible).")
    }

    /// Installe `tag` dans backends/<tag>/ puis l'active. L'ancienne version reste en place
    /// (et continue de tourner) jusqu'au prochain démarrage du backend.
    private func installBackend(tag: String, force: Bool = false, _ log: @escaping (String) -> Void) async throws {
        let dir = backendURL(for: tag)
        if !force && isBackendReady(tag) {
            if manifest.backendTag != tag { updateManifest { $0.backendTag = tag } }
            log("Backend \(tag) déjà installé")
            return
        }
        if force && runningTag == tag && isRunning {
            throw SetupError("Arrêtez le backend avant de réinstaller la version en cours (\(tag)).")
        }

        try FileManager.default.createDirectory(at: backendsURL, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dir)

        // 1. Sources de la release (tarball du tag)
        log("Téléchargement de StemDeck \(tag)…")
        let tarball = try await download("https://github.com/\(Pins.backendRepo)/archive/refs/tags/\(tag).tar.gz")
        defer { try? FileManager.default.removeItem(at: tarball) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try Self.run("/usr/bin/tar", ["xzf", tarball.path, "--strip-components=1", "-C", dir.path])
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw SetupError("Archive du backend illisible : \(error.localizedDescription)")
        }
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("uv.lock").path) else {
            try? FileManager.default.removeItem(at: dir)
            throw SetupError("Archive du backend incomplète (uv.lock absent).")
        }

        // 2. Dépendances exactement comme dans uv.lock (torch, demucs… épinglés par le projet)
        log("Installation des dépendances Python (plusieurs minutes la première fois)…")
        var env = uvEnv()
        // hatch-vcs dérive la version du tag git ; sans dépôt git on la lui fournit.
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        env["SETUPTOOLS_SCM_PRETEND_VERSION"] = version
        env["SETUPTOOLS_SCM_PRETEND_VERSION_FOR_STEMDECK"] = version
        // Sur Apple Silicon, un seul paquet n'existe pas en version précompilée pour
        // Python 3.12 : `diffq` (requis uniquement par `audio-separator`, la séparation
        // optionnelle voix lead / chœurs). Il faut donc un compilateur C. S'il n'y en a pas
        // d'utilisable (outils absents, licence Xcode non acceptée…), on installe tout le
        // reste et seule cette fonction optionnelle est désactivée.
        let compiler = usableCompilerEnv()
        if let compiler { compiler.forEach { env[$0.key] = $0.value } }
        let optionalNative = ["diffq", "audio-separator"]

        var lastLines: [String] = []
        func sync(skipping: [String]) throws {
            var args = ["sync", "--frozen", "--python", Pins.pythonVersion]
            for pkg in skipping { args += ["--no-install-package", pkg] }
            lastLines = []
            try Self.run(uvBinURL.path, args, cwd: dir, env: env, onLine: { line in
                lastLines.append(line); if lastLines.count > 15 { lastLines.removeFirst() }
                if line.contains("Installed") || line.contains("Prepared") || line.contains("Resolved") {
                    log(line.trimmingCharacters(in: .whitespaces))
                }
            })
        }

        var skipped: [String] = []
        do {
            if compiler == nil {
                log("ℹ️ Aucun compilateur utilisable : la séparation voix lead / chœurs sera désactivée")
                skipped = optionalNative
            }
            do {
                try sync(skipping: skipped)
            } catch where skipped.isEmpty {
                // Compilateur présent mais la compilation a échoué : on réessaie sans ces paquets
                log("⚠️ Compilation de diffq impossible — installation sans la séparation voix lead / chœurs")
                skipped = optionalNative
                try sync(skipping: skipped)
            }
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw SetupError("uv sync a échoué pour \(tag) :\n" + lastLines.joined(separator: "\n"))
        }
        updateManifest { $0.skippedPackages = skipped.isEmpty ? nil : skipped }

        // 3. Vérification : le backend s'importe
        do {
            try Self.run(dir.appendingPathComponent(".venv/bin/python").path,
                         ["-c", "import app.main"], cwd: dir, env: backendEnv())
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw SetupError("Le backend \(tag) ne démarre pas : \(error.localizedDescription)")
        }

        FileManager.default.createFile(atPath: dir.appendingPathComponent(".stemdeck-ready").path,
                                       contents: Data(tag.utf8))
        updateManifest { $0.backendTag = tag }
        log("✅ Backend \(tag) prêt")
        DispatchQueue.main.async {
            self.needsRestart = self.isRunning && self.runningTag != nil && self.runningTag != tag
        }
    }

    static let compilerDeclinedKey = "compilerToolsDeclined"
    /// Choix de l'utilisateur (case à cocher de l'assistant) — désactivé par défaut.
    static let installCompilerKey  = "installCompilerTools"

    /// Rend un compilateur utilisable, avec UNE fenêtre de mot de passe macOS au plus :
    ///  • Xcode présent, licence non acceptée → `xcodebuild -license accept`
    ///  • aucun outil → installation silencieuse des Command Line Tools via `softwareupdate`
    ///    (méthode de l'installeur Homebrew), sinon fenêtre Apple `xcode-select --install`.
    /// Annuler le mot de passe n'est jamais bloquant : la fonction optionnelle est désactivée.
    @discardableResult
    func ensureCompiler(interactive: Bool, _ log: (String) -> Void) -> Bool {
        if usableCompilerEnv() != nil { return true }
        guard interactive else {
            log("Outils de compilation absents (non demandés)")
            return false
        }

        let xcode = "/Applications/Xcode.app"
        if FileManager.default.fileExists(atPath: xcode) {
            // Cas 1 : Xcode installé, licence jamais acceptée
            log("Acceptation de la licence Xcode (mot de passe administrateur)…")
            let ok = runAsAdmin(
                "/usr/bin/xcodebuild -license accept",
                prompt: "StemMac doit accepter en votre nom la licence Xcode et Apple SDKs (déjà installés) pour compiler un composant audio optionnel.")
            if ok, usableCompilerEnv() != nil {
                log("✅ Licence Xcode acceptée")
                return true
            }
            if !ok { return declined(log) }
            // licence acceptée mais toujours inutilisable → on tente les Command Line Tools
        }

        // Cas 2 : installer les Command Line Tools sans interface (≈ 1 Go)
        log("Recherche des Outils de ligne de commande Apple…")
        let flag = "/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
        FileManager.default.createFile(atPath: flag, contents: nil)
        defer { try? FileManager.default.removeItem(atPath: flag) }
        let listing = (try? Self.run("/usr/sbin/softwareupdate", ["--list"])) ?? ""
        let label = listing
            .components(separatedBy: "\n")
            .compactMap { line -> String? in
                guard let r = line.range(of: "Label: ") else { return nil }
                let l = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                return l.hasPrefix("Command Line Tools") ? l : nil
            }
            .max { Self.isNewer($1, than: $0) }

        if let label {
            log("Installation de \(label) (plusieurs minutes, mot de passe administrateur)…")
            let quoted = "'" + label.replacingOccurrences(of: "'", with: "'\\''") + "'"
            let ok = runAsAdmin(
                "/usr/sbin/softwareupdate --install \(quoted) --agree-to-license",
                prompt: "StemMac doit installer les Outils de ligne de commande Apple pour compiler un composant audio optionnel.")
            if !ok && usableCompilerEnv() == nil { return declined(log) }
        } else {
            // Repli : la fenêtre d'installation d'Apple ; on attend jusqu'à 20 min
            log("Ouverture de l'installeur Apple — suivez la fenêtre qui s'affiche…")
            _ = try? Self.run("/usr/bin/xcode-select", ["--install"])
            let deadline = Date().addingTimeInterval(20 * 60)
            while usableCompilerEnv() == nil && Date() < deadline {
                Thread.sleep(forTimeInterval: 10)
            }
        }

        if usableCompilerEnv() != nil {
            log("✅ Outils de compilation installés")
            return true
        }
        log("⚠️ Outils de compilation indisponibles — séparation voix lead / chœurs désactivée")
        return false
    }

    private func declined(_ log: (String) -> Void) -> Bool {
        UserDefaults.standard.set(true, forKey: Self.compilerDeclinedKey)
        log("Annulé — séparation voix lead / chœurs désactivée (réactivable dans Réglages › Composants)")
        return false
    }

    /// Lance une commande avec les droits administrateur via la fenêtre de mot de passe macOS.
    /// Renvoie false si l'utilisateur annule ou si la commande échoue.
    private func runAsAdmin(_ command: String, prompt: String) -> Bool {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = "do shell script \"\(esc(command))\" with prompt \"\(esc(prompt))\" with administrator privileges"
        do {
            try Self.run("/usr/bin/osascript", ["-e", script])
            return true
        } catch {
            printLog("Commande administrateur non exécutée : \(error.localizedDescription)")
            return false
        }
    }

    /// Environnement permettant de compiler une extension C, ou nil s'il n'y en a pas.
    /// - Outils Xcode/CLT sélectionnés et licence acceptée → environnement tel quel
    /// - Xcode installé mais licence non acceptée → on bascule sur les Command Line Tools
    ///   (DEVELOPER_DIR), qui n'exigent pas cette licence
    /// Ne lance jamais `cc` si aucun outil n'est installé (évite la fenêtre d'installation macOS).
    private func usableCompilerEnv() -> [String: String]? {
        func works(_ extra: [String: String]) -> Bool {
            var env = baseEnv()
            extra.forEach { env[$0.key] = $0.value }
            return (try? Self.run("/usr/bin/xcrun", ["--find", "clang"], env: env)) != nil
                && (try? Self.run("/usr/bin/cc", ["--version"], env: env)) != nil
        }
        let clt = "/Library/Developer/CommandLineTools"
        let hasCLT = FileManager.default.fileExists(atPath: clt + "/usr/bin/clang")
        let selected = (try? Self.run("/usr/bin/xcode-select", ["-p"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !selected.isEmpty && FileManager.default.fileExists(atPath: selected) && works([:]) {
            return [:]
        }
        if hasCLT && works(["DEVELOPER_DIR": clt]) {
            return ["DEVELOPER_DIR": clt]
        }
        return nil
    }

    /// Supprime les versions de backend qui ne sont ni l'active ni celle en cours d'exécution.
    private func cleanupOldBackends() {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: backendsURL, includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent != manifest.backendTag
                             && item.lastPathComponent != runningTag {
            try? FileManager.default.removeItem(at: item)
            printLog("🧹 Ancien backend supprimé : \(item.lastPathComponent)")
        }
    }

    // MARK: - yt-dlp (au-delà du lock : YouTube change souvent)
    private func updateYtdlp(_ log: (String) -> Void) async {
        guard isBackendReady(manifest.backendTag ?? "") else { return }
        do {
            try Self.run(uvBinURL.path,
                         ["pip", "install", "--python", venvPythonURL.path, "--upgrade", "yt-dlp"],
                         cwd: repoURL, env: uvEnv())
            let v = (try? Self.run(venvPythonURL.path,
                        ["-c", "import yt_dlp.version as v; print(v.__version__)"])) ?? ""
            log("✅ yt-dlp \(v.trimmingCharacters(in: .whitespacesAndNewlines))")
        } catch {
            log("⚠️ yt-dlp non mis à jour : \(error.localizedDescription)")
        }
    }

    // MARK: - Modèles IA (préchargement, non bloquant)
    private func warmupModels(_ log: @escaping (String) -> Void) {
        guard let tag = manifest.backendTag, isBackendReady(tag) else { return }
        var failed: [String] = []
        do {
            try Self.run(venvPythonURL.path, ["-m", "app.pipeline.warmup"],
                         cwd: repoURL, env: backendEnv(), onLine: { line in
                if line.hasPrefix("WARMUP_OK ") {
                    log("✓ \(line.dropFirst("WARMUP_OK ".count))")
                } else if line.hasPrefix("WARMUP_FAILED ") {
                    let rest = line.dropFirst("WARMUP_FAILED ".count)
                    let name = rest.split(separator: " ").first.map(String.init) ?? String(rest)
                    failed.append(name)
                    log("⚠️ \(rest)")
                }
            })
        } catch {
            log("⚠️ Préchargement des modèles interrompu : \(error.localizedDescription)")
            if failed.isEmpty { failed = ["warmup"] }
        }
        updateManifest { $0.modelsWarmedTag = tag; $0.modelsFailed = failed }
    }

    // MARK: - Migration de l'ancienne installation (clone git + ~/.stemdeck)
    private func migrateLegacyInstall() {
        let fm = FileManager.default

        // 1. Bibliothèque : ancien JOBS_DIR = <clone>/jobs → ~/Documents/StemDeck/jobs
        let oldJobs = legacyRepoURL.appendingPathComponent("jobs")
        if let items = try? fm.contentsOfDirectory(at: oldJobs, includingPropertiesForKeys: nil),
           !items.isEmpty {
            try? fm.createDirectory(at: jobsDirURL, withIntermediateDirectories: true)
            var moved = 0
            for item in items {
                let dest = jobsDirURL.appendingPathComponent(item.lastPathComponent)
                if !fm.fileExists(atPath: dest.path), (try? fm.moveItem(at: item, to: dest)) != nil {
                    moved += 1
                }
            }
            printLog("📦 Bibliothèque migrée : \(moved) élément(s) → \(jobsDirURL.path)")
        }
        // Réglages de l'ancien backend
        let oldSettings = legacyRepoURL.appendingPathComponent("settings.json")
        let newSettings = dataDirURL.appendingPathComponent("settings.json")
        if fm.fileExists(atPath: oldSettings.path) && !fm.fileExists(atPath: newSettings.path) {
            try? fm.createDirectory(at: dataDirURL, withIntermediateDirectories: true)
            try? fm.copyItem(at: oldSettings, to: newSettings)
        }

        // 2. Ancien clone : supprimé seulement si la bibliothèque est vide/migrée
        let jobsLeft = (try? fm.contentsOfDirectory(atPath: oldJobs.path))?.isEmpty ?? true
        if fm.fileExists(atPath: legacyRepoURL.path) && jobsLeft {
            try? fm.removeItem(at: legacyRepoURL)
            printLog("🧹 Ancien clone git supprimé")
        }
        try? fm.removeItem(at: legacySentinelURL)

        // 3. Ancien dossier ~/.stemdeck (Node.js, ffmpeg sans ffprobe) — créé uniquement par cette app
        if fm.fileExists(atPath: legacyBinDirURL.path) {
            try? fm.removeItem(at: legacyBinDirURL)
            printLog("🧹 ~/.stemdeck supprimé (Node.js et ancien ffmpeg)")
        }

        // 4. Config yt-dlp GLOBALE écrite par l'ancienne version (affectait tout yt-dlp du Mac)
        let cfg = fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/yt-dlp/config")
        if let content = try? String(contentsOf: cfg, encoding: .utf8),
           content.contains("written by StemDeck") {
            try? fm.removeItem(at: cfg)
            printLog("🧹 ~/.config/yt-dlp/config (écrit par une ancienne version) supprimé")
        }
    }

    // MARK: - Démarrer / arrêter le backend
    func startBackend(port: Int = 8000) {
        self.port = port
        guard !isRunning else { return }
        guard let tag = manifest.backendTag, isBackendReady(tag) else {
            printLog("⚠️ Backend non installé — configuration requise")
            return
        }

        // Libère le port (ancienne instance éventuelle)
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/bin/sh")
        killer.arguments = ["-c", "lsof -ti tcp:\(port) -sTCP:LISTEN | xargs kill 2>/dev/null; sleep 0.5; " +
                                  "lsof -ti tcp:\(port) -sTCP:LISTEN | xargs kill -9 2>/dev/null; true"]
        try? killer.run(); killer.waitUntilExit()

        runningTag = nil
        cleanupOldBackends()

        try? FileManager.default.createDirectory(at: dataDirURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: jobsDirURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        let logHandle = try? FileHandle(forWritingTo: logFileURL)

        let process = Process()
        process.executableURL       = venvPythonURL
        process.arguments           = ["-m", "uvicorn", "app.main:app",
                                       "--host", "127.0.0.1", "--port", "\(port)",
                                       "--timeout-graceful-shutdown", "2"]
        process.currentDirectoryURL = repoURL
        process.environment         = backendEnv()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let d = fh.availableData
            guard !d.isEmpty else { fh.readabilityHandler = nil; return }
            logHandle?.write(d)
            guard let text = String(data: d, encoding: .utf8) else { return }
            AppLogger.shared.log(text, level: .info)
            DispatchQueue.main.async {
                guard let self else { return }
                self.setupLog += text
                if self.setupLog.count > 200_000 { self.setupLog = String(self.setupLog.suffix(100_000)) }
            }
        }
        process.terminationHandler = { [weak self] _ in
            try? logHandle?.close()
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.runningTag = nil
                self?.runningVersion = nil
            }
        }

        do {
            try process.run()
            backendProcess = process
            runningTag = tag
            DispatchQueue.main.async {
                self.isRunning = true
                self.needsRestart = false
            }
            printLog("✅ Backend \(tag) → http://127.0.0.1:\(port)")
        } catch {
            printLog("❌ \(error.localizedDescription)")
        }
    }

    func stopBackend() {
        guard let p = backendProcess else { return }
        p.terminate()
        // uvicorn s'arrête en ~2 s (--timeout-graceful-shutdown) ; sinon on force.
        let deadline = Date().addingTimeInterval(4)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        backendProcess = nil
        runningTag = nil
        DispatchQueue.main.async { self.isRunning = false }
    }

    func restartBackend() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.stopBackend()
            Thread.sleep(forTimeInterval: 0.5)
            self.startBackend(port: self.port)
        }
    }

    // MARK: - Environnements
    private func uvEnv() -> [String: String] {
        var env = baseEnv()
        env["UV_PYTHON_INSTALL_DIR"] = pythonDirURL.path
        env["UV_CACHE_DIR"]          = uvCacheURL.path
        env["UV_PYTHON_PREFERENCE"]  = "only-managed"   // jamais un Python système exotique
        env["UV_NO_PROGRESS"]        = "1"
        return env
    }

    func backendEnv() -> [String: String] {
        var env = baseEnv()
        env["PATH"] = ([repoURL.appendingPathComponent(".venv/bin").path,
                        toolsDirURL.path, jsRuntimeURL.path] + (env["PATH"] ?? "")
                        .split(separator: ":").map(String.init)).joined(separator: ":")
        env["STEMDECK_DATA_DIR"]         = dataDirURL.path
        env["STEMDECK_DEFAULT_JOBS_DIR"] = jobsDirURL.path
        env["STEMDECK_PERSIST_LIBRARY"]  = "1"       // sinon les morceaux sont supprimés après 24 h
        env["STEMDECK_DESKTOP"]          = "1"
        env["STEMDECK_PARENT_PID"]       = String(getpid())   // le backend s'arrête si l'app meurt
        env["TORCH_HOME"]                = dataDirURL.appendingPathComponent("models/torch").path
        env["XDG_CACHE_HOME"]            = dataDirURL.appendingPathComponent("cache").path
        env["PYTHONUNBUFFERED"]          = "1"
        env["PYTHONUTF8"]                = "1"
        // FFmpeg hors du dossier data (secours Homebrew) : on le désigne explicitement
        if let ff = ffmpegPath(), let fp = ffprobePath(), ff != ffmpegBinURL.path {
            env["STEMDECK_FFMPEG"]  = ff
            env["STEMDECK_FFPROBE"] = fp
        }
        // Réglages de l'app
        let d = UserDefaults.standard
        if let device = d.string(forKey: "demucsDevice"), ["mps", "cpu"].contains(device) {
            env["STEMDECK_DEMUCS_DEVICE"] = device
        }
        let maxDur = d.integer(forKey: "maxDuration")
        if maxDur >= 60 { env["STEMDECK_MAX_DURATION_SEC"] = String(maxDur) }
        return env
    }

    private func baseEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Une app lancée depuis le Finder hérite d'un PATH minimal
        let path = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin", "/usr/local/bin"]
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        env["PATH"] = (existing + path.filter { !existing.contains($0) }).joined(separator: ":")
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        env["USER"] = ProcessInfo.processInfo.userName
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        // Ne jamais hériter d'un venv/Python de l'environnement de lancement (Xcode, Terminal)
        for k in ["VIRTUAL_ENV", "PYTHONHOME", "PYTHONPATH", "CONDA_PREFIX"] { env.removeValue(forKey: k) }
        return env
    }

    // MARK: - Recherche des binaires
    func ffmpegPath() -> String? {
        if access(ffmpegBinURL.path, X_OK) == 0 { return ffmpegBinURL.path }
        return ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg"]
            .first { access($0, X_OK) == 0 }
    }
    static func ffmpegPath() -> String? { shared.ffmpegPath() }

    func ffprobePath() -> String? {
        if access(ffprobeBinURL.path, X_OK) == 0 { return ffprobeBinURL.path }
        if let ff = ffmpegPath() {
            let sibling = URL(fileURLWithPath: ff).deletingLastPathComponent()
                .appendingPathComponent("ffprobe").path
            if access(sibling, X_OK) == 0 { return sibling }
        }
        return ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/opt/local/bin/ffprobe"]
            .first { access($0, X_OK) == 0 }
    }
    static func ffprobePath() -> String? { shared.ffprobePath() }

    static func which(_ cmd: String) -> String? {
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/bin"]
        return dirs.map { "\($0)/\(cmd)" }.first { access($0, X_OK) == 0 }
    }
    static func hasCommand(_ cmd: String) -> Bool { which(cmd) != nil }

    // MARK: - Réseau
    private static let userAgent = "StemMac"

    /// Télécharge dans un fichier temporaire.
    private func download(_ urlStr: String) async throws -> URL {
        guard let url = URL(string: urlStr) else { throw SetupError("URL invalide : \(urlStr)") }
        var req = URLRequest(url: url, timeoutInterval: 120)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (tmp, resp) = try await URLSession.shared.download(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            try? FileManager.default.removeItem(at: tmp)
            throw SetupError("HTTP \(http.statusCode) pour \(url.lastPathComponent)")
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("stemdeck-\(UUID().uuidString)-\(url.lastPathComponent)")
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    /// Dernier tag de release GitHub : API, puis redirection de /releases/latest (sans quota API).
    func latestGitHubTag(_ repo: String) async -> String? {
        if let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") {
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String {
                return tag
            }
        }
        if let url = URL(string: "https://github.com/\(repo)/releases/latest") {
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "HEAD"
            req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let final = resp.url, final.path.contains("/releases/tag/") {
                return final.lastPathComponent
            }
        }
        return nil
    }

    private func latestPyPIVersion(_ package: String) async -> String? {
        guard let url = URL(string: "https://pypi.org/pypi/\(package)/json") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["info"] as? [String: Any] else { return nil }
        return info["version"] as? String
    }

    // MARK: - Installation de binaires vérifiés
    private func sha256(of file: URL) throws -> String {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Binaire brut (pas d'archive) : téléchargement, SHA256, test d'exécution, installation.
    private func installRawBinary(url: String, sha256 expected: String?, to dest: URL,
                                  versionArgs: [String]? = ["-version"]) async throws {
        let tmp = try await download(url)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try placeVerified(tmp, sha256: expected, hashedFile: tmp, to: dest, versionArgs: versionArgs)
    }

    /// Binaire dans un .zip (evermeet).
    private func installZippedBinary(named name: String, url: String, sha256 expected: String,
                                     to dest: URL) async throws {
        let archive = try await download(url)
        defer { try? FileManager.default.removeItem(at: archive) }
        guard try sha256(of: archive) == expected else {
            throw SetupError("Somme de contrôle invalide pour \(name)")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stemdeck-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.run("/usr/bin/unzip", ["-q", "-o", archive.path, "-d", dir.path])
        guard let found = Self.findBinary(named: name, in: dir) else {
            throw SetupError("\(name) absent de l'archive")
        }
        try placeVerified(found, sha256: nil, hashedFile: nil, to: dest, versionArgs: ["-version"])
    }

    /// Binaire dans un .tar.gz (fpcalc, uv). Le hash porte sur l'archive.
    private func installArchivedBinary(named name: String, url: String, sha256 expected: String?,
                                       to dest: URL) async throws {
        let archive = try await download(url)
        defer { try? FileManager.default.removeItem(at: archive) }
        if let expected, try sha256(of: archive) != expected {
            throw SetupError("Somme de contrôle invalide pour \(name)")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stemdeck-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.run("/usr/bin/tar", ["xzf", archive.path, "-C", dir.path])
        guard let found = Self.findBinary(named: name, in: dir) else {
            throw SetupError("\(name) absent de l'archive")
        }
        try placeVerified(found, sha256: nil, hashedFile: nil, to: dest,
                          versionArgs: name == "uv" ? ["--version"] : ["-version"])
    }

    private func placeVerified(_ src: URL, sha256 expected: String?, hashedFile: URL?,
                               to dest: URL, versionArgs: [String]?) throws {
        if let expected, let hashedFile, try sha256(of: hashedFile) != expected {
            throw SetupError("Somme de contrôle invalide pour \(dest.lastPathComponent)")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staged = dest.appendingPathExtension("partial")
        try? fm.removeItem(at: staged)
        try fm.copyItem(at: src, to: staged)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
        _ = try? Self.run("/usr/bin/xattr", ["-d", "com.apple.quarantine", staged.path])
        // Le binaire doit réellement s'exécuter sur ce Mac (architecture, Gatekeeper…)
        if let versionArgs {
            do { try Self.run(staged.path, versionArgs) }
            catch {
                try? fm.removeItem(at: staged)
                throw SetupError("\(dest.lastPathComponent) ne s'exécute pas sur ce Mac")
            }
        }
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: staged, to: dest)
    }

    private static func findBinary(named name: String, in dir: URL) -> URL? {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey])
        else { return nil }
        for case let url as URL in e where url.lastPathComponent == name {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { return url }
        }
        return nil
    }

    // MARK: - Exécution de processus (lecture continue → pas de blocage sur gros volumes)
    private final class OutputBox {
        let lock = NSLock()
        var data = Data()
        var pending = ""
    }

    @discardableResult
    static func run(_ exe: String, _ args: [String], cwd: URL? = nil,
                    env: [String: String]? = nil,
                    onLine: ((String) -> Void)? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        if let env { p.environment = env }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        p.standardInput  = FileHandle.nullDevice

        let box = OutputBox()
        let done = DispatchSemaphore(value: 0)
        pipe.fileHandleForReading.readabilityHandler = { fh in
            let d = fh.availableData
            if d.isEmpty {
                fh.readabilityHandler = nil
                done.signal()
                return
            }
            box.lock.lock()
            box.data.append(d)
            var lines: [String] = []
            if onLine != nil, let s = String(data: d, encoding: .utf8) {
                box.pending += s
                let parts = box.pending.components(separatedBy: "\n")
                box.pending = parts.last ?? ""
                lines = parts.dropLast().filter { !$0.isEmpty }
            }
            box.lock.unlock()
            lines.forEach { onLine?($0) }
        }

        do { try p.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            throw SetupError("Impossible de lancer \(URL(fileURLWithPath: exe).lastPathComponent) : \(error.localizedDescription)")
        }
        p.waitUntilExit()
        _ = done.wait(timeout: .now() + 5)

        box.lock.lock()
        let out = String(data: box.data, encoding: .utf8) ?? ""
        if !box.pending.isEmpty { onLine?(box.pending) }
        box.lock.unlock()

        guard p.terminationStatus == 0 else {
            let tail = out.split(separator: "\n").suffix(8).joined(separator: "\n")
            throw SetupError("\(URL(fileURLWithPath: exe).lastPathComponent) (code \(p.terminationStatus))\n\(tail)")
        }
        return out
    }

    // MARK: - Utilitaires
    /// Compare deux versions ("v0.20.1" vs "0.20.0", "2026.9.30" vs "2026.09.30").
    static func isNewer(_ new: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(whereSeparator: { !$0.isNumber })
                .compactMap { Int($0) }
        }
        let n = parts(new), c = parts(current)
        for i in 0..<max(n.count, c.count) {
            let a = i < n.count ? n[i] : 0, b = i < c.count ? c[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    private func firstLine(of s: String) -> String {
        s.components(separatedBy: "\n").first ?? ""
    }

    func printLog(_ msg: String) {
        print("[StemDeck] \(msg)")
        AppLogger.shared.log(msg, level: .info)
        DispatchQueue.main.async { self.setupLog += msg + "\n" }
    }
}

// MARK: - Erreur de configuration
struct SetupError: Error, LocalizedError {
    let message: String
    init(_ msg: String) { self.message = msg }
    var errorDescription: String? { message }
}
