// SPDX-License-Identifier: MPL-2.0
// The chord guide's choices, kept between launches.
import Combine
import FM1MirrorKit
import SwiftUI

enum KeyboardPlacement: String, CaseIterable, Identifiable {
    case off, centre, left
    var id: String { rawValue }
    var title: String { self == .off ? "Off" : self == .centre ? "Centre" : "Left" }
}

@MainActor
final class GuideSettings: ObservableObject {
    @AppStorage("guide.shown") var shown = true
    @AppStorage("guide.tonic") var tonic = 0
    @AppStorage("guide.scale") var scaleRaw = Scale.major.rawValue
    @AppStorage("guide.octave") var octave = 0
    @AppStorage("guide.degree") var degree = 0
    @AppStorage("guide.seventh") var seventh = false
    @AppStorage("guide.inversion") var inversion = 0
    @AppStorage("guide.keyboard") var keyboardRaw = KeyboardPlacement.left.rawValue

    var scale: Scale {
        get { Scale(rawValue: scaleRaw) ?? .major }
        set { scaleRaw = newValue.rawValue }
    }
    var keyboard: KeyboardPlacement {
        get { KeyboardPlacement(rawValue: keyboardRaw) ?? .left }
        set { keyboardRaw = newValue.rawValue }
    }
    var key: MusicalKey { MusicalKey(tonic: tonic, scale: scale) }
    var chord: Chord? { key.chord(degree: degree, seventh: seventh) }
    var voicing: Voicing? { chord.map { Voicing(chord: $0, inversion: inversion, octave: octave) } }
}
