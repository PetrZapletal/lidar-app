import ARKit
import simd
import Accelerate

/// Extracts high-resolution point clouds from fused depth data
final class HighResPointCloudExtractor {

    // MARK: - Configuration

    struct Configuration {
        /// Maximum number of points in output
        var maxPoints: Int = 2_000_000

        /// Voxel size for downsampling (meters)
        var voxelSize: Float = 0.005  // 5mm for high-res

        /// Minimum valid depth (meters)
        var minDepth: Float = 0.1

        /// Maximum valid depth (meters)
        var maxDepth: Float = 5.0

        /// Minimum confidence to include point
        var minConfidence: Float = 0.3

        /// Include edge points with higher priority
        var preserveEdges: Bool = true

        /// Stride for sampling (1 = every pixel)
        var samplingStride: Int = 1
    }

    // MARK: - Extraction Result

    struct ExtractionResult {
        let pointCloud: PointCloud
        let stats: ExtractionStats
    }

    struct ExtractionStats {
        let rawPointCount: Int
        let filteredPointCount: Int
        let finalPointCount: Int
        let edgePointCount: Int
        let coverage: Float
        let processingTimeMs: Double
    }

    // MARK: - Properties

    private let configuration: Configuration

    // MARK: - Initialization

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Point Cloud Extraction

    /// Extract high-resolution point cloud from fusion result
    func extractPointCloud(
        from fusionResult: DepthFusionProcessor.FusionResult,
        camera: ARCamera,
        colorImage: CVPixelBuffer? = nil
    ) -> ExtractionResult {
        let startTime = CACurrentMediaTime()

        let depthMap = fusionResult.fusedDepth
        let confidenceMap = fusionResult.confidenceMap
        let edgeMap = fusionResult.edgeMap

        // Lock buffers
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
        }

        if let edge = edgeMap {
            CVPixelBufferLockBaseAddress(edge, .readOnly)
        }
        defer {
            if let edge = edgeMap {
                CVPixelBufferUnlockBaseAddress(edge, .readOnly)
            }
        }

