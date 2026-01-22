import ARKit
import simd
import Accelerate

/// Extracts point clouds from ARKit depth data
final class PointCloudExtractor: Sendable {

    // MARK: - Configuration

    struct Configuration: Sendable {
        var maxPoints: Int = 500_000
        var minConfidence: Float = 0.5
        var voxelSize: Float = 0.01  // 1cm voxel for downsampling
        var minDepth: Float = 0.1    // 10cm minimum
        var maxDepth: Float = 5.0    // 5m maximum
        var downsampleStride: Int = 2
    }

    private let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Extract from Depth Map

    /// Extract point cloud from AR frame depth data
    func extractPointCloud(from frame: ARFrame) -> PointCloud? {
        // Prefer smoothed depth for better quality
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else {
            return nil
        }

        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap

        return extractPointCloud(
            depthMap: depthMap,
            confidenceMap: confidenceMap,
            camera: frame.camera
        )
    }

    /// Extract point cloud from depth and confidence maps
    func extractPointCloud(
        depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer?,
        camera: ARCamera
    ) -> PointCloud {
        let intrinsics = camera.intrinsics
        let resolution = camera.imageResolution
        let cameraTransform = camera.transform

        // Lock buffers
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let depthData = CVPixelBufferGetBaseAddress(depthMap)!
            .assumingMemoryBound(to: Float32.self)

        // Optional confidence
        var confidenceData: UnsafeMutablePointer<UInt8>?
        if let confidenceMap = confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
            confidenceData = CVPixelBufferGetBaseAddress(confidenceMap)?
                .assumingMemoryBound(to: UInt8.self)
        }
        defer {
            if let confidenceMap = confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
        }

        var points: [simd_float3] = []
        var confidences: [Float] = []

        // Camera intrinsics
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]

        // Scale factors (depth map may have different resolution)
        let scaleX = Float(depthWidth) / Float(resolution.width)
        let scaleY = Float(depthHeight) / Float(resolution.height)

        // Stride for downsampling
        let downsampleStep = configuration.downsampleStride

        for y in Swift.stride(from: 0, to: depthHeight, by: downsampleStep) {
            for x in Swift.stride(from: 0, to: depthWidth, by: downsampleStep) {
                let index = y * depthWidth + x
                let depth = depthData[index]

                // Filter invalid depths
                guard depth > configuration.minDepth && depth < configuration.maxDepth else { continue }

                // Check confidence if available
                var confidence: Float = 1.0
                if let conf = confidenceData {
                    confidence = Float(conf[index]) / 2.0  // 0, 1, 2 -> 0, 0.5, 1.0
                    guard confidence >= configuration.minConfidence else { continue }
                }

                // Back-project to 3D camera space
                let imageX = Float(x) / scaleX
                let imageY = Float(y) / scaleY

                let localX = (imageX - cx) * depth / fx
                let localY = (imageY - cy) * depth / fy
                let localZ = depth

                // Transform to world coordinates
                let localPoint = simd_float4(localX, localY, localZ, 1)
                let worldPoint = cameraTransform * localPoint

                points.append(simd_float3(worldPoint.x, worldPoint.y, worldPoint.z))
                confidences.append(confidence)
            }
        }

        // Voxel downsampling if needed
        if points.count > configuration.maxPoints {
            return voxelDownsample(
                points: points,
                confidences: confidences,
                voxelSize: configuration.voxelSize
            )
        }

        return PointCloud(
            points: points,
            confidences: confidences,
            timestamp: CACurrentMediaTime()
        )
    }

    // MARK: - Extract from Mesh Anchors

    /// Extract point cloud from mesh anchor vertices
    func extractPointCloud(from meshAnchors: [ARMeshAnchor]) -> PointCloud {
        var allPoints: [simd_float3] = []

        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let vertices = geometry.vertices
            let vertexCount = vertices.count

            let stride = vertices.stride
            let offset = vertices.offset

            vertices.buffer.contents().withMemoryRebound(to: UInt8.self, capacity: vertices.buffer.length) { pointer in
                for i in 0..<vertexCount {
                    let vertexPointer = pointer.advanced(by: offset + i * stride)
                    let localPoint = vertexPointer.withMemoryRebound(to: simd_float3.self, capacity: 1) { $0.pointee }

                    // Transform to world coordinates
                    let worldPoint = anchor.transform * simd_float4(localPoint, 1)
                    allPoints.append(simd_float3(worldPoint.x, worldPoint.y, worldPoint.z))
                }
            }
        }

        // Voxel downsampling if needed
        if allPoints.count > configuration.maxPoints {
            return voxelDownsample(
                points: allPoints,
                confidences: nil,
                voxelSize: configuration.voxelSize
            )
        }

        return PointCloud(
            points: allPoints,
            timestamp: CACurrentMediaTime()
        )
    }

    // MARK: - Voxel Downsampling

    private func voxelDownsample(
        points: [simd_float3],
        confidences: [Float]?,
        voxelSize: Float
    ) -> PointCloud {
        var voxelMap: [SIMD3<Int>: (points: [simd_float3], confidences: [Float])] = [:]

        for (index, point) in points.enumerated() {
            let voxelIndex = SIMD3<Int>(
                Int(floor(point.x / voxelSize)),
                Int(floor(point.y / voxelSize)),
                Int(floor(point.z / voxelSize))
            )

            if voxelMap[voxelIndex] == nil {
                voxelMap[voxelIndex] = ([], [])
            }

            voxelMap[voxelIndex]?.points.append(point)
            if let confidences = confidences {
                voxelMap[voxelIndex]?.confidences.append(confidences[index])
            }
        }

        // Return centroid of each voxel
        var downsampledPoints: [simd_float3] = []
        var downsampledConfidences: [Float] = []

        for (_, voxelData) in voxelMap {
            let sum = voxelData.points.reduce(simd_float3.zero, +)
            let centroid = sum / Float(voxelData.points.count)
            downsampledPoints.append(centroid)

            if !voxelData.confidences.isEmpty {
                let avgConfidence = voxelData.confidences.reduce(0, +) / Float(voxelData.confidences.count)
                downsampledConfidences.append(avgConfidence)
            }
        }

        return PointCloud(
            points: downsampledPoints,
            confidences: downsampledConfidences.isEmpty ? nil : downsampledConfidences,
            timestamp: CACurrentMediaTime()
        )
    }

    // MARK: - Depth Map Analysis

    struct DepthStatistics {
        let minDepth: Float
        let maxDepth: Float
        let meanDepth: Float
        let validPixelCount: Int
        let totalPixelCount: Int
        let coverage: Float
    }

    func analyzeDepthMap(_ depthMap: CVPixelBuffer) -> DepthStatistics {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let totalCount = width * height

        let depthData = CVPixelBufferGetBaseAddress(depthMap)!
            .assumingMemoryBound(to: Float32.self)

        var minDepth: Float = .greatestFiniteMagnitude
        var maxDepth: Float = 0
        var sum: Float = 0
        var validCount = 0

        for i in 0..<totalCount {
            let depth = depthData[i]
            if depth > 0 && depth < 10 {  // Valid range
                minDepth = min(minDepth, depth)
                maxDepth = max(maxDepth, depth)
                sum += depth
                validCount += 1
            }
        }

        return DepthStatistics(
            minDepth: validCount > 0 ? minDepth : 0,
            maxDepth: maxDepth,
            meanDepth: validCount > 0 ? sum / Float(validCount) : 0,
            validPixelCount: validCount,
            totalPixelCount: totalCount,
            coverage: Float(validCount) / Float(totalCount)
        )
    }
}

