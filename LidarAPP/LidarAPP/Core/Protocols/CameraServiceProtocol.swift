import Foundation
import AVFoundation
import Combine

/// Protokol pro camera frame capture service
@MainActor
protocol CameraServiceProtocol: AnyObject {
    /// Zda je capture aktivní
    var isCapturing: Bool { get }

    /// Počet zachycených framů
    var capturedFrameCount: Int { get }

    /// Spusť zachytávání framů
    func startCapture()

    /// Zastav zachytávání
    func stopCapture()

    /// Získej aktuální texture frames (pro LRAW export)
    func getTextureFrames() -> [TextureFrame]

    /// Vymaž buffer
    func clearBuffer()
}

// MARK: - Placeholder (Sprint 0)

@MainActor
final class PlaceholderCameraService: CameraServiceProtocol {
    var isCapturing = false
    var capturedFrameCount = 0

    func startCapture() {
        debugLog("PlaceholderCameraService: startCapture not implemented", category: .logCategoryAR)
    }
    func stopCapture() {}
    func getTextureFrames() -> [TextureFrame] { [] }
    func clearBuffer() {}
}
