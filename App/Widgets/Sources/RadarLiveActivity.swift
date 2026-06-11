import ActivityKit
import SwiftUI
import VarioRadarCore
import WidgetKit

/// The Live Activity: Lock Screen / banner layout plus the three Dynamic
/// Island presentations. This is the surface that stays visible while the
/// rider is in another app (e.g. Apple's Workout app).
struct RadarLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RadarActivityAttributes.self) { context in
            RadarLockScreenView(presentation: context.state.presentation)
                .activityBackgroundTint(.black.opacity(0.7))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let presentation = context.state.presentation
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(presentation.isClear ? "Clear" : "\(presentation.threatCount) car\(presentation.threatCount == 1 ? "" : "s")")
                    } icon: {
                        Image(systemName: presentation.highestLevel.symbolName)
                            .foregroundStyle(presentation.highestLevel.color)
                    }
                    .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let distance = presentation.nearestDistanceMeters {
                        VStack(alignment: .trailing) {
                            Text("\(distance) m").font(.headline).monospacedDigit()
                            if let speed = presentation.nearestSpeedKmh {
                                Text("\(speed) km/h").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RadarBarView(presentation: presentation)
                }
            } compactLeading: {
                Image(systemName: presentation.highestLevel.symbolName)
                    .foregroundStyle(presentation.highestLevel.color)
            } compactTrailing: {
                Text(presentation.compactText)
                    .monospacedDigit()
                    .foregroundStyle(presentation.highestLevel.color)
            } minimal: {
                Image(systemName: presentation.highestLevel.symbolName)
                    .foregroundStyle(presentation.highestLevel.color)
            }
            .keylineTint(presentation.highestLevel.color)
        }
    }
}

/// Lock Screen and banner presentation.
struct RadarLockScreenView: View {
    let presentation: RadarPresentation

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: presentation.highestLevel.symbolName)
                .font(.largeTitle)
                .foregroundStyle(presentation.highestLevel.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.isClear ? "Road clear" : "Vehicle approaching")
                    .font(.headline)
                    .foregroundStyle(.white)
                if !presentation.isClear, let distance = presentation.nearestDistanceMeters {
                    Text("\(distance) m" + (presentation.nearestSpeedKmh.map { " · \($0) km/h" } ?? ""))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .monospacedDigit()
                }
            }
            Spacer()
        }
        .padding()
    }
}

/// A compact horizontal distance bar for the expanded island bottom region.
struct RadarBarView: View {
    let presentation: RadarPresentation
    var maxRange = 140

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                if let distance = presentation.nearestDistanceMeters {
                    let fraction = 1 - min(max(Double(distance) / Double(maxRange), 0), 1)
                    Capsule()
                        .fill(presentation.highestLevel.color)
                        .frame(width: max(8, geo.size.width * fraction))
                }
            }
        }
        .frame(height: 8)
    }
}
