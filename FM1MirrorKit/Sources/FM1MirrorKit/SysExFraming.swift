// SPDX-License-Identifier: MPL-2.0
// The update's SysEx framing that the mirror rides on (felucca-bsp ota.c, fm1-base tools/fm1_backup.py frame /
// parse_frame): F0 pack7(00 59 cmd len24 body ~sum8(body)) F7. pack7 packs bytes little-endian into 7-bit words.

public enum SysEx7 {
    /// bytes -> 7-bit words (fm1_install.py pack7)
    public static func pack7(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(data.count * 8 / 7 + 1)
        var acc: UInt32 = 0, nb = 0
        for b in data {
            acc |= UInt32(b) << UInt32(nb)
            nb += 8
            while nb >= 7 {
                out.append(UInt8(acc & 0x7F))
                acc >>= 7
                nb -= 7
            }
        }
        if nb > 0 { out.append(UInt8(acc & 0x7F)) }
        return out
    }

    /// 7-bit words -> bytes (fm1_install.py unpack7): a trailing partial byte is dropped
    public static func unpack7(_ words: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(words.count * 7 / 8 + 1)
        var acc: UInt32 = 0, nb = 0
        for w in words {
            acc |= UInt32(w & 0x7F) << UInt32(nb)
            nb += 7
            while nb >= 8 {
                out.append(UInt8(acc & 0xFF))
                acc >>= 8
                nb -= 8
            }
        }
        return out
    }
}

/// One framed message: its command and body.
public struct MirrorFrame: Equatable {
    public var cmd: UInt8
    public var body: [UInt8]

    public init(cmd: UInt8, body: [UInt8]) {
        self.cmd = cmd
        self.body = body
    }

    /// The whole SysEx message, F0 .. F7, as the host sends it.
    public func encoded() -> [UInt8] {
        let n = body.count
        var msg: [UInt8] = [0x00, 0x59, cmd, UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF)]
        msg += body
        let sum = body.reduce(0) { ($0 &+ Int($1)) & 0xFF }
        msg.append(UInt8(~sum & 0xFF))
        return [0xF0] + SysEx7.pack7(msg) + [0xF7]
    }

    /// A device message F0 .. F7 -> its frame, or nil when it is not one of ours or is damaged.
    public static func parse(_ pkt: [UInt8]) -> MirrorFrame? {
        guard pkt.count >= 2, pkt.first == 0xF0, pkt.last == 0xF7 else { return nil }
        let u = SysEx7.unpack7(Array(pkt[1 ..< pkt.count - 1]))
        guard u.count >= 7, u[0] == 0x00, u[1] == 0x59 else { return nil }
        let n = Int(u[3]) | Int(u[4]) << 8 | Int(u[5]) << 16
        guard n + 7 == u.count else { return nil }
        let body = Array(u[6 ..< 6 + n])
        let sum = body.reduce(0) { ($0 &+ Int($1)) & 0xFF }
        guard UInt8(~sum & 0xFF) == u[6 + n] else { return nil }
        return MirrorFrame(cmd: u[2], body: body)
    }
}

/// Splits a raw byte stream (a recording, or bytes as they arrive) into whole F0 .. F7 messages.
public struct SysExSplitter {
    private var current: [UInt8] = []
    private var inside = false

    public init() {}

    /// Feed bytes; returns the complete messages they finished.
    public mutating func feed(_ bytes: [UInt8]) -> [[UInt8]] {
        var out: [[UInt8]] = []
        for b in bytes {
            if b == 0xF0 {
                current = [0xF0]
                inside = true
            } else if b == 0xF7 && inside {
                current.append(0xF7)
                out.append(current)
                current = []
                inside = false
            } else if inside {
                if b & 0x80 != 0 { continue }   // (a real-time byte in the middle: not ours; the message goes on)
                current.append(b)
            }
        }
        return out
    }
}
