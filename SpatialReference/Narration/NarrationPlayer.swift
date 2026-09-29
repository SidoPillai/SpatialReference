//
//  NarrationPlayer.swift
//  SpatialReference
//

import AVFoundation

/// Speaks a chapter's narration text and publishes the word range currently
/// being spoken, so a caption view can highlight it in sync.
///
/// Uses the system's default (non-spatial) speech output for milestone 1.
/// Positioning the narrator's voice in 3D space via RealityKit's spatial
/// audio components is deferred until the immersive asset view (plan step
/// 5) exists — there needs to be an anchor/entity to attach the sound to.
@MainActor
@Observable
final class NarrationPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    private(set) var isSpeaking = false
    private(set) var highlightedRange: NSRange?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        stop()
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        highlightedRange = nil
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.highlightedRange = characterRange
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.highlightedRange = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.highlightedRange = nil
        }
    }
}
