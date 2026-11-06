// SPDX-License-Identifier: MPL-2.0
// The chord guide beside the mirror: the chord of the key on the left, the key and scale on the right, and the
// numbered keyboard strip where the setting puts it (FM1MirrorKit ChordGuide.swift has the music).
import FM1MirrorKit
import SwiftUI

enum GuideColor {
    static let pane = Color(white: 0.08)
    static let chip = Color(white: 0.15)
    static let on = Color(red: 0.90, green: 0.71, blue: 0.20)
    static let onInk = Color(red: 0.09, green: 0.06, blue: 0.01)
    static let dim = Color(white: 0.55)
    static let root = Color(red: 0.84, green: 0.38, blue: 0.19)
    static let scaleWhite = Color(red: 0.73, green: 0.89, blue: 0.87)
    static let scaleBlack = Color(red: 0.18, green: 0.44, blue: 0.41)
    static let chordBlack = Color(red: 0.73, green: 0.54, blue: 0.11)
}

struct Chip: View {
    let title: String
    let on: Bool
    var small = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(small ? .caption : .footnote.weight(.semibold)).lineLimit(1).fixedSize()
                .padding(.vertical, small ? 3 : 5).padding(.horizontal, small ? 6 : 9)
                .frame(minWidth: 26)
                .background(on ? GuideColor.on : GuideColor.chip, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(on ? GuideColor.onInk : .white)
        }
        .buttonStyle(.plain)
    }
}

/// A key to hold: "W5" over "C4", white or black, the root outlined.
struct KeyChip: View {
    let key: FM1Key?
    let note: Int
    let isRoot: Bool
    var body: some View {
        VStack(spacing: 1) {
            Text(key?.label ?? "?").font(.footnote.weight(.bold))
            Text(NoteName.withOctave(note)).font(.system(size: 9)).opacity(0.75)
        }
        .padding(.vertical, 4).padding(.horizontal, 7)
        .frame(minWidth: 36)
        .background((key?.isBlack ?? true) ? Color(white: 0.18) : Color(white: 0.95), in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle((key?.isBlack ?? true) ? Color.white : Color.black)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke((key?.isBlack ?? true) ? Color(white: 0.4) : .clear, lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isRoot ? GuideColor.root : .clear, lineWidth: 2))
        .opacity(key == nil ? 0.5 : 1)
    }
}

/// Chips that wrap like words: each at its own width, a new line when one does not fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > w { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
struct WrapRow<Content: View>: View {
    let minWidth: CGFloat                           // (unused now: the flow takes each chip's own width)
    @ViewBuilder let content: Content
    var body: some View { FlowLayout(spacing: 4) { content } }
}

struct PaneTitle: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.caption.weight(.bold)).foregroundStyle(GuideColor.dim).kerning(0.5) }
}

/// The 27 keys with their numbers, the scale tinted, the chord lit, the root outlined.
struct KeyboardStrip: View {
    @ObservedObject var g: GuideSettings
    var body: some View {
        let key = g.key, octave = g.octave
        let chordNotes = Set(g.voicing?.notes ?? [])
        let root = g.chord?.root ?? -1
        GeometryReader { geo in
            let whites = FM1Keyboard.whites, ww = geo.size.width / CGFloat(whites.count), h = geo.size.height
            ZStack(alignment: .topLeading) {
                ForEach(whites, id: \.index) { k in
                    let i = whites.firstIndex(of: k)!, n = FM1Keyboard.note(of: k, octave: octave)
                    let inChord = chordNotes.contains(n), inScale = key.contains(pitchClass: k.pitchClass)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(inChord ? GuideColor.on : inScale ? GuideColor.scaleWhite : Color(white: 0.92))
                        .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(inChord && k.pitchClass == root ? GuideColor.root : Color.black.opacity(0.7), lineWidth: inChord && k.pitchClass == root ? 2 : 0.6))
                        .overlay(alignment: .bottom) { Text(String(k.number)).font(.system(size: max(7, min(10, ww * 0.42)), weight: .semibold)).foregroundStyle(Color(white: 0.2)).padding(.bottom, 2) }
                        .frame(width: ww, height: h)
                        .offset(x: CGFloat(i) * ww)
                }
                ForEach(Array(FM1Keyboard.keys.enumerated()), id: \.offset) { pair in
                    let k = pair.element
                    if k.isBlack {
                        let wi = CGFloat(FM1Keyboard.keys[0 ..< k.index].filter { !$0.isBlack }.count)
                        let n = FM1Keyboard.note(of: k, octave: octave)
                        let inChord = chordNotes.contains(n), inScale = key.contains(pitchClass: k.pitchClass)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(inChord ? GuideColor.chordBlack : inScale ? GuideColor.scaleBlack : Color(white: 0.11))
                            .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(inChord && k.pitchClass == root ? GuideColor.root : Color(white: 0.3), lineWidth: inChord && k.pitchClass == root ? 2 : 0.6))
                            .overlay(alignment: .bottom) { Text(String(k.number)).font(.system(size: max(6, min(9, ww * 0.36)), weight: .semibold)).foregroundStyle(Color(white: 0.85)).padding(.bottom, 2) }
                            .frame(width: ww * 0.6, height: h * 0.62)
                            .offset(x: wi * ww - ww * 0.3)
                    }
                }
            }
        }
        .aspectRatio(160.0 / 26.0, contentMode: .fit)
    }
}

