# VarioRadar Phase 1 Analysis

Research and design document for an open source iPhone app that visualises
radar style traffic from a Garmin Bluetooth device. Phase 2 (Xcode scaffold)
follows once the decisions in this document are agreed.

## 0. Naming and scope (read this first)

The brief says "Garmin Vario bluetooth device". That is ambiguous and the
distinction changes almost every technical answer below, so it has to be
nailed down before any code is written. Three realistic interpretations:

1. **Garmin Varia (cycling rear radar)**. The RTL515, RTL516 and the new
   RearVue 820 are short range Doppler radars that broadcast approaching
   vehicles to a phone or head unit. They run on Bluetooth Low Energy with
   a public, reverse engineered service plus an official "Radar Data BLE
   Program" from Garmin. iOS clients are entirely realistic.
   ([Garmin Radar Data BLE Program][gar-rdble], [forum thread][gar-forum],
   [reference C++ impl][var-cpp])
2. **A Garmin aviation product that surfaces ADS-B or FLARM style traffic
   to a phone** (GDL 50, GDL 52, Aera 760, Flight Stream 510/210). These
   speak the GDL 90 protocol but ride on Bluetooth Classic SPP, not BLE,
   which is the single biggest gotcha for any third party iOS app. See
   section A.2. ([GDL 90 ICD][gdl90-icd], [ForeFlight extension][ff-gdl90])
3. **A paraglider vario with FLARM or FANET output** (XC Tracer, Skytraxx,
   Flytec). These do speak BLE, but they are not Garmin. They expose an
   NMEA stream (LK8EX1, XCTRACER, LXWP0) over a serial style BLE link.
   XCTrack already does this on Android and iOS. ([XCTrack external devices][xct-ext])

The brief mentions "D2 Air, GNC Aera, GPSMAP / inReach line" as devices that
"broadcast traffic / ADS-B / FLARM style targets over BLE". This is not
accurate. The D2 watches are output devices that *display* traffic forwarded
from another receiver; they do not receive ADS-B or FLARM themselves. The
inReach is an Iridium satellite messenger and has nothing to do with radar.
The Aera 760 and 795/796 are portable navigators that can connect to a
GDL 50/52 receiver over Bluetooth and forward the data, but the radio
receivers are the GDL devices.

**Recommendation for the first version:** target Garmin Varia (cycling
radar) over BLE. The protocol is documented, the data rate is gentle (1 Hz),
the Live Activity story works, an iOS app can ship without MFi or Garmin
business agreements, and it is the only one of the three that the question
"is third party access actually possible" answers with a clean yes. If you
want aviation traffic in a later phase, the realistic target is FLARM over
BLE NMEA from a third party vario, with optional GDL 90 over UDP/WiFi from
a portable ADS-B receiver. See section A.3 for the aviation route.

The rest of this document assumes the Varia path for concrete recommendations,
and calls out the aviation path explicitly where it differs.

## A. Garmin BLE: what is actually readable from a third party iOS app

### A.1 Garmin Varia (cycling rear radar)

**Devices.** Varia RTL510, RTL511, RTL515, RTL516, the new RearVue 820,
RCT715 and RCT716 (radar + tail light + 1080p dashcam), and the older
RVR315. The 5xx and 7xx series use BLE plus ANT+. The 820 is reported to
have a different BLE behaviour on launch (see Garmin forum thread on
RearVue 820 BLE pairing), so the parser should be defensive about
firmware variance.

**Target device for this project: Varia RCT716** (StVZO variant of RCT715,
confirmed with the user). The RCT716 exposes the same radar BLE service
as the RTL5xx line; the camera adds two extra capabilities that are not
strictly v1 but worth noting:

- *Video stream:* not over BLE. The device hosts a WiFi access point and
  the Garmin Varia app pulls clips over WiFi when explicitly transferred.
  Out of scope for v1.
- *Camera control (start/stop recording, save incident clip):* exposed
  over BLE to the Edge head unit and the Varia app. The command channel
  has not been documented in the public reverse engineering work seen so
  far. Reverse engineering this would be a Phase 2 stretch (a "save clip"
  Action Button intent is a natural addition once we have it).

**BLE service.** A single primary service exposes a single notify
characteristic that streams radar threats once per second.

- Service UUID: `6A4E3200-667B-11E3-949A-0800200C9A66`
  (from community reverse engineering and the harbour-tacho reference
  implementation, [forum][gar-forum], [code][var-cpp])
- The characteristic UUID is the next 16 bit value in the same vendor
  range; the reference implementation refers to it by short alias
  `001e`. The exact 128 bit value should be confirmed against a real
  device with a BLE sniffer (`nRF Connect` on iOS) before locking it in.

