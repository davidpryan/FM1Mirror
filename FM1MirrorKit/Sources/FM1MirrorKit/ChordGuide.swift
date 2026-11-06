// SPDX-License-Identifier: MPL-2.0
// The chord guide's music: the FM-1's keyboard as LOOM-8 numbers it, scales, the chords of a key, and a voicing that
// says which keys to hold. No UI. (The prototype: FM1Mirror/prototype/index.html.)

/// One of the FM-1's 27 keys, F3 (MIDI 53) to G5 (79), as LOOM-8 counts them: white 1..16, black 1..11.
public struct FM1Key: Equatable, Hashable {
    public let index: Int          // 0..26, F3 = 0
    public let isBlack: Bool
    public let number: Int         // white 1..16 or black 1..11
    public var pitchClass: Int { (53 + index) % 12 }
    /// "W5", "B3"
    public var label: String { (isBlack ? "B" : "W") + String(number) }
}

public enum FM1Keyboard {
    public static let count = 27
    public static let lowestNote = 53            // F3 with OCT at 0
    public static let keys: [FM1Key] = {
        var out: [FM1Key] = []
        var w = 0, b = 0
        for k in 0 ..< 27 {
            let black = [1, 3, 6, 8, 10].contains((53 + k) % 12)
            if black { b += 1 } else { w += 1 }
            out.append(FM1Key(index: k, isBlack: black, number: black ? b : w))
        }
        return out
    }()
    public static var whites: [FM1Key] { keys.filter { !$0.isBlack } }
    public static var blacks: [FM1Key] { keys.filter { $0.isBlack } }

    /// The MIDI note key `k` plays with the FM-1's OCT at `octave` (−2..+2).
    public static func note(of k: FM1Key, octave: Int) -> Int { 53 + k.index + 12 * octave }
    /// The key that plays MIDI note `n` at `octave`, if any.
    public static func key(forNote n: Int, octave: Int) -> FM1Key? {
        let i = n - 53 - 12 * octave
        return i >= 0 && i < 27 ? keys[i] : nil
    }
    public static func range(octave: Int) -> ClosedRange<Int> { (53 + 12 * octave) ... (79 + 12 * octave) }
}

public enum NoteName {
    public static let sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    public static let flats = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    public static func name(_ pc: Int) -> String { sharps[((pc % 12) + 12) % 12] }
    /// "C#/Db" for the black ones, "C" for the rest: the tonic chips
    public static func both(_ pc: Int) -> String {
        let p = ((pc % 12) + 12) % 12
        return sharps[p] == flats[p] ? sharps[p] : sharps[p] + "/" + flats[p]
    }
    /// "C4": the note with its octave (MIDI 60 = C4)
    public static func withOctave(_ n: Int) -> String { name(n % 12) + String(n / 12 - 1) }
}

public enum Scale: String, CaseIterable, Identifiable {
    case major, naturalMinor = "natural minor", harmonicMinor = "harmonic minor", melodicMinor = "melodic minor"
    case dorian, phrygian, lydian, mixolydian, locrian
    case majorPentatonic = "major pentatonic", minorPentatonic = "minor pentatonic", blues

