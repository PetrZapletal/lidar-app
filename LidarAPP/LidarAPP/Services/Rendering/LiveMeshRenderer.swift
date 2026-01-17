import RealityKit
import ARKit
import simd
import Combine

/// RealityKit-based live mesh renderer for AR visualization
@MainActor
final class LiveMeshRenderer {

    // MARK: - Configuration

    struct Configuration {
        var showWireframe: Bool = false
        var meshOpacity: Float = 0.7
        var meshColor: simd_float4 = simd_float4(0.3, 0.6, 1.0, 1.0)
        var wireframeColor: simd_float4 = simd_float4(1, 1, 1, 0.5)
        var enableOcclusion: Bool = true
        var updateThrottleMs: Int = 100
        var simplificationLevel: SimplificationLevel = .medium

        enum SimplificationLevel: Float {
            case none = 1.0
            case low = 0.75
            case medium = 0.5
            case high = 0.25
        }
    }

    // MARK: - Mesh Entity

    private struct MeshEntityInfo {
        let entity: ModelEntity
        let anchorIdentifier: UUID
        var lastUpdate: Date
    }

    // MARK: - Properties

    private weak var arView: ARView?
    private var rootAnchor: AnchorEntity?
    private var meshEntities: [UUID: MeshEntityInfo] = [:]
    private var configuration: Configuration

    private var lastUpdateTime: Date = .distantPast
    private var pendingUpdates: Set<UUID> = []

    // Materials
    private var meshMaterial: SimpleMaterial?
    private var wireframeMaterial: SimpleMaterial?
    private var occlusionMaterial: OcclusionMaterial?

