import Foundation
import simd
import UIKit
import CoreImage
import Accelerate

/// Service for projecting camera textures onto mesh geometry
@MainActor
final class TextureMappingService {

    // MARK: - Types

    struct TexturedMesh {
        let vertices: [simd_float3]
        let normals: [simd_float3]
        let uvCoordinates: [simd_float2]
        let faces: [simd_uint3]
        let textureAtlas: UIImage?
        let materialProperties: MaterialProperties
    }

    struct MaterialProperties {
        var diffuseColor: simd_float3 = simd_float3(0.8, 0.8, 0.8)
        var roughness: Float = 0.5
        var metallic: Float = 0.0
        var ambientOcclusion: Float = 1.0
    }

    struct ProjectionResult {
        let uvCoordinate: simd_float2
        let confidence: Float
        let frameIndex: Int
        let isVisible: Bool
    }

    // MARK: - Properties

    private let ciContext = CIContext()

    // MARK: - Main API

    /// Generate UV coordinates for mesh vertices based on camera frames
    func generateUVCoordinates(
        mesh: MeshData,
        textureFrames: [TextureFrame],
        method: UVMappingMethod = .multiViewProjection
    ) async -> [simd_float2] {

        switch method {
        case .multiViewProjection:
            return await projectFromMultipleViews(mesh: mesh, frames: textureFrames)
        case .boxProjection:
            return generateBoxProjection(vertices: mesh.vertices, normals: mesh.normals)
        case .sphericalProjection:
            return generateSphericalProjection(vertices: mesh.vertices)
        case .planarProjection(let axis):
            return generatePlanarProjection(vertices: mesh.vertices, axis: axis)
        }
    }

    /// Create textured mesh with atlas from multiple camera frames
    func createTexturedMesh(
        mesh: MeshData,
        textureFrames: [TextureFrame],
        atlasSize: Int = 2048
    ) async -> TexturedMesh {

        // 1. Generate UV coordinates from best views
        let uvCoordinates = await generateUVCoordinates(
            mesh: mesh,
            textureFrames: textureFrames
        )

        // 2. Create texture atlas from frames
        let atlas = await createTextureAtlas(
            frames: textureFrames,
            atlasSize: atlasSize
        )

        // 3. Estimate material properties from images
        let materials = estimateMaterialProperties(from: textureFrames)

        return TexturedMesh(
            vertices: mesh.vertices,
            normals: mesh.normals,
            uvCoordinates: uvCoordinates,
            faces: mesh.faces,
            textureAtlas: atlas,
            materialProperties: materials
        )
    }

    // MARK: - UV Projection Methods

    private func projectFromMultipleViews(
        mesh: MeshData,
        frames: [TextureFrame]
    ) async -> [simd_float2] {

        var uvCoordinates: [simd_float2] = []
        uvCoordinates.reserveCapacity(mesh.vertices.count)

        for (vertexIndex, vertex) in mesh.vertices.enumerated() {
            let normal = vertexIndex < mesh.normals.count ? mesh.normals[vertexIndex] : simd_float3(0, 1, 0)

            // Find best frame for this vertex (best view angle)
            var bestProjection: ProjectionResult?

            for (frameIndex, frame) in frames.enumerated() {
                if let projection = projectVertexToFrame(
                    vertex: vertex,
                    normal: normal,
                    frame: frame,
                    frameIndex: frameIndex
                ), projection.isVisible {
                    if bestProjection == nil || projection.confidence > bestProjection!.confidence {
                        bestProjection = projection
                    }
                }
            }

            // Use best projection or fallback to spherical
            if let projection = bestProjection {
                uvCoordinates.append(projection.uvCoordinate)
            } else {
                // Fallback to spherical projection
                let sphericalUV = vertexToSphericalUV(vertex)
                uvCoordinates.append(sphericalUV)
            }
        }

        return uvCoordinates
    }

