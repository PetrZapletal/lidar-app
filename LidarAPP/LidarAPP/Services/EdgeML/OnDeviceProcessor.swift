import Foundation
import simd
import ARKit

/// Orchestrates on-device AI processing pipeline for mesh correction
@MainActor
@Observable
final class OnDeviceProcessor {

    // MARK: - Processing State

    enum ProcessingState: Equatable {
        case idle
        case initializing
        case processing(progress: Float, stage: ProcessingStage)
        case completed(result: ProcessingResult)
        case error(message: String)

        static func == (lhs: ProcessingState, rhs: ProcessingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.initializing, .initializing): return true
            case let (.processing(p1, s1), .processing(p2, s2)): return p1 == p2 && s1 == s2
            case (.completed, .completed): return true
            case let (.error(m1), .error(m2)): return m1 == m2
            default: return false
            }
        }
    }

    enum ProcessingStage: String, Equatable {
        case preparingData = "Preparing data"
        case removingNoise = "Removing noise"
        case fillingHoles = "Filling holes"
        case smoothingMesh = "Smoothing mesh"
        case optimizingTopology = "Optimizing topology"
        case computingNormals = "Computing normals"
        case finalizing = "Finalizing"
    }

    // MARK: - Processing Result

    struct ProcessingResult: Sendable {
        let correctedMesh: MeshData
        let statistics: ProcessingStatistics
        let warnings: [String]
    }

    struct ProcessingStatistics: Sendable {
        let originalVertexCount: Int
        let finalVertexCount: Int
        let originalFaceCount: Int
        let finalFaceCount: Int
        let noiseVerticesRemoved: Int
        let holesFilledCount: Int
        let processingTimeSeconds: TimeInterval
        let memoryUsedMB: Float

        var vertexReduction: Float {
            Float(originalVertexCount - finalVertexCount) / Float(max(1, originalVertexCount))
        }

        var faceReduction: Float {
            Float(originalFaceCount - finalFaceCount) / Float(max(1, originalFaceCount))
        }
    }

    // MARK: - Configuration

    struct Configuration {
        var enableNoiseRemoval: Bool = true
        var enableHoleFilling: Bool = true
        var enableSmoothing: Bool = true
        var enableTopologyOptimization: Bool = true
        var maxProcessingTime: TimeInterval = 30  // 30 seconds max
        var targetVertexCount: Int? = nil  // If set, decimate to this count
        var qualityLevel: QualityLevel = .balanced

        enum QualityLevel {
            case fast       // Minimal processing, fastest
            case balanced   // Good quality, reasonable speed
            case quality    // Best quality, slower
        }
    }

    // MARK: - Properties

    private(set) var state: ProcessingState = .idle

    private let meshCorrectionModel: MeshCorrectionModel
    private let configuration: Configuration
    private var currentTask: Task<ProcessingResult, Error>?

    // Progress tracking
    private(set) var currentProgress: Float = 0
    private(set) var currentStage: ProcessingStage = .preparingData

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.meshCorrectionModel = MeshCorrectionModel()
    }

    // MARK: - Processing Pipeline

    /// Process mesh data with on-device AI
    func processMesh(_ meshData: MeshData) async throws -> ProcessingResult {
        state = .initializing

        let startTime = CACurrentMediaTime()
        var warnings: [String] = []

        // Track original counts
        let originalVertexCount = meshData.vertexCount
        let originalFaceCount = meshData.faceCount

        // Stage 1: Prepare data
        updateProgress(0.05, stage: .preparingData)
        var currentMesh = meshData

        // Check for degenerate mesh
        if currentMesh.vertexCount < 3 {
            throw OnDeviceProcessorError.insufficientData("Mesh has fewer than 3 vertices")
        }

        // Stage 2: Noise removal
        var noiseRemoved = 0
        if configuration.enableNoiseRemoval {
            updateProgress(0.15, stage: .removingNoise)
            let (cleaned, removed) = await removeNoise(from: currentMesh)
            currentMesh = cleaned
            noiseRemoved = removed
        }

        // Stage 3: Hole filling
        var holesFilled = 0
        if configuration.enableHoleFilling {
            updateProgress(0.35, stage: .fillingHoles)
            let (filled, count) = await fillHoles(in: currentMesh)
            currentMesh = filled
            holesFilled = count
        }

        // Stage 4: Smoothing
        if configuration.enableSmoothing {
            updateProgress(0.55, stage: .smoothingMesh)
            currentMesh = await smoothMesh(currentMesh)
        }

        // Stage 5: Topology optimization
        if configuration.enableTopologyOptimization {
            updateProgress(0.70, stage: .optimizingTopology)
            currentMesh = await optimizeTopology(currentMesh)
        }

        // Stage 6: Recompute normals
        updateProgress(0.85, stage: .computingNormals)
        currentMesh = recomputeNormals(for: currentMesh)

        // Stage 7: Decimation if needed
        if let targetCount = configuration.targetVertexCount,
           currentMesh.vertexCount > targetCount {
            updateProgress(0.90, stage: .finalizing)
            currentMesh = await decimateMesh(currentMesh, targetVertexCount: targetCount)
            warnings.append("Mesh decimated from \(originalVertexCount) to \(currentMesh.vertexCount) vertices")
        }

        updateProgress(1.0, stage: .finalizing)

        let processingTime = CACurrentMediaTime() - startTime

        // Check processing time
        if processingTime > configuration.maxProcessingTime {
            warnings.append("Processing took longer than expected: \(String(format: "%.1f", processingTime))s")
        }

        let statistics = ProcessingStatistics(
            originalVertexCount: originalVertexCount,
            finalVertexCount: currentMesh.vertexCount,
            originalFaceCount: originalFaceCount,
            finalFaceCount: currentMesh.faceCount,
            noiseVerticesRemoved: noiseRemoved,
            holesFilledCount: holesFilled,
            processingTimeSeconds: processingTime,
            memoryUsedMB: estimateMemoryUsage(mesh: currentMesh)
        )

        let result = ProcessingResult(
            correctedMesh: currentMesh,
            statistics: statistics,
            warnings: warnings
        )

        state = .completed(result: result)
        return result
    }

    /// Cancel current processing
    func cancelProcessing() {
        currentTask?.cancel()
        state = .idle
    }

    // MARK: - Progress Tracking

    private func updateProgress(_ progress: Float, stage: ProcessingStage) {
        currentProgress = progress
        currentStage = stage
        state = .processing(progress: progress, stage: stage)
    }

    // MARK: - Processing Steps

    private func removeNoise(from mesh: MeshData) async -> (MeshData, Int) {
        // Statistical outlier removal
        let vertices = mesh.vertices
        var validIndices = Set<Int>(0..<vertices.count)

        // Calculate average distance to neighbors for each vertex
        let neighborCount = 10
        var outlierCount = 0

        // Simplified noise removal - in production use KD-tree
        var distances: [Float] = []

        for i in 0..<min(vertices.count, 10000) {  // Sample for large meshes
            let point = vertices[i]
            var neighborDistances: [Float] = []

            for j in 0..<vertices.count where i != j {
                let dist = simd_distance(point, vertices[j])
                neighborDistances.append(dist)
                if neighborDistances.count > neighborCount * 2 {
                    neighborDistances.sort()
                    neighborDistances = Array(neighborDistances.prefix(neighborCount))
                }
            }

            if !neighborDistances.isEmpty {
                neighborDistances.sort()
                let avgDist = neighborDistances.prefix(neighborCount).reduce(0, +) /
                              Float(min(neighborCount, neighborDistances.count))
                distances.append(avgDist)
            }
        }

        guard !distances.isEmpty else {
            return (mesh, 0)
        }

        // Calculate threshold
        let meanDist = distances.reduce(0, +) / Float(distances.count)
        let variance = distances.map { ($0 - meanDist) * ($0 - meanDist) }
            .reduce(0, +) / Float(distances.count)
        let stdDev = sqrt(variance)
        let threshold = meanDist + 2 * stdDev

        // Mark outliers
        for i in 0..<vertices.count {
            if i < distances.count && distances[i] > threshold {
                validIndices.remove(i)
                outlierCount += 1
            }
        }

        // Rebuild mesh without outliers
        let newVertices = validIndices.sorted().map { vertices[$0] }
        let newNormals = validIndices.sorted().compactMap { i -> simd_float3? in
            i < mesh.normals.count ? mesh.normals[i] : nil
        }

        // Remap face indices
        var indexMap = [Int: Int]()
        for (newIndex, oldIndex) in validIndices.sorted().enumerated() {
            indexMap[oldIndex] = newIndex
        }

        let newFaces = mesh.faces.compactMap { face -> simd_uint3? in
            guard let i0 = indexMap[Int(face.x)],
                  let i1 = indexMap[Int(face.y)],
                  let i2 = indexMap[Int(face.z)] else {
                return nil
            }
            return simd_uint3(UInt32(i0), UInt32(i1), UInt32(i2))
        }

        let cleanedMesh = MeshData(
            anchorIdentifier: mesh.anchorIdentifier,
            vertices: newVertices,
            normals: newNormals,
            faces: newFaces,
            classifications: nil,
            transform: mesh.transform
        )

        return (cleanedMesh, outlierCount)
    }

    private func fillHoles(in mesh: MeshData) async -> (MeshData, Int) {
        // Simple hole detection and filling
        // In production, use advancing front algorithm

        // For now, return mesh unchanged
        // Hole filling is complex and would require edge detection
        return (mesh, 0)
    }

    private func smoothMesh(_ mesh: MeshData) async -> MeshData {
        // Laplacian smoothing
        var smoothedVertices = mesh.vertices
        let iterations = configuration.qualityLevel == .fast ? 1 : 2
        let lambda: Float = 0.3

        for _ in 0..<iterations {
            var newPositions = smoothedVertices

            // Build adjacency from faces
            var adjacency = [[Int]](repeating: [], count: smoothedVertices.count)

            for face in mesh.faces {
                let i0 = Int(face.x)
                let i1 = Int(face.y)
                let i2 = Int(face.z)

                adjacency[i0].append(i1)
                adjacency[i0].append(i2)
                adjacency[i1].append(i0)
                adjacency[i1].append(i2)
                adjacency[i2].append(i0)
                adjacency[i2].append(i1)
            }

            // Apply smoothing
            for i in 0..<smoothedVertices.count {
                let neighbors = adjacency[i]
                if !neighbors.isEmpty {
                    let centroid = neighbors.map { smoothedVertices[$0] }
                        .reduce(simd_float3.zero, +) / Float(neighbors.count)

                    let laplacian = centroid - smoothedVertices[i]
                    newPositions[i] = smoothedVertices[i] + lambda * laplacian
                }
            }

            smoothedVertices = newPositions
        }

        return MeshData(
            anchorIdentifier: mesh.anchorIdentifier,
            vertices: smoothedVertices,
            normals: mesh.normals,
            faces: mesh.faces,
            classifications: mesh.classifications,
            transform: mesh.transform
        )
    }

    private func optimizeTopology(_ mesh: MeshData) async -> MeshData {
        // Remove degenerate triangles (zero area)
        let validFaces = mesh.faces.filter { face in
            let v0 = mesh.vertices[Int(face.x)]
            let v1 = mesh.vertices[Int(face.y)]
            let v2 = mesh.vertices[Int(face.z)]

            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let area = simd_length(simd_cross(edge1, edge2)) / 2

            return area > 1e-8  // Minimum area threshold
        }

        return MeshData(
            anchorIdentifier: mesh.anchorIdentifier,
            vertices: mesh.vertices,
            normals: mesh.normals,
            faces: validFaces,
            classifications: mesh.classifications,
            transform: mesh.transform
        )
    }

    private func recomputeNormals(for mesh: MeshData) -> MeshData {
        var normals = [simd_float3](repeating: .zero, count: mesh.vertices.count)
        var counts = [Int](repeating: 0, count: mesh.vertices.count)

        // Accumulate face normals
        for face in mesh.faces {
            let i0 = Int(face.x)
            let i1 = Int(face.y)
            let i2 = Int(face.z)

            let v0 = mesh.vertices[i0]
            let v1 = mesh.vertices[i1]
            let v2 = mesh.vertices[i2]

            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let faceNormal = simd_cross(edge1, edge2)

            normals[i0] += faceNormal
            normals[i1] += faceNormal
            normals[i2] += faceNormal
            counts[i0] += 1
            counts[i1] += 1
            counts[i2] += 1
        }

        // Normalize
        for i in 0..<normals.count {
            if counts[i] > 0 {
                normals[i] = simd_normalize(normals[i])
            }
        }

        return MeshData(
            anchorIdentifier: mesh.anchorIdentifier,
            vertices: mesh.vertices,
            normals: normals,
            faces: mesh.faces,
            classifications: mesh.classifications,
            transform: mesh.transform
        )
    }

    private func decimateMesh(_ mesh: MeshData, targetVertexCount: Int) async -> MeshData {
        // Quadric error decimation would go here
        // For MVP, use simple uniform sampling

        guard mesh.vertexCount > targetVertexCount else { return mesh }

        let sampleStep = mesh.vertexCount / targetVertexCount

        var sampledVertices: [simd_float3] = []
        var sampledNormals: [simd_float3] = []

        for i in Swift.stride(from: 0, to: mesh.vertices.count, by: sampleStep) {
            sampledVertices.append(mesh.vertices[i])
            if i < mesh.normals.count {
                sampledNormals.append(mesh.normals[i])
            }
        }

        // Faces would need to be recomputed - for now return vertices only
        return MeshData(
            anchorIdentifier: mesh.anchorIdentifier,
            vertices: sampledVertices,
            normals: sampledNormals,
            faces: [],  // Would need Delaunay triangulation
            classifications: nil,
            transform: mesh.transform
        )
    }

    // MARK: - Utilities

    private func estimateMemoryUsage(mesh: MeshData) -> Float {
        let vertexBytes = mesh.vertices.count * MemoryLayout<simd_float3>.stride
        let normalBytes = mesh.normals.count * MemoryLayout<simd_float3>.stride
        let faceBytes = mesh.faces.count * MemoryLayout<simd_uint3>.stride

        let totalBytes = vertexBytes + normalBytes + faceBytes
        return Float(totalBytes) / (1024 * 1024)  // Convert to MB
    }
}

