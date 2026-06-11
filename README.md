# VarioRadar

Open-source iPhone app that shows approaching-vehicle data from a Garmin
Varia cycling radar on the surfaces that stay visible while you are in
another app: the Dynamic Island and Lock Screen Live Activity. Built for
the case where you are recording a ride in Apple's Workout app (which does
not talk to the radar) but still want to see cars coming up behind you.

Target device: Garmin Varia RCT716 (also works with the RTL5xx and other
Varia radars that expose the standard radar BLE service). MIT licensed.

## Layout

```
Packages/VarioRadarCore/   Pure-Swift parser + model, no CoreBluetooth.
                           Builds and tests on macOS. (swift test)
Tools/FakeVaria/           macOS BLE peripheral that impersonates a Varia,
                           for end-to-end testing without the real device.
App/                       The iOS app + widget extension (Live Activity,
                           Dynamic Island, status widget). Generated with
                           XcodeGen from App/project.yml.
docs/                      Phase 1 research, decisions, protocol notes.
```

## Building the app

The Xcode project is generated, not committed. You need
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```
cd App
xcodegen generate
open VarioRadar.xcodeproj
```

Set your team under Signing & Capabilities before running on a device.
Live Activities, App Groups, and background Bluetooth require a paid Apple
Developer account.

### Developing without the radar

The real RCT716 refuses live BLE sessions from macOS (see
`docs/analysis.md` D2), and the iOS Simulator has no Bluetooth at all. Two
ways to work around that:

- **Simulator:** the app auto-selects a scripted radar source in the
  simulator, so the whole UI and Live Activity pipeline runs against
  generated traffic with no hardware.
- **On device:** run `Tools/FakeVaria` on a Mac. It advertises the real
  radar service and streams scripted frames, so the iPhone app connects to
  it exactly as it would to the radar.

## Testing

```
cd Packages/VarioRadarCore && swift test      # 20 tests, parser + model
```

## Verification status

- `VarioRadarCore`: builds and all tests pass on macOS.
- `FakeVaria`: builds and advertises the radar service on macOS.
- `App/` + widget: both targets typecheck against the iOS 18 simulator
  SDK. A full `xcodebuild` run was not possible in the dev environment
  used to scaffold this (the iOS 26.5 platform runtime was not installed,
  so xcodebuild could not resolve a destination). Open the project in
  Xcode with the iOS platform installed to build and run.