struct ChordPane: View {
    @ObservedObject var g: GuideSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(showsIndicators: false) { chordContent.frame(maxWidth: .infinity, alignment: .leading) }
            if g.keyboard == .left { KeyboardStrip(g: g) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GuideColor.pane, in: RoundedRectangle(cornerRadius: 12))
    }
    private var chordContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneTitle(text: "Chord in \(g.key.name)")
            if g.scale.hasDiatonicChords {
                WrapRow(minWidth: 30) {
                    ForEach(0 ..< 7, id: \.self) { d in
                        Chip(title: g.key.numeral(degree: d, seventh: g.seventh), on: g.degree == d) { g.degree = d }
                    }
                }
                HStack(spacing: 6) {
                    let n = g.chord?.intervals.count ?? 3
                    ForEach(0 ..< n, id: \.self) { i in
                        Chip(title: ["Root", "1st", "2nd", "3rd"][i], on: g.inversion == i, small: true) { g.inversion = i }
                    }
                    Chip(title: "7ths", on: g.seventh, small: true) {
                        g.seventh.toggle()
                        if g.inversion >= (g.chord?.intervals.count ?? 3) { g.inversion = 0 }
                    }
                }
                if let c = g.chord, let v = g.voicing {
                    Text(c.name(inversion: g.inversion)).font(.title2.weight(.heavy))
                    Text(c.noteNames + (g.inversion > 0 ? "  (\(NoteName.name((c.root + c.intervals[g.inversion]) % 12)) at the bottom)" : ""))
                        .font(.footnote).foregroundStyle(GuideColor.dim)
                    WrapRow(minWidth: 40) {
                        ForEach(Array(v.notes.enumerated()), id: \.offset) { pair in
                            KeyChip(key: FM1Keyboard.key(forNote: pair.element, octave: g.octave), note: pair.element, isRoot: pair.element % 12 == c.root)
                        }
                    }
                    if !v.fits {
                        Text("Does not fit the keys at this octave: press OCT− on the FM-1 and set it here too.").font(.caption).foregroundStyle(.orange)
                    } else if v.spilled > 0 {
                        Text("The top \(v.spilled == 1 ? "note" : "\(v.spilled) notes") would be above the last key: left out, or press OCT−.").font(.caption).foregroundStyle(.orange)
                    }
                    Text("Hold these together. Root outlined.").font(.caption2).foregroundStyle(GuideColor.dim)
                }
            } else {
                Text("A five- or six-note scale has no stacked-third chords: pick a seven-note scale.").font(.footnote).foregroundStyle(GuideColor.dim)
            }
        }
    }
}

struct KeyScalePane: View {
    @ObservedObject var g: GuideSettings
    var body: some View {
        ScrollView(showsIndicators: false) { VStack(alignment: .leading, spacing: 8) {
            PaneTitle(text: "Key & scale")
            HStack(spacing: 6) {
                Text("Keys").font(.caption2).foregroundStyle(GuideColor.dim)
                HStack(spacing: 2) {
                    ForEach(KeyboardPlacement.allCases) { p in
                        Chip(title: p.title, on: g.keyboard == p, small: true) { g.keyboard = p }
                    }
                }
                .padding(2).background(Color.black, in: RoundedRectangle(cornerRadius: 7))
                .fixedSize()
            }
            WrapRow(minWidth: 34) {
                ForEach(0 ..< 12, id: \.self) { pc in
                    Chip(title: NoteName.both(pc), on: g.tonic == pc, small: true) { g.tonic = pc }
                }
            }
            Picker("Scale", selection: Binding(get: { g.scale }, set: { g.scale = $0; if !$0.hasDiatonicChords { g.degree = 0 } })) {
                ForEach(Scale.allCases) { s in Text(s.rawValue).tag(s) }
            }
            .pickerStyle(.menu).tint(.white)
            .padding(.horizontal, 6).background(GuideColor.chip, in: RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 8) {
                Text("OCT on the FM-1").font(.caption2).foregroundStyle(GuideColor.dim)
                Chip(title: "−", on: false, small: true) { g.octave = max(-2, g.octave - 1) }
                Text(g.octave > 0 ? "+\(g.octave)" : "\(g.octave)").font(.footnote.weight(.bold)).monospacedDigit()
                Chip(title: "+", on: false, small: true) { g.octave = min(2, g.octave + 1) }
            }
            Text(g.key.name).font(.title2.weight(.heavy))
            let notes = g.key.scaleNotes(octave: g.octave)
            WrapRow(minWidth: 40) {
                ForEach(notes, id: \.self) { n in
                    KeyChip(key: FM1Keyboard.key(forNote: n, octave: g.octave), note: n, isRoot: n % 12 == g.tonic)
                }
            }
            Text(notes.isEmpty ? "No \(NoteName.name(g.tonic)) within the keys at this octave." : "One octave from the lowest \(NoteName.name(g.tonic)) the keys reach; the pattern repeats above.")
                .font(.caption2).foregroundStyle(GuideColor.dim)
        }.frame(maxWidth: .infinity, alignment: .leading) }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GuideColor.pane, in: RoundedRectangle(cornerRadius: 12))
    }
}
