import Foundation
import ARKit
import Combine

// MARK: - Scanning Mode Result

/// Výsledek skenování z libovolného adaptéru
struct ScanningModeResult {
    let meshData: [MeshData]
    let pointCloud: PointCloud?
    let metadata: [String: Any]
}

// MARK: - Scanning Mode Protocol

/// Protokol pro adaptéry skenovacích režimů (LiDAR, RoomPlan, ObjectCapture)
///
/// Každý skenovací režim implementuje tento protokol, aby poskytl jednotné
/// rozhraní pro spuštění, pozastavení a zastavení skenování a sběr výsledků.
@MainActor
protocol ScanningModeProtocol: AnyObject {
    /// Skenovací režim, který tento adaptér implementuje
    var mode: ScanMode { get }

    /// Zda je tento režim na aktuálním zařízení dostupný
    var isAvailable: Bool { get }

    /// Zda právě probíhá skenování
    var isScanning: Bool { get }

    /// Textový popis aktuálního stavu trackingu
    var trackingState: String { get }

    /// Publisher pro průběžně generovaná mesh data
    var meshDataPublisher: AnyPublisher<MeshData, Never> { get }

    /// Publisher pro postup skenování (0.0 - 1.0)
    var progressPublisher: AnyPublisher<Float, Never> { get }

    /// Spustí skenování
    func start() async throws

    /// Pozastaví skenování
    func pause()

    /// Obnoví pozastavené skenování
    func resume()

    /// Zastaví skenování
    func stop()

    /// Vrátí výsledky skenování
    func getResults() -> ScanningModeResult
}
