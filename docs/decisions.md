# VarioRadar Decisions

Short, opinionated recommendations from Phase 1 research. Each line is a
proposed default. Push back on any line before Phase 2 starts.

## Scope

1. **Target Garmin Varia (cycling rear radar) for v1**, because the BLE
   protocol is documented, no MFi or business agreement is needed, and
   the 1 Hz cadence matches the Live Activity story cleanly.
2. **Defer aviation traffic (FLARM, GDL 90)** to a later phase. The
   architecture in this doc is shaped so the parser layer can grow to
   cover it without redesign.
3. **Do not pursue the Garmin Radar Data BLE Program** for v1. The
   community spec is sufficient and signing an NDA would conflict with
   publishing an open source parser.

## Platform

4. **iOS 18 minimum, iOS 19 once GA.** Older floors are not worth the
   maintenance cost for a hobby app and would drop Live Activity
   refinements we want.
5. **Swift 6, SwiftUI only.** No UIKit unless PiP makes us reach for
   `UIViewRepresentable`.
6. **Plain CoreBluetooth.** A small `actor` wrapper, no third party BLE
   framework.

## Surfaces

7. **Dynamic Island plus Lock Screen Live Activity is the killer feature.**
   Drive it from the in process BLE callback while backgrounded; APNs is
   the fallback only.
8. **Set `NSSupportsLiveActivitiesFrequentUpdates = YES`** so the user
   can authorise sustained 1 Hz updates if iOS starts throttling.
9. **Time Sensitive notifications for warnings in v1.** Apply for the
   Critical Alerts entitlement only after the app is in the store.
10. **Add a small Home and Lock Screen widget** for "last seen device,
    battery, last session" only, not for live data. WidgetKit's refresh
    budget is too tight for live targets.
11. **StandBy is rendered from the same widget**, no separate live
    surface.
12. **No CarPlay.** Almost certainly not approvable for this category.
13. **Picture in Picture is a Phase 3 experiment**, not a v1 surface;
    review risk is real.
14. **Apple Watch companion is Phase 3**, scoped to haptic alerts and a
    Smart Stack widget mirroring the Live Activity.
15. **Action Button intent for start/stop session.** Cheap to add, high
    user value.

## Architecture

16. **Single `RadarFrame` actor as the source of truth**, fed only by the
    BLE callback, observed by every UI surface via an `AsyncStream`.
17. **App Group `group.com.varioradar.shared`** for widget/Watch reads of
    the last accepted frame.
18. **Shared Swift Package `VarioRadarCore`** holds BLE, parsers, model,
    and storage so unit tests run on macOS without a device.
19. **Fixture driven parser tests.** Check in real captured byte streams
    from a device. CI runs on macOS-15 with no BLE radio.
20. **Background mode `bluetooth-central` plus `CBCentralManager`
    restoration identifier.** Survive memory pressure relaunches.

## Licence and project hygiene

21. **MIT licence.** Maximum reuse, minimum friction. Apache 2.0 is the
    obvious alternative if we ever take patents seriously.
22. **Publish protocol writeups under `docs/protocols/`** as a deliberate
    open documentation contribution. Cite all prior reverse engineering.
23. **GitHub Actions CI on `macos-15`** running build, lint
    (`swift format` plus `swiftlint`), and the package test suite. No
    device-in-the-loop tests in CI.
