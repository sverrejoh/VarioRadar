import SwiftUI
import VarioRadarCore

/// The wrist view from the SCOPE design: status dot + time, status label,
/// the top-anchored radar scope, and the nearest distance + closing speed.
/// Background is tinted by severity for instant glanceability.
struct WatchRootView: View {
    @StateObject private var model = WatchRadarModel()

    private var p: RadarPresentation { model.presentation }
    private var tint: Color { p.highestLevel.color }

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [tint.opacity(p.isClear ? 0.12 : 0.30), .black],
                center: .init(x: 0.5, y: 0.06), startRadius: 0, endRadius: 190
            )
            .ignoresSafeArea()

            if model.hasData {
                VStack(spacing: 2) {
                    HStack {
                        Circle().fill(tint).frame(width: 9, height: 9)
                            .shadow(color: tint, radius: 5)
                        Spacer()
                        TimelineView(.everyMinute) { ctx in
                            Text(ctx.date, format: .dateTime.hour().minute())
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    Text(p.statusLabel)
                        .font(.system(size: 13, weight: .bold).width(.condensed)).kerning(1)
                        .foregroundStyle(tint)
                    WatchScope(cars: p.cars).frame(maxHeight: .infinity)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(p.nearestDistanceMeters.map(String.init) ?? "—")
                                .font(.system(size: 30, weight: .bold).width(.condensed))
                                .monospacedDigit().contentTransition(.numericText())
                                .foregroundStyle(tint)
                            Text("m").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: 0x7D8389))
                        }
                        Text("↑\(p.nearestSpeedKmh ?? 0)")
                            .font(.system(size: 15, weight: .bold).width(.condensed))
                            .monospacedDigit().foregroundStyle(tint)
                    }
                    .padding(.bottom, 4)
                }
                .padding(.horizontal, 10)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 26)).foregroundStyle(Color.variaAccent)
                    Text("Start a session on\nyour iPhone")
                        .font(.system(size: 13)).multilineTextAlignment(.center)
                        .foregroundStyle(Color(hex: 0x9AA0A6))
                }
            }
        }
        .onAppear { model.activate() }
    }
}

/// Compact top-anchored scope for the watch: rider at the top, contacts
/// down the centreline by distance (range-only).
private struct WatchScope: View {
    let cars: [RadarPresentation.Car]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let midX = w / 2, topY: CGFloat = 12
            let usable = h - topY - 4
            ZStack {
                ForEach([0.55, 1.05], id: \.self) { f in
                    Circle().stroke(.white.opacity(0.06), lineWidth: 1)
                        .frame(width: w * f, height: w * f)
                        .position(x: midX, y: topY)
                }
                Path { p in
                    p.move(to: CGPoint(x: midX, y: topY))
                    p.addLine(to: CGPoint(x: midX, y: h - 2))
                }
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .foregroundStyle(.white.opacity(0.12))
                ForEach(cars) { car in
                    let frac = min(max(CGFloat(car.distanceMeters) / 140, 0), 1)
                    let prox = 1 - frac
                    let s = 8 + prox * 8
                    Circle().fill(car.level.color)
                        .frame(width: s, height: s)
                        .shadow(color: car.level.color, radius: 3 + prox * 4)
                        .position(x: midX, y: topY + frac * usable)
                }
                Image(systemName: "arrowtriangle.up.fill").font(.system(size: 12))
                    .foregroundStyle(Color.variaAccent).shadow(color: Color.variaAccent, radius: 4)
                    .position(x: midX, y: topY - 2)
            }
        }
    }
}
