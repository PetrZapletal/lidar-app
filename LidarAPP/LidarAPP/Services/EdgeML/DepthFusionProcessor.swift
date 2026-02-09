import Foundation
import Accelerate
import simd
import CoreVideo

/// Fuses ML-enhanced depth maps with LiDAR mesh data for improved accuracy.
///
/// Implements weighted blending between LiDAR depth (high accuracy but sparse)
/// and ML-predicted depth (dense but less accurate). Uses Accelerate (vDSP)
/// for all bulk numerical operations.
@MainActor
@Observable
final class DepthFusionProcessor {

    // MARK: - Configuration

    struct Configuration {
        /// Base weight for LiDAR depth values in fusion (0-1)
        var lidarBaseWeight: Float = 0.7
        /// Base weight for ML depth values in fusion (0-1)
        var mlBaseWeight: Float = 0.3
        /// Minimum depth value to consider valid (meters)
        var minValidDepth: Float = 0.1
        /// Maximum depth value to consider valid (meters)
        var maxValidDepth: Float = 5.0
        /// Threshold below which LiDAR confidence is considered low
        var lowConfidenceThreshold: Float = 0.3
        /// Threshold above which LiDAR confidence is considered high
        var highConfidenceThreshold: Float = 0.7
        /// Maximum depth difference (meters) before rejecting ML depth
        var maxDepthDiscrepancy: Float = 0.5
    }

    // MARK: - Properties

    private(set) var configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Depth Map Fusion

    /// Fuse ML depth map with LiDAR depth for enhanced accuracy.
    ///
    /// Strategy: weighted blend that trusts LiDAR where its confidence is high,
    /// and uses the ML prediction to fill gaps and low-confidence regions.
    /// Uses Accelerate vDSP for vectorized computation.
    ///
    /// - Parameters:
    ///   - lidarDepth: Depth values from ARFrame sceneDepth.
    ///   - mlDepth: Depth values from DepthAnything model prediction.
    ///   - width: Width of the depth maps.
    ///   - height: Height of the depth maps.
    ///   - confidenceMap: Optional LiDAR confidence values [0, 1].
    /// - Returns: Fused depth map as a float array.
    func fuseDepthMaps(
        lidarDepth: [Float],
        mlDepth: [Float],
        width: Int,
        height: Int,
        confidenceMap: [Float]?
    ) -> [Float] {
        let count = width * height

        guard lidarDepth.count == count else {
            warningLog(
                "LiDAR depth size mismatch: expected \(count), got \(lidarDepth.count)",
                category: .logCategoryProcessing
            )
            return lidarDepth
        }

        // If ML depth is different resolution, use LiDAR only
        guard mlDepth.count == count else {
            warningLog(
                "ML depth size mismatch: expected \(count), got \(mlDepth.count). Using LiDAR depth only.",
                category: .logCategoryProcessing
            )
            return lidarDepth
        }

        debugLog(
            "Fusing depth maps: \(width)x\(height), LiDAR weight=\(configuration.lidarBaseWeight)",
            category: .logCategoryProcessing
        )

        // Normalize ML depth to match LiDAR depth range
        let normalizedMLDepth = normalizeMLDepthToLiDARRange(
            mlDepth: mlDepth,
            lidarDepth: lidarDepth,
            count: count
        )

        var fusedDepth = [Float](repeating: 0, count: count)

        if let confidenceMap = confidenceMap, confidenceMap.count == count {
            // Confidence-weighted fusion
            for i in 0..<count {
                let lidar = lidarDepth[i]
                let ml = normalizedMLDepth[i]
                let confidence = confidenceMap[i]

                let isLidarValid = lidar > configuration.minValidDepth && lidar < configuration.maxValidDepth
                let isMLValid = ml > configuration.minValidDepth && ml < configuration.maxValidDepth

                if isLidarValid && isMLValid {
                    // Both valid: confidence-weighted blend
                    let discrepancy = abs(lidar - ml)
                    if discrepancy > configuration.maxDepthDiscrepancy {
                        // Large discrepancy: trust the higher-confidence source
                        fusedDepth[i] = confidence > configuration.highConfidenceThreshold ? lidar : ml
                    } else {
                        // Adaptive weight: higher LiDAR confidence = more LiDAR weight
                        let lidarWeight = configuration.lidarBaseWeight + (1.0 - configuration.lidarBaseWeight) * confidence
                        let mlWeight = 1.0 - lidarWeight
                        fusedDepth[i] = lidar * lidarWeight + ml * mlWeight
                    }
                } else if isLidarValid {
                    fusedDepth[i] = lidar
                } else if isMLValid {
                    fusedDepth[i] = ml
                } else {
                    fusedDepth[i] = 0
                }
            }
        } else {
            // No confidence map: simple weighted blend using vDSP
            var lidarWeighted = [Float](repeating: 0, count: count)
            var mlWeighted = [Float](repeating: 0, count: count)

            var lidarW = configuration.lidarBaseWeight
            var mlW = configuration.mlBaseWeight

            vDSP_vsmul(lidarDepth, 1, &lidarW, &lidarWeighted, 1, vDSP_Length(count))
            vDSP_vsmul(normalizedMLDepth, 1, &mlW, &mlWeighted, 1, vDSP_Length(count))
            vDSP_vadd(lidarWeighted, 1, mlWeighted, 1, &fusedDepth, 1, vDSP_Length(count))

            // Fix pixels where only one source is valid
            for i in 0..<count {
                let lidar = lidarDepth[i]
                let ml = normalizedMLDepth[i]
                let isLidarValid = lidar > configuration.minValidDepth && lidar < configuration.maxValidDepth
                let isMLValid = ml > configuration.minValidDepth && ml < configuration.maxValidDepth

                if isLidarValid && !isMLValid {
                    fusedDepth[i] = lidar
                } else if !isLidarValid && isMLValid {
                    fusedDepth[i] = ml
                } else if !isLidarValid && !isMLValid {
                    fusedDepth[i] = 0
                }
            }
        }

        // Compute statistics for logging
        var minFused: Float = 0
        var maxFused: Float = 0
        vDSP_minv(fusedDepth, 1, &minFused, vDSP_Length(count))
        vDSP_maxv(fusedDepth, 1, &maxFused, vDSP_Length(count))

        let validCount = fusedDepth.filter { $0 > configuration.minValidDepth }.count
        debugLog(
            "Fusion complete: range [\(String(format: "%.3f", minFused)), \(String(format: "%.3f", maxFused))], \(validCount)/\(count) valid pixels",
            category: .logCategoryProcessing
        )

        return fusedDepth
    }