**Payload format.** Notify packets are `1 + 3 * N` bytes:

| Offset            | Field            | Meaning                                                 |
|-------------------|------------------|---------------------------------------------------------|
| 0                 | sequence / id    | High 4 bits are a frame id used to reassemble splits.   |
| 1 + 3i            | threat id        | Per target id (`i` from 0 upward).                      |
| 2 + 3i            | distance         | uint8 metres from rider, 0 means slot is empty.         |
| 3 + 3i            | speed            | uint8 closing speed; units inferred (likely km/h \* k). |

If more threats are present than fit in 20 bytes (BLE 4.0 ATT MTU) the
device sends multiple notify packets sharing the same high nibble of byte 0
that should be concatenated. Newer firmware on devices that negotiate a
larger MTU may not split, so the parser should handle both.

Threat level (high two bits of a per slot status byte in some firmware
revisions: 0 none, 1 approaching, 2 fast approaching, 3 unknown) is present
in some captures but not others. The safest model is to derive threat level
client side from `distance` and `speed`.

**Official Garmin support.** Garmin runs a "Radar Data BLE Program" that
gives authorised developers the full specification, including the bits the
community is still guessing at, in exchange for a signed agreement. Access
is by application to Garmin business development. ([overview][gar-rdble])
For an open source project the community spec is enough to ship, and the
official program would conflict with publishing the protocol details under
an open licence; do not pursue it unless we later want to certify against
the official Connext stack.

**iOS feasibility.** Yes. CoreBluetooth scans for the service UUID, connects,
subscribes to notifications, decodes packets. No MFi or entitlement needed.
A real Varia device and a few hours with a BLE sniffer will close the gaps.

**Prior art.**
- `Wunderfitz/harbour-tacho` (Sailfish OS, C++): canonical reference for the
  notify parsing. ([source][var-cpp])
- Garmin Connect IQ forum thread on Varia profile: discussion plus example
  byte captures. ([thread][gar-forum])
- Multiple Connect IQ apps display Varia targets on Garmin watches; the
  source for several is on GitHub but only Connect IQ has direct BLE access
  to the watch, not iOS apps.
- No prominent open source iOS Swift implementation exists, which is part
  of the motivation for this project.

### A.2 Garmin aviation portables (GDL 50, GDL 52, Aera, Flight Stream)

**The protocol is public.** GDL 90 is an FAA published ICD from 2007 with
ForeFlight extensions later layered on top. It frames Heartbeat (id 0),
Ownship (10), Ownship Geo Altitude (11), Traffic Report (20), Uplink (7)
and others with HDLC style escaping, 0x7E flag bytes and a 16 bit CRC.
A Traffic Report is 28 bytes carrying ICAO address, lat, lon, altitude,
heading, horizontal and vertical velocity, NIC/NACp accuracy categories,
emitter type and a callsign. ([FAA ICD][gdl90-icd], [ForeFlight extension][ff-gdl90])

Reference implementations:
- `etdey/gdl90` (Python, decode + encode) ([repo][etdey])
- `cyoung/stratux` (Go, generates GDL 90 from a SDR derived ADS-B feed)
  ([repo][stratux])
- `lyusupov/SoftRF` includes a C parser usable as a port reference
  ([file][softrf-gdl90])
- A Rust crate `gdl90` on lib.rs exists.

**The Bluetooth transport is the problem on iOS.** The GDL 50 series and
Flight Stream 210/510 expose GDL 90 over Bluetooth *Classic* using the
Serial Port Profile (RFCOMM), not BLE. iOS does not let third party apps
talk RFCOMM unless the accessory is part of the Made for iPhone programme.
ForeFlight and Garmin Pilot can do it because their vendors hold MFi
licences for those specific accessories. A new open source app cannot.

Workable routes for aviation:
1. **WiFi GDL 90 from a portable that supports it.** Stratux, Sentry,
   Scout, FreeFlight, and several others broadcast GDL 90 over UDP on the
   local WiFi. iOS can read this trivially. Most pilots already use this.
2. **BLE FLARM/NMEA from a third party vario** (XC Tracer, Skytraxx, see
   A.3). This is the practical Garmin alternative for paraglider and
   sailplane pilots.
3. **Defer the aviation case** and target Varia first. The Live Activity
   plumbing is identical.

### A.3 FLARM over BLE from third party varios

**Devices.** XC Tracer Mini V and Maxx II, Skytraxx 5, Flytec, Naviter
Oudie 5. All of these can act as a BLE peripheral that streams NMEA
sentences over a Nordic UART style service.

