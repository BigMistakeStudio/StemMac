// StemDeckApp.swift
// StemDeck — Native macOS stem separation app
// Minimum deployment: macOS 13.0

import SwiftUI
import AppKit

@available(macOS 13.0, *)
@main
struct StemDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var updater  = UpdaterService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(updater)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Vérifier les mises à jour…") {
                    Task { await updater.checkForUpdates() }
                }
                Divider()
            }
            CommandGroup(replacing: .newItem) {
                Button("Importer un fichier audio…") {
                    appState.showImportSheet = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(updater)
        }
    }
}

// MARK: - AppDelegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Force dark mode — StemDeck is a dark-theme audio app
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        // Stop uvicorn
        PythonRuntimeService.shared.stopBackend()

        // Filet de sécurité : workers Demucs / sections / transcription lancés par le backend.
        // (Ils s'arrêtent normalement seuls grâce à STEMDECK_PARENT_PID.)
        let cleanup = Process()
        cleanup.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        cleanup.arguments = ["-f", "Application Support/StemDeck/backends/"]
        try? cleanup.run()
        cleanup.waitUntilExit()

        // Stop audio engine
        AudioPlayerService.shared.stop()
    }
}