    private func projectVertexToFrame(
        vertex: simd_float3,
        normal: simd_float3,
        frame: TextureFrame,
        frameIndex: Int
    ) -> ProjectionResult? {

        // Transform vertex to camera space
        let worldToCamera = frame.cameraTransform.inverse
        let vertexHomogeneous = simd_float4(vertex.x, vertex.y, vertex.z, 1.0)
        let cameraSpaceVertex = worldToCamera * vertexHomogeneous

        // Check if vertex is in front of camera
        guard cameraSpaceVertex.z < 0 else { return nil } // Camera looks at -Z

        // Get camera position for view angle calculation
        let cameraPosition = simd_float3(
            frame.cameraTransform.columns.3.x,
            frame.cameraTransform.columns.3.y,
            frame.cameraTransform.columns.3.z
        )

        // Calculate view direction
        let viewDirection = simd_normalize(cameraPosition - vertex)

        // Check if surface faces camera (dot product with normal)
        let viewAngle = simd_dot(normal, viewDirection)
        guard viewAngle > 0.1 else { return nil } // Surface must face camera

        // Project to 2D using intrinsics
        let intrinsics = frame.intrinsics
        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        let cx = intrinsics.columns.2.x
        let cy = intrinsics.columns.2.y

        let x = -cameraSpaceVertex.x / cameraSpaceVertex.z
        let y = -cameraSpaceVertex.y / cameraSpaceVertex.z

        let pixelX = fx * x + cx
        let pixelY = fy * y + cy

        // Normalize to UV coordinates (0-1)
        let u = pixelX / Float(frame.resolution.width)
        let v = pixelY / Float(frame.resolution.height)

        // Check if within frame bounds
        guard u >= 0 && u <= 1 && v >= 0 && v <= 1 else { return nil }

        // Calculate confidence based on view angle and distance from center
        let distanceFromCenter = sqrt(pow(u - 0.5, 2) + pow(v - 0.5, 2))
        let centerConfidence = max(0, 1 - distanceFromCenter * 2)
        let confidence = viewAngle * centerConfidence

        return ProjectionResult(
            uvCoordinate: simd_float2(u, v),
            confidence: confidence,
            frameIndex: frameIndex,
            isVisible: true
        )
    }

    private func generateBoxProjection(
        vertices: [simd_float3],
        normals: [simd_float3]
    ) -> [simd_float2] {

        var uvCoordinates: [simd_float2] = []

        for (index, vertex) in vertices.enumerated() {
            let normal = index < normals.count ? normals[index] : simd_float3(0, 1, 0)
            let absNormal = simd_abs(normal)

            var u: Float
            var v: Float

            // Project based on dominant normal axis
            if absNormal.x >= absNormal.y && absNormal.x >= absNormal.z {
                // Project on YZ plane
                u = (vertex.z + 5) / 10.0
                v = (vertex.y + 5) / 10.0
            } else if absNormal.y >= absNormal.x && absNormal.y >= absNormal.z {
                // Project on XZ plane
                u = (vertex.x + 5) / 10.0
                v = (vertex.z + 5) / 10.0
            } else {
                // Project on XY plane
                u = (vertex.x + 5) / 10.0
                v = (vertex.y + 5) / 10.0
            }

            uvCoordinates.append(simd_float2(u.clamped(to: 0...1), v.clamped(to: 0...1)))
        }

        return uvCoordinates
    }

    private func generateSphericalProjection(vertices: [simd_float3]) -> [simd_float2] {
        return vertices.map { vertexToSphericalUV($0) }
    }

    private func generatePlanarProjection(
        vertices: [simd_float3],
        axis: ProjectionAxis
    ) -> [simd_float2] {

        // Calculate bounding box
        var minBound = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBound = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)

        for vertex in vertices {
            minBound = simd_min(minBound, vertex)
            maxBound = simd_max(maxBound, vertex)
        }

        let size = maxBound - minBound

