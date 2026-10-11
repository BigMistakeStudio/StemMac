// Components/TransportView.swift
// Transport controls: Play/Pause/Stop, seek, loop, zoom.
// Mirrors the master transport in the original project.

import SwiftUI

struct TransportView: View {
    @ObservedObject var player: AudioPlayerService
    let duration: Double
    @Binding var zoomLevel: Double

    var body: some View {
        HStack(spacing: 20) {
            // ── Playback controls ─────────────────────────────────────────────
            HStack(spacing: 12) {
                // Stop
                TransportButton(icon: "stop.fill") {
                    player.stop()
                }

                // Rewind 5s
                TransportButton(icon: "backward.end.fill") {
                    player.skipBackward()
                }

                // Play / Pause
                Button {
                    player.isPlaying ? player.pause() : player.play()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.purple))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                // Forward 5s
                TransportButton(icon: "forward.end.fill") {
                    player.skipForward()
                }
            }

            // ── Time display ───────────────────────────────────────────────────
            Text(formatTime(player.currentTime) + " / " + formatTime(duration))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 120)

            // ── Seek bar ───────────────────────────────────────────────────────
            Slider(value: Binding(
                get: { player.currentTime },
                set: { player.seek(to: $0) }
            ), in: 0...max(duration, 1))
            .tint(.purple)

            // ── Loop toggle ────────────────────────────────────────────────────
            Button {
                player.loopEnabled.toggle()
            } label: {
                Label("Loop", systemImage: "repeat")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(player.loopEnabled ? Color.purple.opacity(0.3) : Color.white.opacity(0.06))
                    .foregroundColor(player.loopEnabled ? .purple : .secondary)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // ── Zoom controls ──────────────────────────────────────────────────
            HStack(spacing: 6) {
                TransportButton(icon: "minus.magnifyingglass") {
                    zoomLevel = max(zoomLevel / 1.5, 0.5)
                }
                TransportButton(icon: "plus.magnifyingglass") {
                    zoomLevel = min(zoomLevel * 1.5, 32)
                }
                Button {
                    zoomLevel = 1.0
                } label: {
                    Text("Fit")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.07))
                        .foregroundColor(.secondary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let m = s / 60
        let sec = s % 60
        return String(format: "%d:%02d", m, sec)
    }
}

struct TransportButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.07))
                .foregroundColor(.secondary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
