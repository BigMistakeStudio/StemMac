// Components/VUMeterView.swift
// Vertical VU meter with peak hold.
// Mirrors the live VU meters in the original Web Audio implementation.

import SwiftUI

struct VUMeterView: View {
    let level: Float      // 0–1 linear RMS
    let peak: Float       // 0–1 peak hold
    let color: Color

    private let segmentCount = 20
    private let clippingThreshold: Float = 0.9

    var body: some View {
        GeometryReader { geo in
            let segH = geo.size.height / CGFloat(segmentCount)
            ZStack(alignment: .bottom) {
                // Background segments
                VStack(spacing: 1) {
                    ForEach(0..<segmentCount, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.05))
                            .frame(height: segH - 1)
                    }
                }

                // Active level
                let activeSegments = Int(level * Float(segmentCount))
                VStack(spacing: 1) {
                    ForEach(0..<segmentCount, id: \.self) { i in
                        let idx = segmentCount - 1 - i
                        if idx < activeSegments {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(segColor(for: idx))
                                .frame(height: segH - 1)
                        } else {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.clear)
                                .frame(height: segH - 1)
                        }
                    }
                }

                // Peak hold indicator
                let peakIdx = Int(peak * Float(segmentCount))
                if peakIdx > 0 && peakIdx < segmentCount {
                    let peakY = CGFloat(segmentCount - peakIdx) * segH
                    Rectangle()
                        .fill(peak > clippingThreshold ? Color.red : Color.white)
                        .frame(height: 2)
                        .offset(y: peakY - geo.size.height)
                }
            }
        }
    }

    private func segColor(for index: Int) -> Color {
        let normalized = Float(index) / Float(segmentCount)
        if normalized > 0.85 { return .red }
        if normalized > 0.70 { return .yellow }
        return color
    }
}
