import SwiftUI
import VarioRadarCore

/// The "speed-sign" closing-speed indicator: a severity-coloured ring
/// around a pale face with a bold dark number and a km/h label. Reused from
/// the compact island so closing speed reads at a glance in the larger
/// surfaces (full app, expanded bloom). Shows "—" when no car is present.
struct SpeedRingView: View {
    let speedKmh: Int?
    let color: Color
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle().fill(color)
            Circle().fill(Color(hex: 0xF1F2F3)).padding(size * 0.11)
            VStack(spacing: -size * 0.05) {
                Text(speedKmh.map(String.init) ?? "—")
                    .font(.system(size: size * 0.42, weight: .heavy).width(.condensed))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Color(hex: 0x0B0C0F))
                Text("km/h")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x6B7178))
            }
        }
        .frame(width: size, height: size)
    }
}
