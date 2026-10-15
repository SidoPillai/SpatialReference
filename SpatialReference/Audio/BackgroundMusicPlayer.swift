//
//  BackgroundMusicPlayer.swift
//  SpatialReference
//

import AVFoundation

/// Plays the ambient background music chosen in Settings.
///
/// Music fades in on launch, fades out while the app is in the background or
/// an item is open, softens while narration speaks, and fades out then in on
/// a track change.
final class BackgroundMusicPlayer {
    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    /// Lowered while narration plays; the main mixer handles start/stop fades.
    private let duckMixer = AVAudioMixerNode()
    private var source: AVAudioSourceNode?

    /// The track that is playing or fading in; nil when stopped or stopping.
    private var playingTrackID: String?
    private var isAppActive = false
    private var isViewingItem = false
    private var transition: Task<Void, Never>?
    private var duckFade: Task<Void, Never>?
    private var configurationObserver: (any NSObjectProtocol)?

    private static let volume: Float = 0.5
    private static let duckedLevel: Float = 0.3

    init() {
        engine.attach(reverb)
        engine.attach(duckMixer)
        // A route change (e.g. AirPods connecting) stops the engine.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.playingTrackID != nil else { return }
                self.playingTrackID = nil
                self.refresh()
            }
        }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.backgroundMusic) as? Bool ?? true
    }

    private var selectedTrack: MusicTrack {
        MusicTrack.track(id: UserDefaults.standard.string(forKey: SettingsKey.backgroundMusicTrack))
    }

    func setAppActive(_ active: Bool) {
        isAppActive = active
        refresh()
    }

    /// Pauses the music while an item is open.
    func setViewingItem(_ viewing: Bool) {
        isViewingItem = viewing
        refresh()
    }

    /// Starts, stops or switches tracks to match Settings.
    func refresh() {
        let wanted = isAppActive && !isViewingItem && isEnabled ? selectedTrack : nil
        guard wanted?.id != playingTrackID else { return }
        playingTrackID = wanted?.id
        transition?.cancel()
        transition = Task {
            if engine.isRunning {
                await Self.fade(engine.mainMixerNode, to: 0, over: 0.8)
                guard !Task.isCancelled else { return }
                engine.stop()
            }
            guard let wanted, !Task.isCancelled else { return }
            do {
                try start(wanted)
            } catch {
                playingTrackID = nil
                return
            }
            await Self.fade(engine.mainMixerNode, to: Self.volume, over: 2.5)
        }
    }

    /// Softens the music under narration.
    func setDucked(_ ducked: Bool) {
        duckFade?.cancel()
        duckFade = Task {
            await Self.fade(duckMixer, to: ducked ? Self.duckedLevel : 1, over: ducked ? 0.6 : 1.5)
        }
    }

    private func start(_ track: MusicTrack) throws {
        // Same category as UISounds: mix with other apps' audio.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        if let source { engine.detach(source) }

        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        // Standard (deinterleaved float) stereo is always a valid format.
        let format = AVAudioFormat(standardFormatWithSampleRate: outputRate > 0 ? outputRate : 48_000, channels: 2)!
        let node = AmbientSynth(track: track, sampleRate: format.sampleRate).makeSourceNode(format: format)
        engine.attach(node)
        engine.connect(node, to: reverb, format: format)
        engine.connect(reverb, to: duckMixer, format: format)
        engine.connect(duckMixer, to: engine.mainMixerNode, format: format)
        reverb.loadFactoryPreset(track.reverb)
        reverb.wetDryMix = track.reverbMix
        engine.mainMixerNode.outputVolume = 0
        source = node

        engine.prepare()
        try engine.start()
    }

    private static func fade(_ mixer: AVAudioMixerNode, to target: Float, over duration: Double) async {
        let start = mixer.outputVolume
        let steps = max(1, Int(duration * 30))
        for step in 1...steps {
            try? await Task.sleep(for: .seconds(duration / Double(steps)))
            if Task.isCancelled { return }
            mixer.outputVolume = start + (target - start) * Float(step) / Float(steps)
        }
    }
}
