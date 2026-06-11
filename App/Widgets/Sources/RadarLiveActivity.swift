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
                    if let nearest = presentation.nearest {
                        VStack(alignment: .trailing) {
                            Text("\(nearest.distanceMeters) m")
                                .font(.headline)
                                .monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))
                            Text("\(nearest.speedKmh) km/h")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ApproachTrackView(presentation: presentation, style: .expanded)
                        .frame(height: 36)
                }
            } compactLeading: {
                Image(systemName: "bicycle")
                    .foregroundStyle(presentation.isClear ? .green : presentation.highestLevel.color)
            } compactTrailing: {
                ApproachTrackView(presentation: presentation, style: .compact)
                    .frame(width: 52)
            } minimal: {
                Image(systemName: presentation.highestLevel.symbolName)
                    .foregroundStyle(presentation.highestLevel.color)
            }
            .keylineTint(presentation.highestLevel.color)
        }
    }
}

/// The approach scene: the rider's bike sits at the leading edge and car
/// glyphs slide toward it as they close. Distance maps linearly to
/// horizontal position over the radar's 140 m range. The implicit
/// animation tweens positions between the 1 Hz radar updates, so cars
/// glide rather than jump.
struct ApproachTrackView: View {
    enum Style {
        case compact   // Dynamic Island trailing slot, ~52 pt wide
        case expanded  // expanded island bottom / Lock Screen
    }

    let presentation: RadarPresentation
    var style: Style
    private let maxRange = 140

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let midY = geo.size.height / 2
            let carSize: CGFloat = style == .compact ? 11 : 16
            // Reserve space at the leading edge for the bike in expanded
            // style; compact omits the bike (it lives in compactLeading,
            // on the other side of the island cutout, so the car visually
            // approaches "around" the island).
            let bikeZone: CGFloat = style == .compact ? 2 : 22
            let trackWidth = width - bikeZone - carSize

            ZStack(alignment: .leading) {
                // Road
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(height: style == .compact ? 2 : 3)
                    .padding(.leading, bikeZone)

                if style == .expanded {
                    Image(systemName: "bicycle")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.cyan)
                        .position(x: 10, y: midY)
                }

                if presentation.isClear {
                    if style == .expanded {
                        Text("clear")
                            .font(.caption2)
                            .foregroundStyle(.green.opacity(0.8))
                            .position(x: width / 2, y: midY)
                    }
                } else {
                    ForEach(presentation.cars) { car in
                        let fraction = min(max(CGFloat(car.distanceMeters) / CGFloat(maxRange), 0), 1)
                        Image(systemName: "car.side.fill")
                            .font(.system(size: carSize, weight: .semibold))
                            .foregroundStyle(car.level.color)
                            .shadow(color: car.level.color.opacity(0.7), radius: 3)
                            .position(x: bikeZone + carSize / 2 + fraction * trackWidth, y: midY)
                    }
                }
            }
            .animation(.linear(duration: 0.9), value: presentation.cars)
        }
    }
}

/// Lock Screen and banner presentation: status line plus the full track.
struct RadarLockScreenView: View {
    let presentation: RadarPresentation

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: presentation.highestLevel.symbolName)
                    .font(.title2)
                    .foregroundStyle(presentation.highestLevel.color)
                Text(presentation.isClear ? "Road clear" : "Vehicle approaching")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if let nearest = presentation.nearest {
                    Text("\(nearest.distanceMeters) m")
                        .font(.title3.bold())
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .foregroundStyle(presentation.highestLevel.color)
                }
            }
            ApproachTrackView(presentation: presentation, style: .expanded)
                .frame(height: 30)
        }
        .padding()
    }
}
