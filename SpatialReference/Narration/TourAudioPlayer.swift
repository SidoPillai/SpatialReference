//
//  TourAudioPlayer.swift
//  SpatialReference
//

import AVFoundation

/// Plays a tour stop's recorded narration (an mp3 item resource) and
/// publishes its progress for the stop's transport bar.
///
/// Separate from `NarrationPlayer`, which speaks text with the speech
/// synthesizer; a tour stop without a recording falls back to that.
@MainActor
@Observable
final class TourAudioPlayer {
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var durationTask: Task<Void, Never>?

    private(set) var isPlaying = false
    /// Bumped each time a recording plays to the end, so views can react
    /// (e.g. move on to the next stop) with `onChange`.
    private(set) var finishCount = 0
    private(set) var didFinish = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// Set when the file can't be played (e.g. a corrupt download).
    private(set) var failure: String?
    /// The file being played, so a failed one can be dropped from the cache.
    private(set) var url: URL?
    /// Whether a recording is loaded (playing, paused or finished).
    var isLoaded: Bool { player != nil }

    var progress: Double {
        duration > 0 ? min(1, currentTime / duration) : 0
    }

    /// Starts playing a local audio file from the beginning.
    func play(url: URL) {
        stop()
        self.url = url
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        // The item's own duration is often indefinite for mp3s until it's
        // been read, so ask the asset for it.
        durationTask = Task { [weak self] in
            guard let seconds = try? await item.asset.load(.duration).seconds, seconds.isFinite else { return }
            self?.duration = seconds
        }
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "The narration couldn’t be played."
            Task { @MainActor [weak self] in
                self?.isPlaying = false
                self?.failure = message
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, time.seconds.isFinite else { return }
                self.currentTime = time.seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.didFinish = true
                self.currentTime = self.duration
                self.finishCount += 1
            }
        }

        player.play()
        isPlaying = true
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if didFinish {
                player.seek(to: .zero)
                currentTime = 0
                didFinish = false
            }
            player.play()
            isPlaying = true
        }
    }

    /// Jumps forwards or backwards by `seconds`, clamped to the recording.
    func skip(by seconds: TimeInterval) {
        guard let player else { return }
        let target = min(max(0, currentTime + seconds), max(0, duration))
        currentTime = target
        didFinish = false
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func stop() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        durationTask?.cancel()
        statusObservation = nil
        timeObserver = nil
        endObserver = nil
        durationTask = nil
        player?.pause()
        player = nil
        url = nil
        isPlaying = false
        didFinish = false
        failure = nil
        currentTime = 0
        duration = 0
    }
}