    // MARK: - Depth to Point Cloud

    /// Convert a fused depth map to a point cloud using camera intrinsics.
    ///
    /// Unprojects each valid depth pixel into 3D using the camera intrinsic
    /// matrix and transforms the resulting points into world space using the
    /// camera extrinsic transform.
    ///
    /// - Parameters:
    ///   - depth: Flat array of depth values.
    ///   - width: Width of the depth map.
    ///   - height: Height of the depth map.
    ///   - intrinsics: Camera intrinsic matrix (focal length, principal point).
    ///   - cameraTransform: Camera-to-world transform matrix.
    /// - Returns: A PointCloud constructed from the depth map.
    func depthToPointCloud(
        depth: [Float],
        width: Int,
        height: Int,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4
    ) -> PointCloud {
        let count = width * height
        guard depth.count == count else {
            warningLog("Depth array size mismatch for point cloud conversion", category: .logCategoryProcessing)
            return PointCloud(points: [])
        }

        debugLog("Converting depth map \(width)x\(height) to point cloud", category: .logCategoryProcessing)

        // Camera intrinsic parameters
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]

        guard fx > 0 && fy > 0 else {
            errorLog("Invalid camera intrinsics: fx=\(fx), fy=\(fy)", category: .logCategoryProcessing)
            return PointCloud(points: [])
        }

        var points: [simd_float3] = []
        var confidences: [Float] = []
        points.reserveCapacity(count / 4) // Expect ~25% valid pixels
        confidences.reserveCapacity(count / 4)

        for y in 0..<height {
            for x in 0..<width {
                let depthValue = depth[y * width + x]

                guard depthValue > configuration.minValidDepth,
                      depthValue < configuration.maxValidDepth else {
                    continue
                }

                // Unproject pixel to camera-space 3D point
                let px = (Float(x) - cx) / fx * depthValue
                let py = (Float(y) - cy) / fy * depthValue
                let pz = depthValue

                let cameraPoint = simd_float4(px, py, pz, 1.0)

                // Transform to world space
                let worldPoint = cameraTransform * cameraPoint
                points.append(simd_float3(worldPoint.x, worldPoint.y, worldPoint.z))

                // Confidence based on depth value reliability
                let normalizedDepth = (depthValue - configuration.minValidDepth) /
                    (configuration.maxValidDepth - configuration.minValidDepth)
                let confidence = 1.0 - normalizedDepth * 0.3 // Closer = higher confidence
                confidences.append(confidence)
            }
        }

