// Components/WaveformView.swift
// Waveform canvas + renderer using AVAssetReader (more robust than AVAudioFile).

import SwiftUI
@preconcurrency import AVFoundation

// MARK: - WaveformView
struct WaveformView: View {
    let samples:          [Float]
    let color:            Color
    let isMuted:          Bool
    var playheadPosition: Double = 0
    var duration:         Double = 1
    var loopStart:        Double = 0
    var loopEnd:          Double = 0
    var loopEnabled:      Bool   = false
    var zoomLevel:        Double = 1.0

    var body: some View {
        Canvas { ctx, size in
            let w   = size.width
            let h   = size.height
            let mid = h / 2
            let col: GraphicsContext.Shading = isMuted
                ? .color(color.opacity(0.18))
                : .color(color.opacity(0.82))

            guard !samples.isEmpty else {
                ctx.stroke(
                    Path { p in
                        p.move(to: .init(x: 0, y: mid))
                        p.addLine(to: .init(x: w, y: mid))
                    },
                    with: .color(.white.opacity(0.10)), lineWidth: 1)
                return
            }

            // Loop region
            if loopEnabled && loopEnd > loopStart {
                let sx = CGFloat(loopStart / max(duration, 1)) * w
                let ex = CGFloat(loopEnd   / max(duration, 1)) * w
                ctx.fill(
                    Path(CGRect(x: sx, y: 0, width: ex - sx, height: h)),
                    with: .color(color.opacity(0.12)))
            }

            // Min/max bars
            let n = samples.count
            let px = Int(w)
            for i in 0..<px {
                let i0 = i * n / px
                let i1 = max(i0 + 1, (i + 1) * n / px)
                var peak: Float = 0
                for j in i0..<min(i1, n) { peak = max(peak, abs(samples[j])) }
                let bh = CGFloat(peak) * h * 0.86
                let by = (h - bh) / 2
                ctx.fill(
                    Path(CGRect(x: CGFloat(i), y: by, width: 1.2, height: max(1, bh))),
                    with: col)
            }

            // Playhead
            let phX = CGFloat(playheadPosition / max(duration, 1)) * w
            ctx.stroke(
                Path { p in
                    p.move(to: .init(x: phX, y: 0))
                    p.addLine(to: .init(x: phX, y: h))
                },
                with: .color(.yellow.opacity(0.95)), lineWidth: 1.5)
        }
    }
}

// MARK: - WaveformRenderer (AVAssetReader — handles WAV, M4A, MP3, FLAC…)
final class WaveformRenderer {

    static func render(url: URL, targetSamples: Int = 1800) async -> [Float] {
        // Try AVAssetReader first (most robust)
        if let samples = await renderWithAssetReader(url: url, targetSamples: targetSamples),
           !samples.isEmpty {
            return samples
        }
        // Fallback: AVAudioFile streaming
        return await renderWithAudioFile(url: url, targetSamples: targetSamples)
    }

    // ── Method 1: AVAssetReader ───────────────────────────────────────────────
    private static func renderWithAssetReader(url: URL,
                                               targetSamples: Int) async -> [Float]? {
        let asset = AVURLAsset(url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        // Non-deprecated async API
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }
        // We have the track — now read PCM data on a background thread
        // Capture track data before crossing into Sendable closure
        return await withCheckedContinuation { (cont: CheckedContinuation<[Float]?, Never>) in
            let capturedTrack = track  // AVAssetTrack captured explicitly
            DispatchQueue.global(qos: .utility).async {
                let track = capturedTrack

                let settings: [String: Any] = [
                    AVFormatIDKey:            kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey:   32,
                    AVLinearPCMIsFloatKey:    true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVNumberOfChannelsKey:    1,
                ]

                guard let reader = try? AVAssetReader(asset: asset) else {
                    cont.resume(returning: nil); return
                }
                let output = AVAssetReaderTrackOutput(track: track,
                                                       outputSettings: settings)
                output.alwaysCopiesSampleData = false
                reader.add(output)
                guard reader.startReading() else {
                    print("[Waveform] AVAssetReader failed: \(reader.error?.localizedDescription ?? "?")")
                    cont.resume(returning: nil); return
                }

                var all = [Float]()
                all.reserveCapacity(targetSamples * 100)

                while reader.status == .reading,
                      let buf = output.copyNextSampleBuffer(),
                      let block = CMSampleBufferGetDataBuffer(buf) {
                    let len  = CMBlockBufferGetDataLength(block)
                    var data = [Float](repeating: 0, count: len / 4)
                    CMBlockBufferCopyDataBytes(block, atOffset: 0,
                                              dataLength: len,
                                              destination: &data)
                    all.append(contentsOf: data)
                }

                guard !all.isEmpty else {
                    cont.resume(returning: nil); return
                }

                // Downsample to targetSamples
                let step = max(1, all.count / targetSamples)
                var peaks = [Float]()
                peaks.reserveCapacity(targetSamples)
                var i = 0
                while i < all.count {
                    let end = min(i + step, all.count)
                    var peak: Float = 0
                    for j in i..<end { peak = max(peak, abs(all[j])) }
                    peaks.append(peak)
                    i += step
                }

                let maxVal = peaks.max() ?? 1
                if maxVal > 0 {
                    for k in 0..<peaks.count { peaks[k] /= maxVal }
                }

                print("[Waveform] AVAssetReader ✅ \(url.lastPathComponent): \(peaks.count) pts")
                cont.resume(returning: peaks)
            }
        }
    }

    // ── Method 2: AVAudioFile fallback ────────────────────────────────────────
    private static func renderWithAudioFile(url: URL,
                                             targetSamples: Int) async -> [Float] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                guard let file = try? AVAudioFile(forReading: url) else {
                    print("[Waveform] AVAudioFile ❌ cannot open \(url.lastPathComponent)")
                    cont.resume(returning: []); return
                }
                guard let fmt = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: file.processingFormat.sampleRate,
                    channels: 1, interleaved: false) else {
                    cont.resume(returning: []); return
                }
                let chunk: AVAudioFrameCount = 65536
                guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: chunk) else {
                    cont.resume(returning: []); return
                }

                let totalFrames = Int(file.length)
                let binFrames   = max(1, totalFrames / targetSamples)
                var peaks = [Float]()
                peaks.reserveCapacity(targetSamples + 1)
                var binPeak:   Float = 0
                var frameInBin = 0

                while true {
                    buf.frameLength = 0
                    do { try file.read(into: buf, frameCount: chunk) } catch { break }
                    guard buf.frameLength > 0 else { break }
                    guard let ch = buf.floatChannelData?[0] else { break }
                    for i in 0..<Int(buf.frameLength) {
                        let v = abs(ch[i])
                        if v > binPeak { binPeak = v }
                        frameInBin += 1
                        if frameInBin >= binFrames {
                            peaks.append(binPeak)
                            binPeak = 0; frameInBin = 0
                        }
                    }
                }
                if binPeak > 0 { peaks.append(binPeak) }

                let maxVal = peaks.max() ?? 1
                if maxVal > 0 { for k in 0..<peaks.count { peaks[k] /= maxVal } }

                print("[Waveform] AVAudioFile \(peaks.isEmpty ? "❌" : "✅") \(url.lastPathComponent): \(peaks.count) pts")
                cont.resume(returning: peaks)
            }
        }
    }
}
