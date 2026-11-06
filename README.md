# FM-1 Mirror for iPhone and iPad

The M-VAVE FM-1's screen, live on an iPhone or iPad over USB-C, from any firmware built on
[fm1-base](https://github.com/charlesvestal/fm1-base) with the mirror in it ([LOOM-8](https://github.com/charlesvestal/fm1-loom)
among them). The FM-1 streams its 240 x 240 screen as SysEx over class-compliant USB MIDI, which iOS speaks natively;
this app asks for it (Core MIDI), decodes it and draws it as large as the display allows. Tap the picture to hide
everything else.

No browser on iOS has Web MIDI, which is what fm1-base's own mirror page needs, so a native app is the way.

## Use

1. Connect the FM-1 to the iPhone or iPad by a USB-C to USB-C cable (a Lightning model: Apple's camera adapter). The
   FM-1's USB PORT must be "computer", its power-on default (LOOM-8: Setup), not "MIDI host".
2. Open the app: the FM-1 is picked when its name says so ("LOOM-8 FM-1", "FM-1 Midi", "ChoralRoot FM-1", "Felucca");
   any other MIDI device with an input and an output can be picked from the menu.
3. Mirror. The whole screen comes first, then only what changes. The music comes first on the FM-1: a busy screen
   may skip a frame, which the app notices (a gap in the sequence) and asks for the screen again.
4. Tap the picture for a clean full-screen view; tap again for the controls. Rotate as you like.

Demo (no FM-1 around): the Demo button plays a recorded LOOM-8 session; `--demo` as a launch argument starts it at once
(simulators, screenshots).

## The chord guide

Beside the mirror (landscape) or under it (portrait), for anyone who forgets which keys make which chord:

- **Key & scale** (right): a tonic, a scale (major, the minors, the modes, the pentatonics, blues), and the FM-1's OCT
  as you have set it (LOOM-8 does not report it). It lists one octave of the scale from the lowest tonic the keys reach,
  each note as a key: LOOM-8's own numbers, white 1 to 16 and black 1 to 11 from F3, with the note name under it.
- **Chord in the key** (left): the seven chords of that key as roman numerals (lower case minor, ° diminished), a
  7ths switch and the inversions. It names the chord (a slash chord when inverted), lists its notes, and shows the keys
  to hold, root outlined, from the lowest bass the keys reach; it says when a chord would run past the last key.
- **The keyboard strip**: the 27 keys with their numbers, the scale tinted, the chord lit. Keys off, Centre (under the
  screen; in portrait the panes move down and the screen keeps its width) or Left (at the bottom of the chord pane, so
  the screen keeps its size in landscape too).

Hide guide in the toolbar gives the plain mirror back. Every choice is remembered. The music lives in
`FM1MirrorKit/Sources/FM1MirrorKit/ChordGuide.swift` (`FM1Keyboard`, `MusicalKey`, `Chord`, `Voicing`), tested in
`ChordGuideTests.swift`. For a look at a chosen state in a simulator, the settings take launch arguments, e.g.
`-guide.keyboard centre -guide.degree 5 -guide.inversion 1 -guide.seventh 1`. The design was prototyped in
`prototype/index.html`.

## Build

Xcode 26 or later. Open `FM1Mirror.xcodeproj`, set your team under Signing, pick your iPhone and run. The project is a
synchronized folder (`FM1Mirror/`) plus the local package `FM1MirrorKit/`.

- `FM1MirrorKit/` holds the wire format and the decoder with no UI and no Core MIDI: `swift test` in that folder runs
  its tests on the Mac, among them the whole recorded stream (`Tests/.../Fixtures/mirror.syx`, made by LOOM-8's
  simulator) decoded and compared pixel for pixel with fm1-base's Python decoder (`oracle.rgb565`, from
  `tools/fm1_mirror.py`).
- The simulator: `xcodebuild -project FM1Mirror.xcodeproj -scheme FM1Mirror -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`,
  then `xcrun simctl install booted <the app>` and `xcrun simctl launch booted com.davidpryan.FM1Mirror --demo`.
  Core MIDI in the simulator sees the Mac's MIDI devices, so an FM-1 plugged into the Mac can be mirrored there too.

## The protocol, in short

fm1-base `device/mirror.c`. Every message is `F0 pack7(00 59 cmd len24 body ~sum8(body)) F7`. The host sends
cmd 0x50 with 2 (refresh: on, the whole screen), then 1 every 2 s as a keep-alive (6 s without one and the FM-1 stops),
and 0 to stop. The FM-1 answers with its hello (0x50: version, on, width - 1, height - 1), rectangles (0x51: x, y, w,
h, seq, then the pixels run-length coded on RGB565 with a 64-entry colour cache) and fills (0x52), and reports the
panel (0x53: buttons, keys, encoders, MASTER, the lights). `seq` counts rectangles and fills: a jump means one was
lost. Core MIDI delivers SysEx as Universal MIDI Packets (SysEx7, type 3), reassembled in `UMPSysEx.swift`.

## Not yet

The panel as the FM-1 reports it (its buttons, keys and lights) and playing the FM-1 from the phone (cmd 0x54), both
of which the web page has; Bluetooth MIDI as a transport. The decoder already parses the panel reports.

## Licence

MPL-2.0, like fm1-base's mirror, whose format and reference decoder this follows. Copyright (C) 2026 David Ryan.
