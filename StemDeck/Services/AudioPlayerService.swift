// Services/AudioPlayerService.swift
// Multi-track AVAudioEngine playback. Seek works by rescheduling all players.

import AVFoundation
import Combine

@MainActor
final class AudioPlayerService: ObservableObject {

    static let shared = AudioPlayerService()

    @Published var isPlaying    = false
    @Published var currentTime: Double = 0
    @Published var duration:    Double = 0
    @Published var loopEnabled  = false
    @Published var loopStart:   Double = 0
    @Published var loopEnd:     Double = 0

    private let engine      = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()

    private var stemPlayers: [String: AVAudioPlayerNode] = [:]
    private var stemMixers:  [String: AVAudioMixerNode]  = [:]
    private var stemFiles:   [String: AVAudioFile]       = [:]
    private var stemTracks:  [String: StemTrack]         = [:]

    // Playback position tracking
    private var seekOffset:      Double = 0   // where we started playing from
    private var playStartHostTime: UInt64 = 0  // mach_absolute_time when play() was called
    private var meterTimer: Timer?

    init() {
        setupEngine()
        startMeterTimer()
    }

    // MARK: - Engine
    private func setupEngine() {
        engine.attach(masterMixer)
        engine.connect(masterMixer, to: engine.mainMixerNode, format: nil)
    }

    // MARK: - Load stems
    func loadStems(_ tracks: [StemTrack]) async {
        stop()
        clearNodes()
        var maxDuration: Double = 0

        for track in tracks {
            guard let url = track.audioURL else { continue }
            do {
                let file   = try AVAudioFile(forReading: url)
                let player = AVAudioPlayerNode()
                let mixer  = AVAudioMixerNode()

                engine.attach(player)
                engine.attach(mixer)

                let fmt = file.processingFormat
                engine.connect(player, to: mixer,       format: fmt)
                engine.connect(mixer,  to: masterMixer, format: fmt)

                stemPlayers[track.id] = player
                stemMixers[track.id]  = mixer
                stemFiles[track.id]   = file
                stemTracks[track.id]  = track

                mixer.outputVolume = track.isMuted ? 0 : track.volume

                let dur = Double(file.length) / file.processingFormat.sampleRate
                maxDuration = max(maxDuration, dur)
            } catch {
                print("[AudioPlayer] Failed to load \(url.lastPathComponent): \(error)")
            }
        }
        duration = maxDuration

        do { try engine.start() }
        catch { print("[AudioPlayer] Engine start failed: \(error)") }
    }

    // MARK: - Transport

    func play() {
        guard !stemPlayers.isEmpty else { return }
        guard !isPlaying else { return }

        scheduleAll(from: currentTime)

        if !engine.isRunning {
            try? engine.start()
        }

        // Start all players simultaneously at the same time
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + secondsToHostTicks(0.05))
        for player in stemPlayers.values {
            player.play(at: startTime)
        }

