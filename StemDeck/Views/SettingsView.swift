// Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updater:  UpdaterService
    @AppStorage("backendPort")  private var backendPort:  Int    = 8000
    @AppStorage("demucsDevice") private var demucsDevice: String = "auto"
    @AppStorage("maxDuration")  private var maxDuration:  Int    = 1200
    @AppStorage("autoUpdate")   private var autoUpdate:   Bool   = true
    @State private var showUpdater = false
    @State private var showDiag      = false

    var body: some View {
        TabView {
            // ── General ──────────────────────────────────────────────────────
            Form {
                Section("Backend") {
                    HStack {
                        Text("Port HTTP")
                        Spacer()
                        TextField("8000", value: $backendPort, format: .number)
                            .frame(width: 80).multilineTextAlignment(.trailing)
                    }
                    Picker("Périphérique Demucs", selection: $demucsDevice) {
                        Text("Auto (MPS → CUDA → CPU)").tag("auto")
                        Text("Apple MPS (Silicon)").tag("mps")
                        Text("CPU").tag("cpu")
                    }
                    HStack {
                        Text("Durée max (secondes)")
                        Spacer()
                        TextField("1200", value: $maxDuration, format: .number)
                            .frame(width: 80).multilineTextAlignment(.trailing)
                    }
                    Button("Redémarrer le backend") {
                        PythonRuntimeService.shared.restartBackend()
                    }
                    .foregroundColor(.red)
                }

                Section("Mise à jour automatique") {
                    Toggle("Vérifier et mettre à jour les composants chaque jour", isOn: $autoUpdate)
                    Text("Les réglages ci-dessus s'appliquent au prochain redémarrage du backend.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Général", systemImage: "gear") }

            // ── Composants ───────────────────────────────────────────────────
            ComponentsView()
            .tabItem { Label("Composants", systemImage: "shippingbox") }

            // ── Updates ──────────────────────────────────────────────────────
            VStack(spacing: 20) {
                Spacer()
                VStack(spacing: 8) {
                    Text("StemMac").font(.title3.weight(.semibold))
                    Text("Version \(updater.currentVersion)").foregroundColor(.secondary)
                }

                // Use helper properties — no Equatable needed
                if case .checking = updater.state {
                    ProgressView("Vérification…")
                } else if let rel = updater.state.availableRelease {
                    VStack(spacing: 8) {
                        Text("Version \(rel.versionString) disponible")
                            .font(.callout.weight(.medium)).foregroundColor(.purple)
                        Button("Voir les détails") { showUpdater = true }
                            .buttonStyle(.borderedProminent).tint(.purple)
                    }
                } else if !updater.isConfigured {
                    Text("Mise à jour de l'app non configurée.\nAjoutez la clé StemDeckAppUpdateRepo (ex. « votre-compte/stemdeck-mac ») dans Info.plist.\nLe moteur StemDeck se met à jour dans l'onglet Composants.")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 380)
                } else {
                    Button("Vérifier les mises à jour") {
                        Task { await updater.checkForUpdates() }
                    }
                    .buttonStyle(.borderedProminent).tint(.purple)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .sheet(isPresented: $showUpdater) {
                UpdaterView().environmentObject(updater)
            }
            .tabItem { Label("Mises à jour", systemImage: "arrow.triangle.2.circlepath") }

            // ── Diagnostic ───────────────────────────────────────────────────
            DiagView()
            .tabItem { Label("Diagnostic", systemImage: "stethoscope") }

            // ── About ────────────────────────────────────────────────────────
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 48)).foregroundStyle(.purple.gradient)
                Text("StemMac").font(.largeTitle.weight(.bold))
                Text("Séparation de pistes locale, gratuite et privée")
                    .foregroundColor(.secondary)
                Text("Propulsé par Demucs (Meta AI) · FastAPI · AVFoundation")
                    .font(.caption).foregroundColor(Color.secondary.opacity(0.6))
                Link("github.com/stemdeckapp/stemdeck",
                     destination: URL(string: "https://github.com/stemdeckapp/stemdeck")!)
                    .font(.caption.weight(.medium)).foregroundColor(.purple)

                Divider().frame(maxWidth: 200).padding(.vertical, 4)

                Text("Cette app est un wrapper macOS natif du projet open-source")
                    .font(.caption2).foregroundColor(Color(white: 0.42))
                    .multilineTextAlignment(.center)
                Text("stemdeckapp/stemdeck (Apache 2.0)")
                    .font(.caption2.weight(.semibold)).foregroundColor(Color(white: 0.50))
                Text("Wrapper Swift/SwiftUI — tous les droits du projet original sont préservés.")
                    .font(.caption2).foregroundColor(Color(white: 0.35))
                    .multilineTextAlignment(.center).frame(maxWidth: 340)

                Spacer()
            }
            .tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}

