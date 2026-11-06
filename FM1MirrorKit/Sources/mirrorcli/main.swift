// SPDX-License-Identifier: MPL-2.0
// mirrorcli: the FM-1's screen over Core MIDI from a Mac, through the same MirrorLink and decoder the iOS app uses.
//   swift run mirrorcli [PORT-NAME-PART] [SECONDS] [OUT.png]
// Lists the MIDI devices, connects to the one named (else the first that looks like an FM-1), asks for the screen,
// keeps the mirror alive, prints the wire and the decoder's counts every second, writes the screen as a PNG and
// turns the mirror off. Exit 0 when a screen came, 2 when nothing usable did.
import CoreGraphics
import FM1MirrorKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let want = args.count > 1 ? args[1] : ""
let seconds = args.count > 2 ? Double(args[2]) ?? 6 : 6
let out = args.count > 3 ? args[3] : "fm1-mirror.png"

let link = try MirrorLink(name: "mirrorcli")
let eps = link.endpoints()
print("MIDI sources: \(eps.count)")
for e in eps { print("  - \(e.name)\(e.destination == nil ? " (input only)" : "")\(e.looksLikeFM1 ? "  <- looks like an FM-1" : "")") }
guard let ep = eps.first(where: { !want.isEmpty && $0.name.lowercased().contains(want.lowercased()) && $0.destination != nil })
        ?? eps.first(where: { $0.looksLikeFM1 && $0.destination != nil }) else {
    print("no device to mirror"); exit(2)
}
print("using \(ep.name)")

let screen = MirrorScreen()
let q = DispatchQueue(label: "mirrorcli.screen")
var frames = 0, hellos = 0, refreshAsked = 0
link.onMessage = { msg in
    q.sync {
        let r = screen.feed(message: msg)
        if r.cmd == MirrorCommand.rect || r.cmd == MirrorCommand.fill { frames += 1 }
        if r.cmd == MirrorCommand.request { hellos += 1; print("hello: \(String(describing: screen.hello))") }
        if r.wantsRefresh { refreshAsked += 1; screen.resync(); link.send(MirrorScreen.request(2)) }
    }
}
try link.connect(ep)
var st = link.send(MirrorScreen.request(2))
print("request(2) sent: status \(st)")
let t0 = Date()
var lastKeep = Date()
while Date().timeIntervalSince(t0) < seconds {
    Thread.sleep(forTimeInterval: 1.0)
    if Date().timeIntervalSince(lastKeep) >= 2 { lastKeep = Date(); link.send(MirrorScreen.request(1)) }
    let w = link.wire
    let s = q.sync { screen.stats }
    print(String(format: "t=%.0fs  %@  | frames %d rects %d fills %d inputs %d bad %d gaps %d  refreshes asked %d",
                 Date().timeIntervalSince(t0), w.summary, s.frames, s.rects, s.fills, s.inputs, s.bad, s.gaps, refreshAsked))
}
st = link.send(MirrorScreen.request(0))
link.disconnect()
let rgba = q.sync { screen.rgba() }
let provider = CGDataProvider(data: Data(rgba) as CFData)!
let img = CGImage(width: 240, height: 240, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 960,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
let url = URL(fileURLWithPath: out)
if let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
    print("wrote \(out)")
}
let nonzero = q.sync { screen.pixels.filter { $0 != 0 }.count }
print("frames \(frames), hellos \(hellos), lit pixels \(nonzero)")
exit(frames > 0 && nonzero > 0 ? 0 : 2)
