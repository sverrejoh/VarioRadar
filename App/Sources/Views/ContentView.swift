import SwiftUI
import VarioRadarCore

struct ContentView: View {
    @EnvironmentObject private var store: RadarSessionStore

    private var isConnected: Bool {
        if case .connected = store.status { return true }
        return store.frame != nil
    }

    var body: some View {
        Group {
            if isConnected {
                RadarDashboard()
            } else {
                ConnectView(
                    status: store.status,
                    isSearching: store.isRunning,
                    kind: store.sourceKind,
                    onKindChange: { store.setSourceKind($0) },
                    onConnect: { store.start() }
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// In-app radar dashboard: header, severity status bar, the top-anchored
/// scope, and the NEAREST / CLOSING / CARS stat row.
private struct RadarDashboard: View {
    @EnvironmentObject private var store: RadarSessionStore

    private var threats: [Threat] {
        (store.frame?.threats ?? []).sorted { $0.distanceMeters < $1.distanceMeters }
    }
    private var p: RadarPresentation { store.presentation }
    private var tint: Color {
        if case .disconnected = store.status { return .variaStale }
        return p.highestLevel.color
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 16).padding(.top, 8)
            statusBar.padding(.horizontal, 16).padding(.top, 14)
            RadarView(threats: threats)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 14).padding(.top, 10)
            statRow.padding(.horizontal, 16).padding(.top, 10)
            controlButton.padding(16)
        }
        .background(
            RadialGradient(colors: [Color(hex: 0x0F1319), Color(hex: 0x070809)],
                           center: .init(x: 0.5, y: 0.9), startRadius: 0, endRadius: 420)
                .ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Text("REAR RADAR").font(.system(size: 12, weight: .bold)).kerning(1.6)
                .foregroundStyle(Color(hex: 0xC9CCD0))
            Spacer()
            HStack(spacing: 6) {
                let demo = store.sourceKind == .demo
                let dotColor = demo ? Color.variaAccent : Color(hex: 0x2FD97A)
                Circle().fill(dotColor).frame(width: 6, height: 6)
                    .shadow(color: dotColor, radius: 6)
                Text(store.deviceName ?? (demo ? "DEMO" : "RADAR"))
                    .font(.system(size: 9, weight: .bold)).kerning(0.6).lineLimit(1)
                    .foregroundStyle(Color(hex: 0xC9CCD0))
                Text("›").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: 0x6B7178))
            }
            .padding(.leading, 10).padding(.trailing, 9).padding(.vertical, 5)
            .background(.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        }
    }

    private var statusBar: some View {
        HStack {
            Text(statusText)
                .font(.system(size: 22, weight: .bold).width(.condensed)).kerning(0.5)
                .foregroundStyle(tint)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(p.nearestDistanceMeters.map(String.init) ?? "—")
                    .font(.system(size: 22, weight: .bold).width(.condensed))
                    .monospacedDigit().contentTransition(.numericText())
                    .foregroundStyle(tint)
                Text("m").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: 0x7D8389))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(tint.opacity(0.4), lineWidth: 1))
    }

    private var statusText: String {
        if case .disconnected = store.status { return "NO SIGNAL" }
        return p.statusLabel
    }

    private var statRow: some View {
        HStack(spacing: 12) {
            StatCard(label: "NEAREST", value: p.nearestDistanceMeters.map(String.init) ?? "—", unit: "m")
            VStack(spacing: 3) {
                Text("CLOSING").font(.system(size: 8, weight: .bold)).kerning(1.2)
                    .foregroundStyle(Color(hex: 0x6B7178))
                SpeedRingView(speedKmh: p.isClear ? nil : p.nearestSpeedKmh, color: tint, size: 66)
            }
            StatCard(label: "CARS", value: "\(p.threatCount)", unit: nil, flex: 0.7)
        }
    }

    private var controlButton: some View {
        Button { store.stop() } label: {
            Text("Stop session").font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent).tint(Color(hex: 0x1C2026))
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    let unit: String?
    var flex: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 8, weight: .bold)).kerning(1.2)
                .foregroundStyle(Color(hex: 0x6B7178))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 20, weight: .bold).width(.condensed))
                    .monospacedDigit().contentTransition(.numericText())
                    .foregroundStyle(Color(hex: 0xEEF0F2))
                if let unit { Text(unit).font(.system(size: 10)).foregroundStyle(Color(hex: 0x6B7178)) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(Color(hex: 0x13161B), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.06), lineWidth: 1))
        .layoutPriority(flex)
    }
}

#Preview {
    let store = RadarSessionStore(defaultKind: .demo)
    ContentView().environmentObject(store).onAppear { store.start() }
}