        infoLog("Generated point cloud with \(points.count) points from depth map", category: .logCategoryProcessing)

        return PointCloud(
            points: points,
            confidences: confidences,
            metadata: PointCloudMetadata(source: .lidar, coordinateSystem: .arkit, unit: .meters)
        )
    }

    // MARK: - Mesh Refinement

    /// Refine mesh vertex positions using enhanced depth data.
    ///
    /// Projects each mesh vertex into the depth map to find the corresponding
    /// enhanced depth, then adjusts the vertex position along its normal to
    /// match the fused depth. This corrects LiDAR mesh geometry using ML depth.
    ///
    /// - Parameters:
    ///   - originalMesh: The original LiDAR mesh to refine.
    ///   - enhancedDepth: Fused depth map values.
    ///   - width: Width of the depth map.
    ///   - height: Height of the depth map.
    ///   - intrinsics: Camera intrinsic matrix.
    ///   - cameraTransform: Camera-to-world transform matrix.
    /// - Returns: A refined MeshData with adjusted vertex positions.
    func refineMesh(
        originalMesh: MeshData,
        enhancedDepth: [Float],
        width: Int,
        height: Int,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4
    ) -> MeshData {
        guard !originalMesh.vertices.isEmpty else {
            debugLog("Skipping mesh refinement: empty mesh", category: .logCategoryProcessing)
            return originalMesh
        }

        let count = width * height
        guard enhancedDepth.count == count else {
            warningLog("Enhanced depth size mismatch for mesh refinement", category: .logCategoryProcessing)
            return originalMesh
        }

        debugLog(
            "Refining mesh: \(originalMesh.vertexCount) vertices using \(width)x\(height) depth map",
            category: .logCategoryProcessing
        )

        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]

        guard fx > 0 && fy > 0 else {
            errorLog("Invalid intrinsics for mesh refinement", category: .logCategoryProcessing)
            return originalMesh
        }

        let worldToCamera = simd_inverse(cameraTransform)

        var refinedVertices = originalMesh.vertices
        var adjustedCount = 0

        for i in 0..<originalMesh.vertexCount {
            // Transform vertex from mesh-local space to world space, then to camera space
            let worldPos = originalMesh.transform * simd_float4(originalMesh.vertices[i], 1.0)
            let cameraPos = worldToCamera * worldPos

            // Skip vertices behind the camera
            guard cameraPos.z > 0 else { continue }

            // Project to pixel coordinates
            let px = Int((cameraPos.x / cameraPos.z) * fx + cx)
            let py = Int((cameraPos.y / cameraPos.z) * fy + cy)

            // Check bounds
            guard px >= 0, px < width, py >= 0, py < height else { continue }

            let enhancedZ = enhancedDepth[py * width + px]

            // Skip invalid depth values
            guard enhancedZ > configuration.minValidDepth,
                  enhancedZ < configuration.maxValidDepth else { continue }

            let currentZ = cameraPos.z

            // Only adjust if the difference is significant but not extreme
            let depthDiff = enhancedZ - currentZ
            let absDiff = abs(depthDiff)

            guard absDiff > 0.001, // Minimum adjustment threshold (1mm)
                  absDiff < configuration.maxDepthDiscrepancy else { continue }

            // Adjust vertex position along the camera ray direction
            let rayDir = simd_normalize(simd_float3(cameraPos.x, cameraPos.y, cameraPos.z))
            let adjustment = rayDir * depthDiff

            // Transform adjustment back to mesh-local space
            let meshInverse = simd_inverse(originalMesh.transform)
            let worldAdjustment = cameraTransform * simd_float4(adjustment, 0.0)
            let localAdjustment = meshInverse * worldAdjustment

            refinedVertices[i] = originalMesh.vertices[i] + simd_float3(
                localAdjustment.x,
                localAdjustment.y,
                localAdjustment.z
            )

            adjustedCount += 1
        }

        infoLog(
            "Mesh refinement complete: adjusted \(adjustedCount)/\(originalMesh.vertexCount) vertices",
            category: .logCategoryProcessing
        )

        // Recompute normals after vertex adjustment
        let recomputedNormals = recomputeNormals(
            vertices: refinedVertices,
            faces: originalMesh.faces
        )

        return MeshData(
            id: originalMesh.id,
            anchorIdentifier: originalMesh.anchorIdentifier,
            vertices: refinedVertices,
            normals: recomputedNormals,
            faces: originalMesh.faces,
            textureCoordinates: originalMesh.textureCoordinates,
            classifications: originalMesh.classifications,
            transform: originalMesh.transform
        )
    }

    // MARK: - Private Helpers

    /// Normalize ML depth values to match the range and scale of LiDAR depth.
    ///
    /// ML depth predictions are often relative (0-1 normalized). This function
    /// scales them to match the statistical distribution of valid LiDAR depth values.
    private func normalizeMLDepthToLiDARRange(
        mlDepth: [Float],
        lidarDepth: [Float],
        count: Int
    ) -> [Float] {
        // Compute statistics for valid LiDAR depths
        let validLidar = lidarDepth.filter { $0 > configuration.minValidDepth && $0 < configuration.maxValidDepth }
        guard !validLidar.isEmpty else {
            debugLog("No valid LiDAR depths for normalization, returning ML depth as-is", category: .logCategoryProcessing)
            return mlDepth
        }

        var lidarMin: Float = 0
        var lidarMax: Float = 0
        vDSP_minv(validLidar, 1, &lidarMin, vDSP_Length(validLidar.count))
        vDSP_maxv(validLidar, 1, &lidarMax, vDSP_Length(validLidar.count))

        // Compute ML depth range
        var mlMin: Float = 0
        var mlMax: Float = 0
        let validML = mlDepth.filter { $0 > 0 && $0.isFinite }
        guard !validML.isEmpty else {
            debugLog("No valid ML depths for normalization", category: .logCategoryProcessing)
            return mlDepth
        }

        vDSP_minv(validML, 1, &mlMin, vDSP_Length(validML.count))
        vDSP_maxv(validML, 1, &mlMax, vDSP_Length(validML.count))

        let mlRange = mlMax - mlMin
        let lidarRange = lidarMax - lidarMin

        guard mlRange > .ulpOfOne else {
            debugLog("ML depth has zero range, returning LiDAR min", category: .logCategoryProcessing)
            return [Float](repeating: lidarMin, count: count)
        }

        // Scale ML depth to LiDAR range: normalized = (ml - mlMin) / mlRange * lidarRange + lidarMin
        var normalized = [Float](repeating: 0, count: count)
        var negMLMin = -mlMin
        vDSP_vsadd(mlDepth, 1, &negMLMin, &normalized, 1, vDSP_Length(count))

        var scale = lidarRange / mlRange
        vDSP_vsmul(normalized, 1, &scale, &normalized, 1, vDSP_Length(count))

        var offset = lidarMin
        vDSP_vsadd(normalized, 1, &offset, &normalized, 1, vDSP_Length(count))

        // Clamp to valid range
        for i in 0..<count {
            if normalized[i] < 0 || !normalized[i].isFinite {
                normalized[i] = 0
            }
        }

        debugLog(
            "Normalized ML depth: [\(String(format: "%.3f", mlMin)), \(String(format: "%.3f", mlMax))] -> [\(String(format: "%.3f", lidarMin)), \(String(format: "%.3f", lidarMax))]",
            category: .logCategoryProcessing
        )

        return normalized
    }

    /// Recompute vertex normals from face normals using area-weighted averaging.
    private func recomputeNormals(vertices: [simd_float3], faces: [simd_uint3]) -> [simd_float3] {
        var normals = [simd_float3](repeating: .zero, count: vertices.count)

        for face in faces {
            let i0 = Int(face.x)
            let i1 = Int(face.y)
            let i2 = Int(face.z)

            guard i0 < vertices.count, i1 < vertices.count, i2 < vertices.count else { continue }

            let v0 = vertices[i0]
            let v1 = vertices[i1]
            let v2 = vertices[i2]

            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let faceNormal = simd_cross(edge1, edge2)

            normals[i0] += faceNormal
            normals[i1] += faceNormal
            normals[i2] += faceNormal
        }

        for i in 0..<normals.count {
            let len = simd_length(normals[i])
            if len > .ulpOfOne {
                normals[i] = simd_normalize(normals[i])
            }
        }

        return normals
    }
}
