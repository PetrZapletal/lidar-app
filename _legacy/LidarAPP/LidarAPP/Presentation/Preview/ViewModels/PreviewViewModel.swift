import SwiftUI
import SceneKit
import UIKit

/// ViewModel for the 3D model preview
@MainActor
@Observable
final class PreviewViewModel {

    // MARK: - Visualization Mode

    enum VisualizationMode: String, CaseIterable {
        case solid
        case wireframe
        case points

        var icon: String {
            switch self {
            case .solid: return "cube.fill"
            case .wireframe: return "cube"
            case .points: return "circle.grid.3x3"
            }
        }
    }

    // MARK: - State

    var visualizationMode: VisualizationMode = .solid
    var showStats: Bool = false
    var showExportOptions: Bool = false
    var showARView: Bool = false
    var showMeasurements: Bool = false
    var showShareSheet: Bool = false

    var isLoading: Bool = false
    var errorMessage: String?

    // Camera state
    var cameraDistance: Float = 5.0
    var cameraRotation: simd_float2 = .zero

    // Export state
    var exportProgress: Float = 0
    var exportedFileURL: URL?

    // Screenshot
    var screenshotImage: UIImage?

    // MARK: - Camera Control

    func resetCamera() {
        cameraDistance = 5.0
        cameraRotation = .zero
    }

    func zoomIn() {
        cameraDistance = max(0.5, cameraDistance - 0.5)
    }

    func zoomOut() {
        cameraDistance = min(20, cameraDistance + 0.5)
    }

    // MARK: - Export

    func exportModel(format: ExportFormat) {
        Task {
            isLoading = true
            exportProgress = 0

            do {
                // Simulate export progress
                for i in 1...10 {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    exportProgress = Float(i) / 10.0
                }

                // Create export URL
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let fileName = "export_\(Date().timeIntervalSince1970).\(format.rawValue)"
                exportedFileURL = documentsURL.appendingPathComponent(fileName)

                showShareSheet = true
            } catch {
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }
    }

    // MARK: - Screenshot

    func captureScreenshot() {
        // This would be implemented with access to the SCNView
        // For now, it's a placeholder
    }

    func saveScreenshot(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    // MARK: - Model Info

    struct ModelInfo {
        let vertexCount: Int
        let faceCount: Int
        let boundingBox: BoundingBox?
        let fileSize: Int64?
    }

    func getModelInfo(from url: URL) -> ModelInfo? {
        guard let scene = try? SCNScene(url: url) else {
            return nil
        }

        var totalVertices = 0
        var totalFaces = 0
        var minPoint = simd_float3(repeating: .greatestFiniteMagnitude)
        var maxPoint = simd_float3(repeating: -.greatestFiniteMagnitude)

        scene.rootNode.enumerateChildNodes { node, _ in
            if let geometry = node.geometry {
                for source in geometry.sources where source.semantic == .vertex {
                    totalVertices += source.vectorCount
                }

                for element in geometry.elements {
                    totalFaces += element.primitiveCount
                }

                // Update bounding box
                let (localMin, localMax) = node.boundingBox
                let worldMin = node.convertPosition(localMin, to: nil)
                let worldMax = node.convertPosition(localMax, to: nil)

                minPoint = simd_min(minPoint, simd_float3(Float(worldMin.x), Float(worldMin.y), Float(worldMin.z)))
                maxPoint = simd_max(maxPoint, simd_float3(Float(worldMax.x), Float(worldMax.y), Float(worldMax.z)))
            }
        }

        let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64

        return ModelInfo(
            vertexCount: totalVertices,
            faceCount: totalFaces,
            boundingBox: BoundingBox(min: minPoint, max: maxPoint),
            fileSize: fileSize
        )
    }
}

// MARK: - Scene Statistics

extension PreviewViewModel {

    struct SceneStatistics {
        let vertexCount: Int
        let triangleCount: Int
        let materialCount: Int
        let textureCount: Int
        let nodeCount: Int
        let fps: Double
    }

    func getSceneStatistics(from scnView: SCNView) -> SceneStatistics? {
        guard let scene = scnView.scene else { return nil }

        var vertices = 0
        var triangles = 0
        var materials = 0
        var textures = 0
        var nodes = 0

        scene.rootNode.enumerateChildNodes { node, _ in
            nodes += 1

            if let geometry = node.geometry {
                for source in geometry.sources where source.semantic == .vertex {
                    vertices += source.vectorCount
                }

                for element in geometry.elements {
                    triangles += element.primitiveCount
                }

                materials += geometry.materials.count

                for material in geometry.materials {
                    if material.diffuse.contents is UIImage { textures += 1 }
                    if material.normal.contents is UIImage { textures += 1 }
                    if material.specular.contents is UIImage { textures += 1 }
                }
            }
        }

        return SceneStatistics(
            vertexCount: vertices,
            triangleCount: triangles,
            materialCount: materials,
            textureCount: textures,
            nodeCount: nodes,
            fps: scnView.preferredFramesPerSecond == 0 ? 60 : Double(scnView.preferredFramesPerSecond)
        )
    }
}
