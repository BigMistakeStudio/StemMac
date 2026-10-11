// ContentView.swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updater:  UpdaterService
    @ObservedObject private var runtime = PythonRuntimeService.shared

    var body: some View {
        ZStack {
            // Dark base — always fill the window
            Color(red: 0.051, green: 0.067, blue: 0.090)
                .ignoresSafeArea()

            Group {
                switch appState.screen {
                case .setup:      SetupView()
                case .importing:  ImportView()
                case .processing: ProcessingView()
                case .studio:     StudioView()
                case .library:    LibraryView()
                }
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.3)))

            // Update banners
            if let release = updater.state.availableRelease {
                UpdateBanner(release: release)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
            }
            if runtime.needsRestart && appState.screen != .processing {
                BackendRestartBanner()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
            }
            if updater.state.isReadyToRestart {
                RestartBanner()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
            }
        }
        .onAppear {
            Task { await startBackendAndWait() }
        }
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(updater)
        }
    }

    // MARK: - Backend startup

    private func startBackendAndWait() async {
        let runtime = PythonRuntimeService.shared

        // Installation absente ou incomplète (ex. ancienne version de l'app) → assistant
        guard runtime.isInstalled else {
            appState.isSetupComplete = false
            appState.screen = .setup
            return
        }

        if await BackendService.shared.ping() {
            appState.backendReady = true
        } else {
            runtime.startBackend(port: appState.backendPort)
            for attempt in 1...90 {     // le 1er démarrage charge torch : peut prendre ~30 s
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if await BackendService.shared.ping() {
                    appState.backendReady = true
                    break
                }
                if attempt == 45 && !runtime.isRunning {
                    runtime.restartBackend()
                }
            }
            if !appState.backendReady {
                runtime.printLog("⚠️ Backend non disponible après 90 s — voir Réglages › Diagnostic")
            }
        }

        updater.startPeriodicChecks()

        // Vérification des mises à jour à chaque lancement, en arrière-plan :
        // rien à faire → l'app reste simplement démarrée ; sinon la nouvelle version
        // s'installe à côté et le bandeau « Appliquer » apparaît.
        if UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true {
            runtime.runUpdates { _ in }
        } else {
            await runtime.refreshStatus(checkRemote: false)
        }
    }
}

// MARK: - Update banner
struct UpdateBanner: View {
    let release: GitHubRelease
    @EnvironmentObject var updater: UpdaterService

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundColor(.purple)
            Text("Version \(release.versionString) disponible")
                .font(.callout.weight(.medium))
                .foregroundColor(.primary)
            Spacer()
            Button("Installer") { updater.downloadAndInstall(release) }
                .buttonStyle(.borderedProminent).controlSize(.small).tint(.purple)
            Button { updater.state = .idle } label: {
                Image(systemName: "xmark").font(.caption)
            }
            .buttonStyle(.plain).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
        .shadow(radius: 4)
    }
}

// MARK: - Restart banner
struct RestartBanner: View {
    @EnvironmentObject var updater: UpdaterService

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text("Mise à jour installée — redémarrez StemMac")
                .font(.callout.weight(.medium))
                .foregroundColor(.primary)
            Spacer()
            Button("Redémarrer") { updater.relaunch() }
                .buttonStyle(.borderedProminent).controlSize(.small).tint(.green)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
        .shadow(radius: 4)
    }
}

// MARK: - Nouvelle version du backend installée
struct BackendRestartBanner: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack").foregroundColor(.purple)
            Text("Nouvelle version du moteur StemDeck installée")
                .font(.callout.weight(.medium))
                .foregroundColor(.primary)
            Spacer()
            Button("Appliquer") {
                appState.backendReady = false
                PythonRuntimeService.shared.restartBackend()
                Task {
                    for _ in 0..<90 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        if await BackendService.shared.ping() { appState.backendReady = true; return }
                    }
                }
            }
            .buttonStyle(.borderedProminent).controlSize(.small).tint(.purple)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
        .shadow(radius: 4)
    }
}
