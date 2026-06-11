# FakeVaria

A macOS command-line BLE peripheral that impersonates a Garmin Varia
radar. It advertises the real radar service UUID and streams scripted
target frames on the measurement characteristic at 1 Hz.

This exists because the real RCT716 refuses live BLE sessions from macOS
(see `docs/analysis.md` section D2). FakeVaria lets you develop and test
the VarioRadar iPhone app end to end at your desk: the app connects to
the Mac exactly as it would to the radar, and you control the traffic.

## Run

```
cd Tools/FakeVaria
swift run FakeVaria [scenario]
```

Scenarios (from `RadarScript` in VarioRadarCore):

- `clear` — no vehicles
- `singleApproach` — one car closing from 140 m
- `overtake` — a fast car passing a slower one
- `busyRoad` — several cars phasing in and out (default)

Then on the iPhone (or another Mac), scan for `FakeVaria`, connect, and
subscribe to characteristic `6A4E3203-...`. Frames arrive once per second.

## Notes

- macOS will ask for Bluetooth permission the first time.
- The stream only runs while a central is subscribed; it pauses on
  disconnect and resumes on reconnect, which is handy for exercising the
  app's reconnect path.
- Frames are produced by the shared `RadarScript` / `VariaRadarEncoder`,
  so the bytes on the wire are identical to what the parser expects.
