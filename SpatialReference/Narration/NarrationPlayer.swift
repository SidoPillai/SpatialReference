//
//  NarrationPlayer.swift
//  SpatialReference
//

import AVFoundation

/// Speaks a chapter's narration text and publishes the word range currently
/// being spoken, so a caption view can highlight it in sync.
///
/// Supports pause/resume, word-based skipping, playback speed and a small set
/// of selectable voices. Skipping, speed and voice changes restart the
/// utterance from the current word, since `AVSpeechSynthesizer` can't seek.
///
/// Uses the system's default (non-spatial) speech output for milestone 1.
/// Positioning the narrator's voice in 3D space via RealityKit's spatial
/// audio components is deferred until the immersive asset view (plan step
/// 5) exists — there needs to be an anchor/entity to attach the sound to.
@MainActor
@Observable
final class NarrationPlayer: NSObject, AVSpeechSynthesizerDelegate {
    static let speeds: [Float] = [1, 1.25, 1.5, 0.75]

    /// Rough spoken words-per-second at 1× speed, used for the time labels.
    private static let wordsPerSecond = 2.6

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var fullText = ""
    /// UTF-16 offset in `fullText` where the current utterance starts.
    private var startOffset = 0

    private(set) var isSpeaking = false
    private(set) var isPaused = false
    private(set) var highlightedRange: NSRange?

    private(set) var speed: Float = 1
    private(set) var voiceIndex = 0
    let voices: [AVSpeechSynthesisVoice]

    override init() {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let prefix = String(language.prefix(2))
        var matching = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        // Prefer higher-quality voices, keeping the list short enough to cycle.
        matching.sort { $0.quality.rawValue > $1.quality.rawValue }
        var picked: [AVSpeechSynthesisVoice] = []
        var names = Set<String>()
        for voice in matching where names.insert(voice.name).inserted {
            picked.append(voice)
            if picked.count == 3 { break }
        }
        voices = picked
        super.init()
        synthesizer.delegate = self
    }

    var voiceName: String {
        voices.indices.contains(voiceIndex) ? voices[voiceIndex].name : "Default"
    }

    // MARK: - Progress

    /// Fraction of the text spoken so far, 0...1.
    var progress: Double {
        let length = (fullText as NSString).length
        guard length > 0, let range = highlightedRange else { return 0 }
        return min(1, Double(range.location + range.length) / Double(length))
    }

    /// Estimated total narration time in seconds for the current text.
    var estimatedDuration: TimeInterval {
        Self.estimatedDuration(of: fullText, speed: speed)
    }

    static func estimatedDuration(of text: String, speed: Float) -> TimeInterval {
        let words = text.split(whereSeparator: \.isWhitespace).count
        return Double(words) / (wordsPerSecond * Double(speed))
    }

    // MARK: - Transport

    func speak(_ text: String) {
        speak(text, from: 0)
    }

    private func speak(_ text: String, from offset: Int) {
        stopSynthesizer()
        fullText = text
        let source = text as NSString
        let offset = min(max(0, offset), source.length)
        startOffset = offset
        guard offset < source.length else {
            isSpeaking = false
            return
        }

        let utterance = AVSpeechUtterance(string: source.substring(from: offset))
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * speed)
        if voices.indices.contains(voiceIndex) {
            utterance.voice = voices[voiceIndex]
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        }
        currentUtterance = utterance
        isSpeaking = true
        isPaused = false
        synthesizer.speak(utterance)
    }

    func stop() {
        stopSynthesizer()
        isSpeaking = false
        isPaused = false
        highlightedRange = nil
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    func resume() {
        guard isSpeaking, isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
    }

    /// Moves the narration by whole words (negative goes back) and keeps playing.
    func skip(words delta: Int, in text: String) {
        let ranges = wordRanges(in: text)
        guard !ranges.isEmpty else { return }
        let location = highlightedRange?.location ?? startOffset
        let current = ranges.lastIndex { $0.location <= location } ?? 0
        let target = min(max(0, current + delta), ranges.count - 1)
        speak(text, from: ranges[target].location)
    }

    func cycleSpeed() {
        let index = Self.speeds.firstIndex(of: speed) ?? 0
        speed = Self.speeds[(index + 1) % Self.speeds.count]
        restartAtCurrentWord()
    }

    func cycleVoice() {
        guard voices.count > 1 else { return }
        voiceIndex = (voiceIndex + 1) % voices.count
        restartAtCurrentWord()
    }

    // MARK: - Helpers

    private func restartAtCurrentWord() {
        guard isSpeaking else { return }
        let wasPaused = isPaused
        speak(fullText, from: highlightedRange?.location ?? startOffset)
        if wasPaused { pause() }
    }

    private func stopSynthesizer() {
        currentUtterance = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func wordRanges(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { _, range, _, _ in
            ranges.append(range)
        }
        return ranges
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let current = self.currentUtterance, ObjectIdentifier(current) == id else { return }
            self.highlightedRange = NSRange(location: characterRange.location + self.startOffset, length: characterRange.length)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    /// Ignores callbacks from utterances that have since been replaced, so a
    /// late "cancel" from a restart can't clobber the new utterance's state.
    private nonisolated func finished(_ id: ObjectIdentifier) {
        Task { @MainActor in
            guard let current = self.currentUtterance, ObjectIdentifier(current) == id else { return }
            self.currentUtterance = nil
            self.isSpeaking = false
            self.isPaused = false
            self.highlightedRange = nil
        }
    }
}