        return vertices.map { vertex in
            let normalized = (vertex - minBound) / size

            switch axis {
            case .x: return simd_float2(normalized.y, normalized.z)
            case .y: return simd_float2(normalized.x, normalized.z)
            case .z: return simd_float2(normalized.x, normalized.y)
            }
        }
    }

    private func vertexToSphericalUV(_ vertex: simd_float3) -> simd_float2 {
        let normalized = simd_normalize(vertex)
        let u = 0.5 + atan2(normalized.z, normalized.x) / (2 * Float.pi)
        let v = 0.5 - asin(normalized.y) / Float.pi
        return simd_float2(u, v)
    }

    // MARK: - Texture Atlas

    private func createTextureAtlas(
        frames: [TextureFrame],
        atlasSize: Int
    ) async -> UIImage? {

        guard !frames.isEmpty else { return nil }

        // Select best frames (max 16 for atlas)
        let selectedFrames = selectBestFrames(frames, maxCount: 16)

        // Calculate grid layout
        let gridSize = Int(ceil(sqrt(Double(selectedFrames.count))))
        let cellSize = atlasSize / gridSize

        // Create atlas
        UIGraphicsBeginImageContextWithOptions(
            CGSize(width: atlasSize, height: atlasSize),
            false,
            1.0
        )

        defer { UIGraphicsEndImageContext() }

        for (index, frame) in selectedFrames.enumerated() {
            let row = index / gridSize
            let col = index % gridSize

            if let image = UIImage(data: frame.imageData) {
                let rect = CGRect(
                    x: col * cellSize,
                    y: row * cellSize,
                    width: cellSize,
                    height: cellSize
                )
                image.draw(in: rect)
            }
        }

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    private func selectBestFrames(_ frames: [TextureFrame], maxCount: Int) -> [TextureFrame] {
        // Sort by quality (exposure, ISO) and select diverse viewpoints
        let sorted = frames.sorted { frame1, frame2 in
            // Prefer lower ISO (less noise)
            let iso1 = frame1.iso ?? 100
            let iso2 = frame2.iso ?? 100
            return iso1 < iso2
        }

        // Take evenly distributed frames
        let step = max(1, sorted.count / maxCount)
        var selected: [TextureFrame] = []

        for i in stride(from: 0, to: sorted.count, by: step) {
            if selected.count < maxCount {
                selected.append(sorted[i])
            }
        }

        return selected
    }

    // MARK: - Material Estimation

    private func estimateMaterialProperties(from frames: [TextureFrame]) -> MaterialProperties {
        var properties = MaterialProperties()

        guard let firstFrame = frames.first,
              let image = UIImage(data: firstFrame.imageData),
              let cgImage = image.cgImage else {
            return properties
        }

        // Analyze image for rough material estimation
        let ciImage = CIImage(cgImage: cgImage)

        // Calculate average color
        if let avgColor = getAverageColor(from: ciImage) {
            properties.diffuseColor = simd_float3(
                Float(avgColor.red),
                Float(avgColor.green),
                Float(avgColor.blue)
            )
        }

        // Estimate roughness from image variance (high variance = rough surface)
        let variance = calculateImageVariance(ciImage)
        properties.roughness = Float(min(1.0, variance / 50.0))

        return properties
    }

    private func getAverageColor(from image: CIImage) -> (red: Double, green: Double, blue: Double)? {
        let extentVector = CIVector(
            x: image.extent.origin.x,
            y: image.extent.origin.y,
            z: image.extent.size.width,
            w: image.extent.size.height
        )

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: extentVector
        ]),
              let outputImage = filter.outputImage else {
            return nil
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return (
            red: Double(bitmap[0]) / 255.0,
            green: Double(bitmap[1]) / 255.0,
            blue: Double(bitmap[2]) / 255.0
        )
    }

    private func calculateImageVariance(_ image: CIImage) -> Double {
        // Simplified variance calculation
        return 25.0 // Default medium roughness
    }
}

// MARK: - Supporting Types

enum UVMappingMethod {
    case multiViewProjection
    case boxProjection
    case sphericalProjection
    case planarProjection(axis: ProjectionAxis)
}

enum ProjectionAxis {
    case x, y, z
}

// MARK: - Extensions

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension simd_float4x4 {
    var inverse: simd_float4x4 {
        return simd_inverse(self)
    }
}