// MARK: - Onglet Composants
struct ComponentsView: View {
    @ObservedObject private var runtime = PythonRuntimeService.shared
    @State private var log = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Composants").font(.headline)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if runtime.isBusy { ProgressView().controlSize(.small) }
                Button("Vérifier") {
                    Task { await runtime.refreshStatus(checkRemote: true) }
                }
                .disabled(runtime.isBusy)
                Button("Tout mettre à jour") {
                    log = ""
                    runtime.runUpdates { msg in log += msg + "\n" }
                }
                .buttonStyle(.borderedProminent).tint(.purple)
                .disabled(runtime.isBusy || !runtime.isInstalled)
            }
            .padding(14)

            if runtime.needsRestart {
                HStack {
                    Image(systemName: "arrow.clockwise.circle.fill").foregroundColor(.purple)
                    Text("Une nouvelle version du backend est installée.")
                        .font(.callout)
                    Spacer()
                    Button("Redémarrer le backend") { runtime.restartBackend() }
                        .controlSize(.small)
                }
                .padding(10)
                .background(Color.purple.opacity(0.12))
                .cornerRadius(8)
                .padding(.horizontal, 14)
            }

            List(runtime.components) { c in
                ComponentRow(info: c) {
                    log = ""
                    runtime.repair(c.id) { msg in log += msg + "\n" }
                }
                .disabled(runtime.isBusy)
            }
            .listStyle(.inset)

            if !log.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(log)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8).id("end")
                    }
                    .background(Color.black.opacity(0.4))
                    .frame(height: 120)
                    .onChange(of: log) { _ in proxy.scrollTo("end", anchor: .bottom) }
                }
            }
        }
        .task { await runtime.refreshStatus(checkRemote: true) }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let v = runtime.runningVersion { parts.append("Backend en cours : \(v)") }
        if let d = runtime.manifest.lastUpdateCheck {
            parts.append("Dernière mise à jour : \(d.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.isEmpty ? "Moteur stemdeckapp/stemdeck et outils associés" : parts.joined(separator: " · ")
    }
}

private struct ComponentRow: View {
    let info: ComponentInfo
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: info.id.icon)
                .frame(width: 22)
                .foregroundColor(.purple)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(info.id.title).font(.callout.weight(.medium))
                    if info.id.isOptional {
                        Text("optionnel").font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15)).cornerRadius(4)
                    }
                }
                Text(versionText).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            statusBadge
            Button(buttonTitle, action: action)
                .controlSize(.small)
        }
        .padding(.vertical, 3)
    }

    private var versionText: String {
        let inst = info.installed ?? "non installé"
        if let l = info.latest, l != info.installed { return "\(inst)  →  \(l)" }
        return inst
    }

    private var buttonTitle: String {
        if info.id == .compiler && info.state != .ok { return "Activer (administrateur)" }
        switch info.state {
        case .missing:  return "Installer"
        case .outdated: return info.id == .models ? "Télécharger" : "Mettre à jour"
        default:        return "Réinstaller"
        }
    }

    @ViewBuilder private var statusBadge: some View {
        switch info.state {
        case .ok:
            Label("À jour", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                .font(.caption).labelStyle(.titleAndIcon)
        case .outdated:
            Label(info.id == .models ? "À télécharger" : "Mise à jour", systemImage: "arrow.up.circle.fill")
                .foregroundColor(.orange).font(.caption)
        case .missing:
            Label("Absent", systemImage: "xmark.circle.fill")
                .foregroundColor(info.id.isOptional ? .orange : .red).font(.caption)
        case .checking, .working:
            ProgressView().controlSize(.small)
        case .failed(let msg):
            Label("Erreur", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.red).font(.caption).help(msg)
        case .unknown:
            Text("—").foregroundColor(.secondary)
        }
    }
}
