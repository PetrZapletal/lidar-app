import Foundation
import ARKit
import Combine

/// Protokol pro ARKit scanning service
@MainActor
protocol ARSessionServiceProtocol: AnyObject {
    /// Aktuální stav skenování
    var isScanning: Bool { get }

    /// Tracking stav AR session
    var trackingState: ARCamera.TrackingState? { get }

    /// Počet mesh anchorů
    var meshAnchorCount: Int { get }

    /// Celkový počet vertexů
    var totalVertexCount: Int { get }

    /// Celkový počet faces
    var totalFaceCount: Int { get }

    /// Publisher pro nové mesh anchory
    var meshAnchorsPublisher: AnyPublisher<[ARMeshAnchor], Never> { get }

    /// Spusť AR session s daným skenovacím režimem
    func startSession(mode: ScanMode) throws

    /// Pozastav session
    func pauseSession()

    /// Obnov session
    func resumeSession()

    /// Zastav session
    func stopSession()

    /// Získej aktuální mesh anchory
    func getMeshAnchors() -> [ARMeshAnchor]

    /// Získej aktuální AR frame
    func getCurrentFrame() -> ARFrame?
}

// MARK: - Placeholder (Sprint 0)

@MainActor
final class PlaceholderARSessionService: ARSessionServiceProtocol {
    var isScanning = false
    var trackingState: ARCamera.TrackingState? = nil
    var meshAnchorCount = 0
    var totalVertexCount = 0
    var totalFaceCount = 0
    var meshAnchorsPublisher: AnyPublisher<[ARMeshAnchor], Never> {
        Empty().eraseToAnyPublisher()
    }

    func startSession(mode: ScanMode) throws {
        debugLog("PlaceholderARSessionService: startSession not implemented", category: .logCategoryAR)
    }
    func pauseSession() {}
    func resumeSession() {}
    func stopSession() {}
    func getMeshAnchors() -> [ARMeshAnchor] { [] }
    func getCurrentFrame() -> ARFrame? { nil }
}
