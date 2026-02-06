import SwiftUI
import SceneKit

struct ModelDetailView: View {
    let scan: ScanModel
    let scanStore: ScanStore
    @State private var showARPlacement = false
    @State private var showMeasurement = false
    @State private var showExport = false
    @State private var showShare = false
    @State private var showAIProcessing = false
    @State private var showEnhanced3DViewer = false
    @State private var showRenameAlert = false
    @State private var showDeleteAlert = false
    @State private var newName = ""
    @State private var aiError: String?
    @State private var showAIError = false
    @State private var aiService = AIGeometryGenerationService()
    @Environment(\.dismiss) private var dismiss

    private var session: ScanSession? {
        scanStore.getSession(for: scan.id)
    }

    var body: some View {
        ZStack {
            Model3DViewer(scan: scan, session: session)
                .ignoresSafeArea()

            VStack {
                Spacer()
                actionBar
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(scan.name)
                        .font(.headline)
                    Text(formatStats(scan))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { showShare = true }) {
                        Label("Sdílet", systemImage: "square.and.arrow.up")
                    }
                    Button(action: { showExport = true }) {
                        Label("Exportovat", systemImage: "arrow.down.doc")
                    }
                    Divider()
                    Button(action: {
                        newName = scan.name
                        showRenameAlert = true
                    }) {
                        Label("Přejmenovat", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: {
                        showDeleteAlert = true
                    }) {
                        Label("Smazat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showExport) {
            if let session = session {
                ExportView(session: session, scanName: scan.name)
            } else {
                GalleryExportSheet(scan: scan)
            }
        }
        .fullScreenCover(isPresented: $showARPlacement) {
            ARPlacementView(scan: scan)
        }
        .fullScreenCover(isPresented: $showEnhanced3DViewer) {
            if let session = session {
                NavigationStack {
                    Enhanced3DViewer(session: session)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Zavřít") { showEnhanced3DViewer = false }
                            }
                        }
                }
            }
        }
        .fullScreenCover(isPresented: $showMeasurement) {
            if let session = session {
                NavigationStack {
                    InteractiveMeasurementView(session: session)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Zavřít") { showMeasurement = false }
                            }
                        }
                }
            }
        }
        .alert("Přejmenovat model", isPresented: $showRenameAlert) {
            TextField("Název", text: $newName)
            Button("Zrušit", role: .cancel) { }
            Button("Uložit") {
                if !newName.isEmpty {
                    scanStore.renameScan(scan, to: newName)
                }
            }
        } message: {
            Text("Zadejte nový název pro tento model")
        }
        .alert("Smazat model?", isPresented: $showDeleteAlert) {
            Button("Zrušit", role: .cancel) { }
            Button("Smazat", role: .destructive) {
                scanStore.deleteScan(scan)
                dismiss()
            }
        } message: {
            Text("Tato akce je nevratná. Model \"\(scan.name)\" bude trvale smazán.")
        }
        .alert("Chyba AI zpracování", isPresented: $showAIError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(aiError ?? "Neznámá chyba")
        }
    }

    private var actionBar: some View {
        VStack(spacing: 12) {
            if aiService.isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(aiService.processingStage.rawValue)
                        .font(.caption)
                    Spacer()
                    Text("\(Int(aiService.progress * 100))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }

            HStack(spacing: 12) {
                ActionButton(icon: "wand.and.stars", title: "AI", isActive: aiService.isProcessing) {
                    Task { await processWithAI() }
                }
                .disabled(aiService.isProcessing)

                ActionButton(icon: "ruler", title: "Měřit", isActive: showMeasurement) {
                    showMeasurement.toggle()
                }

                ActionButton(icon: "cube.transparent", title: "3D+", isActive: showEnhanced3DViewer) {
                    showEnhanced3DViewer = true
                }

                ActionButton(icon: "arkit", title: "AR", isActive: false) {
                    showARPlacement = true
                }

                ActionButton(icon: "square.and.arrow.up", title: "Export", isActive: false) {
                    showExport = true
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal)
        }
        .padding(.bottom)
    }

    private func processWithAI() async {
        let workingSession = scanStore.getOrCreateSession(for: scan)

        do {
            let options = AIGeometryGenerationService.GenerationOptions(
                mode: .hybrid,
                completionLevel: .medium,
                preserveDetails: true
            )

            let result = try await aiService.generateGeometry(from: workingSession, options: options)

            if let enhancedMesh = result.enhancedMesh as MeshData? {
                workingSession.addMesh(enhancedMesh)
            }
        } catch {
            print("AI processing error: \(error)")
            aiError = error.localizedDescription
            showAIError = true
        }
    }

    private func formatStats(_ scan: ScanModel) -> String {
        let points = scan.pointCount >= 1_000_000
            ? String(format: "%.1fM bodů", Double(scan.pointCount) / 1_000_000)
            : String(format: "%.0fK bodů", Double(scan.pointCount) / 1_000)
        return points
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(isActive ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isActive ? Color.blue : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - 3D Model Viewer

struct Model3DViewer: View {
    let scan: ScanModel
    let session: ScanSession?

    var body: some View {
        ZStack {
            if let session = session {
                SceneKitModelView(session: session)
            } else {
                VStack {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 120))
                        .foregroundStyle(.blue.opacity(0.3))

                    Text("3D data nejsou k dispozici")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - SceneKit Model View

struct SceneKitModelView: UIViewRepresentable {
    let session: ScanSession

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .systemBackground
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = true
        scnView.showsStatistics = false

        let scene = SCNScene()
        scnView.scene = scene

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.position = SCNVector3(0, 2, 5)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        scene.rootNode.addChildNode(ambientLight)

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        guard let scene = scnView.scene else { return }

        scene.rootNode.childNodes
            .filter { $0.name == "scanGeometry" }
            .forEach { $0.removeFromParentNode() }

        if let pointCloud = session.pointCloud {
            let pointNode = createPointCloudNode(from: pointCloud)
            pointNode.name = "scanGeometry"
            scene.rootNode.addChildNode(pointNode)
        }

        for mesh in session.combinedMesh.meshes.values {
            let meshNode = createMeshNode(from: mesh)
            meshNode.name = "scanGeometry"
            scene.rootNode.addChildNode(meshNode)
        }
    }

    private func createPointCloudNode(from pc: PointCloud) -> SCNNode {
        let node = SCNNode()

        var vertices: [SCNVector3] = []
        var colors: [SCNVector4] = []

        for (i, point) in pc.points.enumerated() {
            vertices.append(SCNVector3(point.x, point.y, point.z))

            if let pcColors = pc.colors, i < pcColors.count {
                let c = pcColors[i]
                colors.append(SCNVector4(c.x, c.y, c.z, c.w))
            } else {
                let normalizedY = (point.y + 1) / 3.0
                colors.append(SCNVector4(Float(normalizedY), 0.5, Float(1 - normalizedY), 1.0))
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
