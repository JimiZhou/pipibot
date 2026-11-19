import SwiftUI
import PipiBotKit
import PipiBotIOSUI

@main
struct PipiBotIOSApp: App {
    @State private var store = PipiAppStore(
        autoConnect: false,
        enableNativeRuntime: true,
        enableEmbeddedBridge: false,
        seedDemoData: false
    )
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if canImport(UserNotifications)
        PipiIOSNotificationManager.configureCategoriesIfSupported()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            PipiIOSCompanionRootView(store: store)
                .task {
                    #if canImport(UserNotifications)
                    _ = await PipiIOSNotificationManager.requestAuthorizationIfNeeded()
                    #endif
                    syncLiveActivitySnapshot()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        syncLiveActivitySnapshot()
                        Task { await store.refreshAllFromDaemon() }
                    case .background, .inactive:
                        syncLiveActivitySnapshot()
                        store.flush()
                    @unknown default:
                        break
                    }
                }
        }
    }

    private func syncLiveActivitySnapshot() {
        let snapshot = PipiIOSWidgetBridge.snapshot(from: store)
        try? PipiIOSWidgetBridge.saveSnapshot(snapshot)
    }
}
