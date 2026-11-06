// swift-tools-version: 5.9
// SPDX-License-Identifier: MPL-2.0
// FM1MirrorKit: the FM-1 screen mirror's wire format and decoder (fm1-base device/mirror.c), with no UI and no
// Core MIDI, so it builds and tests on macOS (swift test) and goes into the iOS app as is.
import PackageDescription

let package = Package(
    name: "FM1MirrorKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "FM1MirrorKit", targets: ["FM1MirrorKit"]),
               .executable(name: "mirrorcli", targets: ["mirrorcli"])],
    targets: [
        .target(name: "FM1MirrorKit"),
        .executableTarget(name: "mirrorcli", dependencies: ["FM1MirrorKit"]),   // a Mac harness: the FM-1 over Core MIDI
        .testTarget(name: "FM1MirrorKitTests", dependencies: ["FM1MirrorKit"], resources: [.copy("Fixtures")]),
    ]
)
