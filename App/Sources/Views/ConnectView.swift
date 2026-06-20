import SwiftUI
import VarioRadarCore

/// First-run pairing screen from the SCOPE design. Shown until the radar
/// is connected and streaming. The Connect button starts a session (which
/// scans, connects, and subscribes); the footer reflects live status.
struct ConnectView: View {
    let status: RadarConnectionStatus
    let isSearching: Bool
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("VARIA RADAR")
                .font(.system(size: 12, weight: .bold)).kerning(2.2)
                .foregroundStyle(Color(hex: 0xC9CCD0))
                .padding(.top, 48)

            Spacer()

            PingingBeacon(active: isSearching)
                .frame(width: 122, height: 122)
                .padding(.bottom, 26)

            Text("Connect your radar")
                .font(.system(size: 25, weight: .bold).width(.condensed))
                .foregroundStyle(Color(hex: 0xEEF0F2))
            Text("Power on your Garmin Varia and keep it within a few metres while we pair.")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x8B9096))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
                .padding(.top, 9)

            DeviceCard(onConnect: onConnect)
                .padding(.top, 26)
                .padding(.horizontal, 24)

            Spacer()

            Text(footer)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: 0x5A5F65))
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(colors: [Color(hex: 0x0F1319), Color(hex: 0x070809)],
                           center: .init(x: 0.5, y: 0.36), startRadius: 0, endRadius: 360)
                .ignoresSafeArea())
    }

    private var footer: String {
        switch status {
        case .scanning: return "Searching for nearby radars..."
        case .connecting: return "Pairing..."
        case .disconnected(let reason): return reason ?? "Disconnected"
        default: return "Tap Connect to begin"
        }
    }
}

private struct PingingBeacon: View {
    let active: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(Color.variaAccent, lineWidth: 1.5)
                    .scaleEffect(animate ? 1.0 : 0.18)
                    .opacity(animate ? 0 : 0.7)
                    .animation(active ? .easeOut(duration: 2.1).repeatForever(autoreverses: false)
                        .delay(Double(i) * 1.05) : .default, value: animate)
            }
            Circle().fill(Color.variaAccent)
                .frame(width: 18, height: 18)
                .shadow(color: Color.variaAccent, radius: 12)
        }
        .onAppear { animate = active }
        .onChange(of: active) { _, now in animate = now }
    }
}

private struct DeviceCard: View {
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x1C2026))
                Circle().stroke(Color.variaAccent, lineWidth: 2).frame(width: 13, height: 13)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("Varia RCT716").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0xEEF0F2))
                Text("Rear radar + tail light · found").font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(hex: 0x6B7178))
            }
            Spacer()
            Button(action: onConnect) {
                Text("Connect").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0B0C0F))
                    .padding(.horizontal, 15).padding(.vertical, 8)
                    .background(Color.variaAccent, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(hex: 0x13161B), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
}
