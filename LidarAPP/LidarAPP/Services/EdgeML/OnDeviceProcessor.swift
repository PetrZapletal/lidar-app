import Foundation
import simd
import CoreImage
import UIKit
import QuartzCore

/// Orchestrates the on-device ML processing pipeline.
///
/// Coordinates depth model inference, depth fusion, and mesh correction
/// stages into a unified processing pipeline. Reports progress through
/// observable state updates.
@MainActor
@Observable
final class OnDeviceProcessor {

    // MARK: - Types

    enum ProcessingState: Equatable {
        case idle
        case processing(progress: Float, stage: String)
        case completed
        case failed(String)

        static func == (lhs: ProcessingState, rhs: ProcessingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.completed, .completed):
                return true
            case (.processing(let p1, let s1), .processing(let p2, let s2)):
                return p1 == p2 && s1 == s2
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Properties

    private(set) var state: ProcessingState = .idle

    let depthModel: DepthAnythingModel
    let meshCorrection: MeshCorrectionModel
    let depthFusion: DepthFusionProcessor

    /// Whether the processor is currently running
    var isProcessing: Bool {
        if case .processing = state { return true }
        return false
    }

    /// Whether the depth model is loaded and ready
    var isModelReady: Bool { depthModel.isReady }

    /// Tracks whether initialization has been performed
    private var isInitialized = false

    // MARK: - Initialization

    init() {
        self.depthModel = DepthAnythingModel()
        self.meshCorrection = MeshCorrectionModel()
        self.depthFusion = DepthFusionProcessor()
        debugLog("OnDeviceProcessor initialized", category: .logCategoryML)
    }

    /// Convenience initializer for dependency injection.
    init(
        depthModel: DepthAnythingModel,
        meshCorrection: MeshCorrectionModel,
        depthFusion: DepthFusionProcessor
    ) {
        self.depthModel = depthModel
        self.meshCorrection = meshCorrection
        self.depthFusion = depthFusion
        debugLog("OnDeviceProcessor initialized with injected dependencies", category: .logCategoryML)
    }

    // MARK: - Lifecycle

    /// Load all ML models and prepare for processing.
    func initialize() async {
        guard !isInitialized else {
            debugLog("OnDeviceProcessor already initialized", category: .logCategoryML)
            return
        }

        debugLog("Initializing on-device processing pipeline...", category: .logCategoryML)
        state = .processing(progress: 0, stage: "Loading ML models")

        await depthModel.loadModel()

        if depthModel.isReady {
            isInitialized = true
            state = .idle
            infoLog("On-device processing pipeline ready", category: .logCategoryML)
        } else {
            state = .failed("Failed to load ML models")
            errorLog("On-device processing pipeline initialization failed", category: .logCategoryML)
        }
    }

    /// Release all models and free memory.
    func cleanup() {
        depthModel.unloadModel()
        isInitialized = false
        state = .idle
        debugLog("OnDeviceProcessor cleaned up", category: .logCategoryML)
    }

    // MARK: - Scan Processing

