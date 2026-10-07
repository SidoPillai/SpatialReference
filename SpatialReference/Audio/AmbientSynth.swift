//
//  AmbientSynth.swift
//  SpatialReference
//

import AVFoundation

/// Real-time generator for a `MusicTrack`: slow crossfading pad chords, a
/// sparse bell melody that random-walks over a scale, and optional
/// filtered-noise swells.
///
/// Once its source node is attached, the synth is driven only from the audio
/// render thread, so its state is never touched from anywhere else. Voices
/// live in preallocated buffers so rendering never allocates.
nonisolated final class AmbientSynth: @unchecked Sendable {

    private struct PadVoice {
        var active = false
        var step = 0.0
        var phaseL = 0.0
        var phaseR = 0.0
        var amp = 0.0
        var target = 0.0
        var gain = 0.0
        var lfoPhase = 0.0
        var lfoStep = 0.0
    }

    private struct BellVoice {
        var active = false
        var step = 0.0
        var phase = 0.0
        var overtonePhase = 0.0
        var level = 0.0
        var overtoneLevel = 0.0
        var age = 0.0
        var gain = 0.0
        var panL = 0.0
        var panR = 0.0
    }

    private static let padCount = 24
    private static let bellCount = 16
    /// Stereo detune of each pad voice (~2.6 cents) for width and movement.
    private static let detune = 0.0015

    private let track: MusicTrack
    private let sampleRate: Double
    private let pads = UnsafeMutablePointer<PadVoice>.allocate(capacity: padCount)
    private let bells = UnsafeMutablePointer<BellVoice>.allocate(capacity: bellCount)

    private let samplesPerChord: Int
    private let samplesPerNote: Int
    private let padCoeff: Double
    private let padLowpass: Double
    private let bellDecay: Double
    private let overtoneDecay: Double
    private let attackSamples: Double

    private var clock = 0
    private var chordIndex = -1
    private var melodyIndex: Int
    private var rng = UInt64.random(in: 1 ... .max)
    private var lowL = 0.0, lowR = 0.0
    private var surfL = 0.0, surfR = 0.0

    init(track: MusicTrack, sampleRate: Double) {
        self.track = track
        self.sampleRate = sampleRate
        samplesPerChord = max(1, Int(track.secondsPerChord * sampleRate))
        samplesPerNote = max(1, Int(sampleRate / track.notesPerSecond))
        // Chords crossfade over roughly a third of their length.
        padCoeff = 1 - exp(-1 / (track.secondsPerChord * 0.3 * sampleRate))
        padLowpass = 1 - exp(-2 * .pi * track.brightness / sampleRate)
        bellDecay = exp(-1 / (track.bellDecay * sampleRate))
        overtoneDecay = exp(-1 / (track.bellDecay * 0.25 * sampleRate))
        attackSamples = 0.004 * sampleRate
        melodyIndex = track.melodyScale.count / 2
        pads.initialize(repeating: PadVoice(), count: Self.padCount)
        bells.initialize(repeating: BellVoice(), count: Self.bellCount)
    }

    deinit {
        pads.deinitialize(count: Self.padCount)
        pads.deallocate()
        bells.deinitialize(count: Self.bellCount)
        bells.deallocate()
    }

    func makeSourceNode(format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { [self] _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            render(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
    }

    // MARK: - Rendering

    private func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        let twoPi = 2 * Double.pi
        for frame in 0..<frames {
            if clock % samplesPerChord == 0 { advanceChord() }
            // Offset by half a slot so bells land between chord changes, and
            // hold them for the first two seconds while the pad fades in.
            if !track.melodyScale.isEmpty,
               clock % samplesPerNote == samplesPerNote / 2,
               Double(clock) > 2 * sampleRate,
               random() < track.noteChance {
                strikeBell()
            }

            var padL = 0.0, padR = 0.0
            for i in 0..<Self.padCount where pads[i].active {
                var v = pads[i]
                v.amp += (v.target - v.amp) * padCoeff
                let tremolo = 0.7 + 0.3 * sin(twoPi * v.lfoPhase)
                let level = v.amp * v.gain * tremolo
                padL += Self.padTone(v.phaseL) * level
                padR += Self.padTone(v.phaseR) * level
                v.phaseL += v.step * (1 - Self.detune)
                v.phaseR += v.step * (1 + Self.detune)
                if v.phaseL >= 1 { v.phaseL -= 1 }
                if v.phaseR >= 1 { v.phaseR -= 1 }
                v.lfoPhase += v.lfoStep
                if v.lfoPhase >= 1 { v.lfoPhase -= 1 }
                if v.target == 0 && v.amp < 0.0001 { v.active = false }
                pads[i] = v
            }
            lowL += padLowpass * (padL - lowL)
            lowR += padLowpass * (padR - lowR)
            var l = lowL, r = lowR

            for i in 0..<Self.bellCount where bells[i].active {
                var b = bells[i]
                let attack = min(1, b.age / attackSamples)
                let s = (sin(twoPi * b.phase) * b.level + 0.35 * sin(twoPi * b.overtonePhase) * b.overtoneLevel)
                    * attack * b.gain
                l += s * b.panL
                r += s * b.panR
                b.level *= bellDecay
                b.overtoneLevel *= overtoneDecay
                b.phase += b.step
                // Slightly inharmonic overtone gives a soft bell/celesta color.
                b.overtonePhase += b.step * 2.76
                if b.phase >= 1 { b.phase -= 1 }
                if b.overtonePhase >= 1 { b.overtonePhase -= floor(b.overtonePhase) }
                b.age += 1
                if b.level < 0.0005 { b.active = false }
                bells[i] = b
            }

            if track.waveLevel > 0 {
                let t = Double(clock) / sampleRate / track.wavePeriod
                let swellL = pow(0.5 - 0.5 * cos(twoPi * t), 2)
                let swellR = pow(0.5 - 0.5 * cos(twoPi * (t + 0.08)), 2)
                // Small-angle one-pole approximation; the cutoff opens as a swell builds.
                surfL += twoPi * (250 + 1100 * swellL) / sampleRate * (noise() - surfL)
                surfR += twoPi * (250 + 1100 * swellR) / sampleRate * (noise() - surfR)
                l += surfL * swellL * track.waveLevel * 2
                r += surfR * swellR * track.waveLevel * 2
            }

            left[frame] = Float(tanh(l))
            right[frame] = Float(tanh(r))
            clock += 1
        }
    }

    /// Soft organ-like tone: a sine with two quiet harmonics.
    private static func padTone(_ phase: Double) -> Double {
        let x = 2 * Double.pi * phase
        return sin(x) + 0.35 * sin(2 * x) + 0.12 * sin(3 * x)
    }

    private func advanceChord() {
        chordIndex = (chordIndex + 1) % track.chords.count
        for i in 0..<Self.padCount { pads[i].target = 0 }
        let chord = track.chords[chordIndex]
        for note in chord {
            startPad(note: note, gain: track.padLevel * 0.09)
        }
        if track.bassLevel > 0, let root = chord.min() {
            startPad(note: root - 12, gain: track.bassLevel * 0.12)
        }
    }

    private func startPad(note: Int, gain: Double) {
        guard let i = (0..<Self.padCount).first(where: { !pads[$0].active }) else { return }
        pads[i] = PadVoice(
            active: true,
            step: Self.frequency(note) / sampleRate,
            phaseL: random(), phaseR: random(),
            amp: 0, target: 1, gain: gain,
            lfoPhase: random(), lfoStep: (0.05 + 0.1 * random()) / sampleRate)
    }

    private func strikeBell() {
        guard let i = (0..<Self.bellCount).first(where: { !bells[$0].active }) else { return }
        let scale = track.melodyScale
        melodyIndex = min(scale.count - 1, max(0, melodyIndex + Int(random() * 5) - 2))
        let pan = 0.2 + 0.6 * random()
        bells[i] = BellVoice(
            active: true,
            step: Self.frequency(scale[melodyIndex]) / sampleRate,
            level: 1, overtoneLevel: 1,
            gain: track.bellLevel * (0.7 + 0.3 * random()),
            panL: sqrt(1 - pan), panR: sqrt(pan))
    }

    private static func frequency(_ midiNote: Int) -> Double {
        440 * pow(2, Double(midiNote - 69) / 12)
    }

    /// xorshift64*, uniform in 0..<1. Realtime-safe (no locks or syscalls).
    private func random() -> Double {
        rng ^= rng >> 12
        rng ^= rng << 25
        rng ^= rng >> 27
        return Double((rng &* 0x2545F4914F6CDD1D) >> 11) / Double(1 << 53)
    }

    private func noise() -> Double {
        random() * 2 - 1
    }
}