**Protocol.** A vendor specific BLE service (typically Nordic UART, UUID
`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`) presents two characteristics, one
TX one RX. The peripheral pushes ASCII NMEA lines on the notify
characteristic. The pilot picks a "BLE protocol" in the vario settings,
options including LK8EX1, LXWP0, XCTRACER, and FLARM. FLARM mode emits
`$PFLAA` (other aircraft positions, relative bearing, alt, ground speed,
turn rate), `$PFLAU` (own status plus highest priority threat), and
standard `$GPRMC`/`$GPGGA` for ownship. ([XCTrack reference][xct-ext],
[FLARM port spec][flarm-port])

**iOS feasibility.** Yes, identical CoreBluetooth pattern to Varia. The
parser is text not binary. The Nordic UART service is widely used so any
existing Swift implementation (Nordic's IOS-BLE-Library, BlueCap, raw
CoreBluetooth) works.

### A.4 Garmin SDKs and what they do not give us

- **Connect IQ Mobile SDK.** This is for building Connect IQ apps that run
  on Garmin watches and head units, not for iOS apps that read data from
  Garmin devices. Not applicable here.
- **Connect IQ Companion SDK / Android Mobile SDK.** Exists on Android,
  not on iOS. The companion side relies on classic Bluetooth which iOS
  blocks anyway.
- **FIT SDK.** For activity files on disk, not for live BLE.
- **ANT+ on iOS.** Apple does not allow ANT+ radios on iPhone. Wahoo's
  ANT+ accessory is the only path and it is not useful here.
- **Garmin Radar Data BLE Program.** Official but gated, see A.1.

Net: there is no Garmin iOS SDK we can use. The job is plain CoreBluetooth
plus a hand written parser.

## B. iPhone Pro surfaces, honestly assessed

The killer scenario asked for in the brief is: while another app is in the
foreground, a small radar with current threats stays visible somewhere on
the device. This narrows the candidate surfaces sharply. Of everything in
iOS today, only **ActivityKit Live Activities** can show continuously
updating, app-specific content while a different app is in the foreground,
and even then there are real limits. Everything else is either timeline
driven (Widgets, StandBy) or only visible when the app is foreground (PiP
within the app, AOD with the app open).

### B.1 Dynamic Island and Lock Screen Live Activity (ActivityKit)

**What it is.** A SwiftUI rendered region tied to a Live Activity. Shows
in three Dynamic Island layouts (compact leading and trailing, minimal,
expanded) and a separate Lock Screen layout. Both are driven from the same
`ActivityAttributes.ContentState` value.

**Update mechanics.**
- While the app is foreground, call `activity.update(...)` directly. No
  budget, no rate limit beyond the SwiftUI render cost. Updates as often
  as you give it new state.
- While the app is in background but has a live CoreBluetooth subscription,
  iOS will still deliver characteristic notifications and the app gets a
  short execution window per callback. From inside that window the app
  *can* call `activity.update`. This is the path we want.
- For app states where the BLE socket is gone (suspended, terminated, or
  out of range temporarily), updates must come from APNs via a Live
  Activity push token. Priority 10 = immediate, counts against a per app
  budget; priority 5 = opportunistic, no budget hit but no delivery
  guarantee. ([Apple docs][lapush])
- Setting `NSSupportsLiveActivitiesFrequentUpdates = YES` in Info.plist
  raises the high priority push budget and gives the user a Settings
  toggle. ([key docs][ns-freq])
- Apple does not publish the exact number of pushes per hour. Reports
  describe roughly 1 high priority push per second sustained when the
  Frequent Updates capability is enabled and the user has not declined.
  Without it the system will silently drop fast pushes after a short burst.

**Lifetime.** A Live Activity lives for at most 8 hours active. After it
ends it can remain on the Lock Screen for up to 4 more hours, total 12.
For a flight or ride longer than 8 hours the app has to start a new
activity. We can paper over the gap with a fresh start on each session.

**Render budget on AOD.** The Lock Screen Live Activity is what shows on
the Always On Display when the screen dims. Apple renders it at a low
refresh rate and applies a tonemap. The SwiftUI view must work without
fine colour distinctions and should treat updates beyond about 1 Hz as
visually wasted.

**Verdict.** This is the right home for the always visible radar. Plan to
keep BLE alive in background, push `activity.update` from the
characteristic notification callback at 1 Hz, and design the Dynamic
Island compact layout to communicate "nearest threat, distance, closure"
in the few pixels available.

### B.2 Home Screen and Lock Screen widgets (WidgetKit)

**What it is.** Static, timeline driven SwiftUI surfaces. The app supplies
a `TimelineProvider` that returns a sequence of (date, view) entries; the
system renders them at the scheduled times.

