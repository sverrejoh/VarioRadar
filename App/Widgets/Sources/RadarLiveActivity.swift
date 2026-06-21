import ActivityKit
import SwiftUI
import VarioRadarCore
import WidgetKit

// Implementation of the "Varia Radar Island" SCOPE design. Range-only
// (no bearing): contacts are placed by distance behind the rider. The
// compact pill pairs closing speed (left of the camera) with nearest
// distance (right); the expanded and Lock Screen views show the full
// circular scope. Greys out to "NO SIGNAL" when the activity is stale.
//
// Notes vs the HTML prototype: continuous sweep/pulse animations do not
// run reliably in a Live Activity, so they are static here; numbers use
// numericText transitions and the closing bar uses ProgressView(timer)
// which the system does animate on-device. Barlow is substituted with the
// system font at condensed width (bundling Barlow is a later polish step).

struct RadarLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RadarActivityAttributes.self) { context in
            RadarLockCard(presentation: context.state.presentation, isStale: context.isStale)
                .activityBackgroundTint(.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let p = context.state.presentation
            let stale = context.isStale
            let tint = islandColor(p, stale: stale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.variaAccent).frame(width: 6, height: 6)
                        Text("VARIA").font(.system(size: 11, weight: .bold)).kerning(1.0)
                            .foregroundStyle(Color(hex: 0x9AA0A6))
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusChip(text: stale ? "NO SIGNAL" : p.statusLabel, color: tint, small: true)
                        .lineLimit(1)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .center, spacing: 16) {
                        RadarScope(cars: p.cars, size: 84, isStale: stale)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NEAREST")
                                .font(.system(size: 9, weight: .semibold)).kerning(1.1)
                                .foregroundStyle(Color(hex: 0x6B7178))
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(p.nearestDistanceMeters.map(String.init) ?? "—")
                                    .font(.system(size: 30, weight: .bold).width(.condensed))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .foregroundStyle(tint)
                                Text("m").font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(tint.opacity(0.6))
                            }
                            Text(stale ? "\(p.threatCount) TRACKED"
                                       : "+\(p.nearestSpeedKmh ?? 0) km/h · \(p.threatCount) tracked")
                                .font(.system(size: 9, weight: .semibold)).kerning(0.6)
                                .foregroundStyle(Color(hex: 0x6B7178))
                            if !stale, let car = p.nearest { ClosingBar(car: car, color: tint) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                SpeedRing(presentation: p, color: tint, isStale: stale)
            } compactTrailing: {
                CompactTrailing(presentation: p, color: tint)
            } minimal: {
                MinimalDot(color: tint, alert: p.highestLevel == .critical && !stale)
            }
            .keylineTint(tint)
        }
    }
}

// MARK: - Shared helpers

func islandColor(_ p: RadarPresentation, stale: Bool) -> Color {
    stale ? .variaStale : p.highestLevel.color
}

/// Fraction (0 far, 1 near) of a contact across the 140 m range.
private func proximity(_ meters: Int) -> CGFloat {
    1 - min(max(CGFloat(meters) / 140, 0), 1)
}

// MARK: - Compact

private struct SpeedRing: View {
    let presentation: RadarPresentation
    let color: Color
    let isStale: Bool

    var body: some View {
        if presentation.isClear && !isStale {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                    .shadow(color: color, radius: 4)
                Text("CLEAR").font(.system(size: 11, weight: .bold)).kerning(1)
                    .foregroundStyle(color)
            }
        } else {
            ZStack {
                Circle().fill(color)
                Circle().fill(Color(hex: 0xF1F2F3)).padding(3)
                Text("\(presentation.nearestSpeedKmh ?? 0)")
                    .font(.system(size: 13, weight: .heavy).width(.condensed))
                    .monospacedDigit().contentTransition(.numericText())
                    .foregroundStyle(Color(hex: 0x0B0C0F))
            }
            .frame(width: 26, height: 26)
        }
    }
}

private struct CompactTrailing: View {
    let presentation: RadarPresentation
    let color: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(presentation.nearestDistanceMeters.map(String.init) ?? "—")
                    .font(.system(size: 15, weight: .bold).width(.condensed))
                    .monospacedDigit().contentTransition(.numericText())
                    .foregroundStyle(color)
                Text("m").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: 0x7D8389))
            }
            // A self-draining bar (animated on-device) when a contact is
            // closing, so the pill keeps moving between sparse background
            // updates; falls back to static dots when speed is unknown.
            if let car = presentation.nearest, car.speedKmh > 0 {
                ClosingBar(car: car, color: color, width: 42, height: 5)
            } else {
                MiniTrack(cars: presentation.cars, color: color)
                    .frame(width: 42, height: 6)
            }
        }
    }
}