    /// Process a complete scan session with ML enhancement.
    ///
    /// Runs the full pipeline: depth enhancement on captured frames,
    /// depth fusion with LiDAR data, and mesh correction on the
    /// resulting geometry. Reports progress at each stage.
    ///
    /// - Parameter session: The scan session to process.
    /// - Returns: A `ProcessedScanResult` with enhanced data.
    /// - Throws: `EdgeMLError` if processing fails.
    func processScan(session: ScanSession) async throws -> ProcessedScanResult {
        let startTime = CACurrentMediaTime()
        var stages: [ProcessingStage] = []

        if !isInitialized {
            debugLog("Auto-initializing processor before scan processing", category: .logCategoryML)
            await initialize()
            guard isInitialized else {
                throw EdgeMLError.modelNotLoaded
            }
        }

        debugLog("Starting scan processing pipeline", category: .logCategoryML)
        state = .processing(progress: 0, stage: "Preparing scan data")

        // Validate that we have data to process
        let meshes = Array(session.combinedMesh.meshes.values)
        guard !meshes.isEmpty else {
            throw EdgeMLError.insufficientData
        }

        let textureFrames = session.textureFrames
        let depthFrames = session.depthFrames

        // Stage 1: Enhance depth maps from texture frames
        let stageOneStart = CACurrentMediaTime()
        state = .processing(progress: 0.1, stage: "Enhancing depth maps")

        var enhancedDepthFrames: [(depthValues: [Float], frame: TextureFrame)] = []

        if depthModel.isReady && !textureFrames.isEmpty {
            let framesToProcess = min(textureFrames.count, 10) // Limit frames for performance
            let frameStep = max(1, textureFrames.count / framesToProcess)

            for (index, frameIndex) in stride(from: 0, to: textureFrames.count, by: frameStep).enumerated() {
                let frame = textureFrames[frameIndex]

                do {
                    let enhancedDepth = try await enhanceDepthFromFrame(frame)
                    enhancedDepthFrames.append((depthValues: enhancedDepth, frame: frame))

                    let progress = 0.1 + 0.3 * Float(index + 1) / Float(framesToProcess)
                    state = .processing(progress: progress, stage: "Enhancing depth \(index + 1)/\(framesToProcess)")
                } catch {
                    warningLog(
                        "Failed to enhance depth for frame \(frame.id): \(error.localizedDescription)",
                        category: .logCategoryML
                    )
                }

                // Check for cancellation
                try Task.checkCancellation()
            }
        }

        stages.append(ProcessingStage(
            name: "Depth Enhancement",
            duration: CACurrentMediaTime() - stageOneStart,
            success: !enhancedDepthFrames.isEmpty || textureFrames.isEmpty
        ))

        // Stage 2: Fuse depth maps with LiDAR data
        let stageTwoStart = CACurrentMediaTime()
        state = .processing(progress: 0.4, stage: "Fusing depth data")

        var enhancedPointCloud: PointCloud?

        if !enhancedDepthFrames.isEmpty && !depthFrames.isEmpty {
            enhancedPointCloud = fuseDepthData(
                enhancedFrames: enhancedDepthFrames,
                lidarFrames: depthFrames
            )
        }

        stages.append(ProcessingStage(
            name: "Depth Fusion",
            duration: CACurrentMediaTime() - stageTwoStart,
            success: enhancedPointCloud != nil || enhancedDepthFrames.isEmpty
        ))

        try Task.checkCancellation()

        // Stage 3: Correct mesh geometry
        let stageThreeStart = CACurrentMediaTime()
        state = .processing(progress: 0.7, stage: "Correcting mesh geometry")

        var enhancedMeshes: [MeshData] = []

        for (index, mesh) in meshes.enumerated() {
            let corrected = meshCorrection.correctMesh(meshData: mesh)
            enhancedMeshes.append(corrected)

            let progress = 0.7 + 0.25 * Float(index + 1) / Float(meshes.count)
            state = .processing(progress: progress, stage: "Correcting mesh \(index + 1)/\(meshes.count)")

            try Task.checkCancellation()
        }

        stages.append(ProcessingStage(
            name: "Mesh Correction",
            duration: CACurrentMediaTime() - stageThreeStart,
            success: true
        ))

        // Stage 4: Refine meshes with enhanced depth (if available)
        let stageFourStart = CACurrentMediaTime()
        state = .processing(progress: 0.95, stage: "Refining meshes with enhanced depth")

        if !enhancedDepthFrames.isEmpty {
            enhancedMeshes = refineMeshesWithDepth(
                meshes: enhancedMeshes,
                enhancedFrames: enhancedDepthFrames
            )
        }

        stages.append(ProcessingStage(
            name: "Mesh Refinement",
            duration: CACurrentMediaTime() - stageFourStart,
            success: true
        ))

        let totalDuration = CACurrentMediaTime() - startTime
        state = .completed

        let result = ProcessedScanResult(
            enhancedMeshData: enhancedMeshes,
            enhancedPointCloud: enhancedPointCloud,
            processingTime: totalDuration,
            stages: stages
        )

        infoLog(
            "Scan processing complete in \(String(format: "%.2f", totalDuration))s: \(enhancedMeshes.count) meshes, \(stages.count) stages",
            category: .logCategoryML
        )

        return result
    }