**Refresh budget.** 40 to 70 reloads per 24 hours for a frequently viewed
widget, allocated dynamically. ([Apple WidgetKit docs][wk-update]) That is
roughly one update every 20 to 30 minutes on average. A widget cannot show
live radar data. It is fine for "last session summary" or "device battery
and last seen".

**Verdict.** Useful for at-a-glance status, not for live targets.

### B.3 StandBy mode (iPhone in landscape on a charger)

**What it is.** A full screen widget showcase available when the phone is
charging, in landscape, and stationary. Third party widgets surface there
automatically if they support the relevant `WidgetFamily` sizes
(`systemSmall`, `systemMedium`, `accessoryRectangular` and the StandBy
specific sizes).

**Update model.** Same WidgetKit timeline budget as section B.2. StandBy
is not a live surface.

**Verdict.** A nicely styled "garage view" widget makes sense for a paired
device. Not the live radar.

### B.4 Notifications, Time Sensitive, and Critical Alerts

Three interruption levels:
- **Active** (default). Plays sound and shows on the Lock Screen.
- **Time Sensitive.** Breaks through Focus, requires the
  `com.apple.developer.usernotifications.time-sensitive` entitlement.
  Reasonable for traffic alerts.
- **Critical.** Bypasses ringer and Do Not Disturb. Requires an Apple
  granted entitlement justified by safety. Aviation collision warnings
  are a plausible case but require Apple approval and a real public app
  before applying. ([entitlement docs][crit-ent])

**Verdict.** Use Time Sensitive for warnings until and unless we earn the
Critical entitlement.

### B.5 Apple Watch companion

**What it gives us.**
- Haptic alerts for proximate threats (taptic feedback).
- Smart Stack widget on watchOS 10+.
- Optional complication.
- A standalone view when the user raises their wrist.

The Watch app talks to the phone over `WatchConnectivity`; it is not a
separate BLE consumer. Building a watchOS app that ships alongside the
phone app is a Phase 3 item.

**Verdict.** High value for the user (silent haptic warnings on the wrist
beat a noise from the phone), but optional and additive.

### B.6 CarPlay

CarPlay supports a small set of app categories (navigation, audio,
messaging, EV charging, parking, fueling, driving task). Sports or
cycling apps are not in the allowed categories. Aviation apps have used
the "Driving Task" template under Apple negotiation. Realistically, a
Varia centric app will not get CarPlay approval. Skip.

### B.7 Action Button and Control Center controls

The Action Button can be bound to an app intent. Useful as "start/stop
radar session". Control Center controls (iOS 18+) can host an app
provided toggle, also useful. These are nice extras, not central.

### B.8 Picture in Picture as a "floating radar"

`AVPictureInPictureController` plus `AVSampleBufferDisplayLayer` lets an
app render arbitrary frames into the system PiP window. The app must be in
the foreground to *start* PiP but, once started, the window persists when
the user moves to another app, and the app keeps running to feed frames.
This has been used for live clocks and translation overlays in the past.

**Risks.**
- App Store review treats non video PiP usage as a grey area. Apps have
  been rejected for "abusing" PiP. Justify it as live navigation/safety
  imagery and it becomes more defensible than a clock app.
- The PiP window is removable by the user; not a guaranteed surface.
- PiP requires the `audio` background mode and an `AVAudioSession`, which
  adds complexity and may dim background music.

**Verdict.** Powerful but risky. Consider it a Phase 3 experiment, not the
default UX. The Dynamic Island already covers the "while in another app"
need for the compact-radar case.

### B.9 Summary table

| Surface              | Continuously updates while another app is foreground? | Practical update rate | Best use                  |
|----------------------|--------------------------------------------------------|-----------------------|---------------------------|
| Dynamic Island       | Yes (via Live Activity + background BLE)               | ~1 Hz                 | Killer feature            |
| Lock Screen LA       | Yes                                                    | ~1 Hz                 | Same canvas, bigger       |
| Always On Display    | Yes (renders the Lock Screen LA)                       | <= 1 Hz, dimmed       | Same as LS LA             |
| StandBy              | Renders Widgets, not LA                                | Timeline only         | At a glance status        |
| Home/Lock Widgets    | No, timeline                                           | ~30 min average       | Last session, battery     |
| Notifications        | Push at moment of event                                | Per event             | Critical threat alert     |
| Apple Watch          | Companion, mirrors LA + haptics                        | ~1 Hz                 | Silent haptic warning     |
| CarPlay              | Probably not approvable                                | n/a                   | Skip                      |
| Action Button / CC   | One off invocation                                     | n/a                   | Start/stop session        |
| Picture in Picture   | Yes, but fragile and review risky                      | 30 fps capable        | Optional floating radar   |

