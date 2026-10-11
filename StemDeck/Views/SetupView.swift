// Views/SetupView.swift — Beautiful first-launch wizard

import SwiftUI

struct SetupView: View {
    @EnvironmentObject var appState: AppState

    @State private var isRunning       = false
    @State private var currentTitle    = ""
    @State private var currentDetail   = ""
    @State private var percent: Double = 0
    @State private var failed          = false
    @State private var errorMessage    = ""
    @State private var showLog         = false
    @State private var log             = ""
    @State private var completedSteps: Set<Int> = []
    @State private var activeStepIndex = -1
    @AppStorage(PythonRuntimeService.installCompilerKey) private var installCompilerTools = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(red:0.05, green:0.04, blue:0.10),
                         Color(red:0.08, green:0.05, blue:0.15)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()

            GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 24)

                // Logo
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.15))
                            .frame(width: 64, height: 64)
                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 30, weight: .thin))
                            .foregroundStyle(
                                LinearGradient(colors: [.purple, .pink],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing))
                    }
                    Text("StemMac")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Séparation de pistes • 100% locale • Gratuite")
                        .font(.callout)
                        .foregroundColor(Color(white: 0.55))
                }
                .padding(.bottom, 20)

                if !isRunning && !failed {
                    // Welcome card
                    welcomeCard
                } else if failed {
                    errorCard
                } else {
                    progressCard
                }

                Spacer(minLength: 20)

                // Log toggle
                if !log.isEmpty {
                    Button(showLog ? "Masquer le journal technique" : "Voir le journal") {
                        showLog.toggle()
                    }
                    .buttonStyle(.plain).font(.caption)
                    .foregroundColor(Color(white: 0.38))
                    .padding(.bottom, 4)
                }
                if showLog && !log.isEmpty {
                    LogScrollView(text: log).frame(maxWidth: 560, maxHeight: 150)
                        .padding(.bottom, 12)
                }

                // Footer
                Text("Propulsé par stemdeckapp/stemdeck · Apache 2.0")
                    .font(.caption2).foregroundColor(Color(white: 0.28))
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            }
        }
        .frame(minWidth: 640, minHeight: 560)
        .onAppear {
            // Installation déjà faite mais incomplète (composant manquant) :
            // on répare directement, sans redemander à l'utilisateur.
            if !isRunning && !failed && PythonRuntimeService.shared.hasPreviousInstall {
                startSetup()
            }
        }
    }

    // MARK: - Welcome card
    private var welcomeCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Bienvenue !")
                    .font(.title2.weight(.semibold)).foregroundColor(.white)
                Text("StemMac installe automatiquement la dernière version du moteur StemDeck et tous ses composants. Rien n'est installé en dehors de l'app (pas de Homebrew requis).")
                    .font(.callout).foregroundColor(Color(white: 0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560)
            }

            // Ce qui sera installé — 2 colonnes pour tenir dans la fenêtre
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(Array(allSetupSteps.enumerated()), id: \.offset) { _, step in
                    HStack(spacing: 10) {
                        Image(systemName: step.icon)
                            .font(.system(size: 13))
                            .foregroundColor(.purple)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.title).font(.callout.weight(.medium))
                                .foregroundColor(.white)
                            Text(step.detail).font(.caption)
                                .foregroundColor(Color(white: 0.48))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1))
                }
            }
            .frame(maxWidth: 640)

            // Option nécessitant un compte administrateur — désactivée par défaut
            Toggle(isOn: $installCompilerTools) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activer la séparation voix lead / chœurs")
                        .font(.callout.weight(.medium)).foregroundColor(.white)
                    Text("Optionnel. Installe les outils de compilation Apple ou accepte la licence Xcode : un mot de passe administrateur sera demandé. Activable plus tard dans Réglages › Composants.")
                        .font(.caption).foregroundColor(Color(white: 0.48))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: 640, alignment: .leading)

            Text("⏱ Durée estimée : 5 à 15 minutes selon votre connexion (≈ 3 Go)")
                .font(.caption).foregroundColor(Color(white: 0.42))

            Button(action: startSetup) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Installer et démarrer")
                        .font(.callout.weight(.semibold))
                }
                .frame(minWidth: 220)
                .padding(.vertical, 14).padding(.horizontal, 36)
                .background(LinearGradient(
                    colors: [.purple, Color(red:0.6,green:0.2,blue:0.9)],
                    startPoint: .leading, endPoint: .trailing))
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: .purple.opacity(0.4), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Progress card
    private var progressCard: some View {
        VStack(spacing: 20) {
            // Step list with status
            VStack(spacing: 0) {
                ForEach(Array(allSetupSteps.enumerated()), id: \.offset) { idx, step in
                    HStack(spacing: 12) {
                        // Status icon
                        ZStack {
                            Circle()
                                .fill(stepBg(idx))
                                .frame(width: 28, height: 28)
                            if completedSteps.contains(idx) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            } else if activeStepIndex == idx {
                                ProgressView().progressViewStyle(.circular)
                                    .scaleEffect(0.55).tint(.white)
                            } else {
                                Image(systemName: step.icon)
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(white: 0.45))
                            }
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.title)
                                .font(.callout.weight(activeStepIndex == idx ? .semibold : .regular))
                                .foregroundColor(activeStepIndex == idx ? .white : Color(white: 0.55))
                            if activeStepIndex == idx {
                                Text(currentDetail)
                                    .font(.caption)
                                    .foregroundColor(Color(white: 0.50))
                                    .transition(.opacity)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(activeStepIndex == idx
                                ? Color.purple.opacity(0.10)
                                : Color.clear)
                }
            }
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1))
            .frame(maxWidth: 440)

            // Progress bar
            VStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [.purple, .pink],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, 440 * CGFloat(percent)), height: 8)
                        .animation(.easeInOut(duration: 0.4), value: percent)
                }
                .frame(maxWidth: 440)
                Text("\(Int(percent * 100))%  •  \(currentTitle)")
                    .font(.caption.weight(.medium))
                    .foregroundColor(Color(white: 0.55))
            }
        }
    }

    // MARK: - Error card
    private var errorCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundColor(.red)
            Text("Erreur lors de la configuration")
                .font(.title3.weight(.semibold)).foregroundColor(.white)
            Text(errorMessage)
                .font(.callout).foregroundColor(Color(white: 0.60))
                .multilineTextAlignment(.center).frame(maxWidth: 440)
                .padding(16)
                .background(Color.red.opacity(0.08))
                .cornerRadius(10)

            Button(action: startSetup) {
                Label("Réessayer", systemImage: "arrow.clockwise")
                    .font(.callout.weight(.semibold))
                    .padding(.vertical, 12).padding(.horizontal, 28)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 440)
    }

    // MARK: - Helpers
    private func stepBg(_ idx: Int) -> Color {
        if completedSteps.contains(idx) { return .green.opacity(0.8) }
        if activeStepIndex == idx       { return .purple }
        return Color.white.opacity(0.10)
    }

    private func startSetup() {
        isRunning = true; failed = false; errorMessage = ""
        log = ""; percent = 0; completedSteps = []; activeStepIndex = 0

        PythonRuntimeService.shared.runSetup(
            progressHandler: { title, detail, pct in
                // Map title to step index
                let idx = allSetupSteps.firstIndex(where: { $0.title.contains(title) || title.contains($0.title) })
                if let i = idx {
                    if i > activeStepIndex {
                        // Mark previous as done
                        for j in 0..<i { completedSteps.insert(j) }
                        activeStepIndex = i
                    }
                }
                currentTitle  = title
                currentDetail = detail
                percent       = pct
                log          += "[\(Int(pct*100))%] \(title) — \(detail)\n"
            },
            completion: { success, error in
                isRunning = false
                if success {
                    // Mark all done
                    for i in 0..<allSetupSteps.count { completedSteps.insert(i) }
                    percent = 1.0
                    PythonRuntimeService.shared.startBackend(port: appState.backendPort)
                    appState.isSetupComplete = true
                    // Poll for backend
                    Task {
                        for _ in 0..<90 {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            if await BackendService.shared.ping() {
                                appState.backendReady = true
                                appState.screen = .importing
                                return
                            }
                        }
                        appState.screen = .importing
                    }
                } else {
                    failed = true
                    errorMessage = error ?? "Erreur inconnue"
                }
            }
        )
    }
}

// MARK: - Log scroll view
private struct LogScrollView: View {
    let text: String
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.green.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).id("end")
            }
            .background(Color.black.opacity(0.5))
            .cornerRadius(8)
            .onChange(of: text) { _ in
                withAnimation { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }
}
