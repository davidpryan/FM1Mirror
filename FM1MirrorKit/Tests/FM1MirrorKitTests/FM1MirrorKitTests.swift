// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import FM1MirrorKit

final class FramingTests: XCTestCase {
    func testPack7RoundTrip() {
        for n in 0 ..< 40 {
            let data = (0 ..< n).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) }
            let packed = SysEx7.pack7(data)
            XCTAssertTrue(packed.allSatisfy { $0 < 0x80 })
            XCTAssertEqual(Array(SysEx7.unpack7(packed).prefix(n)), data)
        }
    }

    func testRequestFrameMatchesPython() {
        // fm1_backup.frame(0x50, b"\x02"): F0 pack7(00 59 50 01 00 00 02 FD) F7
        let f = MirrorScreen.request(2)
        XCTAssertEqual(f.map { String(format: "%02x", $0) }.joined(), "f00032410a000000017d01f7")
        let back = MirrorFrame.parse(f)
        XCTAssertEqual(back, MirrorFrame(cmd: 0x50, body: [2]))
    }

    func testDamagedFramesRejected() {
        var f = MirrorScreen.request(1)
        f[f.count - 2] ^= 0x01                       // the checksum word
        XCTAssertNil(MirrorFrame.parse(f))
        XCTAssertNil(MirrorFrame.parse([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]))   // another maker's SysEx
        XCTAssertNil(MirrorFrame.parse([0x90, 60, 100]))
    }

    func testSplitterFindsMessagesAcrossChunks() {
        let a = MirrorScreen.request(1), b = MirrorScreen.request(2)
        let stream = a + [0x90, 60, 100] + b
        var s = SysExSplitter()
        var got: [[UInt8]] = []
        for chunk in stride(from: 0, to: stream.count, by: 5) {
            got += s.feed(Array(stream[chunk ..< min(chunk + 5, stream.count)]))
        }
        XCTAssertEqual(got, [a, b])
    }
}

final class UMPTests: XCTestCase {
    func testPacketsRoundTrip() {
        for n in [0, 1, 5, 6, 7, 12, 13, 100] {
            let body = (0 ..< n).map { UInt8($0 & 0x7F) }
            let msg = MirrorFrame(cmd: 0x51, body: body).encoded()
            let words = UMPSysEx.packets(for: msg)
            XCTAssertEqual(words.count % 2, 0)
            var asm = UMPSysExAssembler()
            let back = asm.feed(words: words)
            XCTAssertEqual(back, [msg], "n = \(n)")
        }
    }

    func testOtherPacketsInBetweenAreSkipped() {
        let msg = MirrorFrame(cmd: 0x53, body: [UInt8](repeating: 1, count: 27)).encoded()
        var words = UMPSysEx.packets(for: msg)
        words.insert(0x2090_3C64, at: 2)              // a MIDI 1.0 note-on (type 2, one word) between two packets
        words.insert(0x1000_00F8, at: 0)              // a clock (type 1, one word) in front
        var asm = UMPSysExAssembler()
        XCTAssertEqual(asm.feed(words: words), [msg])
    }
}

final class ScreenTests: XCTestCase {
    func testRecordedStreamMatchesTheReferenceDecoder() throws {
        let syx = try Data(contentsOf: Fixtures.url("mirror.syx"))
        let oracle = try Data(contentsOf: Fixtures.url("oracle.rgb565"))
        var splitter = SysExSplitter()
        let screen = MirrorScreen()
        var refreshes = 0
        for msg in splitter.feed([UInt8](syx)) {
            if screen.feed(message: msg).wantsRefresh { refreshes += 1 }
        }
        XCTAssertGreaterThan(screen.stats.rects, 500)
        XCTAssertEqual(screen.stats.bad, 0)
        XCTAssertGreaterThan(screen.stats.inputs, 0)
        XCTAssertEqual(screen.hello?.width, 240)
        XCTAssertEqual(screen.hello?.height, 240)
        let want = stride(from: 0, to: oracle.count, by: 2).map { UInt16(oracle[$0]) << 8 | UInt16(oracle[$0 + 1]) }
        XCTAssertEqual(want.count, 240 * 240)
        XCTAssertEqual(screen.pixels, want)
        XCTAssertGreaterThan(screen.pixels.filter { $0 != 0 }.count, 1000)
        XCTAssertEqual(screen.rgba().count, 240 * 240 * 4)
        _ = refreshes                                 // (the recording has drops and redraws: gaps are expected)
    }

    func testFillAndRectBounds() {
        let screen = MirrorScreen()
        // a fill of the top-left 2 x 2 in red (RGB565 F800), seq 0
        screen.feed(frame: MirrorFrame(cmd: MirrorCommand.fill, body: [0, 0, 2, 2, 0, 0xF8, 0x00]))
        XCTAssertEqual(screen.pixels[0], 0xF800)
        XCTAssertEqual(screen.pixels[241], 0xF800)
        XCTAssertEqual(screen.pixels[2], 0)
        // a rect 3 x 1 at (10, 5): a new colour green (07E0) for 2 pixels, then the colour now for 1 more
        let r = screen.feed(frame: MirrorFrame(cmd: MirrorCommand.rect, body: [10, 5, 3, 1, 1, 0xC1, 0x07, 0xE0, 0x00]))
        XCTAssertFalse(r.wantsRefresh)
        XCTAssertEqual(Array(screen.pixels[5 * 240 + 10 ..< 5 * 240 + 13]), [0x07E0, 0x07E0, 0x07E0])
        // a rect that runs past the screen is refused, and a skipped seq is a gap
        let bad = screen.feed(frame: MirrorFrame(cmd: MirrorCommand.rect, body: [239, 0, 2, 1, 3, 0x01]))
        XCTAssertTrue(bad.wantsRefresh)
        XCTAssertEqual(screen.stats.bad, 1)
        XCTAssertEqual(screen.stats.gaps, 1)
    }
}

enum Fixtures {
    static func url(_ name: String) throws -> URL {
        guard let u = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw NSError(domain: "fixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: "no fixture \(name)"])
        }
        return u
    }
}