## C. App architecture proposal

### C.1 Language and framework

**Swift 6 + SwiftUI**, target iOS 18+ (iOS 19 once shipped). Reasons:

- ActivityKit, WidgetKit, StandBy, AOD, the modern Watch app, Action
  Button intents, Control Center controls, are all SwiftUI first.
- Swift 6 strict concurrency is genuinely helpful for a BLE app: the
  CoreBluetooth delegate callbacks can be hosted on a `@globalActor`
  scoped to BLE work, and the shared model is an `actor`.
- Excluding UIKit entirely is fine. No part of this app needs a UIKit
  escape hatch other than `AVSampleBufferDisplayLayer` if we ever do
  the PiP trick, and that integrates with SwiftUI via `UIViewRepresentable`.

No third party frameworks needed. CoreBluetooth is straightforward enough
that wrappers (RxBluetoothKit, BlueCap) add complexity without buying us
much. If we want a tidy async/await wrapper, write a small `actor` over
`CBCentralManager` rather than pulling a library.

### C.2 Keeping the BLE connection alive in the background

- Add `bluetooth-central` to `UIBackgroundModes` in the app target's
  `Info.plist`. ([Apple background BLE guide][cb-bg])
- Allocate `CBCentralManager` with `CBCentralManagerOptionRestoreIdentifier`
  set to a stable string (for example `com.varioradar.central`).
- Implement `centralManager(_:willRestoreState:)`. After a relaunch from
  state restoration, walk the restored peripherals, re-attach the delegate,
  re-subscribe to characteristics if needed. State preservation means the
  system can terminate the app to reclaim memory and relaunch it when a
  BLE event arrives, so the radar can keep flowing after a long idle.
- Treat *connected* peripheral notifications as the steady state. iOS
  background scanning is limited (no manufacturer data filtering, slower
  duty cycle), but once we are connected, the system will wake the app on
  every characteristic notification for the lifetime of the connection.
- Do as little work as possible in the BLE callback: parse, update the
  shared model, call `activity.update`, return. The system grants only a
  short execution window per callback.

### C.3 Data flow

```
[Garmin Varia / FLARM vario]
        |  BLE notify (1 Hz, binary or NMEA)
        v
+--------------------------+
|  CoreBluetooth actor     |   parses, validates, stamps a timestamp
+--------------------------+
        |
        v
+--------------------------+
|  RadarFrame (actor)      |   single source of truth: ownship + threats
+--------------------------+
   |        |        |        |
   v        v        v        v
 Main UI  LA push  Widget   Watch
 (SwiftUI) update  timeline  via WC
```

- One `RadarFrame` actor owns the latest known set of threats and metadata.
- Live Activity update is fed from the BLE callback path *only*. The main
  UI subscribes to a `AsyncStream<RadarFrame>` from the actor and re-renders.
- Widget reads its timeline from a snapshot file in the App Group container
  (see C.4); never tries to subscribe to anything live.

### C.4 Sharing data between targets

Create an App Group, for example `group.com.varioradar.shared`. The main
app writes a compact `RadarFrame` snapshot (a few hundred bytes of
JSON or property list) into the group container on each accepted frame.
Widget extensions and the Watch app read it. Live Activity reads it only
during recovery (the activity itself receives state via its
`ContentState`, not via the group).

### C.5 Power and thermal

- A constant 1 Hz BLE notify and 1 Hz Live Activity update is well within
  ordinary background usage and should add only single digit milliwatts.
- Avoid timers, polling, or `DispatchQueue.async(after:)` loops. Drive
  everything off the BLE callback.
- When no threats are present, switch the Live Activity to a "quiet"
  layout that does not animate. Most of the visible cost on AOD is in
  the SwiftUI render and tonemapping, not in the data path.
- Reject duplicate frames at the parser. The Varia repeats the same frame
  ID when nothing has changed; do not update the Live Activity for those.

### C.6 Licence

**MIT.** Reasons:
- Lowest friction for contributors.
- Compatible with everything else we are likely to depend on (Nordic
  iOS-BLE-Library is BSD-3, Stratux is BSD-3, ForeFlight's spec is
  publishable as documentation, the FAA GDL 90 ICD is public domain US
  government work).
- Apache 2.0 is the obvious alternative; its patent grant is nicer but
  it is heavier in file headers and offers no concrete benefit here
  since we are not contributing patents.

GPL would close the door to anyone wanting to integrate the parser into a
proprietary EFB plugin and there is no copyleft reason that applies here.

## D. Project skeleton (to be created in Phase 2, not now)

