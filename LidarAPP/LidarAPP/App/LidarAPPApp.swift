import SwiftUI
import Sentry

@main
struct LidarAPPApp: App {
    @State private var services = ServiceContainer()

    init() {
        // Initialize crash reporting (MetricKit)
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

        // Auto-start debug streaming in debug builds
        #if DEBUG
        if DebugSettings.shared.rawDataModeEnabled {
            DebugSettings.shared.debugStreamEnabled = true
            DebugStreamService.shared.startStreaming()
            debugLog("Auto-started debug streaming", category: .logCategoryNetwork)
        }
        #endif

        infoLog("LidarAPP started - Sprint 0 skeleton", category: .logCategoryUI)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(services: services)
        }
    }
}
