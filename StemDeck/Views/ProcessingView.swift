// Views/ProcessingView.swift — macOS 13 compatible
import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject var appState: AppState
    @State private var spinAngle: Double = 0

    var body: some View {
        ZStack {
            Color(red: 0.051, green: 0.067, blue: 0.090).ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer()

                // Spinner
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 6)
                        .frame(width: 90, height: 90)
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(
                            LinearGradient(colors: [.purple, .pink],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(spinAngle))
                        .onAppear {
                            withAnimation(.linear(duration: 1.1)
                                .repeatForever(autoreverses: false)) {
                                spinAngle = 360
                            }
                        }
                    Image(systemName: "waveform")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .pink],
                                           startPoint: .top, endPoint: .bottom))
                }

                // Status text — high contrast
                VStack(spacing: 10) {
                    Text(appState.jobProgress.message.isEmpty
                         ? "Traitement en cours…"
                         : appState.jobProgress.message)
                        .font(.title3.weight(.medium))
                        .foregroundColor(.white)           // ← was .secondary (too dim)
                        .multilineTextAlignment(.center)

                    if !appState.jobProgress.phase.isEmpty {
                        Text(appState.jobProgress.phase)
                            .font(.callout)
                            .foregroundColor(Color(white: 0.65))
                    }
                }

                // Progress bar
                VStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.10))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [.purple, .pink],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(
                                width: max(8, 420 * CGFloat(appState.jobProgress.percent)),
                                height: 8)
                            .animation(.easeInOut(duration: 0.3),
                                       value: appState.jobProgress.percent)
                    }
                    .frame(maxWidth: 420)

                    Text("\(Int(appState.jobProgress.percent * 100))%")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Color(white: 0.60))
                }

                // Cancel button
                Button("Annuler") {
                    Task {
                        if let id = appState.currentJob?.id {
                            try? await BackendService.shared.cancelJob(id: id)
                        }
                        appState.resetForNewJob()
                    }
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundColor(Color.red.opacity(0.75))
                .padding(.top, 4)

                Spacer()
            }
            .padding(40)
        }
    }
}