    // MARK: - Individual Operations

    /// Enhance a depth map from a single image using DepthAnything.
    ///
    /// - Parameter image: The input RGB image.
    /// - Returns: An array of depth float values.
    /// - Throws: `EdgeMLError` if prediction fails.
    func enhanceDepthMap(image: CGImage) async throws -> [Float] {
        guard depthModel.isReady else {
            throw EdgeMLError.modelNotLoaded
        }

        debugLog("Enhancing depth map from \(image.width)x\(image.height) image", category: .logCategoryML)

        let depthBuffer = try await depthModel.predictDepth(from: image)
        let depthValues = depthModel.depthMapToFloatArray(depthBuffer)

        debugLog("Depth enhancement produced \(depthValues.count) values", category: .logCategoryML)
        return depthValues
    }

    /// Correct mesh geometry using the mesh correction pipeline.
    ///
    /// - Parameter meshData: The input mesh to correct.
    /// - Returns: A corrected MeshData.
    func correctMesh(meshData: MeshData) -> MeshData {
        return meshCorrection.correctMesh(meshData: meshData)
    }

    // MARK: - Private Helpers

    /// Enhance depth from a texture frame by converting image data and running ML inference.
    private func enhanceDepthFromFrame(_ frame: TextureFrame) async throws -> [Float] {
        guard let uiImage = UIImage(data: frame.imageData),
              let cgImage = uiImage.cgImage else {
            throw EdgeMLError.invalidInput("Failed to create image from texture frame data")
        }

        return try await enhanceDepthMap(image: cgImage)
    }

    /// Fuse enhanced ML depth frames with LiDAR depth frames.
    private func fuseDepthData(
        enhancedFrames: [(depthValues: [Float], frame: TextureFrame)],
        lidarFrames: [DepthFrame]
    ) -> PointCloud? {
        guard let firstEnhanced = enhancedFrames.first,
              let matchingLidar = findClosestLidarFrame(
                  timestamp: firstEnhanced.frame.timestamp,
                  lidarFrames: lidarFrames
              ) else {
            debugLog("No matching LiDAR frame for fusion", category: .logCategoryProcessing)
            return nil
        }

        // Convert LiDAR confidence from UInt8 to Float [0, 1]
        let confidenceMap: [Float]? = matchingLidar.confidenceValues?.map { Float($0) / 2.0 }

        let mlDepth = firstEnhanced.depthValues
        let lidarDepth = matchingLidar.depthValues

        // Resize ML depth to match LiDAR dimensions if needed
        let resizedMLDepth: [Float]
        let mlPixelCount = Int(firstEnhanced.frame.resolution.width) * Int(firstEnhanced.frame.resolution.height)

        if mlDepth.count != lidarDepth.count && mlDepth.count == mlPixelCount {
            resizedMLDepth = resizeDepthMap(
                source: mlDepth,
                sourceWidth: Int(firstEnhanced.frame.resolution.width),
                sourceHeight: Int(firstEnhanced.frame.resolution.height),
                targetWidth: matchingLidar.width,
                targetHeight: matchingLidar.height
            )
        } else {
            resizedMLDepth = mlDepth
        }

        let fusedDepth = depthFusion.fuseDepthMaps(
            lidarDepth: lidarDepth,
            mlDepth: resizedMLDepth,
            width: matchingLidar.width,
            height: matchingLidar.height,
            confidenceMap: confidenceMap
        )

        return depthFusion.depthToPointCloud(
            depth: fusedDepth,
            width: matchingLidar.width,
            height: matchingLidar.height,
            intrinsics: matchingLidar.cameraIntrinsics,
            cameraTransform: matchingLidar.cameraTransform
        )
    }

