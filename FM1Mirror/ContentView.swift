// SPDX-License-Identifier: MPL-2.0
import FM1MirrorKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var mirror: MirrorController
    @State private var chromeHidden = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    if !chromeHidden { toolbar.padding(.horizontal).padding(.top, 6) }
                    Spacer(minLength: 0)
                    ScreenView(image: mirror.image)
                        .frame(width: side(geo), height: side(geo))
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() } }
                    Spacer(minLength: 0)
                    if !chromeHidden { status.padding(.horizontal).padding(.bottom, 8) }
                }
            }
        }
        .statusBarHidden(chromeHidden)
        .onAppear {                                  // (--demo: the recording at once, for a look with no FM-1: simulators, screenshots)
            if CommandLine.arguments.contains("--demo") { mirror.startDemo() }
        }
        .persistentSystemOverlays(chromeHidden ? .hidden : .automatic)
    }

    private func side(_ geo: GeometryProxy) -> CGFloat {
        let reserve: CGFloat = chromeHidden ? 0 : 140
        return max(120, min(geo.size.width, geo.size.height - reserve))
    }

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
            Spacer()
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(dot).frame(width: 9, height: 9)
                Text(stateText).font(.footnote)
                Spacer()
                if mirror.stats.frames > 0 {
                    Text("\(mirror.stats.frames) frames · \(mirror.stats.gaps) gaps · \(mirror.stats.bad) bad")
                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Text("Tap the screen to hide this. Connect the FM-1 by USB-C; its USB PORT must be \"computer\" (LOOM-8's Setup).")
                .font(.caption2).foregroundStyle(.secondary)
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
        case .idle: return mirror.devices.isEmpty ? "No MIDI device found" : "Ready"
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
                    Rectangle().fill(Color(white: 0.08))
                    Text("240 × 240").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
