// SPDX-License-Identifier: MPL-2.0
// The session, on FM1MirrorKit's MirrorLink (the Core MIDI side, the same code mirrorcli proves against an FM-1 from
// a Mac): the FM-1 found among the endpoints, the mirror asked for (cmd 0x50: 2 refresh at the start, 1 every 2 s;
// the device gives up after 6 s without one), refreshed when a frame is missed, off (0) when the app goes to the
// background or the user disconnects. The screen is MirrorScreen's; the picture is drawn 30 times a second at most.
import Combine
import FM1MirrorKit
import Foundation
import UIKit

typealias MIDIDevice = MirrorEndpoint

@MainActor
final class MirrorController: ObservableObject {
    enum State: Equatable { case idle, connecting, mirroring, demo, failed(String) }

    @Published private(set) var devices: [MIDIDevice] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var image: CGImage?
    @Published private(set) var stats = MirrorStats()
    @Published private(set) var hello: MirrorHello?
    @Published private(set) var input: MirrorInput?
    @Published private(set) var wire = MirrorLink.Wire()
    @Published private(set) var mirrorFrames = 0
    @Published var selected: MIDIDevice?

    let screen = MirrorScreen()
    private var link: MirrorLink?
    private var keepAlive: Timer?
    private var redraw: Timer?
    private var lastGeneration = -1
    private var lastRefreshAsk = Date.distantPast
    private var connectedAt = Date.distantPast
    private var demoTask: Task<Void, Never>?
    private var lifecycle: [AnyCancellable] = []

    init() {
        do {
            let l = try MirrorLink(name: "FM1Mirror")
            l.onMessage = { [weak self] msg in Task { @MainActor in self?.handle(msg) } }
            l.onSetupChanged = { [weak self] in Task { @MainActor in self?.rescan() } }
            link = l
        } catch {
            state = .failed(String(describing: error))
        }
        rescan()
        let nc = NotificationCenter.default
        nc.publisher(for: UIApplication.didEnterBackgroundNotification).sink { [weak self] _ in self?.pauseForBackground() }
            .store(in: &lifecycle)
        nc.publisher(for: UIApplication.willEnterForegroundNotification).sink { [weak self] _ in self?.rescan() }
            .store(in: &lifecycle)
    }

    func rescan() {
        guard let link else { return }
        let found = link.endpoints()
        devices = found
        if selected == nil || !found.contains(where: { $0.id == selected?.id }) {
            selected = found.first(where: { $0.looksLikeFM1 && $0.destination != nil }) ?? found.first(where: { $0.destination != nil })
        }
        if case .mirroring = state, link.isConnected, !found.contains(where: { $0.id == selected?.id }) {
            disconnect(note: "The FM-1 was unplugged.")
        }
    }

    // MARK: the session

    func connect() {
        guard let link else { return }
        guard let dev = selected, dev.destination != nil else {
            state = .failed("No MIDI device with an input and an output. Connect the FM-1 by USB-C.")
            return
        }
        stopDemo()
        do { try link.connect(dev) } catch { state = .failed("\(dev.name): \(error)"); return }
        screen.clear()
        screen.resync()
        mirrorFrames = 0
        hello = nil
        state = .connecting
        connectedAt = Date()
        link.send(MirrorScreen.request(2))
        wire = link.wire
        keepAlive?.invalidate()
        keepAlive = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let link = self.link else { return }
                link.send(MirrorScreen.request(1))
                if case .connecting = self.state, Date().timeIntervalSince(self.connectedAt) > 6 {
                    link.send(MirrorScreen.request(2))   // (asked again: the first may have gone before the device was ready)
                }
                self.wire = link.wire
            }
        }
        startRedraw()
    }

    func disconnect(note: String? = nil) {
        keepAlive?.invalidate()
        keepAlive = nil
        if let link, link.isConnected {
            link.send(MirrorScreen.request(0))
            link.disconnect()
        }
        stopRedraw()
        state = note.map { .failed($0) } ?? .idle
    }

    func askRefresh() {
        guard let link, link.isConnected else { return }
        screen.resync()
        link.send(MirrorScreen.request(2))
    }

    private func handle(_ msg: [UInt8]) {
        let r = screen.feed(message: msg)
        if r.cmd != nil { mirrorFrames += 1 }
        if r.cmd == MirrorCommand.request, let h = screen.hello {
            hello = h
            if h.on, case .connecting = state { state = .mirroring }
        }
        if r.cmd == MirrorCommand.input { input = screen.input }
        if r.wantsRefresh, Date().timeIntervalSince(lastRefreshAsk) > 0.5 {
            lastRefreshAsk = Date()
            askRefresh()
        }
        if case .connecting = state, r.cmd == MirrorCommand.rect || r.cmd == MirrorCommand.fill { state = .mirroring }
        stats = screen.stats
    }

    /// The status line's second half: what the wire says while the screen is awaited, or after a failure.
    var wireNote: String {
        let w = link?.wire ?? wire
        if case .connecting = state, Date().timeIntervalSince(connectedAt) > 4 {
            if w.packets == 0 { return "Nothing comes back from the device. Is its USB PORT \"computer\" (LOOM-8: Setup)? " + w.summary }
            if w.sysex == 0 { return "MIDI comes in but no SysEx: not a mirror. " + w.summary }
            if mirrorFrames == 0 { return "SysEx comes in but not the mirror's: the firmware may lack it. " + w.summary }
        }
        return w.summary + " / \(mirrorFrames) mirror"
    }

    // MARK: the picture

    private func startRedraw() {
        redraw?.invalidate()
        redraw = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.redrawIfChanged() }
        }
    }

    private func stopRedraw() {
        redraw?.invalidate()
        redraw = nil
    }

    private func redrawIfChanged() {
        if let link { wire = link.wire }
        guard screen.generation != lastGeneration else { return }
        lastGeneration = screen.generation
        image = Self.makeImage(screen.rgba())
    }

    static func makeImage(_ rgba: [UInt8]) -> CGImage? {
        let w = MirrorScreen.width, h = MirrorScreen.height
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: background

    private func pauseForBackground() {
        switch state {
        case .mirroring, .connecting: disconnect(); state = .idle
        default: break
        }
    }

    // MARK: the demo (a recorded stream, so the app shows a screen with no FM-1 around)

    func startDemo() {
        disconnect()
        guard let url = Bundle.main.url(forResource: "demo", withExtension: "syx"),
              let data = try? Data(contentsOf: url) else {
            state = .failed("No demo recording in the app.")
            return
        }
        var splitter = SysExSplitter()
        let messages = splitter.feed([UInt8](data))
        screen.clear()
        screen.resync()
        state = .demo
        startRedraw()
        demoTask?.cancel()
        demoTask = Task { [weak self] in
            for (k, msg) in messages.enumerated() {      // about the pace it was made: ~150 messages a second
                if Task.isCancelled { return }
                guard let self else { return }
                self.screen.feed(message: msg)
                self.stats = self.screen.stats
                if k % 3 == 0 { try? await Task.sleep(nanoseconds: 20_000_000) }
            }
        }
    }

    func stopDemo() {
        demoTask?.cancel()
        demoTask = nil
        if case .demo = state { state = .idle; stopRedraw() }
    }
}
