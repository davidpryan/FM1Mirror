// SPDX-License-Identifier: MPL-2.0
import FM1MirrorKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var mirror: MirrorController
    @StateObject private var guide = GuideSettings()
    @State private var chromeHidden = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 6) {
                    if !chromeHidden { toolbar.padding(.horizontal, 10).padding(.top, 4) }
                    if guide.shown {
                        if landscape { landscapeBody(geo) } else { portraitBody(geo) }
                    } else {
                        Spacer(minLength: 0)
                        screen.frame(width: plainSide(geo), height: plainSide(geo))
                        Spacer(minLength: 0)
                    }
                    if !chromeHidden { status.padding(.horizontal, 10).padding(.bottom, 6) }
                }
            }
        }
        .statusBarHidden(chromeHidden)
        .persistentSystemOverlays(chromeHidden ? .hidden : .automatic)
        .onAppear {                                  // (--demo: the recording at once, for a look with no FM-1: simulators, screenshots)
            if CommandLine.arguments.contains("--demo") { mirror.startDemo() }
        }
    }

    // MARK: layouts

    private func landscapeBody(_ geo: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ChordPane(g: guide).frame(maxWidth: .infinity)
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                screen.aspectRatio(1, contentMode: .fit)
                if guide.keyboard == .centre { KeyboardStrip(g: guide); legend }
                Spacer(minLength: 0)
            }
            .frame(width: max(200, geo.size.height - (chromeHidden ? 20 : 110)))
            KeyScalePane(g: guide).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
    }

    private func portraitBody(_ geo: GeometryProxy) -> some View {
        VStack(spacing: 6) {
            screen.aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
            if guide.keyboard == .centre { KeyboardStrip(g: guide).padding(.horizontal, 8); legend }
            HStack(alignment: .top, spacing: 6) {
                ScrollView { ChordPane(g: guide) }
                ScrollView { KeyScalePane(g: guide) }
            }
            .padding(.horizontal, 8)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            Label { Text("in the scale") } icon: { RoundedRectangle(cornerRadius: 2).fill(GuideColor.scaleWhite).frame(width: 9, height: 9) }
            Label { Text("the chord") } icon: { RoundedRectangle(cornerRadius: 2).fill(GuideColor.on).frame(width: 9, height: 9) }
            Label { Text("root") } icon: { RoundedRectangle(cornerRadius: 2).stroke(GuideColor.root, lineWidth: 2).frame(width: 9, height: 9) }
        }
        .font(.system(size: 9)).foregroundStyle(GuideColor.dim)
    }

    private var screen: some View {
        ScreenView(image: mirror.image)
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() } }
    }

    private func plainSide(_ geo: GeometryProxy) -> CGFloat {
        let reserve: CGFloat = chromeHidden ? 0 : 140
        return max(120, min(geo.size.width, geo.size.height - reserve))
    }

    // MARK: chrome

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Device", selection: $mirror.selected) {
                Text("No device").tag(MIDIDevice?.none)
                ForEach(mirror.devices) { d in
                    Text(d.name + (d.destination == nil ? " (input only)" : "")).tag(MIDIDevice?.some(d))
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .lineLimit(1)
            Spacer()
            Button(guide.shown ? "Hide guide" : "Guide") { withAnimation { guide.shown.toggle() } }
            switch mirror.state {
            case .mirroring, .connecting:
                Button("Refresh") { mirror.askRefresh() }
                Button("Stop", role: .destructive) { mirror.disconnect() }
            case .demo:
                Button("Stop demo") { mirror.stopDemo() }
            default:
                Button("Mirror") { mirror.connect() }.buttonStyle(.borderedProminent)
                Button("Demo") { mirror.startDemo() }
            }
        }
        .font(.callout)
    }

    private var status: some View {
        HStack {
            Circle().fill(dot).frame(width: 9, height: 9)
            Text(stateText).font(.footnote).lineLimit(1)
            Spacer()
            if mirror.stats.frames > 0 {
                Text("\(mirror.stats.frames) frames · \(mirror.stats.gaps) gaps · \(mirror.stats.bad) bad")
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private var dot: Color {
        switch mirror.state {
        case .mirroring: return .green
        case .connecting, .demo: return .yellow
        case .failed: return .red
        case .idle: return .gray
        }
    }

    private var stateText: String {
        switch mirror.state {
        case .idle: return mirror.devices.isEmpty ? "No MIDI device: connect the FM-1 by USB-C (USB PORT: computer)" : "Ready"
        case .connecting: return "Asking for the screen…"
        case .mirroring:
            if let h = mirror.hello { return "Mirroring (mirror version \(h.version), \(h.width) × \(h.height))" }
            return "Mirroring"
        case .demo: return "Demo: a recorded LOOM-8 session"
        case .failed(let why): return why
        }
    }
}

struct ScreenView: View {
    let image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
            } else {
                ZStack {
                    Rectangle().fill(Color(white: 0.08)).aspectRatio(1, contentMode: .fit)
                    Text("240 × 240").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
