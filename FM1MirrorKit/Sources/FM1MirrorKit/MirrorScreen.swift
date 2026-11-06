// SPDX-License-Identifier: MPL-2.0
// The viewer's decoder (fm1-base device/mirror.c; web/mirror/index.html createMirror; tools/fm1_mirror.py Screen):
// a 240 x 240 RGB565 screen kept up to date from rect and fill frames, the input reports and the hello parsed.

public enum MirrorCommand {
    public static let request: UInt8 = 0x50   // host -> device: 0 off, 1 on (keep-alive), 2 refresh; device -> host: hello
    public static let rect: UInt8 = 0x51
    public static let fill: UInt8 = 0x52
    public static let input: UInt8 = 0x53
    public static let remote: UInt8 = 0x54
}

public struct MirrorHello: Equatable {
    public var version: Int
    public var on: Bool
    public var width: Int
    public var height: Int
}

/// The panel as the device reports it (cmd 0x53, little-endian, 27 bytes from version 4; 21 before).
public struct MirrorInput: Equatable {
    public var buttonsHeld: UInt16 = 0
    public var keysHeld: UInt32 = 0
    public var encoders: [Int8] = []        // SELECT, ALGORITHM, PRESETS, KNOB 1..4: detents since the last report
    public var master: UInt16 = 0           // 0..4096
    public var litButtons: UInt16 = 0       // bit 15: PLAY lit red
    public var litKeys: UInt32 = 0
    public var dimButtons: UInt16 = 0
    public var dimKeys: UInt32 = 0

    public init() {}

    public init?(body b: [UInt8]) {
        guard b.count >= 21 else { return nil }
        func u16(_ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
        func u32(_ i: Int) -> UInt32 { UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24 }
        buttonsHeld = u16(0)
        keysHeld = u32(2)
        encoders = (0 ..< 7).map { Int8(bitPattern: b[6 + $0]) }
        master = u16(13)
        litButtons = u16(15)
        litKeys = u32(17)
        if b.count >= 27 {
            dimButtons = u16(21)
            dimKeys = u32(23)
        }
    }
}

public struct MirrorStats: Equatable {
    public var frames = 0, rects = 0, fills = 0, inputs = 0, bad = 0, gaps = 0, hellos = 0
    public init() {}
}

public final class MirrorScreen {
    public static let width = 240
    public static let height = 240

    /// RGB565, row-major, `width * height` entries.
    public private(set) var pixels = [UInt16](repeating: 0, count: MirrorScreen.width * MirrorScreen.height)
    public private(set) var stats = MirrorStats()
    public private(set) var hello: MirrorHello?
    public private(set) var input: MirrorInput?
    /// Counts up with every change of the picture: a view redraws when it moves.
    public private(set) var generation = 0
    private var seq = -1

    public init() {}

    /// Forget the sequence: after asking for a refresh, so the next frame is not a gap.
    public func resync() { seq = -1 }

    public func clear() {
        pixels = [UInt16](repeating: 0, count: MirrorScreen.width * MirrorScreen.height)
        generation += 1
    }

    /// One whole F0 .. F7 message. Returns the mirror command it carried (nil: not the mirror's), and whether
    /// a refresh should be asked for (a frame missed or damaged).
    @discardableResult
    public func feed(message: [UInt8]) -> (cmd: UInt8?, wantsRefresh: Bool) {
        guard let f = MirrorFrame.parse(message) else { return (nil, false) }
        return feed(frame: f)
    }

    @discardableResult
    public func feed(frame f: MirrorFrame) -> (cmd: UInt8?, wantsRefresh: Bool) {
        var refresh = false
        switch f.cmd {
        case MirrorCommand.rect, MirrorCommand.fill:
            stats.frames += 1
            guard f.body.count >= 5 else { stats.bad += 1; return (f.cmd, true) }
            let s = Int(f.body[4])
            if seq >= 0 && s != seq {
                stats.gaps += 1
                refresh = true
            }
            seq = (s + 1) & 255
            if f.cmd == MirrorCommand.rect {
                stats.rects += 1
                if !applyRect(f.body) {
                    stats.bad += 1
                    refresh = true
                }
            } else {
                stats.fills += 1
                if !applyFill(f.body) {
                    stats.bad += 1
                    refresh = true
                }
            }
            generation += 1
        case MirrorCommand.input:
            stats.inputs += 1
            input = MirrorInput(body: f.body)
        case MirrorCommand.request:
            stats.hellos += 1
            if f.body.count >= 4 {
                hello = MirrorHello(version: Int(f.body[0]), on: f.body[1] != 0, width: Int(f.body[2]) + 1,
                                    height: Int(f.body[3]) + 1)
            }
        default:
            break
        }
        return (f.cmd, refresh)
    }

    /// Requests to the device (cmd 0x50): 0 off, 1 on (the keep-alive), 2 refresh.
    public static func request(_ op: UInt8) -> [UInt8] { MirrorFrame(cmd: MirrorCommand.request, body: [op]).encoded() }

    static func hash(_ c: UInt16) -> Int { Int((UInt32(c) &* 40503) >> 10 & 63) }

    private func applyRect(_ b: [UInt8]) -> Bool {
        let w = MirrorScreen.width, h = MirrorScreen.height
        let x = Int(b[0]), y = Int(b[1]), rw = Int(b[2]) == 0 ? 256 : Int(b[2]), rh = Int(b[3])
        guard rw > 0, rh > 0, x + rw <= w, y + rh <= h else { return false }
        let total = rw * rh
        var p = 0, i = 5
        var cur: UInt16 = 0
        var cache = [UInt16](repeating: 0, count: 64)
        func put(_ c: UInt16, _ n: Int) -> Bool {
            if p + n > total { return false }
            for _ in 0 ..< n {
                pixels[(y + p / rw) * w + x + p % rw] = c
                p += 1
            }
            return true
        }
        while i < b.count {
            let op = Int(b[i])
            i += 1
            let ok: Bool
            if op < 0x80 {
                ok = put(cur, op + 1)
            } else if op < 0xC0 {
                cur = cache[op & 63]
                ok = put(cur, 1)
            } else {
                guard i + 2 <= b.count else { return false }
                cur = UInt16(b[i]) << 8 | UInt16(b[i + 1])
                i += 2
                cache[MirrorScreen.hash(cur)] = cur
                ok = put(cur, (op & 63) + 1)
            }
            if !ok { return false }
        }
        return p == total
    }

    private func applyFill(_ b: [UInt8]) -> Bool {
        guard b.count >= 7 else { return false }
        let w = MirrorScreen.width, h = MirrorScreen.height
        let x = Int(b[0]), y = Int(b[1]), rw = Int(b[2]) == 0 ? 256 : Int(b[2]), rh = Int(b[3])
        let c = UInt16(b[5]) << 8 | UInt16(b[6])
        guard x < w, y < h else { return false }
        for j in y ..< min(h, y + rh) {
            for i in x ..< min(w, x + rw) {
                pixels[j * w + i] = c
            }
        }
        return true
    }

    /// The screen as 8-bit RGBA, row-major, for an image.
    public func rgba() -> [UInt8] {
        var out = [UInt8](repeating: 255, count: pixels.count * 4)
        for (k, v) in pixels.enumerated() {
            out[k * 4] = UInt8(Int(v >> 11) * 255 / 31)
            out[k * 4 + 1] = UInt8(Int(v >> 5 & 63) * 255 / 63)
            out[k * 4 + 2] = UInt8(Int(v & 31) * 255 / 31)
        }
        return out
    }
}
