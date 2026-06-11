import SwiftUI
import VarioRadarCore

/// Shared visual vocabulary so the app, Live Activity, and widgets all map
/// severity to the same colour and wording.
extension ThreatLevel {
    var color: Color {
        switch self {
        case .none: return .green
        case .approaching: return .yellow
        case .warning: return .orange
        case .critical: return .red
        }
    }

    var shortLabel: String {
        switch self {
        case .none: return "Clear"
        case .approaching: return "Car"
        case .warning: return "Closing"
        case .critical: return "Fast"
        }
    }

    var symbolName: String {
        switch self {
        case .none: return "checkmark.circle.fill"
        case .approaching: return "car.fill"
        case .warning: return "car.fill"
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
}
