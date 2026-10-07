//
//  MusicTrack.swift
//  SpatialReference
//

import AVFoundation

/// A built-in background music track. Tracks are generated live by
/// `AmbientSynth` instead of being bundled, so they cost no app size and
/// loop without an audible seam.
nonisolated struct MusicTrack: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Pad chords as MIDI note numbers, cycled in order.
    let chords: [[Int]]
    let secondsPerChord: Double
    let padLevel: Double
    /// Level of a sub-octave under each chord's lowest note; 0 for none.
    let bassLevel: Double
    /// Notes (MIDI) the bell melody wanders over; empty for no melody.
    let melodyScale: [Int]
    /// Melody grid; each slot plays a note with probability `noteChance`.
    let notesPerSecond: Double
    let noteChance: Double
    /// Seconds for a bell note to decay by ~63%.
    let bellDecay: Double
    let bellLevel: Double
    /// Filtered-noise swells (surf, wind); 0 for none.
    let waveLevel: Double
    let wavePeriod: Double
    /// Pad low-pass cutoff in Hz; lower is darker.
    let brightness: Double
    let reverb: AVAudioUnitReverbPreset
    let reverbMix: Float

    static let catalog: [MusicTrack] = [
        MusicTrack(
            id: "morningLight", title: "Morning Light",
            chords: [[48, 55, 64, 71], [45, 52, 60, 67], [41, 53, 57, 64], [43, 50, 59, 62]],
            secondsPerChord: 8, padLevel: 0.8, bassLevel: 0,
            melodyScale: [72, 74, 76, 79, 81, 84, 86, 88],
            notesPerSecond: 1.5, noteChance: 0.35, bellDecay: 2.5, bellLevel: 0.12,
            waveLevel: 0, wavePeriod: 1, brightness: 1800,
            reverb: .largeHall, reverbMix: 45),
        MusicTrack(
            id: "oceanDrift", title: "Ocean Drift",
            chords: [[50, 57, 61, 66], [47, 54, 62, 69], [43, 54, 59, 62], [45, 52, 59, 61]],
            secondsPerChord: 12, padLevel: 0.8, bassLevel: 0.3,
            melodyScale: [],
            notesPerSecond: 1, noteChance: 0, bellDecay: 1, bellLevel: 0,
            waveLevel: 0.35, wavePeriod: 10, brightness: 1200,
            reverb: .cathedral, reverbMix: 40),
        MusicTrack(
            id: "musicBox", title: "Music Box",
            chords: [[53, 60, 65, 69], [50, 57, 62, 65], [46, 58, 62, 65], [48, 55, 64, 67]],
            secondsPerChord: 6, padLevel: 0.35, bassLevel: 0,
            melodyScale: [77, 79, 81, 84, 86, 89, 91, 93],
            notesPerSecond: 3, noteChance: 0.6, bellDecay: 1.2, bellLevel: 0.13,
            waveLevel: 0, wavePeriod: 1, brightness: 1400,
            reverb: .mediumHall, reverbMix: 35),
        MusicTrack(
            id: "nightSky", title: "Night Sky",
            chords: [[45, 52, 59, 60, 64], [41, 52, 57, 60, 64], [38, 50, 57, 60, 65], [40, 52, 55, 59, 62]],
            secondsPerChord: 14, padLevel: 0.75, bassLevel: 0.5,
            melodyScale: [81, 84, 86, 88, 91, 93],
            notesPerSecond: 0.7, noteChance: 0.3, bellDecay: 4, bellLevel: 0.07,
            waveLevel: 0.06, wavePeriod: 17, brightness: 900,
            reverb: .cathedral, reverbMix: 55),
    ]

    static let defaultID = "morningLight"

    static func track(id: String?) -> MusicTrack {
        catalog.first { $0.id == id } ?? catalog[0]
    }
}
