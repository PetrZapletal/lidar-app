import Foundation
import CoreML
import simd
import Accelerate
import Combine

/// AI-powered 3D Geometry Generation Service
/// Combines on-device lightweight models with cloud heavy processing
/// for intelligent geometry completion and enhancement
@MainActor
final class AIGeometryGenerationService: ObservableObject {

    // MARK: - Types

    /// Processing mode
    enum ProcessingMode {
        case edgeOnly       // Fast, on-device only
        case cloudOnly      // Full quality, requires network
        case hybrid         // Edge preprocessing + cloud refinement
    }

    /// Generation result
    struct GenerationResult {
        let originalMesh: MeshData
        let enhancedMesh: MeshData
        let completedRegions: [CompletedRegion]
        let confidence: Float
        let processingTime: TimeInterval

        struct CompletedRegion {
            let bounds: BoundingBox
            let type: RegionType
            let vertexCount: Int

            enum RegionType: String {
                case hole           // Filled hole
                case extension_     // Extended geometry
                case detail         // Added detail
                case smoothed       // Smoothed area
            }
        }
    }

    /// Neural implicit representation for a scene
    struct NeuralSceneRepresentation {
        let featureGrid: [Float]    // 3D feature volume
        let resolution: simd_int3
        let boundingBox: BoundingBox
        let density: [Float]        // Occupancy/density field
        let sdfValues: [Float]      // Signed distance field
    }

    /// Generation options
    struct GenerationOptions {
        var mode: ProcessingMode = .hybrid
        var completionLevel: CompletionLevel = .medium
        var preserveDetails: Bool = true
        var generateTextures: Bool = false
        var targetTriangleCount: Int? = nil
        var semanticAwareness: Bool = true

        enum CompletionLevel: Float, CaseIterable {
            case minimal = 0.3
            case medium = 0.6
            case aggressive = 0.9

            var description: String {
                switch self {
                case .minimal: return "Minimální - pouze malé díry"
                case .medium: return "Střední - díry a částečně chybějící oblasti"
                case .aggressive: return "Agresivní - kompletní dogenerování"
                }
            }
        }
    }

    // MARK: - Published Properties

    @Published var isProcessing = false
    @Published var processingStage: ProcessingStage = .idle
    @Published var progress: Float = 0
    @Published var currentResult: GenerationResult?

    enum ProcessingStage: String {
        case idle = "Připraveno"
        case analyzing = "Analyzuji geometrii..."
        case detectingHoles = "Detekuji díry..."
        case generatingFeatures = "Generuji features..."
        case neuralInference = "Neuronová inference..."
        case extractingMesh = "Extrakce mesh..."
        case refining = "Zjemňuji detaily..."
        case uploading = "Nahrávám do cloudu..."
        case cloudProcessing = "Cloud AI zpracování..."
        case downloading = "Stahuji výsledek..."
        case complete = "Dokončeno"
        case failed = "Chyba"
    }

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // Edge ML models (would be loaded from CoreML)
    private var depthCompletionModel: MLModel?
    private var geometryPriorModel: MLModel?

    // Neural field parameters
    private let featureGridResolution: Int = 64
    private let marchingCubesResolution: Int = 128

    // MARK: - Initialization

    init() {
        loadEdgeModels()
    }

    private func loadEdgeModels() {
        // Load CoreML models for on-device processing
        // In production, these would be actual trained models

        // DepthCompletion.mlmodel - fills missing depth values
        // GeometryPrior.mlmodel - understands room/object shapes
    }

    // MARK: - Main API

