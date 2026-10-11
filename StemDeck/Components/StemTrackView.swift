// Components/StemTrackView.swift
// Reusable stem chip + expanded track info used in the mixer sidebar.

import SwiftUI

struct StemTrackView: View {
    @ObservedObject var track: StemTrack
    var showExpanded: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            // Color dot
            Circle()
                .fill(track.kind.color)
                .frame(width: 8, height: 8)

            // Name
            Text(track.kind.displayName)
                .font(.caption.weight(.semibold))
                .foregroundColor(track.isMuted ? .secondary : .white)
                .frame(width: 60, alignment: .leading)

            if showExpanded {
                // Volume label
                Text(String(format: "%.0f%%", track.volume * 100))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 36)

                // Status badges
                HStack(spacing: 3) {
                    if track.isMuted   { badge("M", .orange) }
                    if track.isSolo    { badge("S", .yellow) }
                    if track.isMonitor { badge("Mon", .cyan) }
                }
            }

            Spacer()

            // Mini VU
            VUMeterView(level: track.vuLevel, peak: track.peakLevel,
                        color: track.kind.color)
                .frame(width: 8, height: 24)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
    }

    private func badge(_ label: String, _ color: Color) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.25))
            .foregroundColor(color)
            .cornerRadius(2)
    }
}
