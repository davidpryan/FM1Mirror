// SPDX-License-Identifier: MPL-2.0
// The Core MIDI side of the mirror, the same on iOS and macOS: the endpoints, one connected source with its paired
// destination, SysEx out as Universal MIDI Packets, SysEx in reassembled from them. No UI: the app wraps it, and
// mirrorcli drives it from a Mac against a real FM-1.
#if canImport(CoreMIDI)
import CoreMIDI
import Foundation

public struct MirrorEndpoint: Identifiable, Hashable {
    public let id: MIDIUniqueID
    public let name: String
    public let source: MIDIEndpointRef
    public let destination: MIDIEndpointRef?

    /// The FM-1 firmwares name their port after the app ("LOOM-8 FM-1", "FM-1 Midi", "ChoralRoot FM-1", "Felucca");
    /// macOS may also keep an earlier firmware's name for the same USB device.
    public var looksLikeFM1: Bool {
        let n = name.lowercased()
        return n.contains("fm-1") || n.contains("fm1") || n.contains("loom") || n.contains("choralroot") || n.contains("felucca")
    }
}

public final class MirrorLink {
    public struct Wire: Equatable {
        public var sent = 0, sendErrors = 0, lastSendStatus: OSStatus = 0
        public var packets = 0, words = 0, sysex = 0
        public var lastHead = ""
        public init() {}
        public var summary: String {
            var s = "out \(sent)" + (sendErrors > 0 ? " (\(sendErrors) failed, \(lastSendStatus))" : "")
            s += " · in \(packets) pkt / \(words) words / \(sysex) sysex"
            if !lastHead.isEmpty { s += " · last " + lastHead }
            return s
        }
    }

    /// A whole F0 .. F7 message from the connected source (Core MIDI's thread).
    public var onMessage: (([UInt8]) -> Void)?
    /// The MIDI setup changed (a device came or went); Core MIDI's thread.
    public var onSetupChanged: (() -> Void)?

    private var client = MIDIClientRef()
    private var inPort = MIDIPortRef()
    private var outPort = MIDIPortRef()
    private var connectedSource: MIDIEndpointRef = 0
    private var destination: MIDIEndpointRef = 0
    private var assembler = UMPSysExAssembler()
    private let lock = NSLock()
    private var wireValue = Wire()
    public var wire: Wire { lock.lock(); defer { lock.unlock() }; return wireValue }
    public var isConnected: Bool { connectedSource != 0 }

    public init(name: String = "FM1Mirror") throws {
        var status = MIDIClientCreateWithBlock(name as CFString, &client) { [weak self] _ in self?.onSetupChanged?() }
        guard status == noErr else { throw LinkError.client(status) }
        status = MIDIInputPortCreateWithProtocol(client, "\(name) in" as CFString, ._1_0, &inPort) { [weak self] list, _ in
            self?.receive(list)
        }
        guard status == noErr else { throw LinkError.port(status) }
        status = MIDIOutputPortCreate(client, "\(name) out" as CFString, &outPort)
        guard status == noErr else { throw LinkError.port(status) }
    }

    public enum LinkError: Error, CustomStringConvertible {
        case client(OSStatus), port(OSStatus), connect(OSStatus), noDestination
        public var description: String {
            switch self {
            case .client(let s): return "Core MIDI client: \(s)"
            case .port(let s): return "Core MIDI port: \(s)"
            case .connect(let s): return "could not listen to the source: \(s)"
            case .noDestination: return "the device has no input to send to"
            }
        }
    }

    // MARK: endpoints

    public func endpoints() -> [MirrorEndpoint] {
        var out: [MirrorEndpoint] = []
        for i in 0 ..< MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            var entity = MIDIEntityRef()
            MIDIEndpointGetEntity(src, &entity)
            var dest: MIDIEndpointRef? = nil
            if entity != 0, MIDIEntityGetNumberOfDestinations(entity) > 0 {
                dest = MIDIEntityGetDestination(entity, 0)
            }
            if dest == nil {                            // (no entity, as with virtual ports: a destination of the same name)
                let name = Self.displayName(src)
                for j in 0 ..< MIDIGetNumberOfDestinations() where Self.displayName(MIDIGetDestination(j)) == name {
                    dest = MIDIGetDestination(j); break
                }
            }
            out.append(MirrorEndpoint(id: Self.uniqueID(src), name: Self.displayName(src), source: src, destination: dest))
        }
        return out
    }

    static func uniqueID(_ e: MIDIEndpointRef) -> MIDIUniqueID {
        var id: MIDIUniqueID = 0
        MIDIObjectGetIntegerProperty(e, kMIDIPropertyUniqueID, &id)
        return id
    }

    static func displayName(_ e: MIDIEndpointRef) -> String {
        var cf: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &cf) == noErr, let s = cf?.takeRetainedValue() { return s as String }
        if MIDIObjectGetStringProperty(e, kMIDIPropertyName, &cf) == noErr, let s = cf?.takeRetainedValue() { return s as String }
        return "MIDI device"
    }

    // MARK: the connection

    public func connect(_ e: MirrorEndpoint) throws {
        guard let dest = e.destination else { throw LinkError.noDestination }
        disconnect()
        let status = MIDIPortConnectSource(inPort, e.source, nil)
        guard status == noErr else { throw LinkError.connect(status) }
        lock.lock()
        connectedSource = e.source
        destination = dest
        assembler = UMPSysExAssembler()
        wireValue = Wire()
        lock.unlock()
    }

    public func disconnect() {
        lock.lock()
        let src = connectedSource
        connectedSource = 0
        destination = 0
        lock.unlock()
        if src != 0 { MIDIPortDisconnectSource(inPort, src) }
    }

    /// A whole F0 .. F7 message to the connected destination, as SysEx7 packets in one event list.
    @discardableResult
    public func send(_ message: [UInt8]) -> OSStatus {
        lock.lock()
        let dest = destination
        lock.unlock()
        guard dest != 0 else { return OSStatus(kMIDIUnknownEndpoint) }
        let words = UMPSysEx.packets(for: message)
        var status: OSStatus = noErr
        var i = 0
        while i < words.count {                          // 64 words a list at most: one inline packet
            let n = min(64, words.count - i)
            var list = MIDIEventList()
            let packet = MIDIEventListInit(&list, ._1_0)
            let chunk = Array(words[i ..< i + n])
            let added = chunk.withUnsafeBufferPointer { MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, n, $0.baseAddress!) }
            if added == nil { status = OSStatus(kMIDIMessageSendErr); break }
            let st = MIDISendEventList(outPort, dest, &list)
            if st != noErr { status = st; break }
            i += n
        }
        lock.lock()
        wireValue.sent += 1
        if status != noErr { wireValue.sendErrors += 1; wireValue.lastSendStatus = status }
        lock.unlock()
        return status
    }

    private func receive(_ list: UnsafePointer<MIDIEventList>) {
        var words: [UInt32] = []
        var packets = 0
        for p in list.unsafeSequence() {
            let n = Int(p.pointee.wordCount)
            withUnsafeBytes(of: p.pointee.words) { raw in
                let w = raw.bindMemory(to: UInt32.self)
                words.append(contentsOf: w.prefix(n))
            }
            packets += 1
        }
        let messages = assembler.feed(words: words)     // (Core MIDI delivers on one thread per port: the assembler is its)
        lock.lock()
        wireValue.packets += packets
        wireValue.words += words.count
        wireValue.sysex += messages.count
        if let last = messages.last { wireValue.lastHead = last.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ") }
        lock.unlock()
        for m in messages { onMessage?(m) }
    }
}
#endif