```
VarioRadar/
  Package.swift                        # SwiftPM workspace root
  VarioRadar.xcodeproj/                # umbrella Xcode project
  App/
    VarioRadarApp.swift                # @main, Scene, AppDelegate adapter
    Info.plist                         # bluetooth-central, NSBluetoothAlwaysUsageDescription,
                                       # NSSupportsLiveActivitiesFrequentUpdates
    Assets.xcassets/
    Views/                             # SwiftUI main UI (map, threat list)
    LiveActivity/
      RadarActivityAttributes.swift    # ContentState shared with widget extension
      RadarActivityView.swift          # Lock screen + Dynamic Island layouts
    Intents/
      StartRadarIntent.swift           # Action Button + Control Center
  Widgets/
    VarioRadarWidgets/                 # widget extension target
      RadarStatusWidget.swift          # last frame, battery, last seen
      StandByRadarWidget.swift
  Watch/                               # Phase 3
    VarioRadarWatchApp/
  Packages/
    VarioRadarCore/                    # SwiftPM library, all platforms
      Sources/VarioRadarCore/
        BLE/
          BLECentral.swift             # actor wrapper around CBCentralManager
          PeripheralSession.swift
        Devices/
          VariaRadar.swift             # Garmin Varia parser
          FlarmNmea.swift              # later: FLARM/NMEA parser
          Gdl90.swift                  # later: GDL 90 (over UDP) parser
        Model/
          RadarFrame.swift
          Threat.swift
        Storage/
          AppGroupSnapshot.swift
      Tests/VarioRadarCoreTests/
        VariaRadarTests.swift          # fixture-driven decode tests
        FlarmNmeaTests.swift
        Gdl90Tests.swift
  Fixtures/                            # captured byte streams from real devices
    varia_rtl515_quiet.bin
    varia_rtl515_one_car.bin
    varia_rtl515_split_packet.bin
    flarm_pflaa_sample.nmea
  docs/
    analysis.md
    decisions.md
    protocols/
      varia-ble.md                     # canonical writeup, ours
      flarm-nmea.md
      gdl90-extended.md
  LICENSE                              # MIT
  README.md
  .github/
    workflows/
      ci.yml                           # build, lint, test on macos-15 runner
```

Notes:
- The shared parser lives in a Swift Package so the unit tests can run on
  macOS, and so the Watch and Widget targets can link it without rebuilding.
- Fixtures are binary captures from a real device, checked in. Tests run
  against the bytes, no device required for CI.
- The protocol writeups in `docs/protocols/` are our open documentation
  contribution; even if no one else uses the app, those pages have value.

## D2. Hardware probe findings (2026-06-11, real RCT716 on the Mac)

We probed the user's actual device with a throwaway CoreBluetooth CLI on
macOS while the unit was docked over USB. Findings:

- **Identity.** `GarminDevice.xml` on the mass storage volume confirms
  RCT716, firmware 5.50, part `006-B3808-00`, unit ID `3506078425`.
- **USB is mass storage only.** The volume exposes `DCIM` (dashcam MP4s,
  `100EVENT`, `101PHOTO`, `102SAVED`, `103UNSVD`), GPX in/out, error
  report JSONs, and the firmware update drop point. No live data channel
  over USB; the radar feed is BLE only, as assumed.
- **Advertising confirmed.** Even while docked, the device advertises as
  `RCT716-78425` (suffix is the unit ID tail) with exactly the expected
  radar service `6A4E3200-667B-11E3-949A-0800200C9A66` in the
  advertisement. Strong signal (RSSI around -40 at desk range).
- **Connection refused while docked.** Every connection attempt succeeds
  at the link layer, then the device drops us about one second later
  (`CBErrorDomain code 7`, peripheral initiated) before GATT service
  discovery returns. Reproduced across ~40 attempts, including after
  ejecting the mass storage volume. Two candidate explanations, untested
  because both need physical action:
  1. Varia firmware disables live sessions while on USB power
     (most likely; matches how the unit behaves with an Edge while
     charging).
  2. The RCT7xx requires pairing/bonding for new centrals (the RTL5xx
     line did not, per community reports, but the camera models have a
     richer pairing flow in the Varia app).
- **Root cause of the disconnects (bluetoothd log analysis).** The kick
  is macOS specific, not a device defect, and not USB or pairing mode
  related (reproduced unplugged and in pairing mode):
  1. On every LE connection, macOS bluetoothd does housekeeping: it reads
     the GAP device name characteristic (0x2A00).
  2. The RCT716 protects GAP reads: it answers
     `LE_ATT_ERROR_INSUFFICIENT_AUTHENTICATION`.
  3. bluetoothd auto-starts SMP pairing
     (`GATT is Asking to pair ... startAutoPairing=1`).
  4. The Garmin refuses standard SMP and terminates the link about 60 ms
     into pairing (HCI reason 0x13, "Remote User Terminated", surfaced as
     reason 719 / CBErrorDomain code 7).
  This loop is unavoidable on macOS (a fast-subscribe race lost 210/210
  attempts; characteristic discovery needs live ATT round trips and the
  link dies first). iOS does not do the automatic GAP name read, which is
  why third party iOS and Android apps (Ride with GPS, Cadence, pycycling
  on Linux) work with the RCT715/716 without bonding.
