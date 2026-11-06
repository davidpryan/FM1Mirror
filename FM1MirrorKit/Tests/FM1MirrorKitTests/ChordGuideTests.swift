// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import FM1MirrorKit

final class ChordGuideTests: XCTestCase {
    func testKeyboardNumbering() {
        XCTAssertEqual(FM1Keyboard.whites.count, 16)
        XCTAssertEqual(FM1Keyboard.blacks.count, 11)
        XCTAssertEqual(FM1Keyboard.keys[0].label, "W1")                 // F3
        XCTAssertEqual(FM1Keyboard.keys[1].label, "B1")                 // F#3
        XCTAssertEqual(FM1Keyboard.key(forNote: 60, octave: 0)?.label, "W5")   // C4
        XCTAssertEqual(FM1Keyboard.key(forNote: 72, octave: 1)?.label, "W5")   // C5 with OCT +1
        XCTAssertNil(FM1Keyboard.key(forNote: 52, octave: 0))
        XCTAssertEqual(FM1Keyboard.keys.last?.label, "W16")             // G5
        XCTAssertEqual(NoteName.withOctave(60), "C4")
        XCTAssertEqual(NoteName.both(1), "C#/Db")
    }

    func testCMajorTriads() {
        let key = MusicalKey(tonic: 0, scale: .major)
        let names = (0 ..< 7).map { key.chord(degree: $0, seventh: false)!.name }
        XCTAssertEqual(names, ["C", "Dm", "Em", "F", "G", "Am", "Bdim"])
        let numerals = (0 ..< 7).map { key.numeral(degree: $0, seventh: false) }
        XCTAssertEqual(numerals, ["I", "ii", "iii", "IV", "V", "vi", "vii°"])
        let sevenths = (0 ..< 7).map { key.chord(degree: $0, seventh: true)!.name }
        XCTAssertEqual(sevenths, ["Cmaj7", "Dm7", "Em7", "Fmaj7", "G7", "Am7", "Bm7♭5"])
        let v = Voicing(chord: key.chord(degree: 0, seventh: false)!, inversion: 0, octave: 0)
        XCTAssertEqual(v.keys.map { $0?.label }, ["W5", "W7", "W9"])    // C4 E4 G4
        XCTAssertTrue(v.fits)
    }

    func testDSharpMinorOnBlackKeys() {
        let key = MusicalKey(tonic: 3, scale: .naturalMinor)
        let i = key.chord(degree: 0, seventh: false)!
        XCTAssertEqual(i.name, "D#m")
        let v = Voicing(chord: i, inversion: 0, octave: 0)
        XCTAssertEqual(v.keys.map { $0?.label }, ["B5", "B6", "B8"])    // D#4 F#4 A#4
        XCTAssertEqual(key.scaleNotes(octave: 0).map { FM1Keyboard.key(forNote: $0, octave: 0)!.label },
                       ["B5", "W8", "B6", "B7", "B8", "W11", "B9", "B10"])
    }

    func testInversions() {
        let key = MusicalKey(tonic: 0, scale: .major)
        let am = key.chord(degree: 5, seventh: false)!
        let first = Voicing(chord: am, inversion: 1, octave: 0)
        XCTAssertEqual(am.name(inversion: 1), "Am / C")
        XCTAssertEqual(first.keys.map { $0?.label }, ["W5", "W7", "W10"])   // C4 E4 A4
        let second = Voicing(chord: am, inversion: 2, octave: 0)
        XCTAssertEqual(second.notes, [64, 69, 72])                         // E4 A4 C5
        let g7 = key.chord(degree: 4, seventh: true)!
        XCTAssertEqual(g7.name(inversion: 3), "G7 / F")
        XCTAssertEqual(Voicing(chord: g7, inversion: 3, octave: 0).notes, [53, 55, 59, 62])   // F3 G3 B3 D4
    }

    func testSpillAndOctave() {
        // Bdim7 on C harmonic minor's vii, root position from B4 (71): B4 D5 F5 G#5 -> G#5 (80) is past G5
        let key = MusicalKey(tonic: 0, scale: .harmonicMinor)
        let vii = key.chord(degree: 6, seventh: true)!
        XCTAssertEqual(vii.name, "Bdim7")
        let v = Voicing(chord: vii, inversion: 0, octave: 0)
        XCTAssertEqual(v.notes, [59, 62, 65, 68])                          // it drops an octave and fits whole
        XCTAssertTrue(v.fits)
        // with OCT +1 the keys start at F4: B4 D5 F5 G#5 fits (G#5 = 80 <= 91)
        XCTAssertEqual(Voicing(chord: vii, inversion: 0, octave: 1).notes, [71, 74, 77, 80])
        // a chord whose only placement spills: C9-like five notes are not diatonic; use a wide seventh at OCT -2
        let wide = Chord(root: 5, intervals: [0, 4, 7, 11])                // Fmaj7 from F3 at OCT 0 fits
        XCTAssertEqual(Voicing(chord: wide, inversion: 0, octave: 0).notes, [53, 57, 60, 64])
    }

    func testPentatonicHasNoChords() {
        let key = MusicalKey(tonic: 9, scale: .minorPentatonic)
        XCTAssertNil(key.chord(degree: 0, seventh: false))
        XCTAssertEqual(key.scaleNotes(octave: 0).count, 6)                // five notes and the tonic above
    }
}
