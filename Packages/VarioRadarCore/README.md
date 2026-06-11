# VarioRadarCore

Device-independent core for VarioRadar: the Garmin Varia radar wire-format
parser and the shared data model. No CoreBluetooth dependency, so it builds
and tests on macOS, iOS, and watchOS.

## What's here

- `Model/Threat` — one tracked vehicle (id, distance, speed) plus derived
  `closingTimeSeconds` and a tunable `ThreatLevel` severity.
- `Model/RadarFrame` — one decoded notification (counter + threats), with
  `nearestThreat`, `highestLevel`, and receive-time stamping.
- `Devices/VariaRadarParser` — pure `Data -> RadarFrame` decoder for the
  `6A4E3203` measurement characteristic.
- `BLE/VariaIdentifiers` — the service and characteristic UUIDs as strings
  (the app layer wraps them in `CBUUID`).

## Wire format

```
byte 0        packet counter / fragment id
byte 1 + 3i   target id
byte 2 + 3i   distance from rider, metres (uint8)
byte 3 + 3i   closing speed, km/h (uint8)
```

A one-byte packet means the road is clear. Source: community reverse
engineering (pycycling et al.), confirmed compatible with the RCT715/716.

## Test fixtures

The fixtures in the test suite are synthetic, hand-built from the wire
format above, because the RCT716 refuses live BLE sessions from macOS (see
`docs/analysis.md` section D2). The byte math is protocol-accurate; replace
with real iPhone captures when available.

## Running tests

```
cd Packages/VarioRadarCore && swift test
```
