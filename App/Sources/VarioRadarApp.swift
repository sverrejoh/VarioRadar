import SwiftUI

@main
struct VarioRadarApp: App {
    @StateObject private var store: RadarSessionStore

    init() {
        // Default: real radar on device, demo in the simulator (no BLE).
        // VR_SOURCE=demo|real (launch env) overrides, for headless testing.
        #if targetEnvironment(simulator)
        var defaultKind: RadarSessionStore.SourceKind = .demo
        #else
        var defaultKind: RadarSessionStore.SourceKind = .real
        #endif
        switch ProcessInfo.processInfo.environment["VR_SOURCE"] {
        case "demo": defaultKind = .demo
        case "real": defaultKind = .real
        default: break
        }
        _store = StateObject(wrappedValue: RadarSessionStore(defaultKind: defaultKind))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    if ProcessInfo.processInfo.environment["VR_AUTOSTART"] == "1" {
                        store.start()
                    }
                }
        }
    }
}
