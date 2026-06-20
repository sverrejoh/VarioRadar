# VarioRadar in the Dynamic Island: Technical Implementation Guide

A complete, self-contained reference for implementing and extending the
Garmin Varia radar display in the iPhone Dynamic Island and Lock Screen
Live Activity. Written to be handed to another agent or engineer with no
prior context on this project.

Scope: what the radar can render, how often it can change, the exact
ActivityKit APIs and patterns, the limits, and the project-specific
recommendations. Targets iOS 18+, Swift 6 / SwiftUI, ActivityKit +
WidgetKit.

---

## 1. The data we have to display

The app connects to a Garmin Varia rear radar (target device: RCT716) over
BLE and decodes a measurement characteristic into frames. Relevant facts
for the UI layer:

- **Cadence of source data:** the radar streams notifications at roughly
  **8 Hz** (about every 120 ms). Clear-road frames are a single byte; a
  frame with targets is `1 + 3*N` bytes (`[counter, (id, distance_m,
  speed_kmh) x N]`). Distance is metres (0..~150), speed is km/h, both
  uint8. The radar tracks up to ~8 vehicles.
- **The model the UI consumes** (`App/Shared/RadarPresentation.swift`),
  already `Codable & Hashable & Sendable` and well under the 4 KB
  ActivityKit payload limit:

  ```swift
  struct RadarPresentation: Codable, Hashable, Sendable {
      struct Car: Codable, Hashable, Sendable, Identifiable {
          var id: UInt8
          var distanceMeters: Int
          var speedKmh: Int
          var levelRaw: Int        // ThreatLevel rawValue
      }
      var isClear: Bool
      var cars: [Car]              // sorted nearest-first, capped at 8
      var highestLevelRaw: Int
      var updatedAt: Date
      // helpers: nearest, nearestDistanceMeters, nearestSpeedKmh,
      //          threatCount, highestLevel, compactText
  }
  ```

- **Severity model** (`VarioRadarCore.ThreatLevel`): `none`, `approaching`,
  `warning`, `critical`, derived from closing time (distance / closing
  speed). Color ramp used everywhere: green / yellow / orange / red.
- **A car with speed 0 is valid** (the RearVue 820 always reports 0); only
  distance 0 means "empty slot". Do not treat speed 0 as "not a threat".

The Live Activity `ContentState` is simply `{ presentation:
RadarPresentation }` (`App/Shared/RadarActivityAttributes.swift`).

---

## 2. The four presentations and what the radar puts in each

The system picks the presentation; you supply all of them. The radar
mapping that works:

| Presentation | When shown | Render space (approx, Pro) | Radar content |
|---|---|---|---|
| **Compact leading** | one activity active | 52-62 pt wide, 37 pt tall | bike glyph, tinted by `highestLevel` |
| **Compact trailing** | pairs with leading | 52-62 pt wide, 37 pt tall | nearest distance `"\(m)"` + a mini approach track, or a closing `ProgressView` |
| **Minimal** | another app also has an activity | ~37 pt circle | single severity glyph (one car/warning symbol) tinted by severity |
| **Expanded** | long-press, or briefly on an alerting update | up to ~160 pt tall, 4 regions | full approach track + car count + nearest distance/speed |

Expanded regions: `.leading`, `.trailing`, `.center`, `.bottom`. Use
`.bottom` for the full-width approach track (bike at the left edge, car
glyphs positioned by distance over a 0..140 m range).

The compact pair is the 95% case a rider actually sees. Design it to carry
the whole message: "is something behind me, how close, how urgent."

---

## 3. What can and cannot be rendered

The Live Activity / island runs a sandboxed WidgetKit extension with a
**strict SwiftUI subset**.

**Renders:**
- `Text` (styled, custom fonts, `Text(timerInterval:)`, formatted values)
- `Image` from bundled assets and **SF Symbols** (multicolor / hierarchical), with fade / content transitions on change
- Shapes and `Path` (Capsule, Circle, RoundedRectangle, custom drawing)
- `Gauge`, `ProgressView` (including the self-filling `timerInterval` style)
- `Color`, gradients, `Material`, opacity, blend modes, `.tint`
- Layout: `HStack`/`VStack`/`ZStack`/`Grid`, `.overlay`, `.background`
- `Button` and `Toggle` bound to **App Intents** (iOS 17+)

**Ignored / unsupported (do not use):**
- Video (`AVPlayer`, `VideoPlayer`), `Map` (renders blank: draw your own track)
- Animated GIF / APNG (first frame only)
- `ScrollView`, `List`, `WebView`, any `UIViewRepresentable` / UIKit
- Network image loading at render time (assets must be bundled or in the App Group)
- Free-form gestures; arbitrary continuous animation (`.repeatForever`, `TimelineView(.periodic)` are throttled or dropped once locked/backgrounded)