// MARK: - Color Extraction

extension PointCloudExtractor {

    /// Extract point cloud with colors from camera image
    func extractColoredPointCloud(
        from frame: ARFrame
    ) -> PointCloud? {
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else {
            return nil
        }

        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap
        let capturedImage = frame.capturedImage
        let camera = frame.camera

        // Lock buffers
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(capturedImage, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(capturedImage, .readOnly)
        }

        if let confidenceMap = confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        }
        defer {
            if let confidenceMap = confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
        }

        let intrinsics = camera.intrinsics
        let cameraTransform = camera.transform

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let depthBuffer = CVPixelBufferGetBaseAddress(depthMap)!
            .assumingMemoryBound(to: Float32.self)

        let imageWidth = CVPixelBufferGetWidth(capturedImage)
        let imageHeight = CVPixelBufferGetHeight(capturedImage)
        let imageBytesPerRow = CVPixelBufferGetBytesPerRow(capturedImage)

        var points: [simd_float3] = []
        var colors: [simd_float4] = []

        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]

        let scaleX = Float(depthWidth) / Float(imageWidth)
        let scaleY = Float(depthHeight) / Float(imageHeight)

        let downsampleStep = configuration.downsampleStride

        for y in Swift.stride(from: 0, to: depthHeight, by: downsampleStep) {
            for x in Swift.stride(from: 0, to: depthWidth, by: downsampleStep) {
                let index = y * depthWidth + x
                let depth = depthBuffer[index]

                guard depth > configuration.minDepth && depth < configuration.maxDepth else { continue }

                // Get image coordinates
                let imageX = Int(Float(x) / scaleX)
                let imageY = Int(Float(y) / scaleY)

                // Back-project to world space
                let localX = (Float(x) / scaleX - cx) * depth / fx
                let localY = (Float(y) / scaleY - cy) * depth / fy
                let localZ = depth

                let localPoint = simd_float4(localX, localY, localZ, 1)
                let worldPoint = cameraTransform * localPoint

                points.append(simd_float3(worldPoint.x, worldPoint.y, worldPoint.z))

                // Sample color from image (assuming BGRA format)
                if let baseAddress = CVPixelBufferGetBaseAddress(capturedImage) {
                    let pixelOffset = imageY * imageBytesPerRow + imageX * 4
                    let pixel = baseAddress.advanced(by: pixelOffset).assumingMemoryBound(to: UInt8.self)
                    let b = Float(pixel[0]) / 255.0
                    let g = Float(pixel[1]) / 255.0
                    let r = Float(pixel[2]) / 255.0
                    colors.append(simd_float4(r, g, b, 1.0))
                }
            }
        }

        return PointCloud(
            points: points,
            colors: colors,
            timestamp: frame.timestamp
        )
    }
}
