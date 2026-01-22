import SwiftUI
import SceneKit

/// Preview view for mock data
struct MockDataPreviewView: View {
    @State private var selectedTab = 0
    @State private var mockSession: ScanSession?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Data Type", selection: $selectedTab) {
                Text("Point Cloud").tag(0)
                Text("Mesh").tag(1)
                Text("Measurements").tag(2)
                Text("Session").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()

            TabView(selection: $selectedTab) {
                PointCloudPreviewTab()
                    .tag(0)

                MeshPreviewTab()
                    .tag(1)

                MeasurementsPreviewTab()
                    .tag(2)

                SessionPreviewTab(session: $mockSession)
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("Mock Data Preview")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if mockSession == nil {
                mockSession = MockDataProvider.shared.createMockScanSession()
            }
        }
    }
}

// MARK: - Point Cloud Preview

private struct PointCloudPreviewTab: View {
    @State private var pointCloud: PointCloud?
    @State private var pointCount = 5000

    var body: some View {
        VStack {
            if let pc = pointCloud {
                MockSceneView(pointCloud: pc, mesh: nil)
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
                    .padding()

                statsView(for: pc)
            } else {
                ProgressView("Generating...")
            }

            Spacer()

            VStack(spacing: 16) {
                HStack {
                    Text("Point Count: \(pointCount)")
                    Spacer()
                }

                Slider(value: Binding(
                    get: { Double(pointCount) },
                    set: { pointCount = Int($0) }
                ), in: 1000...50000, step: 1000)

                Button("Generate Point Cloud") {
                    pointCloud = MockDataProvider.shared.generateSamplePointCloud(pointCount: pointCount)
                }
                .buttonStyle(.borderedProminent)

                Button("Generate Room") {
                    pointCloud = MockDataProvider.shared.generateRoomPointCloud(pointDensity: pointCount)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .onAppear {
            if pointCloud == nil {
                pointCloud = MockDataProvider.shared.generateSamplePointCloud(pointCount: pointCount)
            }
        }
    }

    private func statsView(for pc: PointCloud) -> some View {
        GroupBox("Statistics") {
            VStack(alignment: .leading, spacing: 8) {
                MockStatRow(label: "Points", value: "\(pc.pointCount)")
                MockStatRow(label: "Has Colors", value: pc.colors != nil ? "Yes" : "No")
                MockStatRow(label: "Has Normals", value: pc.normals != nil ? "Yes" : "No")
                if let bbox = pc.boundingBox {
                    MockStatRow(label: "Bounding Box", value: String(format: "%.2f x %.2f x %.2f",
                        bbox.size.x, bbox.size.y, bbox.size.z))
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Mesh Preview

private struct MeshPreviewTab: View {
    @State private var mesh: MeshData?

    var body: some View {
        VStack {
            if let m = mesh {
                MockSceneView(pointCloud: nil, mesh: m)
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
                    .padding()

                statsView(for: m)
            } else {
                ProgressView("Generating...")
            }

            Spacer()

            VStack(spacing: 16) {
                Button("Generate Cube") {
                    mesh = MockDataProvider.shared.generateSampleMesh()
                }
                .buttonStyle(.borderedProminent)

                Button("Generate Floor") {
                    mesh = MockDataProvider.shared.generateFloorMesh()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .onAppear {
            if mesh == nil {
                mesh = MockDataProvider.shared.generateSampleMesh()
            }
        }
    }

    private func statsView(for mesh: MeshData) -> some View {
        GroupBox("Statistics") {
            VStack(alignment: .leading, spacing: 8) {
                MockStatRow(label: "Vertices", value: "\(mesh.vertexCount)")
                MockStatRow(label: "Faces", value: "\(mesh.faceCount)")
                MockStatRow(label: "Surface Area", value: String(format: "%.2f m²", mesh.surfaceArea))
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Measurements Preview

private struct MeasurementsPreviewTab: View {
    @State private var measurements: [Measurement] = []

    var body: some View {
        List {
            ForEach(measurements) { measurement in
                HStack {
                    Image(systemName: measurement.type.icon)
                        .foregroundColor(.blue)
                        .frame(width: 30)

                    VStack(alignment: .leading) {
                        Text(measurement.label ?? measurement.type.rawValue.capitalized)
                            .font(.headline)
                        Text(measurement.formattedValue)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(measurement.type.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }
        }
        .onAppear {
            if measurements.isEmpty {
                measurements = MockDataProvider.shared.generateSampleMeasurements()
            }
        }
    }
}

// MARK: - Session Preview

private struct SessionPreviewTab: View {
    @Binding var session: ScanSession?

    var body: some View {
        if let session = session {
            List {
                Section("Session Info") {
                    MockStatRow(label: "Name", value: session.name)
                    MockStatRow(label: "State", value: session.state.displayName)
                    MockStatRow(label: "Duration", value: session.formattedDuration)
                }

                Section("Data") {
                    MockStatRow(label: "Point Cloud", value: session.pointCloud != nil ? "\(session.pointCloud!.pointCount) points" : "None")
                    MockStatRow(label: "Meshes", value: "\(session.combinedMesh.meshes.count)")
                    MockStatRow(label: "Vertices", value: "\(session.vertexCount)")
                    MockStatRow(label: "Faces", value: "\(session.faceCount)")
                    MockStatRow(label: "Measurements", value: "\(session.measurements.count)")
                }

                Section("Actions") {
                    Button("Regenerate Session") {
                        self.session = MockDataProvider.shared.createMockScanSession()
                    }
                }
            }
        } else {
            ProgressView("Loading...")
        }
    }
}

// MARK: - Mock Scene View

private struct MockSceneView: UIViewRepresentable {
    let pointCloud: PointCloud?
    let mesh: MeshData?

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .systemBackground
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = true

        let scene = SCNScene()
        scnView.scene = scene

        // Add camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 2, 4)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        guard let scene = scnView.scene else { return }

        // Remove old geometry
        scene.rootNode.childNodes
            .filter { $0.name == "geometry" }
            .forEach { $0.removeFromParentNode() }

        // Add point cloud
        if let pc = pointCloud {
            let pointsNode = createPointCloudNode(from: pc)
            pointsNode.name = "geometry"
            scene.rootNode.addChildNode(pointsNode)
        }

        // Add mesh
        if let m = mesh {
            let meshNode = createMeshNode(from: m)
            meshNode.name = "geometry"
            scene.rootNode.addChildNode(meshNode)
        }
    }

    private func createPointCloudNode(from pc: PointCloud) -> SCNNode {
        let node = SCNNode()

        // Create point geometry
        var vertices: [SCNVector3] = []
        var colors: [SCNVector4] = []

        for (i, point) in pc.points.enumerated() {
            vertices.append(SCNVector3(point.x, point.y, point.z))

            if let pcColors = pc.colors, i < pcColors.count {
                let c = pcColors[i]
                colors.append(SCNVector4(c.x, c.y, c.z, c.w))
            } else {
                colors.append(SCNVector4(0.5, 0.5, 1.0, 1.0))
            }
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
        elements.pointSize = 3
        elements.minimumPointScreenSpaceRadius = 1
        elements.maximumPointScreenSpaceRadius = 5

        let geometry = SCNGeometry(sources: [pointSource, colorSource], elements: [elements])
        node.geometry = geometry

        return node
    }

    private func createMeshNode(from mesh: MeshData) -> SCNNode {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []

        for v in mesh.vertices {
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
        material.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.7)
        material.isDoubleSided = true
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        return node
    }
}

// MARK: - Stat Row

private struct MockStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        MockDataPreviewView()
    }
}
