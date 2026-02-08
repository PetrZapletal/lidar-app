import SwiftUI
import Sentry

@main
struct LidarAPPApp: App {
    @State private var authService = AuthService()
    @State private var scanStore = ScanStore()

    init() {
        CrashReporter.shared.start()

        // Initialize Sentry for crash reporting and performance monitoring
        SentrySDK.start { options in
            options.dsn = "https://911d47dc3b35bf0c45b1c38097797d61@o4510844790243328.ingest.de.sentry.io/4510844795945040"
            options.tracesSampleRate = 1.0
            options.profilesSampleRate = 1.0
            options.enableAutoSessionTracking = true
            options.enableCaptureFailedRequests = true
            options.attachScreenshot = true
            options.enableUserInteractionTracing = true
            #if DEBUG
            options.debug = true
            options.environment = "debug"
            #else
            options.environment = "production"
            #endif
        }

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