        if let color = colorImage {
            CVPixelBufferLockBaseAddress(color, .readOnly)
        }
        defer {
            if let color = colorImage {
                CVPixelBufferUnlockBaseAddress(color, .readOnly)
            }
        }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap),
              let confBase = CVPixelBufferGetBaseAddress(confidenceMap) else {
            return emptyResult(startTime: startTime)
        }

        let depthData = depthBase.assumingMemoryBound(to: Float32.self)
        let confData = confBase.assumingMemoryBound(to: UInt8.self)

        var edgeData: UnsafeMutablePointer<UInt8>?
        if let edge = edgeMap {
            edgeData = CVPixelBufferGetBaseAddress(edge)?.assumingMemoryBound(to: UInt8.self)
        }

        // Color data
        var colorData: UnsafeMutablePointer<UInt8>?
        var colorWidth = 0
        var colorHeight = 0
        var colorBytesPerRow = 0

        if let color = colorImage {
            colorData = CVPixelBufferGetBaseAddress(color)?.assumingMemoryBound(to: UInt8.self)
            colorWidth = CVPixelBufferGetWidth(color)
            colorHeight = CVPixelBufferGetHeight(color)
            colorBytesPerRow = CVPixelBufferGetBytesPerRow(color)
        }

        // Camera intrinsics (scaled to output resolution)
        let intrinsics = camera.intrinsics
        let imageResolution = camera.imageResolution
        let cameraTransform = camera.transform

        // Scale intrinsics to fused depth resolution
        let scaleX = Float(width) / Float(imageResolution.width)
        let scaleY = Float(height) / Float(imageResolution.height)

        let fx = intrinsics[0, 0] * scaleX
        let fy = intrinsics[1, 1] * scaleY
        let cx = intrinsics[2, 0] * scaleX
        let cy = intrinsics[2, 1] * scaleY

        // Extract points
        var points: [simd_float3] = []
        var colors: [simd_float4] = []
        var confidences: [Float] = []
        var normals: [simd_float3] = []

        var rawCount = 0
        var filteredCount = 0
        var edgeCount = 0

        let stride = configuration.samplingStride

        for y in stride(from: 0, to: height, by: stride) {
            for x in stride(from: 0, to: width, by: stride) {
                let idx = y * width + x
                let depth = depthData[idx]
                let confidence = Float(confData[idx]) / 255.0

                rawCount += 1

                // Filter invalid depths
                guard depth > configuration.minDepth &&
                      depth < configuration.maxDepth else { continue }

                // Filter low confidence
                guard confidence >= configuration.minConfidence else { continue }

                filteredCount += 1

                // Check if edge point
                let isEdge = edgeData?[idx] ?? 0 > 0
                if isEdge { edgeCount += 1 }

                // Back-project to 3D camera space
                let localX = (Float(x) - cx) * depth / fx
                let localY = (Float(y) - cy) * depth / fy
                let localZ = depth

                // Transform to world coordinates
                let localPoint = simd_float4(localX, localY, localZ, 1)
                let worldPoint = cameraTransform * localPoint

                points.append(simd_float3(worldPoint.x, worldPoint.y, worldPoint.z))
                confidences.append(confidence)

                // Sample color if available
                if let colorPtr = colorData {
                    let colorScaleX = Float(colorWidth) / Float(width)
                    let colorScaleY = Float(colorHeight) / Float(height)

                    let cx = Int(Float(x) * colorScaleX)
                    let cy = Int(Float(y) * colorScaleY)

                    if cx >= 0 && cx < colorWidth && cy >= 0 && cy < colorHeight {
                        let colorIdx = cy * colorBytesPerRow + cx * 4
                        let b = Float(colorPtr[colorIdx]) / 255.0
                        let g = Float(colorPtr[colorIdx + 1]) / 255.0
                        let r = Float(colorPtr[colorIdx + 2]) / 255.0
                        colors.append(simd_float4(r, g, b, 1.0))
                    } else {
                        colors.append(simd_float4(0.5, 0.5, 0.5, 1.0))
                    }
                }

                // Estimate normal from depth gradient
                if x > 0 && x < width - 1 && y > 0 && y < height - 1 {
                    let normal = estimateNormal(
                        depthData: depthData,
                        x: x, y: y,
                        width: width,
                        fx: fx, fy: fy, cx: cx, cy: cy
                    )
                    normals.append(normal)
                } else {
                    normals.append(simd_float3(0, 1, 0))
                }
            }
        }

        // Voxel downsampling if needed
        var finalPoints = points
        var finalColors = colors
        var finalConfidences = confidences
        var finalNormals = normals

        if points.count > configuration.maxPoints {
            (finalPoints, finalColors, finalConfidences, finalNormals) = voxelDownsample(
                points: points,
                colors: colors.isEmpty ? nil : colors,
                confidences: confidences,
                normals: normals.isEmpty ? nil : normals,
                voxelSize: configuration.voxelSize,
                maxPoints: configuration.maxPoints
            )
        }

        let processingTime = (CACurrentMediaTime() - startTime) * 1000

        let pointCloud = PointCloud(
            points: finalPoints,
            colors: finalColors.isEmpty ? nil : finalColors,
            normals: finalNormals.isEmpty ? nil : finalNormals,
            confidences: finalConfidences.isEmpty ? nil : finalConfidences,
            timestamp: CACurrentMediaTime()
        )

        return ExtractionResult(
            pointCloud: pointCloud,
            stats: ExtractionStats(
                rawPointCount: rawCount,
                filteredPointCount: filteredCount,
                finalPointCount: finalPoints.count,
                edgePointCount: edgeCount,
                coverage: Float(filteredCount) / Float(rawCount),
                processingTimeMs: processingTime
            )
        )
    }

    // MARK: - Normal Estimation

    private func estimateNormal(
        depthData: UnsafeMutablePointer<Float32>,
        x: Int, y: Int,
        width: Int,
        fx: Float, fy: Float, cx: Float, cy: Float
    ) -> simd_float3 {
        // Get depths of neighbors
        let dL = depthData[y * width + (x - 1)]
        let dR = depthData[y * width + (x + 1)]
        let dU = depthData[(y - 1) * width + x]
        let dD = depthData[(y + 1) * width + x]
        let dC = depthData[y * width + x]

        // Check validity
        guard dL > 0.1 && dR > 0.1 && dU > 0.1 && dD > 0.1 && dC > 0.1 else {
            return simd_float3(0, 0, -1)
        }

        // Compute 3D positions
        let pL = simd_float3((Float(x-1) - cx) * dL / fx, (Float(y) - cy) * dL / fy, dL)
        let pR = simd_float3((Float(x+1) - cx) * dR / fx, (Float(y) - cy) * dR / fy, dR)
        let pU = simd_float3((Float(x) - cx) * dU / fx, (Float(y-1) - cy) * dU / fy, dU)
        let pD = simd_float3((Float(x) - cx) * dD / fx, (Float(y+1) - cy) * dD / fy, dD)

        // Cross product of tangent vectors
        let tangentX = pR - pL
        let tangentY = pD - pU

        var normal = simd_cross(tangentX, tangentY)
        let length = simd_length(normal)

        if length > 1e-6 {
            normal /= length
            // Ensure normal points towards camera
            if normal.z > 0 { normal = -normal }
        } else {
            normal = simd_float3(0, 0, -1)
        }

        return normal
    }

    // MARK: - Voxel Downsampling

    private func voxelDownsample(
        points: [simd_float3],
        colors: [simd_float4]?,
        confidences: [Float],
        normals: [simd_float3]?,
        voxelSize: Float,
        maxPoints: Int
    ) -> ([simd_float3], [simd_float4], [Float], [simd_float3]) {
        struct VoxelData {
            var pointSum: simd_float3 = .zero
            var colorSum: simd_float4 = .zero
            var normalSum: simd_float3 = .zero
            var confidenceSum: Float = 0
            var count: Int = 0
        }

        var voxelMap: [SIMD3<Int>: VoxelData] = [:]

        for (index, point) in points.enumerated() {
            let voxelKey = SIMD3<Int>(
                Int(floor(point.x / voxelSize)),
                Int(floor(point.y / voxelSize)),
                Int(floor(point.z / voxelSize))
            )

            if voxelMap[voxelKey] == nil {
                voxelMap[voxelKey] = VoxelData()
            }

            voxelMap[voxelKey]!.pointSum += point
            voxelMap[voxelKey]!.confidenceSum += confidences[index]
            voxelMap[voxelKey]!.count += 1

            if let colors = colors {
                voxelMap[voxelKey]!.colorSum += colors[index]
            }

            if let normals = normals {
                voxelMap[voxelKey]!.normalSum += normals[index]
            }
        }

        // Sort by confidence and take top maxPoints
        var sortedVoxels = voxelMap.values.sorted {
            ($0.confidenceSum / Float($0.count)) > ($1.confidenceSum / Float($1.count))
        }

        if sortedVoxels.count > maxPoints {
            sortedVoxels = Array(sortedVoxels.prefix(maxPoints))
        }

        var outPoints: [simd_float3] = []
        var outColors: [simd_float4] = []
        var outConfidences: [Float] = []
        var outNormals: [simd_float3] = []

        for voxel in sortedVoxels {
            let count = Float(voxel.count)
            outPoints.append(voxel.pointSum / count)
            outConfidences.append(voxel.confidenceSum / count)

            if colors != nil {
                outColors.append(voxel.colorSum / count)
            }

            if normals != nil {
                var avgNormal = voxel.normalSum / count
                let length = simd_length(avgNormal)
                if length > 1e-6 {
                    avgNormal /= length
                } else {
                    avgNormal = simd_float3(0, 1, 0)
                }
                outNormals.append(avgNormal)
            }
        }

        return (outPoints, outColors, outConfidences, outNormals)
    }

    // MARK: - Helpers

    private func emptyResult(startTime: CFTimeInterval) -> ExtractionResult {
        let processingTime = (CACurrentMediaTime() - startTime) * 1000

        return ExtractionResult(
            pointCloud: PointCloud(
                points: [],
                timestamp: CACurrentMediaTime()
            ),
            stats: ExtractionStats(
                rawPointCount: 0,
                filteredPointCount: 0,
                finalPointCount: 0,
                edgePointCount: 0,
                coverage: 0,
                processingTimeMs: processingTime
            )
        )
    }
}