    // MARK: - Initialization

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        setupMaterials()
    }

    // MARK: - Setup

    func attach(to arView: ARView) {
        self.arView = arView

        // Create root anchor for all mesh entities
        let anchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(anchor)
        rootAnchor = anchor
    }

    func detach() {
        rootAnchor?.removeFromParent()
        rootAnchor = nil
        meshEntities.removeAll()
        arView = nil
    }

    private func setupMaterials() {
        // Main mesh material
        var material = SimpleMaterial()
        material.color = .init(
            tint: UIColor(
                red: CGFloat(configuration.meshColor.x),
                green: CGFloat(configuration.meshColor.y),
                blue: CGFloat(configuration.meshColor.z),
                alpha: CGFloat(configuration.meshOpacity)
            ),
            texture: nil
        )
        material.metallic = .init(floatLiteral: 0.1)
        material.roughness = .init(floatLiteral: 0.8)
        meshMaterial = material

        // Wireframe material (using unlit for visibility)
        var wireMaterial = SimpleMaterial()
        wireMaterial.color = .init(
            tint: UIColor(
                red: CGFloat(configuration.wireframeColor.x),
                green: CGFloat(configuration.wireframeColor.y),
                blue: CGFloat(configuration.wireframeColor.z),
                alpha: CGFloat(configuration.wireframeColor.w)
            ),
            texture: nil
        )
        wireframeMaterial = wireMaterial

        // Occlusion material
        occlusionMaterial = OcclusionMaterial()
    }

    // MARK: - Mesh Updates

    func updateMesh(from anchor: ARMeshAnchor) {
        let identifier = anchor.identifier
        let now = Date()

        // Throttle updates
        if now.timeIntervalSince(lastUpdateTime) < Double(configuration.updateThrottleMs) / 1000.0 {
            pendingUpdates.insert(identifier)
            return
        }

        lastUpdateTime = now
        pendingUpdates.remove(identifier)

        Task {
            await performMeshUpdate(anchor: anchor)
        }
    }

    private func performMeshUpdate(anchor: ARMeshAnchor) async {
        guard let rootAnchor = rootAnchor else { return }

        let identifier = anchor.identifier
        let geometry = anchor.geometry

        // Generate mesh descriptor
        guard let meshResource = createMeshResource(from: geometry) else { return }

        if let existingInfo = meshEntities[identifier] {
            // Update existing entity
            existingInfo.entity.model?.mesh = meshResource
            existingInfo.entity.transform = Transform(matrix: anchor.transform)
            meshEntities[identifier]?.lastUpdate = Date()
        } else {
            // Create new entity
            let material = configuration.enableOcclusion ? occlusionMaterial as? Material : meshMaterial as? Material
            let entity = ModelEntity(mesh: meshResource, materials: [material].compactMap { $0 })
            entity.transform = Transform(matrix: anchor.transform)

            rootAnchor.addChild(entity)

            meshEntities[identifier] = MeshEntityInfo(
                entity: entity,
                anchorIdentifier: identifier,
                lastUpdate: Date()
            )
        }
    }

    func removeMesh(identifier: UUID) {
        if let info = meshEntities[identifier] {
            info.entity.removeFromParent()
            meshEntities.removeValue(forKey: identifier)
        }
    }

    func removeAllMeshes() {
        for info in meshEntities.values {
            info.entity.removeFromParent()
        }
        meshEntities.removeAll()
    }

    // MARK: - Mesh Resource Creation

    private func createMeshResource(from geometry: ARMeshGeometry) -> MeshResource? {
        let vertices = geometry.vertices
        let faces = geometry.faces
        let normals = geometry.normals

        var meshDescriptor = MeshDescriptor(name: "ARMesh")

        // Extract positions
        var positions: [simd_float3] = []
        positions.reserveCapacity(vertices.count)

        vertices.buffer.contents().withMemoryRebound(to: UInt8.self, capacity: vertices.buffer.length) { pointer in
            for i in 0..<vertices.count {
                let vertexPointer = pointer.advanced(by: vertices.offset + i * vertices.stride)
                let position = vertexPointer.withMemoryRebound(to: simd_float3.self, capacity: 1) { $0.pointee }
                positions.append(position)
            }
        }

        meshDescriptor.positions = MeshBuffer(positions)

        // Extract normals
        var normalArray: [simd_float3] = []
        normalArray.reserveCapacity(normals.count)

        normals.buffer.contents().withMemoryRebound(to: UInt8.self, capacity: normals.buffer.length) { pointer in
            for i in 0..<normals.count {
                let normalPointer = pointer.advanced(by: normals.offset + i * normals.stride)
                let normal = normalPointer.withMemoryRebound(to: simd_float3.self, capacity: 1) { $0.pointee }
                normalArray.append(normal)
            }
        }

        meshDescriptor.normals = MeshBuffer(normalArray)

        // Extract face indices
        var indices: [UInt32] = []
        indices.reserveCapacity(faces.count * 3)

        let bytesPerIndex = faces.bytesPerIndex
        let indicesPerFace = faces.indexCountPerPrimitive
        let buffer = faces.buffer.contents()

        for i in 0..<faces.count {
            let offset = i * indicesPerFace * bytesPerIndex

            if bytesPerIndex == 4 {
                let pointer = (buffer + offset).bindMemory(to: UInt32.self, capacity: indicesPerFace)
                indices.append(pointer[0])
                indices.append(pointer[1])
                indices.append(pointer[2])
            } else {
                let pointer = (buffer + offset).bindMemory(to: UInt16.self, capacity: indicesPerFace)
                indices.append(UInt32(pointer[0]))
                indices.append(UInt32(pointer[1]))
                indices.append(UInt32(pointer[2]))
            }
        }

        meshDescriptor.primitives = .triangles(indices)

        do {
            return try MeshResource.generate(from: [meshDescriptor])
        } catch {
            print("Failed to generate mesh resource: \(error)")
            return nil
        }
    }

    // MARK: - Visualization Modes

    func setVisualizationMode(_ mode: VisualizationMode) {
        for info in meshEntities.values {
            switch mode {
            case .solid:
                if let material = meshMaterial {
                    info.entity.model?.materials = [material]
                }
            case .wireframe:
                if let material = wireframeMaterial {
                    info.entity.model?.materials = [material]
                }
            case .occlusion:
                if let material = occlusionMaterial {
                    info.entity.model?.materials = [material]
                }
            case .hidden:
                info.entity.isEnabled = false
            }

            if mode != .hidden {
                info.entity.isEnabled = true
            }
        }
    }

    enum VisualizationMode {
        case solid
        case wireframe
        case occlusion
        case hidden
    }

    // MARK: - Configuration Updates

    func setOpacity(_ opacity: Float) {
        configuration.meshOpacity = opacity
        setupMaterials()
        updateAllMaterials()
    }

    func setColor(_ color: simd_float4) {
        configuration.meshColor = color
        setupMaterials()
        updateAllMaterials()
    }

    func setWireframeEnabled(_ enabled: Bool) {
        configuration.showWireframe = enabled
        setVisualizationMode(enabled ? .wireframe : .solid)
    }

    func setOcclusionEnabled(_ enabled: Bool) {
        configuration.enableOcclusion = enabled
        setVisualizationMode(enabled ? .occlusion : .solid)
    }

    private func updateAllMaterials() {
        guard let material = meshMaterial else { return }

        for info in meshEntities.values {
            info.entity.model?.materials = [material]
        }
    }

    // MARK: - Statistics

    var meshCount: Int {
        meshEntities.count
    }

    var totalVertexCount: Int {
        var count = 0
        for info in meshEntities.values {
            count += info.entity.model?.mesh.contents.models.first?.parts.first?.positions.count ?? 0
        }
        return count
    }

    var totalFaceCount: Int {
        var count = 0
        for info in meshEntities.values {
            if let indices = info.entity.model?.mesh.contents.models.first?.parts.first?.triangleIndices {
                count += indices.count / 3
            }
        }
        return count
    }

    // MARK: - Export

    func exportCombinedMesh() -> MeshData? {
        var allVertices: [simd_float3] = []
        var allNormals: [simd_float3] = []
        var allFaces: [simd_uint3] = []
        var vertexOffset: UInt32 = 0

        for info in meshEntities.values {
            guard let mesh = info.entity.model?.mesh,
                  let part = mesh.contents.models.first?.parts.first else {
                continue
            }

            let transform = info.entity.transform.matrix

            // Get positions
            let positions = part.positions.elements
            for position in positions {
                let worldPosition = transform * simd_float4(position, 1)
                allVertices.append(simd_float3(worldPosition.x, worldPosition.y, worldPosition.z))
            }

            // Get normals
            if let normals = part.normals {
                let normalMatrix = simd_float3x3(
                    simd_float3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                    simd_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                    simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
                )
                for normal in normals.elements {
                    allNormals.append(simd_normalize(normalMatrix * normal))
                }
            }

            // Get faces
            if let indices = part.triangleIndices {
                let indexArray = Array(indices.elements)
                for i in stride(from: 0, to: indexArray.count, by: 3) {
                    allFaces.append(simd_uint3(
                        vertexOffset + indexArray[i],
                        vertexOffset + indexArray[i + 1],
                        vertexOffset + indexArray[i + 2]
                    ))
                }
            }

            vertexOffset += UInt32(positions.count)
        }

        guard !allVertices.isEmpty else { return nil }

        return MeshData(
            anchorIdentifier: UUID(),
            vertices: allVertices,
            normals: allNormals,
            faces: allFaces
        )
    }
}

