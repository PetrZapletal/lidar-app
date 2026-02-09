import SwiftUI
import SceneKit
import simd

/// SCNView obaleny v UIViewRepresentable pro zobrazeni MeshData
struct ModelPreviewView: UIViewRepresentable {
    let meshData: MeshData?
    let displayMode: DisplayMode

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60

        let scene = SCNScene()
        scene.background.contents = makeGradientImage()

        // Ambient light
        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 400
        ambientNode.light?.color = UIColor(white: 0.6, alpha: 1)
        scene.rootNode.addChildNode(ambientNode)

        // Directional light
        let directionalNode = SCNNode()
        directionalNode.light = SCNLight()
        directionalNode.light?.type = .directional
        directionalNode.light?.intensity = 800
        directionalNode.light?.castsShadow = true
        directionalNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(directionalNode)

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.position = SCNVector3(0, 1.5, 4)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        scnView.scene = scene

        if let mesh = meshData {
            addMeshNode(mesh, to: scene, mode: displayMode)
        }

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        guard let scene = scnView.scene else { return }

        // Remove old mesh nodes
        scene.rootNode.childNodes
            .filter { $0.name == "meshNode" }
            .forEach { $0.removeFromParentNode() }

        if let mesh = meshData {
            addMeshNode(mesh, to: scene, mode: displayMode)
        }
    }

    // MARK: - Build Mesh Geometry

    private func addMeshNode(_ mesh: MeshData, to scene: SCNScene, mode: DisplayMode) {
        guard !mesh.vertices.isEmpty else { return }

        let node: SCNNode

        if mode == .points {
            node = createPointNode(from: mesh)
        } else {
            node = createTriangleNode(from: mesh, mode: mode)
        }

        node.name = "meshNode"
        scene.rootNode.addChildNode(node)
    }

    private func createTriangleNode(from mesh: MeshData, mode: DisplayMode) -> SCNNode {
        var scnVertices: [SCNVector3] = []
        scnVertices.reserveCapacity(mesh.vertices.count)
        for v in mesh.vertices {
            scnVertices.append(SCNVector3(v.x, v.y, v.z))
        }

        var scnNormals: [SCNVector3] = []
        scnNormals.reserveCapacity(mesh.normals.count)
        for n in mesh.normals {
            scnNormals.append(SCNVector3(n.x, n.y, n.z))
        }

        var indices: [Int32] = []
        indices.reserveCapacity(mesh.faces.count * 3)
        for face in mesh.faces {
            indices.append(Int32(face.x))
            indices.append(Int32(face.y))
            indices.append(Int32(face.z))
        }

        let vertexSource = SCNGeometrySource(vertices: scnVertices)
        let normalSource = SCNGeometrySource(normals: scnNormals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])

        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.85)
        material.isDoubleSided = true
        material.fillMode = mode.scnFillMode
        material.lightingModel = .physicallyBased
        geometry.materials = [material]

        return SCNNode(geometry: geometry)
    }

    private func createPointNode(from mesh: MeshData) -> SCNNode {
        var scnVertices: [SCNVector3] = []
        scnVertices.reserveCapacity(mesh.vertices.count)
        for v in mesh.vertices {
            scnVertices.append(SCNVector3(v.x, v.y, v.z))
        }

        let vertexSource = SCNGeometrySource(vertices: scnVertices)
        let element = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: scnVertices.count,
            bytesPerIndex: 0
        )
        element.pointSize = 3
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 5

        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.cyan
        material.lightingModel = .constant
        geometry.materials = [material]

        return SCNNode(geometry: geometry)
    }

    // MARK: - Background

    private func makeGradientImage() -> UIImage {
        let size = CGSize(width: 1, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [
                UIColor(white: 0.08, alpha: 1).cgColor,
                UIColor(white: 0.18, alpha: 1).cgColor
            ]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 1]
            )!
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }
}
