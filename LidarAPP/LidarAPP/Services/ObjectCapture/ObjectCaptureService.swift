import Foundation
import RealityKit
import Combine
import simd

// MARK: - Object Capture Service Protocol

protocol ObjectCaptureServiceProtocol {
    var captureStatus: AnyPublisher<ObjectCaptureStatus, Never> { get }
    var captureProgress: AnyPublisher<Float, Never> { get }
    var imageCount: AnyPublisher<Int, Never> { get }

    func startCapture() async throws
    func stopCapture() async -> ObjectCaptureResult?
    func cancelCapture()
}

// MARK: - Object Capture Status

enum ObjectCaptureStatus: Equatable {
    case idle
    case preparing
    case capturing
    case processing
    case completed(URL?)
    case failed(String)

    var displayName: String {
        switch self {
        case .idle: return "Připraveno"
        case .preparing: return "Příprava..."
        case .capturing: return "Skenování"
        case .processing: return "Zpracování..."
        case .completed: return "Dokončeno"
        case .failed: return "Chyba"
        }
    }

    static func == (lhs: ObjectCaptureStatus, rhs: ObjectCaptureStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.preparing, .preparing), (.capturing, .capturing), (.processing, .processing):
            return true
        case (.completed(let a), .completed(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Object Capture Result

struct ObjectCaptureResult {
    let modelURL: URL?
    let pointCloud: PointCloud?
    let meshData: MeshData?
    let imageCount: Int
    let boundingBox: (min: simd_float3, max: simd_float3)?
}

// MARK: - Object Capture Service

/// Service for capturing 3D objects on iOS.
/// Uses LiDAR + camera capture, then processes on backend with Gaussian Splatting.
/// Note: Apple's ObjectCaptureSession is macOS-only; this is our iOS implementation.
@MainActor
final class ObjectCaptureService: NSObject, ObjectCaptureServiceProtocol {

    static let shared = ObjectCaptureService()

    // MARK: - Properties

    private var capturedImages: [URL] = []
    private var outputURL: URL?

    private let statusSubject = CurrentValueSubject<ObjectCaptureStatus, Never>(.idle)
    private let progressSubject = PassthroughSubject<Float, Never>()
    private let imageCountSubject = CurrentValueSubject<Int, Never>(0)

    var captureStatus: AnyPublisher<ObjectCaptureStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    var captureProgress: AnyPublisher<Float, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    var imageCount: AnyPublisher<Int, Never> {
        imageCountSubject.eraseToAnyPublisher()
    }

    /// Object capture is supported on devices with LiDAR
    static var isSupported: Bool {
        return DeviceCapabilities.hasLiDAR
    }

    var currentStatus: ObjectCaptureStatus {
        statusSubject.value
    }

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Capture Control

    func startCapture() async throws {
        guard Self.isSupported || MockDataProvider.isMockModeEnabled else {
            throw ObjectCaptureError.notSupported
        }

        statusSubject.send(.preparing)
        capturedImages = []
        imageCountSubject.send(0)

        // Create output directory
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let captureDir = documentsDir.appendingPathComponent("ObjectCapture/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)

        outputURL = captureDir

        statusSubject.send(.capturing)
    }

    func stopCapture() async -> ObjectCaptureResult? {
        statusSubject.send(.processing)

        // Wait for any pending operations
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Create result
        let result = ObjectCaptureResult(
            modelURL: outputURL,
            pointCloud: nil,
            meshData: nil,
            imageCount: imageCountSubject.value,
            boundingBox: nil
        )

        statusSubject.send(.completed(outputURL))

        return result
    }

    func cancelCapture() {
        statusSubject.send(.idle)
        imageCountSubject.send(0)
    }

    /// Add a captured image to the session
    func addCapturedImage(at url: URL) {
        capturedImages.append(url)
        imageCountSubject.send(capturedImages.count)

        // Update progress (assuming ~50 images for good capture)
        let progress = min(Float(capturedImages.count) / 50.0, 0.95)
        progressSubject.send(progress)
    }

    // MARK: - Conversion

    func convertToScanSession() -> ScanSession {
        let session = ScanSession(name: "Object Scan")

        // For mock mode, generate sample point cloud
        if MockDataProvider.isMockModeEnabled {
            session.pointCloud = MockDataProvider.shared.generateObjectPointCloud()
        }

        return session
    }
}

// MARK: - Errors

enum ObjectCaptureError: LocalizedError {
    case notSupported
    case sessionCreationFailed
    case captureFailed
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Object Capture vyžaduje zařízení s LiDAR senzorem."
        case .sessionCreationFailed:
            return "Nepodařilo se vytvořit capture session"
        case .captureFailed:
            return "Skenování objektu selhalo"
        case .processingFailed(let message):
            return "Zpracování selhalo: \(message)"
        }
    }
}
