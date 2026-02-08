import Foundation

/// Centrální DI container - constructor injection pro všechny služby.
///
/// Použití:
/// ```swift
/// @State private var services = ServiceContainer()
/// MainTabView(services: services)
/// ```
///
/// Pro testy:
/// ```swift
/// let services = ServiceContainer(arSession: MockARSessionService())
/// ```
@MainActor
@Observable
final class ServiceContainer {

    // MARK: - Debug Services (always available)

    let logger: DebugLogger
    let debugStream: DebugStreamService
    let performanceMonitor: PerformanceMonitor
    let crashReporter: CrashReporter

    // MARK: - Feature Services (protocol-backed)

    let arSession: any ARSessionServiceProtocol
    let camera: any CameraServiceProtocol
    let export: any ExportServiceProtocol
    let network: any NetworkServiceProtocol
    let persistence: any PersistenceServiceProtocol
    let measurement: any MeasurementServiceProtocol

    // MARK: - Production Init

    init() {
        self.logger = DebugLogger.shared
        self.debugStream = DebugStreamService.shared
        self.performanceMonitor = PerformanceMonitor.shared
        self.crashReporter = CrashReporter.shared

        // Feature services - will be replaced with real implementations in Sprint 1+
        self.arSession = PlaceholderARSessionService()
        self.camera = PlaceholderCameraService()
        self.export = PlaceholderExportService()
        self.network = PlaceholderNetworkService()
        self.persistence = PlaceholderPersistenceService()
        self.measurement = PlaceholderMeasurementService()
    }

    // MARK: - Testing Init

    init(
        logger: DebugLogger = .shared,
        debugStream: DebugStreamService = .shared,
        performanceMonitor: PerformanceMonitor = .shared,
        crashReporter: CrashReporter = .shared,
        arSession: any ARSessionServiceProtocol = PlaceholderARSessionService(),
        camera: any CameraServiceProtocol = PlaceholderCameraService(),
        export: any ExportServiceProtocol = PlaceholderExportService(),
        network: any NetworkServiceProtocol = PlaceholderNetworkService(),
        persistence: any PersistenceServiceProtocol = PlaceholderPersistenceService(),
        measurement: any MeasurementServiceProtocol = PlaceholderMeasurementService()
    ) {
        self.logger = logger
        self.debugStream = debugStream
        self.performanceMonitor = performanceMonitor
        self.crashReporter = crashReporter
        self.arSession = arSession
        self.camera = camera
        self.export = export
        self.network = network
        self.persistence = persistence
        self.measurement = measurement
    }
}
