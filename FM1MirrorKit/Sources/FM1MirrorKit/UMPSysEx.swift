// SPDX-License-Identifier: MPL-2.0
// SysEx over the Universal MIDI Packet, as Core MIDI's event lists carry it (MIDI 1.0 protocol): message type 3,
// 64-bit packets of up to 6 data bytes, status 0 complete / 1 start / 2 continue / 3 end. F0 and F7 are not in
// the data. (iOS 14+: MIDIInputPortCreateWithProtocol, MIDISendEventList.)

public struct UMPSysExAssembler {
    private var current: [UInt8] = []
    private var inside = false

    public init() {}

    /// One 64-bit SysEx7 packet (two words); returns a whole F0 .. F7 message when the packet ends one.
    public mutating func feed(word0: UInt32, word1: UInt32) -> [UInt8]? {
        guard word0 >> 28 == 3 else { return nil }
        let status = Int(word0 >> 20 & 0xF), count = Int(word0 >> 16 & 0xF)
        let bytes: [UInt8] = [UInt8(word0 >> 8 & 0x7F), UInt8(word0 & 0x7F), UInt8(word1 >> 24 & 0x7F),
                              UInt8(word1 >> 16 & 0x7F), UInt8(word1 >> 8 & 0x7F), UInt8(word1 & 0x7F)]
        let data = Array(bytes.prefix(min(count, 6)))
        switch status {
        case 0:
            return [0xF0] + data + [0xF7]
        case 1:
            current = [0xF0] + data
            inside = true
            return nil
        case 2:
            if inside { current += data }
            return nil
        case 3:
            guard inside else { return nil }
            current += data
            current.append(0xF7)
            inside = false
            let msg = current
            current = []
            return msg
        default:
            return nil
        }
    }

    /// Any sequence of 32-bit words: the SysEx7 packets among them, in order (other message types skipped by size).
    public mutating func feed(words: [UInt32]) -> [[UInt8]] {
        var out: [[UInt8]] = []
        var i = 0
        while i < words.count {
            let type = words[i] >> 28
            let size: Int
            switch type {
            case 0, 1, 2, 6, 7: size = 1
            case 3, 4, 8, 9, 10: size = 2
            case 11, 12: size = 3
            default: size = 4
            }
            if type == 3, i + 1 < words.count, let msg = feed(word0: words[i], word1: words[i + 1]) {
                out.append(msg)
            }
            i += size
        }
        return out
    }
}

public enum UMPSysEx {
    /// A whole F0 .. F7 message -> its SysEx7 packets (pairs of words) for group `group`.
    public static func packets(for message: [UInt8], group: UInt8 = 0) -> [UInt32] {
        var data = message
        if data.first == 0xF0 { data.removeFirst() }
        if data.last == 0xF7 { data.removeLast() }
        var words: [UInt32] = []
        let chunks = stride(from: 0, to: max(data.count, 1), by: 6).map { Array(data[$0 ..< min($0 + 6, data.count)]) }
        for (k, chunk) in chunks.enumerated() {
            let status: UInt32 = chunks.count == 1 ? 0 : k == 0 ? 1 : k == chunks.count - 1 ? 3 : 2
            var b = chunk + [UInt8](repeating: 0, count: 6 - chunk.count)
            b = b.map { $0 & 0x7F }
            let w0 = UInt32(3) << 28 | UInt32(group & 0xF) << 24 | status << 20 | UInt32(chunk.count) << 16
                | UInt32(b[0]) << 8 | UInt32(b[1])
            let w1 = UInt32(b[2]) << 24 | UInt32(b[3]) << 16 | UInt32(b[4]) << 8 | UInt32(b[5])
            words += [w0, w1]
        }
        return words
    }
}
