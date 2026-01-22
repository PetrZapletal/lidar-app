import SwiftUI
import SceneKit
import RealityKit
import QuickLook

/// 3D model viewer with interactive controls
struct ModelPreviewView: View {
    let modelURL: URL?
    let session: ScanSession?

    @State private var viewModel = PreviewViewModel()
    @Environment(\.dismiss) private var dismiss

    init(modelURL: URL? = nil, session: ScanSession? = nil) {
        self.modelURL = modelURL
        self.session = session
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 3D View
                if let url = modelURL {
                    Model3DView(url: url, viewModel: viewModel)
                        .ignoresSafeArea()
                } else if let session = session {
                    MeshPreviewView(session: session, viewModel: viewModel)
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "No Model",
                        systemImage: "cube.transparent",
                        description: Text("No 3D model to display")
                    )
                }

                // Overlay controls
                VStack {
                    Spacer()

                    // Control bar
                    PreviewControlBar(viewModel: viewModel)
                        .padding()
                }
            }
            .navigationTitle(session?.name ?? "Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { viewModel.showExportOptions = true }) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }

                        Button(action: { viewModel.showARView = true }) {
                            Label("View in AR", systemImage: "arkit")
                        }

                        Button(action: { viewModel.showMeasurements = true }) {
                            Label("Measurements", systemImage: "ruler")
                        }

                        Divider()

                        Button(action: { viewModel.resetCamera() }) {
                            Label("Reset View", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showExportOptions) {
                ExportOptionsSheet(
                    session: session,
                    modelURL: modelURL,
                    onExport: { format in
                        viewModel.exportModel(format: format)
                    }
                )
            }
            .fullScreenCover(isPresented: $viewModel.showARView) {
                if let url = modelURL {
                    ARQuickLookView(modelURL: url)
                }
            }
            .sheet(isPresented: $viewModel.showMeasurements) {
                if let session = session {
                    MeasurementsSheet(session: session)
                }
            }
        }
    }
}

// MARK: - Model 3D View (SceneKit)

struct Model3DView: UIViewRepresentable {
    let url: URL
    let viewModel: PreviewViewModel

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X

        // Load model
        loadModel(into: scnView)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update based on viewModel changes
        uiView.showsStatistics = viewModel.showStats
        updateVisualization(uiView)
    }

    private func loadModel(into scnView: SCNView) {
        let scene = SCNScene()

        // Try to load USDZ or other supported formats
        if let loadedScene = try? SCNScene(url: url, options: [
            .checkConsistency: true,
            .flattenScene: true
        ]) {
            // Copy nodes from loaded scene
            for child in loadedScene.rootNode.childNodes {
                scene.rootNode.addChildNode(child)
            }
        }

        // Add lighting
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.position = SCNVector3(0, 10, 10)
        scene.rootNode.addChildNode(lightNode)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor.darkGray
        scene.rootNode.addChildNode(ambientLight)

        // Add camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 1, 3)
        scene.rootNode.addChildNode(cameraNode)

        scnView.scene = scene
    }

    private func updateVisualization(_ scnView: SCNView) {
        guard let scene = scnView.scene else { return }

        scene.rootNode.enumerateChildNodes { node, _ in
            if let geometry = node.geometry {
                switch viewModel.visualizationMode {
                case .solid:
                    geometry.firstMaterial?.fillMode = .fill
                case .wireframe:
                    geometry.firstMaterial?.fillMode = .lines
                case .points:
                    // SceneKit doesn't support point mode directly
                    geometry.firstMaterial?.fillMode = .fill
                }
            }
        }
    }
}

// MARK: - Mesh Preview View (for ScanSession)

struct MeshPreviewView: UIViewRepresentable {
    let session: ScanSession
    let viewModel: PreviewViewModel

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor(white: 0.1, alpha: 1)
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true

