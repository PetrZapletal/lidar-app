import SwiftUI
import SceneKit
import simd

// MARK: - Enhanced 3D Viewer

struct Enhanced3DViewer: View {
    let session: ScanSession
    @State private var viewMode: ViewMode = .pointCloud
    @State private var showGrid: Bool = true
    @State private var showBoundingBox: Bool = false
    @State private var showNormals: Bool = false
    @State private var lightingMode: LightingMode = .pbr
    @State private var colorMode: ColorMode = .original
    @State private var pointSize: Float = 3

    enum ViewMode: String, CaseIterable {
        case pointCloud = "Body"
        case mesh = "Mesh"
        case wireframe = "Drátěný"
        case combined = "Kombinovaný"
    }

    enum LightingMode: String, CaseIterable {
        case ambient = "Okolní"
        case pbr = "PBR"
        case flat = "Plochý"
    }

    enum ColorMode: String, CaseIterable {
        case original = "Původní"
        case height = "Výška"
        case normal = "Normály"
        case classification = "Klasifikace"
    }

    var body: some View {
        ZStack {
            EnhancedSceneKitView(
                session: session,
                viewMode: viewMode,
                showGrid: showGrid,
                showBoundingBox: showBoundingBox,
                showNormals: showNormals,
                lightingMode: lightingMode,
                colorMode: colorMode,
                pointSize: pointSize
            )
            .ignoresSafeArea()

            // Controls overlay
            VStack {
                // Top toolbar
                viewerToolbar

                Spacer()

                // Bottom controls
                viewerControls
            }
        }
    }