    /// Generate enhanced 3D geometry from scan data
    func generateGeometry(
        from session: ScanSession,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> GenerationResult {

        isProcessing = true
        let startTime = Date()

        defer {
            isProcessing = false
        }

        // Get combined mesh
        guard let inputMesh = session.combinedMesh.asSingleMesh() else {
            throw AIGeometryError.noInputData
        }

        switch options.mode {
        case .edgeOnly:
            return try await processOnDevice(mesh: inputMesh, session: session, options: options, startTime: startTime)

        case .cloudOnly:
            return try await processInCloud(mesh: inputMesh, session: session, options: options, startTime: startTime)

        case .hybrid:
            return try await processHybrid(mesh: inputMesh, session: session, options: options, startTime: startTime)
        }
    }

    // MARK: - On-Device Processing

    private func processOnDevice(
        mesh: MeshData,
        session: ScanSession,
        options: GenerationOptions,
        startTime: Date
    ) async throws -> GenerationResult {

        // 1. Analyze mesh for holes and incomplete regions
        processingStage = .analyzing
        progress = 0.1
        let analysis = analyzeMesh(mesh)

        // 2. Detect holes and boundaries
        processingStage = .detectingHoles
        progress = 0.2
        let holes = detectHoles(mesh: mesh, analysis: analysis)

        // 3. Generate neural features
        processingStage = .generatingFeatures
        progress = 0.3
        let neuralRepresentation = await generateNeuralRepresentation(
            mesh: mesh,
            pointCloud: session.pointCloud,
            options: options
        )

        // 4. Neural inference for hole filling
        processingStage = .neuralInference
        progress = 0.5
        let completedSDF = await neuralHoleFilling(
            representation: neuralRepresentation,
            holes: holes,
            options: options
        )

        // 5. Extract mesh from SDF
        processingStage = .extractingMesh
        progress = 0.7
        let completedMesh = extractMeshFromSDF(sdf: completedSDF, bounds: neuralRepresentation.boundingBox)

        // 6. Refine and smooth
        processingStage = .refining
        progress = 0.9
        let finalMesh = refineMesh(
            original: mesh,
            completed: completedMesh,
            preserveDetails: options.preserveDetails
        )

        processingStage = .complete
        progress = 1.0

        return GenerationResult(
            originalMesh: mesh,
            enhancedMesh: finalMesh,
            completedRegions: holes.map { hole in
                GenerationResult.CompletedRegion(
                    bounds: hole.bounds,
                    type: .hole,
                    vertexCount: hole.boundaryVertices.count * 2
                )
            },
            confidence: 0.75,
            processingTime: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Cloud Processing

    private func processInCloud(
        mesh: MeshData,
        session: ScanSession,
        options: GenerationOptions,
        startTime: Date
    ) async throws -> GenerationResult {

        // 1. Prepare and upload data
        processingStage = .uploading
        progress = 0.1

        let uploadData = prepareUploadData(mesh: mesh, session: session)
        let scanId = try await uploadToCloud(data: uploadData)

        // 2. Start cloud processing
        processingStage = .cloudProcessing
        progress = 0.3

        try await startCloudProcessing(scanId: scanId, options: options)

        // 3. Poll for completion and download
        let result = try await waitForCloudResult(scanId: scanId)

        processingStage = .downloading
        progress = 0.9

        let enhancedMesh = try await downloadEnhancedMesh(scanId: scanId)

        processingStage = .complete
        progress = 1.0

        return GenerationResult(
            originalMesh: mesh,
            enhancedMesh: enhancedMesh,
            completedRegions: result.completedRegions,
            confidence: result.confidence,
            processingTime: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Hybrid Processing

    private func processHybrid(
        mesh: MeshData,
        session: ScanSession,
        options: GenerationOptions,
        startTime: Date
    ) async throws -> GenerationResult {

        // 1. Quick on-device preprocessing
        processingStage = .analyzing
        progress = 0.05

        let analysis = analyzeMesh(mesh)
        let holes = detectHoles(mesh: mesh, analysis: analysis)

        // 2. On-device neural completion for small holes
        processingStage = .neuralInference
        progress = 0.15

        let smallHoles = holes.filter { $0.boundaryVertices.count < 50 }
        let largeHoles = holes.filter { $0.boundaryVertices.count >= 50 }

        var edgeMesh = mesh
        if !smallHoles.isEmpty {
            let representation = await generateNeuralRepresentation(
                mesh: mesh,
                pointCloud: session.pointCloud,
                options: options
            )
            let completedSDF = await neuralHoleFilling(
                representation: representation,
                holes: smallHoles,
                options: options
            )
            let completedSmall = extractMeshFromSDF(sdf: completedSDF, bounds: representation.boundingBox)
            edgeMesh = mergeMeshes(mesh, completedSmall)
        }

        // 3. If large holes exist, send to cloud
        var cloudRegions: [GenerationResult.CompletedRegion] = []
        var finalMesh = edgeMesh

        if !largeHoles.isEmpty {
            processingStage = .uploading
            progress = 0.3

            let uploadData = prepareUploadData(mesh: edgeMesh, session: session)
            let scanId = try await uploadToCloud(data: uploadData)

            processingStage = .cloudProcessing
            progress = 0.5

            try await startCloudProcessing(scanId: scanId, options: options)
            let cloudResult = try await waitForCloudResult(scanId: scanId)

            processingStage = .downloading
            progress = 0.8

            finalMesh = try await downloadEnhancedMesh(scanId: scanId)
            cloudRegions = cloudResult.completedRegions
        }

        // 4. Final refinement
        processingStage = .refining
        progress = 0.95

        finalMesh = refineMesh(
            original: mesh,
            completed: finalMesh,
            preserveDetails: options.preserveDetails
        )

        processingStage = .complete
        progress = 1.0

        let allRegions = smallHoles.map { hole in
            GenerationResult.CompletedRegion(
                bounds: hole.bounds,
                type: .hole,
                vertexCount: hole.boundaryVertices.count * 2
            )
        } + cloudRegions

        return GenerationResult(
            originalMesh: mesh,
            enhancedMesh: finalMesh,
            completedRegions: allRegions,
            confidence: 0.9,
            processingTime: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Mesh Analysis

    private struct MeshAnalysis {
        let boundingBox: BoundingBox
        let surfaceArea: Float
        let volume: Float
        let holeCount: Int
        let averageEdgeLength: Float
        let boundaryEdges: [(v1: Int, v2: Int)]
        let curvatureMap: [Float]
    }

    private func analyzeMesh(_ mesh: MeshData) -> MeshAnalysis {
        var minBound = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBound = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)

        for vertex in mesh.vertices {
            minBound = simd_min(minBound, vertex)
            maxBound = simd_max(maxBound, vertex)
        }

        // Build edge-face adjacency
        var edgeFaces: [String: [Int]] = [:]
        for (faceIdx, face) in mesh.faces.enumerated() {
            let edges = [
                (min(face.x, face.y), max(face.x, face.y)),
                (min(face.y, face.z), max(face.y, face.z)),
                (min(face.z, face.x), max(face.z, face.x))
            ]
            for edge in edges {
                let key = "\(edge.0)-\(edge.1)"
                edgeFaces[key, default: []].append(faceIdx)
            }
        }

        // Find boundary edges (edges with only one face)
        var boundaryEdges: [(v1: Int, v2: Int)] = []
        var edgeLengthSum: Float = 0
        var edgeCount = 0

        for (key, faces) in edgeFaces {
            if faces.count == 1 {
                let parts = key.split(separator: "-")
                if let v1 = Int(parts[0]), let v2 = Int(parts[1]) {
                    boundaryEdges.append((v1, v2))
                }
            }

            let parts = key.split(separator: "-")
            if let v1 = Int(parts[0]), let v2 = Int(parts[1]),
               v1 < mesh.vertices.count && v2 < mesh.vertices.count {
                edgeLengthSum += simd_length(mesh.vertices[v1] - mesh.vertices[v2])
                edgeCount += 1
            }
        }

        // Calculate surface area
        var surfaceArea: Float = 0
        for face in mesh.faces {
            let v0 = mesh.vertices[Int(face.x)]
            let v1 = mesh.vertices[Int(face.y)]
            let v2 = mesh.vertices[Int(face.z)]
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            surfaceArea += simd_length(simd_cross(edge1, edge2)) / 2
        }

        // Calculate volume (assuming closed mesh)
        var volume: Float = 0
        for face in mesh.faces {
            let v0 = mesh.vertices[Int(face.x)]
            let v1 = mesh.vertices[Int(face.y)]
            let v2 = mesh.vertices[Int(face.z)]
            volume += simd_dot(v0, simd_cross(v1, v2)) / 6
        }

        // Curvature estimation
        let curvatureMap = estimateCurvature(mesh: mesh)

        return MeshAnalysis(
            boundingBox: BoundingBox(min: minBound, max: maxBound),
            surfaceArea: surfaceArea,
            volume: abs(volume),
            holeCount: countHoles(boundaryEdges: boundaryEdges),
            averageEdgeLength: edgeCount > 0 ? edgeLengthSum / Float(edgeCount) : 0.01,
            boundaryEdges: boundaryEdges,
            curvatureMap: curvatureMap
        )
    }

    private func countHoles(boundaryEdges: [(v1: Int, v2: Int)]) -> Int {
        guard !boundaryEdges.isEmpty else { return 0 }

        var visited = Set<Int>()
        var holeCount = 0

        // Build adjacency for boundary vertices
        var adjacency: [Int: Set<Int>] = [:]
        for edge in boundaryEdges {
            adjacency[edge.v1, default: []].insert(edge.v2)
            adjacency[edge.v2, default: []].insert(edge.v1)
        }

        // BFS to find connected components (each is a hole)
        for start in adjacency.keys where !visited.contains(start) {
            var queue = [start]
            while !queue.isEmpty {
                let current = queue.removeFirst()
                guard !visited.contains(current) else { continue }
                visited.insert(current)

                for neighbor in adjacency[current, default: []] where !visited.contains(neighbor) {
                    queue.append(neighbor)
                }
            }
            holeCount += 1
        }

        return holeCount
    }

    private func estimateCurvature(mesh: MeshData) -> [Float] {
        var curvature = [Float](repeating: 0, count: mesh.vertices.count)

        // Calculate vertex normals and compare with neighbors
        var vertexNormals = [simd_float3](repeating: .zero, count: mesh.vertices.count)
        var vertexFaceCount = [Int](repeating: 0, count: mesh.vertices.count)

        for face in mesh.faces {
            let v0 = mesh.vertices[Int(face.x)]
            let v1 = mesh.vertices[Int(face.y)]
            let v2 = mesh.vertices[Int(face.z)]

            let faceNormal = simd_normalize(simd_cross(v1 - v0, v2 - v0))

            vertexNormals[Int(face.x)] += faceNormal
            vertexNormals[Int(face.y)] += faceNormal
            vertexNormals[Int(face.z)] += faceNormal

            vertexFaceCount[Int(face.x)] += 1
            vertexFaceCount[Int(face.y)] += 1
            vertexFaceCount[Int(face.z)] += 1
        }

        for i in 0..<vertexNormals.count {
            if vertexFaceCount[i] > 0 {
                vertexNormals[i] = simd_normalize(vertexNormals[i])
            }
        }

        // Curvature as normal variation
        for face in mesh.faces {
            let n0 = vertexNormals[Int(face.x)]
            let n1 = vertexNormals[Int(face.y)]
            let n2 = vertexNormals[Int(face.z)]

            let variation = (1 - simd_dot(n0, n1)) + (1 - simd_dot(n1, n2)) + (1 - simd_dot(n2, n0))

            curvature[Int(face.x)] += variation / 3
            curvature[Int(face.y)] += variation / 3
            curvature[Int(face.z)] += variation / 3
        }

        return curvature
    }

    // MARK: - Hole Detection

    private struct DetectedHole {
        let boundaryVertices: [Int]
        let bounds: BoundingBox
        let area: Float
        let normalDirection: simd_float3
    }

    private func detectHoles(mesh: MeshData, analysis: MeshAnalysis) -> [DetectedHole] {
        var holes: [DetectedHole] = []
        var visited = Set<Int>()

        // Build adjacency from boundary edges
        var adjacency: [Int: [Int]] = [:]
        for edge in analysis.boundaryEdges {
            adjacency[edge.v1, default: []].append(edge.v2)
            adjacency[edge.v2, default: []].append(edge.v1)
        }

        // Find connected boundary loops
        for start in adjacency.keys where !visited.contains(start) {
            var loop: [Int] = []
            var current = start

            // Walk the boundary loop
            while !visited.contains(current) {
                visited.insert(current)
                loop.append(current)

                // Find next unvisited neighbor
                if let next = adjacency[current]?.first(where: { !visited.contains($0) }) {
                    current = next
                } else {
                    break
                }
            }

            if loop.count >= 3 {
                let hole = createHoleFromLoop(loop: loop, mesh: mesh)
                holes.append(hole)
            }
        }

        return holes.sorted { $0.boundaryVertices.count > $1.boundaryVertices.count }
    }

    private func createHoleFromLoop(loop: [Int], mesh: MeshData) -> DetectedHole {
        var minBound = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBound = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)

        var center = simd_float3.zero
        for idx in loop {
            let v = mesh.vertices[idx]
            minBound = simd_min(minBound, v)
            maxBound = simd_max(maxBound, v)
            center += v
        }
        center /= Float(loop.count)

        // Estimate area using shoelace formula in local coordinates
        let normal = estimateHoleNormal(loop: loop, mesh: mesh)
        let area = estimateHoleArea(loop: loop, mesh: mesh, normal: normal)

        return DetectedHole(
            boundaryVertices: loop,
            bounds: BoundingBox(min: minBound, max: maxBound),
            area: area,
            normalDirection: normal
        )
    }

    private func estimateHoleNormal(loop: [Int], mesh: MeshData) -> simd_float3 {
        var normal = simd_float3.zero

        for i in 0..<loop.count {
            let v1 = mesh.vertices[loop[i]]
            let v2 = mesh.vertices[loop[(i + 1) % loop.count]]
            let v3 = mesh.vertices[loop[(i + 2) % loop.count]]

            normal += simd_cross(v2 - v1, v3 - v2)
        }

        return simd_normalize(normal)
    }

    private func estimateHoleArea(loop: [Int], mesh: MeshData, normal: simd_float3) -> Float {
        guard loop.count >= 3 else { return 0 }

        // Fan triangulation to estimate area
        var area: Float = 0
        let center = loop.reduce(simd_float3.zero) { $0 + mesh.vertices[$1] } / Float(loop.count)

        for i in 0..<loop.count {
            let v1 = mesh.vertices[loop[i]]
            let v2 = mesh.vertices[loop[(i + 1) % loop.count]]
            area += simd_length(simd_cross(v1 - center, v2 - center)) / 2
        }

        return area
    }

    // MARK: - Neural Representation

    private func generateNeuralRepresentation(
        mesh: MeshData,
        pointCloud: PointCloud?,
        options: GenerationOptions
    ) async -> NeuralSceneRepresentation {

        // Create feature grid
        let resolution = simd_int3(
            Int32(featureGridResolution),
            Int32(featureGridResolution),
            Int32(featureGridResolution)
        )

        let gridSize = Int(resolution.x * resolution.y * resolution.z)

        // Guard against empty mesh
        guard !mesh.vertices.isEmpty, !mesh.faces.isEmpty else {
            print("[AIGeometry] Warning: Empty mesh passed to generateNeuralRepresentation")
            return NeuralSceneRepresentation(
                featureGrid: [Float](repeating: 0, count: gridSize * 8),
                resolution: resolution,
                boundingBox: BoundingBox(min: .zero, max: simd_float3(1, 1, 1)),
                density: [Float](repeating: 0, count: gridSize),
                sdfValues: [Float](repeating: 1000, count: gridSize)
            )
        }

        let analysis = analyzeMesh(mesh)
        let bounds = analysis.boundingBox

        // Validate bounds - ensure max >= min with minimum size
        let minCellSize: Float = 0.001 // 1mm minimum
        let validBounds = BoundingBox(
            min: simd_float3(
                min(bounds.min.x, bounds.max.x),
                min(bounds.min.y, bounds.max.y),
                min(bounds.min.z, bounds.max.z)
            ),
            max: simd_float3(
                max(bounds.min.x, bounds.max.x),
                max(bounds.min.y, bounds.max.y),
                max(bounds.min.z, bounds.max.z)
            )
        )

        var featureGrid = [Float](repeating: 0, count: gridSize * 8) // 8 features per voxel
        var density = [Float](repeating: 0, count: gridSize)
        var sdfValues = [Float](repeating: 1000, count: gridSize) // Large positive = outside

        // Calculate cell size with minimum to avoid division by zero
        let cellSize = simd_float3(
            max((validBounds.max.x - validBounds.min.x) / Float(resolution.x), minCellSize),
            max((validBounds.max.y - validBounds.min.y) / Float(resolution.y), minCellSize),
            max((validBounds.max.z - validBounds.min.z) / Float(resolution.z), minCellSize)
        )

        // Sample mesh to populate grids
        let vertexCount = mesh.vertices.count
        let normalCount = mesh.normals.count

        for face in mesh.faces {
            // Validate face indices
            let i0 = Int(face.x)
            let i1 = Int(face.y)
            let i2 = Int(face.z)

            guard i0 >= 0, i0 < vertexCount,
                  i1 >= 0, i1 < vertexCount,
                  i2 >= 0, i2 < vertexCount else {
                continue
            }

            let v0 = mesh.vertices[i0]
            let v1 = mesh.vertices[i1]
            let v2 = mesh.vertices[i2]

            // Sample points on triangle
            for _ in 0..<10 {
                let r1 = Float.random(in: 0...1)
                let r2 = Float.random(in: 0...1)
                let point: simd_float3
                if r1 + r2 <= 1 {
                    point = v0 + r1 * (v1 - v0) + r2 * (v2 - v0)
                } else {
                    point = v0 + (1 - r1) * (v1 - v0) + (1 - r2) * (v2 - v0)
                }

                // Voxel index - use validBounds
                let gridPos = (point - validBounds.min) / cellSize
                let ix = max(0, min(Int(gridPos.x), Int(resolution.x - 1)))
                let iy = max(0, min(Int(gridPos.y), Int(resolution.y - 1)))
                let iz = max(0, min(Int(gridPos.z), Int(resolution.z - 1)))

                let idx = iz * Int(resolution.x * resolution.y) + iy * Int(resolution.x) + ix

                // Bounds check for idx
                guard idx >= 0 && idx < gridSize else { continue }

                density[idx] = 1
                sdfValues[idx] = 0 // On surface

                // Features: position, normal, distance
                // Validate normal indices
                guard i0 < normalCount, i1 < normalCount, i2 < normalCount else { continue }

                let n0 = mesh.normals[i0]
                let n1 = mesh.normals[i1]
                let n2 = mesh.normals[i2]
                let normalSum = n0 + n1 + n2
                let normalLength = simd_length(normalSum)
                let normal = normalLength > 0.0001 ? normalSum / normalLength : simd_float3(0, 1, 0)

                let featureIdx = idx * 8
                guard featureIdx + 5 < featureGrid.count else { continue }

                featureGrid[featureIdx + 0] = point.x
                featureGrid[featureIdx + 1] = point.y
                featureGrid[featureIdx + 2] = point.z
                featureGrid[featureIdx + 3] = normal.x
                featureGrid[featureIdx + 4] = normal.y
                featureGrid[featureIdx + 5] = normal.z
            }
        }

        // Propagate SDF values using fast marching
        sdfValues = propagateSDF(sdf: sdfValues, density: density, resolution: resolution)

        return NeuralSceneRepresentation(
            featureGrid: featureGrid,
            resolution: resolution,
            boundingBox: validBounds,
            density: density,
            sdfValues: sdfValues
        )
    }

    private func propagateSDF(
        sdf: [Float],
        density: [Float],
        resolution: simd_int3
    ) -> [Float] {

        var result = sdf
        let maxIterations = 20

        for _ in 0..<maxIterations {
            var changed = false

            for z in 1..<(Int(resolution.z) - 1) {
                for y in 1..<(Int(resolution.y) - 1) {
                    for x in 1..<(Int(resolution.x) - 1) {
                        let idx = z * Int(resolution.x * resolution.y) + y * Int(resolution.x) + x

                        if density[idx] > 0 { continue } // Already on surface

                        let neighbors = [
                            result[idx - 1], result[idx + 1],
                            result[idx - Int(resolution.x)], result[idx + Int(resolution.x)],
                            result[idx - Int(resolution.x * resolution.y)], result[idx + Int(resolution.x * resolution.y)]
                        ]

                        let minNeighbor = neighbors.min() ?? 1000
                        let newValue = minNeighbor + 1

                        if newValue < result[idx] {
                            result[idx] = newValue
                            changed = true
                        }
                    }
                }
            }

            if !changed { break }
        }

        return result
    }

    // MARK: - Neural Hole Filling

    private func neuralHoleFilling(
        representation: NeuralSceneRepresentation,
        holes: [DetectedHole],
        options: GenerationOptions
    ) async -> [Float] {

        var sdf = representation.sdfValues
        let resolution = representation.resolution
        let bounds = representation.boundingBox

        let cellSize = simd_float3(
            (bounds.max.x - bounds.min.x) / Float(resolution.x),
            (bounds.max.y - bounds.min.y) / Float(resolution.y),
            (bounds.max.z - bounds.min.z) / Float(resolution.z)
        )

        for hole in holes {
            // Generate geometry to fill this hole using learned priors

            // 1. Estimate surface continuation
            let fillSurface = generateHoleFillSurface(
                hole: hole,
                representation: representation,
                options: options
            )

            // 2. Update SDF with filled geometry
            for point in fillSurface {
                let gridPos = (point - bounds.min) / cellSize
                let ix = Int(gridPos.x)
                let iy = Int(gridPos.y)
                let iz = Int(gridPos.z)

                guard ix >= 0 && ix < Int(resolution.x) &&
                      iy >= 0 && iy < Int(resolution.y) &&
                      iz >= 0 && iz < Int(resolution.z) else { continue }

                let idx = iz * Int(resolution.x * resolution.y) + iy * Int(resolution.x) + ix
                sdf[idx] = 0 // Mark as on surface
            }
        }

        return sdf
    }

    private func generateHoleFillSurface(
        hole: DetectedHole,
        representation: NeuralSceneRepresentation,
        options: GenerationOptions
    ) -> [simd_float3] {

        // Simple planar fill with refinement
        // In production, this would use a neural network for smart completion

        var fillPoints: [simd_float3] = []

        let center = (hole.bounds.min + hole.bounds.max) / 2
        let normal = hole.normalDirection

        // Create planar grid to fill hole
        let tangent = simd_normalize(simd_cross(normal, simd_float3(0, 1, 0)))
        let bitangent = simd_normalize(simd_cross(normal, tangent))

        let size = hole.bounds.max - hole.bounds.min
        let maxExtent = max(size.x, max(size.y, size.z))
        let step = maxExtent / 10

        for u in stride(from: -maxExtent/2, to: maxExtent/2, by: step) {
            for v in stride(from: -maxExtent/2, to: maxExtent/2, by: step) {
                let point = center + u * tangent + v * bitangent

                // Check if point is within hole boundary (simplified)
                if isPointInHole(point: point, hole: hole) {
                    fillPoints.append(point)
                }
            }
        }

        return fillPoints
    }

    private func isPointInHole(point: simd_float3, hole: DetectedHole) -> Bool {
        // Simplified bounding box check
        return point.x >= hole.bounds.min.x && point.x <= hole.bounds.max.x &&
               point.y >= hole.bounds.min.y && point.y <= hole.bounds.max.y &&
               point.z >= hole.bounds.min.z && point.z <= hole.bounds.max.z
    }

    // MARK: - Mesh Extraction

    private func extractMeshFromSDF(sdf: [Float], bounds: BoundingBox) -> MeshData {
        // Marching Cubes implementation
        let resolution = marchingCubesResolution
        let cellSize = simd_float3(
            (bounds.max.x - bounds.min.x) / Float(resolution),
            (bounds.max.y - bounds.min.y) / Float(resolution),
            (bounds.max.z - bounds.min.z) / Float(resolution)
        )

        var vertices: [simd_float3] = []
        var faces: [simd_uint3] = []

        // Simplified marching cubes
        let sdfResolution = Int(sqrt(Double(sdf.count / marchingCubesResolution)))

        for z in 0..<(resolution - 1) {
            for y in 0..<(resolution - 1) {
                for x in 0..<(resolution - 1) {
                    // Sample SDF at cube corners
                    let corners = getCubeCornerValues(x: x, y: y, z: z, sdf: sdf, resolution: sdfResolution)

                    // Check if surface passes through cube
                    var cubeIndex = 0
                    for i in 0..<8 {
                        if corners[i] < 0 {
                            cubeIndex |= (1 << i)
                        }
                    }

                    if cubeIndex == 0 || cubeIndex == 255 { continue }

                    // Generate triangles (simplified - just add cube center vertex)
                    let cubeCenter = bounds.min + cellSize * simd_float3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)

                    let vertexIndex = UInt32(vertices.count)
                    vertices.append(cubeCenter)

                    // In full implementation, interpolate edge vertices
                }
            }
        }

        // Generate normals
        let normals = vertices.map { _ in simd_float3(0, 1, 0) }

        return MeshData(
            anchorIdentifier: UUID(),
            vertices: vertices,
            normals: normals,
            faces: faces
        )
    }

    private func getCubeCornerValues(x: Int, y: Int, z: Int, sdf: [Float], resolution: Int) -> [Float] {
        var values = [Float](repeating: 1, count: 8)

        let offsets = [
            (0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),
            (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)
        ]

        for (i, offset) in offsets.enumerated() {
            let px = x + offset.0
            let py = y + offset.1
            let pz = z + offset.2

            if px < resolution && py < resolution && pz < resolution {
                let idx = pz * resolution * resolution + py * resolution + px
                if idx < sdf.count {
                    values[i] = sdf[idx]
                }
            }
        }

        return values
    }

    // MARK: - Mesh Refinement

    private func refineMesh(
        original: MeshData,
        completed: MeshData,
        preserveDetails: Bool
    ) -> MeshData {

        // Merge original and completed meshes
        var mergedMesh = mergeMeshes(original, completed)

        // Remove duplicate vertices
        mergedMesh = removeDuplicateVertices(mergedMesh)

        // Laplacian smoothing (gentle)
        if !preserveDetails {
            mergedMesh = laplacianSmooth(mesh: mergedMesh, iterations: 2, lambda: 0.3)
        }

        return mergedMesh
    }

    private func mergeMeshes(_ mesh1: MeshData, _ mesh2: MeshData) -> MeshData {
        let offset = UInt32(mesh1.vertices.count)

        var vertices = mesh1.vertices + mesh2.vertices
        var normals = mesh1.normals + mesh2.normals
        var faces = mesh1.faces

        for face in mesh2.faces {
            faces.append(simd_uint3(face.x + offset, face.y + offset, face.z + offset))
        }

        return MeshData(
            anchorIdentifier: UUID(),
            vertices: vertices,
            normals: normals,
            faces: faces
        )
    }

    private func removeDuplicateVertices(_ mesh: MeshData) -> MeshData {
        let epsilon: Float = 0.0001

        var uniqueVertices: [simd_float3] = []
        var uniqueNormals: [simd_float3] = []
        var indexMap: [Int: Int] = [:]

        for (oldIndex, vertex) in mesh.vertices.enumerated() {
            // Check if similar vertex exists
            var foundIndex: Int?
            for (newIndex, existing) in uniqueVertices.enumerated() {
                if simd_length(vertex - existing) < epsilon {
                    foundIndex = newIndex
                    break
                }
            }

            if let found = foundIndex {
                indexMap[oldIndex] = found
            } else {
                indexMap[oldIndex] = uniqueVertices.count
                uniqueVertices.append(vertex)
                uniqueNormals.append(oldIndex < mesh.normals.count ? mesh.normals[oldIndex] : simd_float3(0, 1, 0))
            }
        }

        // Remap faces
        var newFaces: [simd_uint3] = []
        for face in mesh.faces {
            if let i0 = indexMap[Int(face.x)],
               let i1 = indexMap[Int(face.y)],
               let i2 = indexMap[Int(face.z)] {
                newFaces.append(simd_uint3(UInt32(i0), UInt32(i1), UInt32(i2)))
            }
        }

        return MeshData(
            anchorIdentifier: mesh.anchorIdentifier,
            vertices: uniqueVertices,
            normals: uniqueNormals,
            faces: newFaces
        )
    }

    private func laplacianSmooth(mesh: MeshData, iterations: Int, lambda: Float) -> MeshData {
        var vertices = mesh.vertices

        // Build vertex adjacency
        var adjacency: [[Int]] = Array(repeating: [], count: vertices.count)
        for face in mesh.faces {
            adjacency[Int(face.x)].append(Int(face.y))
            adjacency[Int(face.x)].append(Int(face.z))
            adjacency[Int(face.y)].append(Int(face.x))
            adjacency[Int(face.y)].append(Int(face.z))
            adjacency[Int(face.z)].append(Int(face.x))
            adjacency[Int(face.z)].append(Int(face.y))
        }

        for _ in 0..<iterations {
            var newVertices = vertices

            for i in 0..<vertices.count {
                let neighbors = Array(Set(adjacency[i]))
                guard !neighbors.isEmpty else { continue }

                var centroid = simd_float3.zero
                for n in neighbors {
                    centroid += vertices[n]
                }
                centroid /= Float(neighbors.count)

                newVertices[i] = vertices[i] + lambda * (centroid - vertices[i])
            }

            vertices = newVertices
        }

        // Recalculate normals
        var normals = [simd_float3](repeating: .zero, count: vertices.count)
        for face in mesh.faces {
            let v0 = vertices[Int(face.x)]
            let v1 = vertices[Int(face.y)]
            let v2 = vertices[Int(face.z)]
            let faceNormal = simd_cross(v1 - v0, v2 - v0)

            normals[Int(face.x)] += faceNormal
            normals[Int(face.y)] += faceNormal
            normals[Int(face.z)] += faceNormal
        }

        normals = normals.map { simd_normalize($0) }

        return MeshData(
            anchorIdentifier: mesh.anchorIdentifier,
            vertices: vertices,
            normals: normals,
            faces: mesh.faces
        )
    }

    // MARK: - Cloud Communication

    private struct CloudUploadData: Encodable {
        let meshData: Data
        let pointCloudData: Data?
        let metadata: ScanMetadata

        struct ScanMetadata: Encodable {
            let vertexCount: Int
            let faceCount: Int
            let boundingBox: [Float]
            let deviceModel: String
        }
    }

    private struct CloudProcessingResult {
        let completedRegions: [GenerationResult.CompletedRegion]
        let confidence: Float
    }

    private func prepareUploadData(mesh: MeshData, session: ScanSession) -> CloudUploadData {
        // Encode mesh as binary PLY
        let meshData = encodeMeshAsPLY(mesh)

        // Encode point cloud if available
        let pointCloudData = session.pointCloud.map { encodePointCloudAsPLY($0) }

        let bounds = mesh.boundingBox ?? BoundingBox(min: .zero, max: simd_float3(1, 1, 1))
        let metadata = CloudUploadData.ScanMetadata(
            vertexCount: mesh.vertices.count,
            faceCount: mesh.faces.count,
            boundingBox: [bounds.min.x, bounds.min.y, bounds.min.z, bounds.max.x, bounds.max.y, bounds.max.z],
            deviceModel: session.deviceModel
        )

        return CloudUploadData(
            meshData: meshData,
            pointCloudData: pointCloudData,
            metadata: metadata
        )
    }

    private func encodeMeshAsPLY(_ mesh: MeshData) -> Data {
        var ply = """
        ply
        format binary_little_endian 1.0
        element vertex \(mesh.vertices.count)
        property float x
        property float y
        property float z
        property float nx
        property float ny
        property float nz
        element face \(mesh.faces.count)
        property list uchar int vertex_indices
        end_header

        """

        var data = Data(ply.utf8)

        for (i, v) in mesh.vertices.enumerated() {
            var vertex = v
            var normal = i < mesh.normals.count ? mesh.normals[i] : simd_float3(0, 1, 0)
            data.append(Data(bytes: &vertex, count: 12))
            data.append(Data(bytes: &normal, count: 12))
        }

        for face in mesh.faces {
            var count: UInt8 = 3
            var indices = [Int32(face.x), Int32(face.y), Int32(face.z)]
            data.append(Data(bytes: &count, count: 1))
            data.append(Data(bytes: &indices, count: 12))
        }

        return data
    }

    private func encodePointCloudAsPLY(_ pointCloud: PointCloud) -> Data {
        var ply = """
        ply
        format binary_little_endian 1.0
        element vertex \(pointCloud.pointCount)
        property float x
        property float y
        property float z
        end_header

        """

        var data = Data(ply.utf8)

        for point in pointCloud.points {
            var p = point
            data.append(Data(bytes: &p, count: 12))
        }

        return data
    }

    private func uploadToCloud(data: CloudUploadData) async throws -> String {
        // In production, use ChunkedUploader for large files
        let scanId = UUID().uuidString

        // Simulated upload
        try await Task.sleep(nanoseconds: 500_000_000)

        return scanId
    }

    private func startCloudProcessing(scanId: String, options: GenerationOptions) async throws {
        // POST /api/v1/scans/{scanId}/process
        // In production, this would call the actual API
    }

    private func waitForCloudResult(scanId: String) async throws -> CloudProcessingResult {
        // Poll /api/v1/scans/{scanId}/status until complete
        // Or use WebSocket for real-time updates

        // Simulated processing
        for i in 0..<10 {
            try await Task.sleep(nanoseconds: 500_000_000)
            progress = 0.3 + Float(i) * 0.05
        }

        return CloudProcessingResult(
            completedRegions: [],
            confidence: 0.95
        )
    }

    private func downloadEnhancedMesh(scanId: String) async throws -> MeshData {
        // GET /api/v1/scans/{scanId}/download?format=ply
        // For now, return empty mesh as placeholder
        return MeshData(
            anchorIdentifier: UUID(),
            vertices: [],
            normals: [],
            faces: []
        )
    }
}

// MARK: - Supporting Types
// Note: BoundingBox is defined in PointCloud.swift

enum AIGeometryError: Error, LocalizedError {
    case noInputData
    case processingFailed(String)
    case cloudError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noInputData:
            return "Žádná vstupní data pro zpracování"
        case .processingFailed(let message):
            return "Zpracování selhalo: \(message)"
        case .cloudError(let message):
            return "Cloud chyba: \(message)"
        case .cancelled:
            return "Zpracování zrušeno"
        }
    }
}

// MARK: - CombinedMesh Extension

extension CombinedMesh {
    func asSingleMesh() -> MeshData? {
        guard !meshes.isEmpty else { return nil }

        var allVertices: [simd_float3] = []
        var allNormals: [simd_float3] = []
        var allFaces: [simd_uint3] = []

        for mesh in meshes.values {
            let offset = UInt32(allVertices.count)
            allVertices.append(contentsOf: mesh.vertices)
            allNormals.append(contentsOf: mesh.normals)

            for face in mesh.faces {
                allFaces.append(simd_uint3(
                    face.x + offset,
                    face.y + offset,
                    face.z + offset
                ))
            }
        }

        return MeshData(
            anchorIdentifier: UUID(),
            vertices: allVertices,
            normals: allNormals,
            faces: allFaces
        )
    }
}

// Note: MeshData.boundingBox is already defined in MeshData.swift
