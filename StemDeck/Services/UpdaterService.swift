// Services/UpdaterService.swift
// Auto-update via GitHub Releases API.

import Foundation
import AppKit

// MARK: - GitHub models
struct GitHubRelease: Codable {
    let tagName:     String
    let name:        String
    let body:        String
    let prerelease:  Bool
    let publishedAt: String
    let assets:      [GitHubAsset]
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, prerelease
        case publishedAt = "published_at"
        case assets
    }
    var versionString: String { tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v")) }
}

struct GitHubAsset: Codable {
    let name:               String
    let browserDownloadURL: String
    let size:               Int
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

// MARK: - Updater state  (no Equatable needed — use @Published pattern)
enum UpdaterState {
    case idle
    case checking
    case upToDate
    case updateAvailable(GitHubRelease)
    case downloading(Double)
    case installing
    case readyToRestart
    case error(String)

    // Manual equality for the banner checks
    var isUpdateAvailable: Bool {
        if case .updateAvailable = self { return true }
        return false
    }
    var isReadyToRestart: Bool {
        if case .readyToRestart = self { return true }
        return false
    }
    var availableRelease: GitHubRelease? {
        if case .updateAvailable(let r) = self { return r }
        return nil
    }
}

// MARK: - UpdaterService
@MainActor
final class UpdaterService: ObservableObject {

    @Published var state: UpdaterState = .idle
    @Published var releaseNotes: String = ""
    @Published var latestVersion: String = ""

    /// Dépôt GitHub qui publie CETTE app (DMG). Clé Info.plist « StemDeckAppUpdateRepo ».
    /// ⚠️ Ne jamais mettre stemdeckapp/stemdeck ici : ses DMG sont l'app officielle (Tauri),
    /// qui remplacerait ce wrapper. Le moteur StemDeck se met à jour via PythonRuntimeService.
    private let repo: String? = {
        guard let r = Bundle.main.object(forInfoDictionaryKey: "StemDeckAppUpdateRepo") as? String,
              !r.isEmpty, r.lowercased() != "stemdeckapp/stemdeck" else { return nil }
        return r
    }()
    var isConfigured: Bool { repo != nil }
    /// Nom du paquet de l'app (StemMac.app)
    nonisolated static var appBundleName: String { Bundle.main.bundleURL.lastPathComponent }
    private let apiBase = "https://api.github.com"
    private var checkTask: Task<Void, Never>?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Check
    func checkForUpdates() async {
        guard isConfigured else { state = .idle; return }
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            latestVersion  = release.versionString
            releaseNotes   = release.body
            if isNewer(release.versionString, than: currentVersion) {
                state = .updateAvailable(release)
            } else {
                state = .upToDate
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    if case .upToDate = self?.state { self?.state = .idle }
                }
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Download & install
    func downloadAndInstall(_ release: GitHubRelease) {
        guard let asset = pickAsset(from: release) else {
            state = .error("Aucun fichier DMG compatible trouvé.")
            return
        }
        guard let url = URL(string: asset.browserDownloadURL) else {
            state = .error("URL invalide.")
            return
        }
        state = .downloading(0)

        let task = URLSession.shared.downloadTask(with: url) { [weak self] tmpURL, _, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in self.state = .error(error.localizedDescription) }
                return
            }
            guard let tmpURL else { return }
            Task { @MainActor in await self.installDMG(from: tmpURL, assetName: asset.name) }
        }
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            Task { @MainActor [weak self] in self?.state = .downloading(p.fractionCompleted) }
        }
        _ = observation
        task.resume()
    }

    // MARK: - Periodic checks
    func startPeriodicChecks() {
        guard isConfigured else { return }
        checkTask?.cancel()
        checkTask = Task {
            while !Task.isCancelled {
                await checkForUpdates()
                try? await Task.sleep(nanoseconds: 24 * 60 * 60 * 1_000_000_000)
            }
        }
    }

    // MARK: - Relaunch
    func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = [path]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: - Internals
    private func fetchLatestRelease() async throws -> GitHubRelease {
        guard let repo else { throw URLError(.unsupportedURL) }
        let url = URL(string: "\(apiBase)/repos/\(repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28",                  forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("StemMac/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func pickAsset(from release: GitHubRelease) -> GitHubAsset? {
        #if arch(arm64)
        let suffix = "arm64"
        #else
        let suffix = "x64"
        #endif
        return release.assets.first {
            $0.name.lowercased().contains("macos") &&
            $0.name.lowercased().contains(suffix) &&
            $0.name.hasSuffix(".dmg")
        } ?? release.assets.first { $0.name.hasSuffix(".dmg") }
    }

    private func installDMG(from tmpURL: URL, assetName: String) async {
        state = .installing
        let dmgDest = FileManager.default.temporaryDirectory.appendingPathComponent(assetName)
        try? FileManager.default.moveItem(at: tmpURL, to: dmgDest)

        let mount = await shell("/usr/bin/hdiutil",
                                args: ["attach", dmgDest.path, "-nobrowse", "-quiet"])
        guard mount.ok else { state = .error("Impossible de monter le DMG."); return }

        guard let appSrc = findApp(in: URL(fileURLWithPath: "/Volumes")) else {
            state = .error("\(Self.appBundleName) introuvable dans le DMG."); return
        }
        let appDest   = URL(fileURLWithPath: Bundle.main.bundlePath)
        let parent    = appDest.deletingLastPathComponent()
        let backup    = parent.appendingPathComponent(Self.appBundleName + ".bak")
        do {
            try? FileManager.default.removeItem(at: backup)
            try  FileManager.default.moveItem(at: appDest, to: backup)
            try  FileManager.default.copyItem(at: appSrc,  to: appDest)
            try? FileManager.default.removeItem(at: backup)
        } catch {
            try? FileManager.default.moveItem(at: backup, to: appDest)
            state = .error("Remplacement échoué : \(error.localizedDescription)"); return
        }
        _ = await shell("/usr/bin/hdiutil",
                        args: ["detach", appSrc.deletingLastPathComponent().path, "-quiet"])
        state = .readyToRestart
    }

    private func findApp(in dir: URL) -> URL? {
        guard let vols = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return nil }
        for vol in vols {
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: vol, includingPropertiesForKeys: nil),
               let app = contents.first(where: { $0.lastPathComponent == Self.appBundleName }) {
                return app
            }
        }
        return nil
    }

    private func shell(_ exe: String, args: [String]) async -> (ok: Bool, out: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe; p.standardError = pipe
                try? p.run(); p.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                cont.resume(returning: (p.terminationStatus == 0, out))
            }
        }
    }

    func isNewer(_ new: String, than current: String) -> Bool {
        let n = new.components(separatedBy: ".").compactMap(Int.init)
        let c = current.components(separatedBy: ".").compactMap(Int.init)
        for i in 0..<max(n.count, c.count) {
            let ni = i < n.count ? n[i] : 0
            let ci = i < c.count ? c[i] : 0
            if ni > ci { return true }
            if ni < ci { return false }
        }
        return false
    }
}
