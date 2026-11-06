// SPDX-License-Identifier: MPL-2.0
// FM1Mirror: the M-VAVE FM-1's screen, live on an iPhone or iPad over USB-C (Core MIDI, class-compliant USB MIDI),
// from any fm1-base firmware with the mirror built in (LOOM-8 among them: fm1.toml mirror = true). The wire format
// and the decoder are FM1MirrorKit's (fm1-base device/mirror.c).
import SwiftUI

@main
struct FM1MirrorApp: App {
    @StateObject private var mirror = MirrorController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mirror)
                .preferredColorScheme(.dark)
        }
    }
}
