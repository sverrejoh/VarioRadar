import SwiftUI

@main
struct VarioRadarApp: App {
    @StateObject private var store: RadarSessionStore

    init() {
        // Default: real radar on device, demo in the simulator (no BLE).
        // The user's persisted choice wins over this default; a VR_SOURCE
        // launch env (below) overrides everything, for headless testing.
        #if targetEnvironment(simulator)
        let defaultKind: RadarSessionStore.SourceKind = .demo
        #else
        let defaultKind: RadarSessionStore.SourceKind = .real
        #endif
        _store = StateObject(wrappedValue: RadarSessionStore(defaultKind: defaultKind))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    let env = ProcessInfo.processInfo.environment
                    switch env["VR_SOURCE"] {
                    case "demo": store.setSourceKind(.demo)
                    case "real": store.setSourceKind(.real)
                    default: break
                    }
                    if env["VR_AUTOSTART"] == "1" { store.start() }
                }
        }
    }
}
