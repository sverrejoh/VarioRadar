import SwiftUI
import VarioRadarCore

// Palette from the "Varia Radar Island" SCOPE design.
extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// Varia brand lime, used for the FWD marker, brand dots, and accents.
    static let variaAccent = Color(hex: 0xD4FF2E)
    /// Greyed-out colour when the radar link is lost (stale).
    static let variaStale = Color(hex: 0x6B7178)
    static let variaScopeInk = Color(hex: 0x0B0C0F)
}

/// Shared visual vocabulary so the app, Live Activity, and widgets all map
/// severity to the same colour and wording. Colours match the SCOPE design.
extension ThreatLevel {
    var color: Color {
        switch self {
        case .none: return Color(hex: 0x2FD97A)        // clear, green
        case .tracking: return Color(hex: 0x39DE7E)    // detected but far, green
        case .approaching: return Color(hex: 0xFFD02E) // yellow
        case .warning: return Color(hex: 0xFF8A1F)     // orange
        case .critical: return Color(hex: 0xFF3B30)    // red
        }
    }

    /// Status word shown in the island/Lock Screen chips.
    var islandLabel: String {
        switch self {
        case .none: return "CLEAR"
        case .tracking: return "CAR BACK"
        case .approaching: return "APPROACHING"
        case .warning: return "WARNING"
        case .critical: return "DANGER"
        }
    }

    var symbolName: String {
        switch self {
        case .none, .tracking: return "checkmark.circle.fill"
        case .approaching, .warning: return "car.fill"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }
}

extension RadarPresentation {
    /// One-line status suitable for the compact Dynamic Island and widgets.
    var compactText: String {
        guard !isClear, let distance = nearestDistanceMeters else { return "Clear" }
        return "\(distance) m"
    }

    /// Status word for the worst current threat.
    var statusLabel: String { highestLevel.islandLabel }
}