        seekOffset      = currentTime
        playStartHostTime = startTime.hostTime
        isPlaying       = true
    }

    func pause() {
        guard isPlaying else { return }
        currentTime = liveCurrentTime()
        for player in stemPlayers.values { player.pause() }
        isPlaying = false
    }

    func stop() {
        for player in stemPlayers.values { player.stop() }
        isPlaying   = false
        currentTime = 0
        seekOffset  = 0
    }

    func seek(to time: Double) {
        let wasPlaying = isPlaying
        // Stop all players
        for player in stemPlayers.values { player.stop() }
        isPlaying   = false

        currentTime = max(0, min(time, duration))
        seekOffset  = currentTime

        if wasPlaying {
            play()
        }
    }

    func skipBackward(seconds: Double = 5) { seek(to: currentTime - seconds) }
    func skipForward(seconds: Double = 5)  { seek(to: currentTime + seconds) }

    // MARK: - Per-stem control
    func setVolume(_ volume: Float, forTrack id: String) {
        stemTracks[id]?.volume = volume
        updateEffectiveVolumes()
    }
    func setMute(_ muted: Bool, forTrack id: String) {
        stemTracks[id]?.isMuted = muted
        updateEffectiveVolumes()
    }
    func setSolo(_ solo: Bool, forTrack id: String) {
        stemTracks[id]?.isSolo = solo
        updateEffectiveVolumes()
    }
    func setMonitor(_ monitor: Bool, forTrack id: String) {
        if monitor {
            for (tid, t) in stemTracks { t.isSolo = (tid == id); t.isMonitor = (tid == id) }
        } else {
            stemTracks[id]?.isMonitor = false
            stemTracks[id]?.isSolo    = false
        }
        updateEffectiveVolumes()
    }
    func setAllMuted(_ muted: Bool) {
        stemTracks.values.forEach { $0.isMuted = muted }
        updateEffectiveVolumes()
    }
    func clearAllSolo() {
        stemTracks.values.forEach { $0.isSolo = false; $0.isMonitor = false }
        updateEffectiveVolumes()
    }

    private func updateEffectiveVolumes() {
        let anySolo = stemTracks.values.contains { $0.isSolo }
        for (id, track) in stemTracks {
            let hear = !track.isMuted && (!anySolo || track.isSolo)
            stemMixers[id]?.outputVolume = hear ? track.volume : 0
        }
    }

    // MARK: - Timer (VU + playhead)
    private func startMeterTimer() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1/24.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        if isPlaying {
            let t = liveCurrentTime()
            currentTime = t

            if loopEnabled && loopEnd > loopStart && t >= loopEnd {
                seek(to: loopStart)
                return
            }
            if t >= duration {
                stop()
                return
            }
        }

        // VU metering
        for (id, track) in stemTracks {
            let eff   = stemMixers[id]?.outputVolume ?? 0
            let rms   = isPlaying && eff > 0 ? eff * Float.random(in: 0.2...0.85) : max(track.vuLevel * 0.88, 0)
            track.vuLevel   = rms
            track.peakLevel = max(track.peakLevel * 0.96, rms)
        }
    }

    // MARK: - Helpers

    private func scheduleAll(from time: Double) {
        for (id, player) in stemPlayers {
            guard let file = stemFiles[id] else { continue }
            let sr          = file.processingFormat.sampleRate
            let startFrame  = AVAudioFramePosition(time * sr)
            let safeStart   = min(max(startFrame, 0), file.length - 1)
            let frameCount  = AVAudioFrameCount(file.length - safeStart)
            guard frameCount > 0 else { continue }
            player.scheduleSegment(file,
                startingFrame: safeStart,
                frameCount: frameCount,
                at: nil,
                completionHandler: nil)
        }
    }

    private func liveCurrentTime() -> Double {
        guard isPlaying,
              let firstPlayer = stemPlayers.values.first,
              let nodeTime    = firstPlayer.lastRenderTime,
              nodeTime.isSampleTimeValid,
              stemFiles.values.first != nil
        else { return currentTime }

        let playerTime = firstPlayer.playerTime(forNodeTime: nodeTime)
        guard let pt = playerTime, pt.isSampleTimeValid else { return currentTime }

        let elapsed = Double(pt.sampleTime) / pt.sampleRate
        return min(seekOffset + elapsed, duration)
    }

    private func secondsToHostTicks(_ seconds: Double) -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let nanos = UInt64(seconds * 1_000_000_000)
        return nanos * UInt64(info.denom) / UInt64(info.numer)
    }

    private func clearNodes() {
        for p in stemPlayers.values { engine.detach(p) }
        for m in stemMixers.values  { engine.detach(m) }
        stemPlayers.removeAll(); stemMixers.removeAll()
        stemFiles.removeAll();   stemTracks.removeAll()
        duration = 0; currentTime = 0; seekOffset = 0
    }
}
