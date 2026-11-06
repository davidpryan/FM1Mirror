// SPDX-License-Identifier: MPL-2.0
// The session: a Core MIDI client, the FM-1 found among the sources, the mirror asked for, kept alive (cmd 0x50:
// 2 refresh at the start, 1 every 2 s; the device gives up after 6 s without one), refreshed when a frame is missed,
// and turned off (0) when the app goes to the background or the user disconnects. The screen is FM1MirrorKit's.
import Combine
import CoreMIDI
import FM1MirrorKit
import Foundation
import UIKit

struct MIDIDevice: Identifiable, Hashable {
    let id: MIDIUniqueID
    let name: String
    let source: MIDIEndpointRef
    let destination: MIDIEndpointRef?

    /// The FM-1 firmwares name their port after the app: "LOOM-8 FM-1", "FM-1 Midi", "ChoralRoot FM-1", "Felucca".
    var looksLikeFM1: Bool {
        let n = name.lowercased()
        return n.contains("fm-1") || n.contains("fm1") || n.contains("loom") || n.contains("choralroot") || n.contains("felucca")
    }
}

@MainActor
final class MirrorController: ObservableObject {
    enum State: Equatable { case idle, connecting, mirroring, demo, failed(String) }

    @Published private(set) var devices: [MIDIDevice] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var image: CGImage?
    @Published private(set) var stats = MirrorStats()
    @Published private(set) var hello: MirrorHello?
    @Published private(set) var input: MirrorInput?
    @Published var selected: MIDIDevice?

    let screen = MirrorScreen()
    private var client = MIDIClientRef()
    private var inPort = MIDIPortRef()
    private var outPort = MIDIPortRef()
    private var connectedSource: MIDIEndpointRef = 0
    private var destination: MIDIEndpointRef = 0
    private var assembler = UMPSysExAssembler()
    private var keepAlive: Timer?
    private var redraw: Timer?
    private var lastGeneration = -1
    private var lastRefreshAsk = Date.distantPast
    private var demoTask: Task<Void, Never>?
    private var lifecycle: [AnyCancellable] = []

    init() {
        setUpMIDI()
        rescan()
        let nc = NotificationCenter.default
        nc.publisher(for: UIApplication.didEnterBackgroundNotification).sink { [weak self] _ in self?.pauseForBackground() }
            .store(in: &lifecycle)
        nc.publisher(for: UIApplication.willEnterForegroundNotification).sink { [weak self] _ in self?.resumeFromBackground() }
            .store(in: &lifecycle)
    }

    // MARK: Core MIDI

    private func setUpMIDI() {
        let status = MIDIClientCreateWithBlock("FM1Mirror" as CFString, &client) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        }
        guard status == noErr else { state = .failed("Core MIDI client: \(status)"); return }
        MIDIInputPortCreateWithProtocol(client, "FM1Mirror in" as CFString, ._1_0, &inPort) { [weak self] list, _ in
            // (Core MIDI's own thread: the words copied out, the parsing on the main actor)
            var words: [UInt32] = []
            let count = Int(list.pointee.numPackets)
            var packet = list.pointee.packet
            for _ in 0 ..< count {
                let n = Int(packet.wordCount)
                withUnsafeBytes(of: &packet.words) { raw in
                    let p = raw.bindMemory(to: UInt32.self)
                    words.append(contentsOf: p.prefix(n))
                }
                packet = MIDIEventPacketNext(&packet).pointee
            }
            Task { @MainActor in self?.receive(words: words) }
        }
        MIDIOutputPortCreate(client, "FM1Mirror out" as CFString, &outPort)
    }

    func rescan() {
        var found: [MIDIDevice] = []
        for i in 0 ..< MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            var entity = MIDIEntityRef()
            MIDIEndpointGetEntity(src, &entity)
            var dest: MIDIEndpointRef? = nil
            if entity != 0, MIDIEntityGetNumberOfDestinations(entity) > 0 {
                dest = MIDIEntityGetDestination(entity, 0)
            }
            found.append(MIDIDevice(id: uniqueID(src), name: displayName(src), source: src, destination: dest))
        }
        devices = found
        if selected == nil || !found.contains(where: { $0.id == selected?.id }) {
            selected = found.first(where: { $0.looksLikeFM1 && $0.destination != nil }) ?? found.first(where: { $0.destination != nil })
        }
        if case .mirroring = state, !found.contains(where: { $0.source == connectedSource }) {
            disconnect(note: "The FM-1 was unplugged.")
        }
    }

    private func uniqueID(_ e: MIDIEndpointRef) -> MIDIUniqueID {
        var id: MIDIUniqueID = 0
        MIDIObjectGetIntegerProperty(e, kMIDIPropertyUniqueID, &id)
        return id
    }

    private func displayName(_ e: MIDIEndpointRef) -> String {
        var cf: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &cf) == noErr, let s = cf?.takeRetainedValue() {
            return s as String
        }
        if MIDIObjectGetStringProperty(e, kMIDIPropertyName, &cf) == noErr, let s = cf?.takeRetainedValue() {
            return s as String
        }
        return "MIDI device"
    }

    // MARK: the session

    func connect() {
        guard let dev = selected, let dest = dev.destination else {
            state = .failed("No MIDI device with an input and an output. Connect the FM-1 by USB-C.")
            return
        }
        stopDemo()
        if connectedSource != 0 { MIDIPortDisconnectSource(inPort, connectedSource) }
        let status = MIDIPortConnectSource(inPort, dev.source, nil)
        guard status == noErr else { state = .failed("Could not listen to \(dev.name): \(status)"); return }
        connectedSource = dev.source
        destination = dest
        assembler = UMPSysExAssembler()
        screen.clear()
        screen.resync()
        state = .connecting
        send(MirrorScreen.request(2))
        keepAlive?.invalidate()
        keepAlive = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.send(MirrorScreen.request(1)) }
        }
        startRedraw()
    }

    func disconnect(note: String? = nil) {
        keepAlive?.invalidate()
        keepAlive = nil
        if destination != 0 { send(MirrorScreen.request(0)) }
        if connectedSource != 0 { MIDIPortDisconnectSource(inPort, connectedSource) }
        connectedSource = 0
        destination = 0
        stopRedraw()
        state = note.map { .failed($0) } ?? .idle
    }

    func askRefresh() {
        guard destination != 0 else { return }
        screen.resync()
        send(MirrorScreen.request(2))
    }

    private func send(_ message: [UInt8]) {
        guard destination != 0 else { return }
        let words = UMPSysEx.packets(for: message)
        // one event list per message; a long SysEx is several packets, each 2 words
        var list = MIDIEventList()
        let cap = 64
        var packet = MIDIEventListInit(&list, ._1_0)
        var i = 0
        while i < words.count {
            let n = min(cap, words.count - i)
            let chunk = Array(words[i ..< i + n])
            packet = chunk.withUnsafeBufferPointer { MIDIEventListAdd(&list, 1024, packet, 0, n, $0.baseAddress!) }
            i += n
        }
        MIDISendEventList(outPort, destination, &list)
    }

    private func receive(words: [UInt32]) {
        for msg in assembler.feed(words: words) {
            let r = screen.feed(message: msg)
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
        }
        stats = screen.stats
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
        if case .mirroring = state { disconnect() ; state = .idle }
        if case .connecting = state { disconnect() ; state = .idle }
    }

    private func resumeFromBackground() {
        rescan()
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
            // the recording at about the pace it was made: ~150 messages a second
            for (k, msg) in messages.enumerated() {
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