// MARK: - Classification Colors

extension LiveMeshRenderer {

    func setClassificationColoring(enabled: Bool, mesh: ARMeshAnchor) {
        guard enabled, let geometry = mesh.classification else { return }

        // Classification-based coloring would require custom materials
        // This is a placeholder for future implementation
    }

    static func colorForClassification(_ classification: ARMeshClassification) -> simd_float4 {
        switch classification {
        case .none:
            return simd_float4(0.5, 0.5, 0.5, 1.0)  // Gray
        case .wall:
            return simd_float4(0.8, 0.8, 0.9, 1.0)  // Light blue-gray
        case .floor:
            return simd_float4(0.6, 0.4, 0.2, 1.0)  // Brown
        case .ceiling:
            return simd_float4(0.9, 0.9, 0.9, 1.0)  // White
        case .table:
            return simd_float4(0.6, 0.3, 0.1, 1.0)  // Dark brown
        case .seat:
            return simd_float4(0.2, 0.5, 0.8, 1.0)  // Blue
        case .window:
            return simd_float4(0.7, 0.9, 1.0, 0.5)  // Light cyan, transparent
        case .door:
            return simd_float4(0.5, 0.3, 0.1, 1.0)  // Dark wood
        @unknown default:
            return simd_float4(1.0, 0.0, 1.0, 1.0)  // Magenta for unknown
        }
    }
}