---

## 4. The refresh model (the part that is easy to get wrong)

**The view is a static snapshot.** It only changes when you call
`activity.update(_:)` (or a push delivers a new `ContentState`). There is
no run loop you can animate against inside the island.

Three ways pixels change:

1. **Discrete updates.** Each `update()` swaps in a new snapshot. On
   iOS 17+ the system **auto-animates the transition**: numbers roll,
   symbols fade, layout springs. You can steer this with
   `.contentTransition(.numericText(value:))` on changing numbers and with
   `.transition(...)` on appearing/disappearing views.
2. **Self-interpolating primitives.** Exactly two things keep moving
   frame-by-frame on the device with **no updates at all**, because the
   system drives them off the wall clock and they survive lock and
   suspension:
   - `Text(timerInterval:countsDown:)` - a live counting clock
   - `ProgressView(timerInterval:countsDown:)` with linear style - a
     smoothly filling/draining bar or ring
3. **Custom animation** (`withAnimation`, `.repeatForever`,
   `TimelineView`) - **unreliable**. Ignored or throttled when locked or
   backgrounded. Do not depend on it.

Practical consequence for the radar: update the snapshot at ~1-2 Hz
(not the full 8 Hz; the island cannot usefully show more and high-rate
updates burn battery and budget), and use the interpolating primitives to
make motion look continuous between snapshots.

---

## 5. Hard limits

| Limit | Value | Note |
|---|---|---|
| `ContentState` payload | **4 KB** | per update, local or push. Our frame is a few hundred bytes. |
| Active lifetime | **8 hours** | activity ends after 8 h; restart a fresh one for longer rides. |
| Lock-screen tail | **+4 h (12 h total)** | lingers but stops updating. |
| Sustained update rate | **~1 / second** | even with the frequent-updates entitlement; the system throttles bursts. |
| Always-On Display | dimmed, low refresh | design the compact state to read in the muted, slow mode. |

---

## 6. The update engine for this app

Do **not** use any background-keep-alive trick (silent audio, fake
location). They get rejected and are unnecessary here. The radar gives us a
legitimate engine:

- The app declares `UIBackgroundMode = bluetooth-central` (real, used).
- Each BLE radar notification wakes the app; in the CoreBluetooth callback
  we decode the frame and call `activity.update(_:)`. This is the
  sanctioned path and works while another app is foreground or the phone
  is locked, as long as the BLE connection is alive.
- **Throttle** updates to ~1-2 Hz (coalesce the 8 Hz stream). Skip
  updates when the presentation is unchanged (e.g. identical clear-road
  frames).
- For when the app is fully suspended/killed, an APNs `liveactivity` push
  path can be added later; gate it with
  `NSSupportsLiveActivitiesFrequentUpdates = YES`. Not required for v1
  because the BLE connection keeps the app running.

Info.plist keys already set (`App/project.yml`): `NSSupportsLiveActivities`,
`NSSupportsLiveActivitiesFrequentUpdates`, `UIBackgroundModes:
[bluetooth-central]`, plus the App Group for widget reads.

---

## 7. Code patterns

### 7.1 Widget configuration (widget extension)

```swift
struct RadarLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RadarActivityAttributes.self) { context in
            // Lock Screen / banner
            RadarLockScreenView(presentation: context.state.presentation)
                .activityBackgroundTint(.black.opacity(0.7))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let p = context.state.presentation
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading)  { /* count + icon */ }
                DynamicIslandExpandedRegion(.trailing) { /* distance + speed */ }
                DynamicIslandExpandedRegion(.bottom)   { ApproachTrack(p, .expanded) }
            } compactLeading: {
                Image(systemName: "bicycle").foregroundStyle(p.highestLevel.color)
            } compactTrailing: {
                ApproachTrack(p, .compact).frame(width: 52)
            } minimal: {
                Image(systemName: p.highestLevel.symbolName)
                    .foregroundStyle(p.highestLevel.color)
            }
            .keylineTint(p.highestLevel.color)
        }
    }
}
```

### 7.2 Smooth motion between 1 Hz snapshots

Roll the distance number and drive a closing bar that keeps moving even if
the next frame is late:

```swift
// Distance rolls instead of jumping:
Text("\(car.distanceMeters)")
    .contentTransition(.numericText(value: Double(car.distanceMeters)))

// Closing bar drains on-device with no further updates. estimatedImpact
// is `now + closingTimeSeconds`, recomputed each update:
ProgressView(timerInterval: car.lastSeen...car.estimatedImpact,
             countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
    .progressViewStyle(.linear)
    .tint(car.level.color)
```

### 7.3 Lifecycle (app side)