    public var id: String { rawValue }
    public var intervals: [Int] {
        switch self {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: return [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor: return [0, 2, 3, 5, 7, 8, 11]
        case .melodicMinor: return [0, 2, 3, 5, 7, 9, 11]
        case .dorian: return [0, 2, 3, 5, 7, 9, 10]
        case .phrygian: return [0, 1, 3, 5, 7, 8, 10]
        case .lydian: return [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian: return [0, 2, 4, 5, 7, 9, 10]
        case .locrian: return [0, 1, 3, 5, 6, 8, 10]
        case .majorPentatonic: return [0, 2, 4, 7, 9]
        case .minorPentatonic: return [0, 3, 5, 7, 10]
        case .blues: return [0, 3, 5, 6, 7, 10]
        }
    }
    /// Seven notes: chords can be stacked in thirds on each degree.
    public var hasDiatonicChords: Bool { intervals.count == 7 }
}

/// A key: its tonic (pitch class 0..11) and scale.
public struct MusicalKey: Equatable {
    public var tonic: Int
    public var scale: Scale
    public init(tonic: Int, scale: Scale) { self.tonic = tonic; self.scale = scale }

    public var name: String { NoteName.name(tonic) + " " + scale.rawValue }
    public var pitchClasses: [Int] { scale.intervals.map { (tonic + $0) % 12 } }
    public func contains(pitchClass pc: Int) -> Bool { pitchClasses.contains(((pc % 12) + 12) % 12) }

    /// One octave of the scale from the lowest tonic the keys reach at `octave` (the note numbers), the tonic above
    /// closing it; empty when no tonic is in reach.
    public func scaleNotes(octave: Int) -> [Int] {
        let r = FM1Keyboard.range(octave: octave)
        var out: [Int] = []
        for n in r where contains(pitchClass: n % 12) {
            if out.isEmpty && n % 12 != tonic { continue }
            out.append(n)
            if out.count == pitchClasses.count + 1 { break }
        }
        return out
    }

    /// The chord on scale degree `degree` (0..6), stacked in thirds within the scale; a triad, or a seventh.
    public func chord(degree: Int, seventh: Bool) -> Chord? {
        guard scale.hasDiatonicChords, (0 ..< 7).contains(degree) else { return nil }
        let sc = scale.intervals
        func pick(_ j: Int) -> Int { tonic + sc[(degree + j) % 7] + 12 * ((degree + j) / 7) }
        let members = seventh ? [0, 2, 4, 6] : [0, 2, 4]
        let ivs = members.map { pick($0) - pick(0) }
        return Chord(root: (tonic + sc[degree]) % 12, intervals: ivs)
    }

    /// "I", "ii", "vii°", "III+": the degree's numeral as its chord's quality reads
    public func numeral(degree: Int, seventh: Bool) -> String {
        let roman = ["I", "II", "III", "IV", "V", "VI", "VII"]
        guard let c = chord(degree: degree, seventh: seventh), (0 ..< 7).contains(degree) else { return "" }
        let r = roman[degree], q = c.quality
        if q.hasPrefix("dim") || q.hasPrefix("m7♭5") { return r.lowercased() + "°" }
        if q.hasPrefix("aug") { return r + "+" }
        if q.hasPrefix("m") && !q.hasPrefix("maj") { return r.lowercased() }
        return r
    }
}

public struct Chord: Equatable {
    public var root: Int             // pitch class
    public var intervals: [Int]      // from the root, ascending: [0, 4, 7], [0, 3, 7, 10] ...
    public init(root: Int, intervals: [Int]) { self.root = root; self.intervals = intervals }

    public var pitchClasses: [Int] { intervals.map { (root + $0) % 12 } }
    /// "", "m", "dim", "aug", "7", "maj7", "m7", "m7♭5", "dim7", "m(maj7)", "aug7"
    public var quality: String {
        let t = Array(intervals.prefix(3))
        var q: String
        switch t {
        case [0, 4, 7]: q = ""
        case [0, 3, 7]: q = "m"
        case [0, 3, 6]: q = "dim"
        case [0, 4, 8]: q = "aug"
        case [0, 2, 7]: q = "sus2"
        case [0, 5, 7]: q = "sus4"
        default: q = "?"
        }
        if intervals.count > 3 {
            let s = intervals[3]
            switch t {
            case [0, 3, 6]: q = s == 9 ? "dim7" : "m7♭5"
            case [0, 4, 7]: q = s == 11 ? "maj7" : "7"
            case [0, 3, 7]: q = s == 11 ? "m(maj7)" : "m7"
            default: q += "7"
            }
        }
        return q
    }
    public var name: String { NoteName.name(root) + quality }
    /// "C", "Am / C" for an inversion
    public func name(inversion: Int) -> String {
        guard inversion > 0, inversion < intervals.count else { return name }
        return name + " / " + NoteName.name((root + intervals[inversion]) % 12)
    }
    public var noteNames: String { pitchClasses.map(NoteName.name).joined(separator: " · ") }
}

/// Where a chord lands on the keys: the notes to hold, from the lowest bass the keys reach.
public struct Voicing: Equatable {
    public var notes: [Int]          // MIDI notes, ascending
    public var fits: Bool            // at least three notes landed
    public var spilled: Int          // notes left out above the last key
    public var keys: [FM1Key?] { notes.map { FM1Keyboard.key(forNote: $0, octave: octave) } }
    public var octave: Int

    /// Inversion `inversion` (0 root position) of `chord` within the keyboard at `octave`.
    public init(chord: Chord, inversion inv: Int, octave: Int) {
        let n = chord.intervals.count, inversion = inv % max(n, 1)
        let order = (0 ..< n).map { i -> Int in
            let j = (inversion + i) % n
            return chord.intervals[j] + (inversion + i >= n ? 12 : 0)
        }
        let base = order[0]
        let rel = order.map { $0 - base }
        let bassPc = (chord.root + base) % 12
        let r = FM1Keyboard.range(octave: octave)
        self.octave = octave
        var b = r.lowerBound + ((bassPc - r.lowerBound) % 12 + 12) % 12
        while b <= r.upperBound {
            let candidate = rel.map { b + $0 }
            if candidate.allSatisfy({ $0 <= r.upperBound }) {
                notes = candidate; fits = true; spilled = 0
                return
            }
            b += 12
        }
        b = r.lowerBound + ((bassPc - r.lowerBound) % 12 + 12) % 12
        let kept = rel.map { b + $0 }.filter { $0 <= r.upperBound }
        notes = kept
        fits = kept.count >= 3
        spilled = rel.count - kept.count
    }
}