- **Full GATT table** (recovered from the bluetoothd cache dump):

  | Handle | Service                                  | Note                       |
  |--------|------------------------------------------|----------------------------|
  | 0x0001 | 0x1800 GAP                               | name read is auth gated    |
  | 0x0007 | 0x1801 GATT                              |                            |
  | 0x000B | ABD23100-81B1-4429-BC15-EB4869827151     | Garmin proprietary         |
  | 0x004A | ABD23150-...                             | Garmin proprietary         |
  | 0x0050 | ABD23120-...                             | Garmin proprietary         |
  | 0x0056 | ABD23130-...                             | Garmin proprietary         |
  | 0x0094 | ABD23170-...                             | Garmin proprietary         |
  | 0x00A4 | ABD23180-...                             | Garmin proprietary         |
  | 0x00AB | ABD23190-...                             | Garmin proprietary         |
  | 0x00B5 | ABD231A0-...                             | Garmin proprietary         |
  | 0x00BB | 6A4E3200-667B-11E3-949A-0800200C9A66     | radar, ends 0x00C1         |
  | 0x00C2 | 0x180A Device Information                |                            |
  | 0x00D5 | 0x180F Battery                           |                            |

  The ABD231xx block is presumably camera control, Garmin auth, and
  firmware plumbing; the radar service spans 7 handles (room for two
  characteristics plus descriptors).