```swift
// Start: end orphaned activities first (they outlive the process).
for old in Activity<RadarActivityAttributes>.activities {
    await old.end(nil, dismissalPolicy: .immediate)
}
let activity = try Activity.request(
    attributes: RadarActivityAttributes(sessionName: "Ride"),
    content: .init(state: .init(presentation: .clear), staleDate: nil))

// Update (throttled to ~1-2 Hz, from the BLE callback):
await activity.update(
    .init(state: .init(presentation: p),
          staleDate: Date().addingTimeInterval(5)))  // dims if updates stop

// End:
await activity.end(activity.content, dismissalPolicy: .immediate)
```

Set `staleDate` a few seconds out so a dropped BLE connection visibly dims
the activity instead of showing a stale reading as if it were live.

Near the 8 h ceiling, end and immediately re-request a fresh activity,
carrying the current state, so long rides continue.

### 7.4 Escalation: pop the island + haptic on a critical car

`Activity.update` takes an optional alert configuration. Fire it **only**
on a transition into `critical` closing, never routinely:

```swift
let alert = AlertConfiguration(
    title: "Vehicle approaching fast",
    body: "\(meters) m and closing",
    sound: .default)
await activity.update(.init(state: .init(presentation: p),
                            staleDate: Date().addingTimeInterval(5)),
                      alertConfiguration: alert)
```

This auto-expands the island briefly and alerts. Spamming it reads as a
broken app and trains the user to ignore it.

### 7.5 Optional interactivity (iOS 17+)

A `Button(intent:)` / `Toggle(isOn:intent:)` bound to a `LiveActivityIntent`
runs without launching the app. Useful for "mute alerts for this ride" or
"save dashcam clip" directly from the expanded island. Keep it to one
control; the island is not a control panel.

---

## 8. Recommended radar UX per surface

- **Compact leading:** bike glyph, tinted by `highestLevel` (green when
  clear).
- **Compact trailing:** nearest distance in metres + a mini track where a
  car glyph slides toward the camera cutout as it closes; tint by severity;
  roll the number with `.numericText`.
- **Minimal:** a single severity glyph (it is all you get when sharing the
  island with another app).
- **Expanded:** leading = car count + icon; trailing = nearest distance +
  speed; bottom = full approach track with bike at the leading edge and all
  tracked cars positioned by distance, each labeled with its metres.
- **Lock Screen / banner:** status line ("Road clear" / "Vehicle
  approaching") + nearest distance + the full track. This is also what the
  Always-On Display renders, dimmed.

Color is functional, not decorative: it is the fastest channel a glancing
rider has, so keep the severity ramp consistent across every surface.

---

## 9. Pitfalls / do-not

- Do not push at 8 Hz. Coalesce to 1-2 Hz; dedup unchanged frames.
- Do not rely on `.repeatForever` / `TimelineView` for the sliding car;
  use position from the latest snapshot plus `numericText`/`timerInterval`
  interpolation.
- Do not draw a `Map`, load a remote image, or use any UIKit view.
- Do not leave orphaned activities; end them on start (they survive app
  relaunch and otherwise show frozen "clear" forever).
- Do not treat speed 0 as "no threat" (820 reports 0).
- Do not exceed 4 KB state (we will not, but keep `cars` capped at 8).
- Do not fire the alert configuration on routine traffic.
- Remember the simulator has no Bluetooth and Live Activities do render
  there: develop the UI in the simulator against a scripted radar source.

---

## 10. Current implementation status (repo pointers)

- `App/Shared/RadarPresentation.swift` - the transport model + helpers.
- `App/Shared/RadarActivityAttributes.swift` - `ActivityAttributes` + `ContentState`.
- `App/Sources/LiveActivity/RadarActivityManager.swift` - start/update/end, orphan cleanup, staleDate.
- `App/Widgets/Sources/RadarLiveActivity.swift` - the widget config, Dynamic Island regions, `ApproachTrackView`, Lock Screen view. Compact distance already uses `.numericText`.
- `App/Sources/RadarSource/BLERadarSource.swift` - the BLE wake loop that drives updates.

Not yet implemented (good next steps): `ProgressView(timerInterval:)`
closing bars for sub-second smoothness; alert-configuration escalation on
critical; the 8 h auto-restart; optional App Intent control.

---

## 11. Source notes

Apple does not publish exact background push budgets or island pixel
dimensions; figures here are HIG guidance plus developer-report consensus
as of mid-2026 and shift between iOS releases. Verify lifetime, payload,
and frequency limits against current ActivityKit docs before depending on
them. Key references: Apple ActivityKit docs, Apple HIG "Live Activities",
`NSSupportsLiveActivitiesFrequentUpdates` property-list key. A companion
visual explainer lives at `docs/dynamic-island-capabilities.html`.
