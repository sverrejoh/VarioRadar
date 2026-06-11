import SwiftUI
import VarioRadarCore

/// A rear-facing radar fan: the rider sits at the bottom centre, vehicles
/// approach from the top. Distance maps to vertical position, severity to
/// colour. Designed to read at a glance.
struct RadarView: View {
    let threats: [Threat]
    var maxRange: Int = 140

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                rangeRings(in: size)
                ForEach(threats) { threat in
                    marker(for: threat, in: size)
                }
                riderMarker(in: size)
            }
        }
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func rangeRings(in size: CGSize) -> some View {
        let rings = [maxRange, maxRange * 2 / 3, maxRange / 3]
        return ZStack {
            ForEach(rings, id: \.self) { range in
                let y = yPosition(forDistance: range, in: size)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                Text("\(range) m")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .position(x: 22, y: y - 8)
            }
        }
    }

    private func marker(for threat: Threat, in size: CGSize) -> some View {
        let y = yPosition(forDistance: threat.distanceMeters, in: size)
        return Circle()
            .fill(threat.level.color)
            .frame(width: 18, height: 18)
            .overlay(
                Circle().stroke(.white.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: threat.level.color.opacity(0.8), radius: 6)
            .position(x: size.width / 2, y: y)
            .overlay(
                Text("\(threat.speedKmh)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .position(x: size.width / 2 + 22, y: y)
            )
    }

    private func riderMarker(in size: CGSize) -> some View {
        Image(systemName: "bicycle")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.cyan)
            .position(x: size.width / 2, y: size.height - 18)
    }

    /// Distance 0 sits just above the rider; `maxRange` sits at the top.
    private func yPosition(forDistance distance: Int, in size: CGSize) -> CGFloat {
        let usable = size.height - 40
        let clamped = min(max(distance, 0), maxRange)
        let fraction = CGFloat(clamped) / CGFloat(maxRange)
        return 20 + usable * (1 - fraction)
    }
}

#Preview {
    RadarView(threats: [
        Threat(id: 1, distanceMeters: 120, speedKmh: 32),
        Threat(id: 2, distanceMeters: 60, speedKmh: 55),
        Threat(id: 3, distanceMeters: 18, speedKmh: 80),
    ])
    .frame(height: 360)
    .padding()
}
