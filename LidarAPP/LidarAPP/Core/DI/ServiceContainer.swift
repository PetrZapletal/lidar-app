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

        // Sprint 1: Real AR and Camera services
        self.arSession = ARSessionService()
        self.camera = CameraService()
        // Sprint 2: Real Export and Persistence services
        self.export = ExportService()
        // Sprint 4: Real Network service
        self.network = NetworkService()
        self.persistence = PersistenceService()
        // Sprint 3: Real Measurement service
        self.measurement = MeasurementService()
    }

    // MARK: - Testing Init

    init(
        logger: DebugLogger = .shared,
        debugStream: DebugStreamService = .shared,
        performanceMonitor: PerformanceMonitor = .shared,
        crashReporter: CrashReporter = .shared,
        arSession: any ARSessionServiceProtocol = ARSessionService(),
        camera: any CameraServiceProtocol = CameraService(),
        export: any ExportServiceProtocol = ExportService(),
        network: any NetworkServiceProtocol = NetworkService(),
        persistence: any PersistenceServiceProtocol = PersistenceService(),
        measurement: any MeasurementServiceProtocol = MeasurementService()
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
