import SwiftUI

@main
struct LidarAPPApp: App {
    @State private var authService = AuthService()
    @State private var scanStore = ScanStore()

    init() {
        CrashReporter.shared.start()

        #if DEBUG
        if DebugSettings.shared.rawDataModeEnabled {
            DebugSettings.shared.debugStreamEnabled = true
            DebugStreamService.shared.startStreaming()
            print("Debug: Auto-started debug streaming (rawDataModeEnabled)")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(authService: authService, scanStore: scanStore)
                .task {
                    await authService.restoreSession()
                    await scanStore.loadScans()
                }
        }
    }
}