- **Radar characteristic confirmed via pycycling**: the measurement
  characteristic is `6A4E3203-667B-11E3-949A-0800200C9A66` (notify).
  Payload: byte 0 packet id, then per threat `[id, distance_m, speed_kmh]`
  as uint8 triplets. pycycling lists RVR315, RTL515/516 and RCT715 as
  compatible, which covers our RCT716.
  (https://github.com/zacharyedwardbull/pycycling)
- **Consequence for the project.** Live frame capture cannot happen from
  macOS. First live validation happens on an iPhone: either nRF Connect
  (manual, zero code) or the Phase 2 app skeleton deployed via Xcode.
  Fixtures get captured on iPhone (nRF Connect export or a debug logging
  screen in the app) instead of on the Mac. Bench probe sources from this
  session are in `/tmp/blescan/` and can be promoted to `tools/` in
  Phase 2 if useful.

### D2.1 Correction (2026-06-11, later the same day): bonding is the gate, macOS works

The conclusion above ("iOS works unbonded, macOS is a dead end") was
**wrong**. On-device testing from a real iPhone showed the identical
drop-during-discovery signature, which prompted a retest of the pairing
path with simultaneous bluetoothd logging:

- **The RCT716 (firmware 5.50) requires a standard BLE bond from every
  central, on every platform.** Unbonded centrals are dropped about one
  second after connect, during GATT discovery. This is a departure from
  the RTL5xx behaviour the community documented (subscribe-without-bond),
  presumably part of the camera model's privacy hardening.
- **With the radar in pairing mode** (power off, hold button ~2 s, LED
  flashes purple, 5-minute window) **standard "Just Works" SMP pairing
  succeeds**: encryption enabled, keys persisted, and the radar streams.
  Verified end to end on macOS; the log shows
  `Pairing succeeded ... Writing keys to disk`.
- After bonding, macOS receives live notifications on `6A4E3203`. The
  Mac is therefore a fully usable dev client after a one-time pairing.
- Full radar service layout from the bonded session:
  `6A4E3203` (read + notify, the measurement stream; a direct read
  returns a 20-byte zero buffer) and `6A4E3205` (read + write +
  write-no-response; reads `0xff`; purpose unknown, likely a control
  register, possibly threat-level/alert config or camera related).
- Observed idle stream: single-byte frames (clear road) at roughly 7 Hz
  with a cycling sequence nibble, not the 1 Hz the RTL5xx lore suggests.
  Multi-target frame layout still needs live confirmation with real
  traffic.
- **App consequence:** first-time setup needs a pairing flow: radar in
  pairing mode, connect, iOS shows the system pairing prompt, user
  accepts, bond persists. The app should surface this in onboarding
  ("put your radar in pairing mode"). After that, reconnects are
  automatic and unattended.

## E. Risks and open questions

| # | Risk / question                                                   | Severity | Mitigation / next step                                                                 |
|---|-------------------------------------------------------------------|----------|----------------------------------------------------------------------------------------|
| 1 | Confirm the RCT716 advertises the same radar service UUID as the RTL5xx (very likely but not yet verified on hardware). | Low      | Sniff with nRF Connect on first contact; lock the UUID into a fixture. |
| 2 | Resolved: target device is Garmin Varia RCT716 (cycling rear radar). | -        | -                                                                                              |
| 3 | iOS Simulator has no BLE radio.                                   | Medium   | All BLE work tested on device. Unit tests run on captured byte fixtures.               |
| 4 | Apple Developer paid account required for Live Activities, Push, App Groups, Critical Alerts, distribution. | Medium | Confirm an active Apple Developer Program membership. Free profile cannot ship LA push or AOD properly. |
| 5 | Live Activity push budget may throttle 1 Hz updates.              | Medium   | Use local updates from the background BLE callback as the primary path. Push is a backup. Set `NSSupportsLiveActivitiesFrequentUpdates`. |
| 6 | Garmin firmware updates can change the BLE payload silently (the RearVue 820 already differs). | Medium | Parser version-tags every fixture. Fail soft on unknown frame ids; log; surface a "protocol drift" warning to the user. |
| 7 | App Store review may reject "always visible radar" if framed as a constant overlay. | Medium | Frame the app as a session based safety tool. Start a Live Activity when the user begins a ride; end it when they stop. Do not request Always On Bluetooth in marketing copy. |
| 8 | Critical Alerts entitlement may be denied.                        | Low      | Time Sensitive notifications are sufficient for v1. Apply for Critical only after ship. |
| 9 | Garmin may object to publishing the reverse engineered protocol.  | Low      | Cite the existing public threads and prior reverse engineering. Do not republish anything obtained under the Radar Data BLE Program. Keep our doc derived from community sources, properly attributed. |
| 10| ANT+ users (some older Varia models) cannot use a BLE only app.   | Low      | Document the supported device list clearly. The 5xx and 8xx series are BLE; the 3xx series are ANT+ only and out of scope. |
| 11| Live Activity 8h ceiling shorter than long sailplane flights.     | Low      | Auto-renew by ending and starting a fresh activity at 7h45m, copying current state. The visual transition is brief.|

## Sources

[gar-rdble]: https://developer.garmin.com/radar-data-ble/overview/
[gar-forum]: https://forums.garmin.com/developer/connect-iq/f/discussion/240452/bluetooth-profile-for-garmin-varia-rtl515
[var-cpp]: https://github.com/Wunderfitz/harbour-tacho/blob/master/src/variaconnectivity.cpp
[gdl90-icd]: https://www.faa.gov/sites/faa.gov/files/air_traffic/technology/adsb/archival/GDL90_Public_ICD_RevA.PDF
[ff-gdl90]: https://www.foreflight.com/connect/spec/
[etdey]: https://github.com/etdey/gdl90
[stratux]: https://github.com/cyoung/stratux
[softrf-gdl90]: https://github.com/lyusupov/SoftRF/blob/master/software/firmware/source/libraries/rotobox/gdl90.c
[xct-ext]: https://xctrack.org/External_Devices.html
[flarm-port]: https://flarm.com/
[lapush]: https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications
[ns-freq]: https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivitiesfrequentupdates
[crit-ent]: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.critical-alerts
[wk-update]: https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
[cb-bg]: https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html

- Garmin Radar Data BLE Program overview ([link][gar-rdble])
- Garmin Connect IQ forum, "Bluetooth profile for Garmin Varia RTL515" ([link][gar-forum])
- harbour-tacho reference implementation, Wunderfitz on GitHub ([link][var-cpp])
- FAA GDL 90 Public ICD Rev A, 2007 ([link][gdl90-icd])
- ForeFlight GDL 90 Extended Specification ([link][ff-gdl90])
- etdey/gdl90 Python decoder ([link][etdey])
- cyoung/stratux Go GDL 90 generator ([link][stratux])
- lyusupov/SoftRF C parser ([link][softrf-gdl90])
- XCTrack external devices documentation ([link][xct-ext])
- FLARM product documentation ([link][flarm-port])
- Apple, Starting and updating Live Activities with ActivityKit push notifications ([link][lapush])
- Apple, NSSupportsLiveActivitiesFrequentUpdates ([link][ns-freq])
- Apple, Critical Alerts entitlement ([link][crit-ent])
- Apple, Keeping a widget up to date ([link][wk-update])
- Apple, Performing tasks while your app is in the background (CoreBluetooth) ([link][cb-bg])
