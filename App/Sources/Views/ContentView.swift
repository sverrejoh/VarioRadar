import SwiftUI
import VarioRadarCore

struct ContentView: View {
    @EnvironmentObject private var store: RadarSessionStore

    private var threats: [Threat] {
        (store.frame?.threats ?? []).sorted { $0.distanceMeters < $1.distanceMeters }
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            RadarView(threats: threats)
                .frame(maxHeight: .infinity)
            threatSummary
            controlButton
        }
        .padding()
        .background(Color(white: 0.06).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("VarioRadar")
                    .font(.title2.bold())
                Text(store.status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: store.presentation.highestLevel.symbolName)
                .font(.title)
                .foregroundStyle(store.presentation.highestLevel.color)
        }
    }

    private var threatSummary: some View {
        Group {
            if threats.isEmpty {
                Label("Road clear", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                VStack(spacing: 6) {
                    ForEach(threats) { threat in
                        HStack {
                            Circle()
                                .fill(threat.level.color)
                                .frame(width: 10, height: 10)
                            Text("\(threat.distanceMeters) m")
                                .monospacedDigit()
                            Spacer()
                            Text("\(threat.speedKmh) km/h")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var controlButton: some View {
        Button {
            store.isRunning ? store.stop() : store.start()
        } label: {
            Text(store.isRunning ? "Stop session" : "Start session")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(store.isRunning ? .red : .accentColor)
    }
}

#Preview {
    let store = RadarSessionStore(source: ScriptedRadarSource(scenario: .overtake))
    return ContentView()
        .environmentObject(store)
        .onAppear { store.start() }
}
