import SwiftUI
import VarioRadarCore

/// The in-app radar scope from the SCOPE design: a top-anchored radial
/// view where the rider (YOU) sits at the top and contacts appear down the
/// centreline by distance (range-only, no bearing). Nearest traffic is near
/// the top; far traffic sinks toward the bottom.
struct RadarView: View {
    let threats: [Threat]
    var maxRange: Int = 140

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let midX = w / 2
            let topY: CGFloat = 26
            let usable = h - topY - 10

            ZStack {
                // Concentric range rings, centred on the rider at the top.
                ForEach([40, 80, 120], id: \.self) { r in
                    let radius = topY + CGFloat(r) / CGFloat(maxRange) * usable
                    Circle()
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(x: midX, y: topY)
                    Text("\(r)m")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x4A5058))
                        .position(x: midX + 16, y: topY + radius)
                }

                // Centreline behind the rider.
                Path { p in
                    p.move(to: CGPoint(x: midX, y: topY))
                    p.addLine(to: CGPoint(x: midX, y: h - 6))
                }
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .foregroundStyle(.white.opacity(0.13))

                // Contacts down the centreline.
                ForEach(threats) { threat in
                    let frac = min(max(CGFloat(threat.distanceMeters) / CGFloat(maxRange), 0), 1)
                    let prox = 1 - frac
                    let size = 10 + prox * 10
                    Circle()
                        .fill(threat.level.color)
                        .frame(width: size, height: size)
                        .shadow(color: threat.level.color, radius: 4 + prox * 6)
                        .position(x: midX, y: topY + frac * usable)
                }

                // The rider marker at the top.
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.variaAccent)
                    .shadow(color: Color.variaAccent, radius: 5)
                    .position(x: midX, y: 10)
                Text("YOU")
                    .font(.system(size: 8, weight: .bold)).kerning(1)
                    .foregroundStyle(Color.variaAccent)
                    .position(x: midX, y: topY)

                Text("BEHIND")
                    .font(.system(size: 7, weight: .bold)).kerning(1.4)
                    .foregroundStyle(Color(hex: 0x525860))
                    .position(x: 24, y: h - 10)
            }
        }
        .background(Color(hex: 0x0B0C0F))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    RadarView(threats: [
        Threat(id: 1, distanceMeters: 28, speedKmh: 44),
        Threat(id: 2, distanceMeters: 72, speedKmh: 30),
        Threat(id: 3, distanceMeters: 120, speedKmh: 26),
    ])
    .frame(width: 280, height: 420)
    .padding()
    .background(.black)
}