/// Horizontal approach track for the compact pill: far at the right, the
/// rider (camera cutout) at the left.
private struct MiniTrack: View {
    let cars: [RadarPresentation.Car]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16)).frame(height: 1.5)
                ForEach(cars) { car in
                    let x = (4 + (CGFloat(min(car.distanceMeters, 140)) / 140) * 90) / 100 * w
                    Circle().fill(car.level.color)
                        .frame(width: 5, height: 5)
                        .shadow(color: car.level.color, radius: 3)
                        .position(x: x, y: geo.size.height / 2)
                }
            }
        }
    }
}

private struct MinimalDot: View {
    let color: Color
    let alert: Bool
    var body: some View {
        Circle().fill(color)
            .frame(width: alert ? 11 : 9, height: alert ? 11 : 9)
            .shadow(color: color, radius: alert ? 8 : 5)
    }
}

// MARK: - Scope

/// The circular radar scope: concentric range rings, a forward marker at
/// the centre, and contacts placed below it by distance (range-only).
struct RadarScope: View {
    let cars: [RadarPresentation.Car]
    let size: CGFloat
    let isStale: Bool

    var body: some View {
        ZStack {
            Circle().fill(
                RadialGradient(colors: [Color(hex: 0x0E1218), Color(hex: 0x070A0E)],
                               center: .center, startRadius: 0, endRadius: size / 2))
            Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1)
            Circle().strokeBorder(.white.opacity(0.07), lineWidth: 1).padding(size * 0.17)
            Circle().strokeBorder(.white.opacity(0.06), lineWidth: 1).padding(size * 0.34)
            Rectangle().fill(.white.opacity(0.05)).frame(width: 1)
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: size * 0.07))
                .foregroundStyle(isStale ? Color.variaStale : Color.variaAccent)
            ForEach(cars) { car in
                let dn = min(max(CGFloat(car.distanceMeters) / 140, 0), 1)
                let offsetY = (0.10 + dn * 0.38) * size
                let blip = 0.045 * size + proximity(car.distanceMeters) * 0.04 * size
                Circle().fill(car.level.color)
                    .frame(width: blip, height: blip)
                    .shadow(color: car.level.color, radius: 4)
                    .offset(y: offsetY)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }
}

private struct StatusChip: View {
    let text: String
    let color: Color
    var small: Bool = false
    var body: some View {
        Text(text)
            .font(.system(size: small ? 9 : 11, weight: .bold)).kerning(1)
            .foregroundStyle(color)
            .padding(.horizontal, small ? 7 : 9).padding(.vertical, small ? 2 : 4)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: small ? 6 : 7))
            .overlay(RoundedRectangle(cornerRadius: small ? 6 : 7)
                .strokeBorder(color.opacity(0.5), lineWidth: 1))
    }
}

/// A self-draining bar that estimates time-to-pass. Uses the timer-driven
/// ProgressView so it keeps moving on-device between radar updates, even
/// when the system is throttling Live Activity refreshes in the background.
private struct ClosingBar: View {
    let car: RadarPresentation.Car
    let color: Color
    var width: CGFloat = 70
    var height: CGFloat = 3

    var body: some View {
        if let seconds = closingTime, seconds > 0 {
            ProgressView(timerInterval: Date()...Date().addingTimeInterval(seconds),
                         countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(color)
                .frame(width: width, height: height)
                .padding(.top, 2)
        }
    }

    private var closingTime: Double? {
        guard car.speedKmh > 0 else { return nil }
        return min(Double(car.distanceMeters) / (Double(car.speedKmh) / 3.6), 14)
    }
}

// MARK: - Lock Screen / banner

struct RadarLockCard: View {
    let presentation: RadarPresentation
    let isStale: Bool

    private var tint: Color { islandColor(presentation, stale: isStale) }

    var body: some View {
        HStack(spacing: 16) {
            RadarScope(cars: presentation.cars, size: 78, isStale: isStale)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Circle().fill(Color.variaAccent).frame(width: 7, height: 7)
                    Text("VARIA RADAR").font(.system(size: 10, weight: .bold)).kerning(1.4)
                        .foregroundStyle(Color(hex: 0x9AA0A6))
                    Spacer()
                    StatusChip(text: isStale ? "NO SIGNAL" : presentation.statusLabel,
                               color: tint, small: true)
                }
                Text("NEAREST").font(.system(size: 9, weight: .semibold)).kerning(1.1)
                    .foregroundStyle(Color(hex: 0x6B7178)).padding(.top, 2)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(presentation.nearestDistanceMeters.map(String.init) ?? "—")
                        .font(.system(size: 30, weight: .bold).width(.condensed))
                        .monospacedDigit().contentTransition(.numericText())
                        .foregroundStyle(tint)
                    Text("m").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.6))
                }
                Text(isStale ? "LINK LOST" : "CLOSING +\(presentation.nearestSpeedKmh ?? 0) km/h")
                    .font(.system(size: 9, weight: .semibold)).kerning(1.0)
                    .foregroundStyle(Color(hex: 0x6B7178))
            }
        }
        .padding(14)
    }
}