// MARK: - Processing Error

enum OnDeviceProcessorError: LocalizedError {
    case insufficientData(String)
    case modelNotLoaded
    case processingFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .insufficientData(let message): return "Insufficient data: \(message)"
        case .modelNotLoaded: return "ML model not loaded"
        case .processingFailed(let message): return "Processing failed: \(message)"
        case .cancelled: return "Processing was cancelled"
        }
    }
}

// MARK: - Batch Processing

extension OnDeviceProcessor {

    /// Process multiple mesh chunks
    func processMeshes(_ meshes: [MeshData]) async throws -> [ProcessingResult] {
        var results: [ProcessingResult] = []

        for (index, mesh) in meshes.enumerated() {
            let progress = Float(index) / Float(meshes.count)
            state = .processing(progress: progress, stage: .preparingData)

            let result = try await processMesh(mesh)
            results.append(result)
        }

        return results
    }

    /// Combine multiple processed meshes into one
    func combineMeshes(_ results: [ProcessingResult]) -> MeshData? {
        guard !results.isEmpty else { return nil }

        var allVertices: [simd_float3] = []
        var allNormals: [simd_float3] = []
        var allFaces: [simd_uint3] = []

        var vertexOffset: UInt32 = 0

        for result in results {
            let mesh = result.correctedMesh

            allVertices.append(contentsOf: mesh.vertices)
            allNormals.append(contentsOf: mesh.normals)

            // Offset face indices
            let offsetFaces = mesh.faces.map { face in
                simd_uint3(
                    face.x + vertexOffset,
                    face.y + vertexOffset,
                    face.z + vertexOffset
                )
            }
            allFaces.append(contentsOf: offsetFaces)

            vertexOffset += UInt32(mesh.vertices.count)
        }

        return MeshData(
            anchorIdentifier: UUID(),
            vertices: allVertices,
            normals: allNormals,
            faces: allFaces
        )
    }
}