// MARK: - Batch Processing

extension HighResPointCloudExtractor {

    /// Extract and merge point clouds from multiple frames
    func extractMergedPointCloud(
        from frames: [(fusion: DepthFusionProcessor.FusionResult, camera: ARCamera, color: CVPixelBuffer?)],
        progressHandler: ((Float) -> Void)? = nil
    ) -> ExtractionResult {
        let startTime = CACurrentMediaTime()

        var allPoints: [simd_float3] = []
        var allColors: [simd_float4] = []
        var allConfidences: [Float] = []
        var allNormals: [simd_float3] = []

        var totalRaw = 0
        var totalFiltered = 0
        var totalEdges = 0

        for (index, frame) in frames.enumerated() {
            let result = extractPointCloud(
                from: frame.fusion,
                camera: frame.camera,
                colorImage: frame.color
            )

            allPoints.append(contentsOf: result.pointCloud.points)

            if let colors = result.pointCloud.colors {
                allColors.append(contentsOf: colors)
            }

            if let confs = result.pointCloud.confidences {
                allConfidences.append(contentsOf: confs)
            }

            if let normals = result.pointCloud.normals {
                allNormals.append(contentsOf: normals)
            }

            totalRaw += result.stats.rawPointCount
            totalFiltered += result.stats.filteredPointCount
            totalEdges += result.stats.edgePointCount

            progressHandler?(Float(index + 1) / Float(frames.count))
        }

        // Global voxel downsampling
        var finalPoints = allPoints
        var finalColors = allColors
        var finalConfidences = allConfidences
        var finalNormals = allNormals

        if allPoints.count > configuration.maxPoints {
            (finalPoints, finalColors, finalConfidences, finalNormals) = voxelDownsample(
                points: allPoints,
                colors: allColors.isEmpty ? nil : allColors,
                confidences: allConfidences.isEmpty ? [Float](repeating: 1.0, count: allPoints.count) : allConfidences,
                normals: allNormals.isEmpty ? nil : allNormals,
                voxelSize: configuration.voxelSize,
                maxPoints: configuration.maxPoints
            )
        }

        let processingTime = (CACurrentMediaTime() - startTime) * 1000

        let pointCloud = PointCloud(
            points: finalPoints,
            colors: finalColors.isEmpty ? nil : finalColors,
            normals: finalNormals.isEmpty ? nil : finalNormals,
            confidences: finalConfidences.isEmpty ? nil : finalConfidences,
            timestamp: CACurrentMediaTime()
        )

        return ExtractionResult(
            pointCloud: pointCloud,
            stats: ExtractionStats(
                rawPointCount: totalRaw,
                filteredPointCount: totalFiltered,
                finalPointCount: finalPoints.count,
                edgePointCount: totalEdges,
                coverage: totalRaw > 0 ? Float(totalFiltered) / Float(totalRaw) : 0,
                processingTimeMs: processingTime
            )
        )
    }
}
