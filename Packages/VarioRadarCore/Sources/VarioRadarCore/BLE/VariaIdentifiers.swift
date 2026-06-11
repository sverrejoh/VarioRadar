import Foundation

/// Bluetooth LE identifiers for the Garmin Varia radar service.
///
/// These are 128-bit vendor UUIDs in the `6A4E32xx-667B-11E3-949A-...`
/// range. They are kept as plain strings here so the core package has no
/// dependency on CoreBluetooth and stays testable on any platform; the
/// app layer wraps them in `CBUUID`.
///
/// Verified against a real RCT716 (firmware 5.50) on 2026-06-11: the
/// device advertises ``service`` in its advertisement packet. The
/// measurement characteristic value matches the community spec used by
/// pycycling, which lists the RCT715 (and by extension the RCT716) as
/// compatible.
public enum VariaIdentifiers {
    /// Primary radar service.
    public static let service = "6A4E3200-667B-11E3-949A-0800200C9A66"

    /// Notify characteristic carrying the tracked-target list at ~1 Hz.
    public static let radarMeasurement = "6A4E3203-667B-11E3-949A-0800200C9A66"
}