    private var viewerToolbar: some View {
        HStack {
            // View mode picker
            Menu {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Button(mode.rawValue) {
                        viewMode = mode
                    }
                }
            } label: {
                HStack {
                    Image(systemName: viewModeIcon)
                    Text(viewMode.rawValue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            // Options
            HStack(spacing: 12) {
                Toggle(isOn: $showGrid) {
                    Image(systemName: "grid")
                }
                .toggleStyle(.button)

                Toggle(isOn: $showBoundingBox) {
                    Image(systemName: "cube.transparent")
                }
                .toggleStyle(.button)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding()
    }

    private var viewerControls: some View {
        VStack(spacing: 12) {
            // Lighting mode
            HStack {
                Text("Osvětlení")
                    .font(.caption)
                Picker("", selection: $lightingMode) {
                    ForEach(LightingMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Color mode
            HStack {
                Text("Barvy")
                    .font(.caption)
                Picker("", selection: $colorMode) {
                    ForEach(ColorMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Point size (for point cloud mode)
            if viewMode == .pointCloud || viewMode == .combined {
                HStack {
                    Text("Velikost bodů")
                        .font(.caption)
                    Slider(value: $pointSize, in: 1...10)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private var viewModeIcon: String {
        switch viewMode {
        case .pointCloud: return "circle.dotted"
        case .mesh: return "cube.fill"
        case .wireframe: return "cube"
        case .combined: return "cube.transparent"
        }
    }
}

// MARK: - Enhanced SceneKit View

struct EnhancedSceneKitView: UIViewRepresentable {
    let session: ScanSession
    let viewMode: Enhanced3DViewer.ViewMode
    let showGrid: Bool
    let showBoundingBox: Bool
    let showNormals: Bool
    let lightingMode: Enhanced3DViewer.LightingMode
    let colorMode: Enhanced3DViewer.ColorMode
    let pointSize: Float

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1)
        scnView.allowsCameraControl = true
        scnView.showsStatistics = false
        scnView.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        scnView.scene = scene

        // Setup camera
        let cameraNode = SCNNode()
        cameraNode.name = "mainCamera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.zFar = 1000
        cameraNode.camera?.fieldOfView = 60
        scene.rootNode.addChildNode(cameraNode)

        // Position camera based on point cloud bounds
        positionCamera(cameraNode, for: session)

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        guard let scene = scnView.scene else { return }

        // Check if we need to update (avoid recreating heavy geometry)
        let needsFullUpdate = context.coordinator.lastViewMode != viewMode ||
                              context.coordinator.lastColorMode != colorMode ||
                              context.coordinator.lastPointSize != pointSize

        // Update cached state
        context.coordinator.lastViewMode = viewMode
        context.coordinator.lastColorMode = colorMode
        context.coordinator.lastPointSize = pointSize

        // Only recreate content if view mode or color mode changed
        if needsFullUpdate {
            // Clear existing content (except camera and lights)
            scene.rootNode.childNodes
                .filter { $0.name != "mainCamera" && $0.light == nil }
                .forEach { $0.removeFromParentNode() }

            // Add content based on view mode
            switch viewMode {
            case .pointCloud:
                addPointCloud(to: scene)
            case .mesh:
                addMesh(to: scene, wireframe: false)
            case .wireframe:
                addMesh(to: scene, wireframe: true)
            case .combined:
                addPointCloud(to: scene)
                addMesh(to: scene, wireframe: true)
            }
        }

        // Update toggleable elements (lighter updates)
        updateGrid(in: scene)
        updateBoundingBox(in: scene)
        updateLighting(in: scene)
    }

    private func updateGrid(in scene: SCNScene) {
        let existingGrid = scene.rootNode.childNode(withName: "grid", recursively: false)
        if showGrid && existingGrid == nil {
            addGrid(to: scene)
        } else if !showGrid, let grid = existingGrid {
            grid.removeFromParentNode()
        }
    }

    private func updateBoundingBox(in scene: SCNScene) {
        let existingBox = scene.rootNode.childNode(withName: "boundingBox", recursively: false)
        if showBoundingBox && existingBox == nil {
            addBoundingBox(to: scene)
        } else if !showBoundingBox, let box = existingBox {
            box.removeFromParentNode()
        }
    }

    private func updateLighting(in scene: SCNScene) {
        // Remove old lights and add new ones only when mode changes
        // For now, just setup lighting once
        if scene.rootNode.childNodes.filter({ $0.light != nil }).isEmpty {
            setupLighting(scene: scene)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var lastViewMode: Enhanced3DViewer.ViewMode?
        var lastColorMode: Enhanced3DViewer.ColorMode?
        var lastPointSize: Float?
    }

    private func positionCamera(_ cameraNode: SCNNode, for session: ScanSession) {
        if let pointCloud = session.pointCloud,
           let bbox = pointCloud.boundingBox {
            let center = bbox.center
            let diagonal = bbox.diagonal
            let distance = max(diagonal * 1.5, 2.0)

            cameraNode.position = SCNVector3(
                center.x + distance * 0.5,
                center.y + distance * 0.5,
                center.z + distance
            )
            cameraNode.look(at: SCNVector3(center.x, center.y, center.z))
        } else {
            cameraNode.position = SCNVector3(0, 2, 5)
            cameraNode.look(at: SCNVector3(0, 0, 0))
        }
    }

    private func setupLighting(scene: SCNScene) {
        // Remove existing lights
        scene.rootNode.childNodes
            .filter { $0.light != nil }
            .forEach { $0.removeFromParentNode() }

        switch lightingMode {
        case .ambient:
            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.intensity = 1000
            ambientLight.light?.color = UIColor.white
            scene.rootNode.addChildNode(ambientLight)

        case .pbr:
            // Ambient fill
            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.intensity = 300
            ambientLight.light?.color = UIColor(white: 0.3, alpha: 1)
            scene.rootNode.addChildNode(ambientLight)

            // Key light
            let keyLight = SCNNode()
            keyLight.light = SCNLight()
            keyLight.light?.type = .directional
            keyLight.light?.intensity = 800
            keyLight.light?.color = UIColor(white: 1.0, alpha: 1)
            keyLight.light?.castsShadow = true
            keyLight.position = SCNVector3(5, 10, 5)
            keyLight.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(keyLight)

            // Fill light
            let fillLight = SCNNode()
            fillLight.light = SCNLight()
            fillLight.light?.type = .directional
            fillLight.light?.intensity = 400
            fillLight.light?.color = UIColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 1)
            fillLight.position = SCNVector3(-5, 5, -5)
            fillLight.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(fillLight)

            // Rim light
            let rimLight = SCNNode()
            rimLight.light = SCNLight()
            rimLight.light?.type = .directional
            rimLight.light?.intensity = 300
            rimLight.light?.color = UIColor(red: 1.0, green: 0.9, blue: 0.8, alpha: 1)
            rimLight.position = SCNVector3(0, 2, -10)
            rimLight.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(rimLight)

        case .flat:
            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.intensity = 1500
            scene.rootNode.addChildNode(ambientLight)
        }
    }

    private func addGrid(to scene: SCNScene) {
        let gridNode = SCNNode()
        gridNode.name = "grid"

        let gridSize: Float = 10
        let gridSpacing: Float = 0.5
        let lineCount = Int(gridSize / gridSpacing)

        // Create grid lines
        var vertices: [SCNVector3] = []

        for i in -lineCount...lineCount {
            let offset = Float(i) * gridSpacing

            // X-axis parallel lines
            vertices.append(SCNVector3(-gridSize/2, 0, offset))
            vertices.append(SCNVector3(gridSize/2, 0, offset))

            // Z-axis parallel lines
            vertices.append(SCNVector3(offset, 0, -gridSize/2))
            vertices.append(SCNVector3(offset, 0, gridSize/2))
        }

        let source = SCNGeometrySource(vertices: vertices)
        var indices: [Int32] = []
        for i in stride(from: 0, to: vertices.count, by: 2) {
            indices.append(Int32(i))
            indices.append(Int32(i + 1))
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)

        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(white: 0.3, alpha: 0.5)
        material.isDoubleSided = true
        geometry.materials = [material]

        gridNode.geometry = geometry
        scene.rootNode.addChildNode(gridNode)

        // Add axis indicators
        addAxisIndicators(to: scene)
    }

    private func addAxisIndicators(to scene: SCNScene) {
        let axisLength: Float = 1.0
        let axisRadius: Float = 0.01

        // X axis (red)
        let xAxis = SCNCylinder(radius: CGFloat(axisRadius), height: CGFloat(axisLength))
        xAxis.firstMaterial?.diffuse.contents = UIColor.red
        let xNode = SCNNode(geometry: xAxis)
        xNode.position = SCNVector3(axisLength/2, 0, 0)
        xNode.eulerAngles = SCNVector3(0, 0, -Float.pi/2)
        scene.rootNode.addChildNode(xNode)

        // Y axis (green)
        let yAxis = SCNCylinder(radius: CGFloat(axisRadius), height: CGFloat(axisLength))
        yAxis.firstMaterial?.diffuse.contents = UIColor.green
        let yNode = SCNNode(geometry: yAxis)
        yNode.position = SCNVector3(0, axisLength/2, 0)
        scene.rootNode.addChildNode(yNode)

        // Z axis (blue)
        let zAxis = SCNCylinder(radius: CGFloat(axisRadius), height: CGFloat(axisLength))
        zAxis.firstMaterial?.diffuse.contents = UIColor.blue
        let zNode = SCNNode(geometry: zAxis)
        zNode.position = SCNVector3(0, 0, axisLength/2)
        zNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        scene.rootNode.addChildNode(zNode)

        // Origin sphere
        let origin = SCNSphere(radius: 0.03)
        origin.firstMaterial?.diffuse.contents = UIColor.white
        let originNode = SCNNode(geometry: origin)
        scene.rootNode.addChildNode(originNode)
    }

    private func addPointCloud(to scene: SCNScene) {
        guard let pointCloud = session.pointCloud else { return }

        let node = SCNNode()
        node.name = "pointCloud"

        var vertices: [SCNVector3] = []
        var colors: [SCNVector4] = []

        // Limit points for performance - max 5000 points for smooth rendering
        let maxPoints = 5000
        let totalPoints = pointCloud.points.count
        let stride = max(1, totalPoints / maxPoints)

        for i in Swift.stride(from: 0, to: totalPoints, by: stride) {
            let point = pointCloud.points[i]
            vertices.append(SCNVector3(point.x, point.y, point.z))

            let color = calculatePointColor(
                index: i,
                point: point,
                pointCloud: pointCloud
            )
            colors.append(color)
        }

        let pointSource = SCNGeometrySource(vertices: vertices)
        let colorData = Data(bytes: colors, count: colors.count * MemoryLayout<SCNVector4>.size)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector4>.size
        )

        let elements = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: vertices.count,
            bytesPerIndex: 0
        )
        elements.pointSize = CGFloat(pointSize)
        elements.minimumPointScreenSpaceRadius = 1
        elements.maximumPointScreenSpaceRadius = CGFloat(pointSize * 2)

        let geometry = SCNGeometry(sources: [pointSource, colorSource], elements: [elements])
        node.geometry = geometry

        scene.rootNode.addChildNode(node)
    }

    private func calculatePointColor(
        index: Int,
        point: simd_float3,
        pointCloud: PointCloud
    ) -> SCNVector4 {
        switch colorMode {
        case .original:
            if let pcColors = pointCloud.colors, index < pcColors.count {
                let c = pcColors[index]
                return SCNVector4(c.x, c.y, c.z, c.w)
            }
            return SCNVector4(0.7, 0.7, 0.8, 1.0)

        case .height:
            guard let bbox = pointCloud.boundingBox else {
                return SCNVector4(0.5, 0.5, 0.5, 1.0)
            }
            let normalizedY = (point.y - bbox.min.y) / (bbox.max.y - bbox.min.y)

            // Cool to warm color gradient
            if normalizedY < 0.5 {
                let t = normalizedY * 2
                return SCNVector4(0, Float(t), Float(1 - t * 0.5), 1.0)
            } else {
                let t = (normalizedY - 0.5) * 2
                return SCNVector4(Float(t), Float(1 - t * 0.5), 0, 1.0)
            }

        case .normal:
            if let normals = pointCloud.normals, index < normals.count {
                let n = normals[index]
                return SCNVector4(
                    (n.x + 1) / 2,
                    (n.y + 1) / 2,
                    (n.z + 1) / 2,
                    1.0
                )
            }
            return SCNVector4(0.5, 0.5, 1.0, 1.0)

        case .classification:
            // Default gray for point clouds (classification is mainly for meshes)
            return SCNVector4(0.6, 0.6, 0.7, 1.0)
        }
    }

    private func addMesh(to scene: SCNScene, wireframe: Bool) {
        for mesh in session.combinedMesh.meshes.values {
            let node = createMeshNode(from: mesh, wireframe: wireframe)
            node.name = "mesh"
            scene.rootNode.addChildNode(node)
        }
    }

    private func createMeshNode(from mesh: MeshData, wireframe: Bool) -> SCNNode {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []

        for v in mesh.worldVertices {
            vertices.append(SCNVector3(v.x, v.y, v.z))
        }

        for n in mesh.normals {
            normals.append(SCNVector3(n.x, n.y, n.z))
        }

        for face in mesh.faces {
            indices.append(Int32(face.x))
            indices.append(Int32(face.y))
            indices.append(Int32(face.z))
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])

        let material = SCNMaterial()

        if wireframe {
            material.fillMode = .lines
            material.diffuse.contents = UIColor.cyan.withAlphaComponent(0.8)
            material.isDoubleSided = true
        } else {
            switch colorMode {
            case .original, .height:
                material.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.9)
            case .normal:
                material.diffuse.contents = UIColor.systemGreen.withAlphaComponent(0.9)
            case .classification:
                // Apply classification colors based on mesh data
                if let classifications = mesh.classifications, !classifications.isEmpty {
                    material.diffuse.contents = UIColor.systemOrange.withAlphaComponent(0.9)
                } else {
                    material.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.9)
                }
            }
            material.isDoubleSided = true
            material.lightingModel = lightingMode == .pbr ? .physicallyBased : .blinn
            material.metalness.contents = 0.1
            material.roughness.contents = 0.7
        }

        geometry.materials = [material]

        return SCNNode(geometry: geometry)
    }

    private func addBoundingBox(to scene: SCNScene) {
        guard let pointCloud = session.pointCloud,
              let bbox = pointCloud.boundingBox else {
            return
        }

        let boxNode = SCNNode()
        boxNode.name = "boundingBox"

        let size = bbox.size
        let center = bbox.center

        // Create wireframe box
        let box = SCNBox(
            width: CGFloat(size.x),
            height: CGFloat(size.y),
            length: CGFloat(size.z),
            chamferRadius: 0
        )

        let material = SCNMaterial()
        material.fillMode = .lines
        material.diffuse.contents = UIColor.yellow.withAlphaComponent(0.8)
        material.isDoubleSided = true
        box.materials = [material]

        boxNode.geometry = box
        boxNode.position = SCNVector3(center.x, center.y, center.z)

        scene.rootNode.addChildNode(boxNode)
    }
}

// MARK: - Preview

#Preview {
    Enhanced3DViewer(session: MockDataProvider.shared.createMockScanSession())
}