    /// Find the LiDAR frame closest in time to the given timestamp.
    private func findClosestLidarFrame(
        timestamp: TimeInterval,
        lidarFrames: [DepthFrame]
    ) -> DepthFrame? {
        guard !lidarFrames.isEmpty else { return nil }

        var closest: DepthFrame?
        var minDelta: TimeInterval = .infinity

        for frame in lidarFrames {
            let delta = abs(frame.timestamp - timestamp)
            if delta < minDelta {
                minDelta = delta
                closest = frame
            }
        }

        return closest
    }

    /// Refine mesh data using enhanced depth frames.
    private func refineMeshesWithDepth(
        meshes: [MeshData],
        enhancedFrames: [(depthValues: [Float], frame: TextureFrame)]
    ) -> [MeshData] {
        guard let bestFrame = enhancedFrames.first else { return meshes }

        let width = Int(bestFrame.frame.resolution.width)
        let height = Int(bestFrame.frame.resolution.height)

        guard bestFrame.depthValues.count == width * height else {
            warningLog(
                "Depth values count \(bestFrame.depthValues.count) does not match \(width)x\(height)",
                category: .logCategoryProcessing
            )
            return meshes
        }

        return meshes.map { mesh in
            depthFusion.refineMesh(
                originalMesh: mesh,
                enhancedDepth: bestFrame.depthValues,
                width: width,
                height: height,
                intrinsics: bestFrame.frame.intrinsics,
                cameraTransform: bestFrame.frame.cameraTransform
            )
        }
    }

    /// Resize a depth map using bilinear interpolation.
    private func resizeDepthMap(
        source: [Float],
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) -> [Float] {
        let targetCount = targetWidth * targetHeight
        var result = [Float](repeating: 0, count: targetCount)

        let xScale = Float(sourceWidth) / Float(targetWidth)
        let yScale = Float(sourceHeight) / Float(targetHeight)

        for ty in 0..<targetHeight {
            for tx in 0..<targetWidth {
                let sx = Float(tx) * xScale
                let sy = Float(ty) * yScale

                let x0 = min(Int(sx), sourceWidth - 1)
                let y0 = min(Int(sy), sourceHeight - 1)
                let x1 = min(x0 + 1, sourceWidth - 1)
                let y1 = min(y0 + 1, sourceHeight - 1)

                let xFrac = sx - Float(x0)
                let yFrac = sy - Float(y0)

                // Bilinear interpolation
                let topLeft = source[y0 * sourceWidth + x0]
                let topRight = source[y0 * sourceWidth + x1]
                let bottomLeft = source[y1 * sourceWidth + x0]
                let bottomRight = source[y1 * sourceWidth + x1]

                let top = topLeft * (1 - xFrac) + topRight * xFrac
                let bottom = bottomLeft * (1 - xFrac) + bottomRight * xFrac

                result[ty * targetWidth + tx] = top * (1 - yFrac) + bottom * yFrac
            }
        }

        return result
    }
}

// MARK: - Processing Result Types

/// Result of a full scan processing pipeline run.
struct ProcessedScanResult {
    let enhancedMeshData: [MeshData]
    let enhancedPointCloud: PointCloud?
    let processingTime: TimeInterval
    let stages: [ProcessingStage]

    /// Total number of vertices across all enhanced meshes
    var totalVertexCount: Int {
        enhancedMeshData.reduce(0) { $0 + $1.vertexCount }
    }

    /// Total number of faces across all enhanced meshes
    var totalFaceCount: Int {
        enhancedMeshData.reduce(0) { $0 + $1.faceCount }
    }

    /// Human-readable summary of the processing result
    var summary: String {
        let stagesSummary = stages.map { stage in
            "\(stage.name): \(String(format: "%.2f", stage.duration))s [\(stage.success ? "OK" : "FAIL")]"
        }.joined(separator: ", ")

        return "Processed \(enhancedMeshData.count) meshes (\(totalVertexCount) vertices, \(totalFaceCount) faces) in \(String(format: "%.2f", processingTime))s. Stages: \(stagesSummary)"
    }
}

/// Represents a single stage in the processing pipeline.
struct ProcessingStage {
    let name: String
    let duration: TimeInterval
    let success: Bool
}
