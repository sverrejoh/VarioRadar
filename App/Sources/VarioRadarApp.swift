import SwiftUI

@main
struct VarioRadarApp: App {
    @StateObject private var store: RadarSessionStore

    init() {
        // The simulator has no Bluetooth radio, so it always uses the
        // scripted source. Real hardware uses CoreBluetooth.
        #if targetEnvironment(simulator)
        let source: RadarSource = ScriptedRadarSource(scenario: .busyRoad)
        #else
        let source: RadarSource = BLERadarSource()
        #endif
        _store = StateObject(wrappedValue: RadarSessionStore(source: source))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