        createMeshScene(in: scnView)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.showsStatistics = viewModel.showStats
    }

    private func createMeshScene(in scnView: SCNView) {
        let scene = SCNScene()

        // Create mesh from session data
        if !session.combinedMesh.meshes.isEmpty {
            let meshNode = createMeshNode(from: session.combinedMesh)
            scene.rootNode.addChildNode(meshNode)
        }

        // Add point cloud if available
        if let pointCloud = session.pointCloud {
            let pointsNode = createPointCloudNode(from: pointCloud)
            scene.rootNode.addChildNode(pointsNode)
        }

        // Add lighting
        addLighting(to: scene)

        // Add camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.position = SCNVector3(0, 1, 3)
        scene.rootNode.addChildNode(cameraNode)

        scnView.scene = scene
    }

    private func createMeshNode(from mesh: CombinedMesh) -> SCNNode {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        var vertexOffset: Int32 = 0

        for meshData in mesh.meshes.values {
            for vertex in meshData.worldVertices {
                vertices.append(SCNVector3(vertex.x, vertex.y, vertex.z))
            }

            for normal in meshData.normals {
                normals.append(SCNVector3(normal.x, normal.y, normal.z))
            }

            for face in meshData.faces {
                indices.append(Int32(face.x) + vertexOffset)
                indices.append(Int32(face.y) + vertexOffset)
                indices.append(Int32(face.z) + vertexOffset)
            }

            vertexOffset += Int32(meshData.vertices.count)
        }

        guard !vertices.isEmpty else {
            return SCNNode()
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])

        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.8)
        material.isDoubleSided = true
        geometry.materials = [material]

        return SCNNode(geometry: geometry)
    }

    private func createPointCloudNode(from pointCloud: PointCloud) -> SCNNode {
        let vertices = pointCloud.points.map { SCNVector3($0.x, $0.y, $0.z) }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(
            indices: Array(0..<Int32(vertices.count)),
            primitiveType: .point
        )

        element.pointSize = 2
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 5

        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.cyan
        geometry.materials = [material]

        return SCNNode(geometry: geometry)
    }

    private func addLighting(to scene: SCNScene) {
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.intensity = 1000
        lightNode.position = SCNVector3(0, 5, 5)
        scene.rootNode.addChildNode(lightNode)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        scene.rootNode.addChildNode(ambientLight)
    }
}

// MARK: - Preview Control Bar

struct PreviewControlBar: View {
    @Bindable var viewModel: PreviewViewModel

    var body: some View {
        HStack(spacing: 20) {
            // Visualization mode
            Menu {
                Button(action: { viewModel.visualizationMode = .solid }) {
                    Label("Solid", systemImage: "cube.fill")
                }
                Button(action: { viewModel.visualizationMode = .wireframe }) {
                    Label("Wireframe", systemImage: "cube")
                }
                Button(action: { viewModel.visualizationMode = .points }) {
                    Label("Points", systemImage: "circle.grid.3x3")
                }
            } label: {
                Image(systemName: viewModel.visualizationMode.icon)
                    .font(.title2)
            }

            Divider()
                .frame(height: 30)

            // Stats toggle
            Button(action: { viewModel.showStats.toggle() }) {
                Image(systemName: viewModel.showStats ? "info.circle.fill" : "info.circle")
                    .font(.title2)
            }

            // Screenshot
            Button(action: { viewModel.captureScreenshot() }) {
                Image(systemName: "camera")
                    .font(.title2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Export Options Sheet

struct ExportOptionsSheet: View {
    let session: ScanSession?
    let modelURL: URL?
    let onExport: (ExportFormat) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("3D Formats") {
                    ForEach(ExportFormat.meshFormats, id: \.self) { format in
                        Button(action: {
                            onExport(format)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: format.icon)
                                    .foregroundStyle(.blue)
                                    .frame(width: 30)

                                VStack(alignment: .leading) {
                                    Text(format.displayName)
                                    Text(format.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Data Formats") {
                    ForEach(ExportFormat.dataFormats, id: \.self) { format in
                        Button(action: {
                            onExport(format)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: format.icon)
                                    .foregroundStyle(.orange)
                                    .frame(width: 30)

                                VStack(alignment: .leading) {
                                    Text(format.displayName)
                                    Text(format.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - AR QuickLook View

struct ARQuickLookView: UIViewControllerRepresentable {
    let modelURL: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: modelURL)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

// MARK: - Measurements Sheet

struct MeasurementsSheet: View {
    let session: ScanSession

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if session.measurements.isEmpty {
                    ContentUnavailableView(
                        "No Measurements",
                        systemImage: "ruler",
                        description: Text("Add measurements during scanning")
                    )
                } else {
                    ForEach(session.measurements) { measurement in
                        HStack {
                            Image(systemName: measurement.type.icon)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading) {
                                Text(measurement.label ?? measurement.type.rawValue.capitalized)
                                    .font(.headline)
                                Text(formatMeasurement(measurement))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func formatMeasurement(_ measurement: Measurement) -> String {
        return measurement.formattedValue
    }
}

// Note: ExportFormat is now defined in ExportView.swift

// MARK: - Preview

#Preview {
    ModelPreviewView(session: ScanSession())
}
