import SwiftUI
import SceneKit
import simd

// MARK: - Interactive Measurement View

struct InteractiveMeasurementView: View {
    let session: ScanSession
    @State private var measurementService = MeasurementServiceWrapper()
    @State private var showMeasurementList = false
    @State private var selectedMeasurementMode: MeasurementService.MeasurementMode = .distance
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // 3D View with touch handling
            MeasurementSceneView(
                session: session,
                measurementService: measurementService,
                selectedMode: selectedMeasurementMode
            )
            .ignoresSafeArea()

            // Measurement UI overlay
            VStack {
                // Top toolbar
                measurementToolbar

                Spacer()

                // Current measurement preview
                if !measurementService.currentPoints.isEmpty {
                    currentMeasurementPreview
                }

                // Mode selector and controls
                measurementControls
            }
        }
        .sheet(isPresented: $showMeasurementList) {
            MeasurementListView(measurements: measurementService.measurements) { id in
                measurementService.deleteMeasurement(id)
            }
        }
    }

    private var measurementToolbar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            // Measurement count badge
            Button(action: { showMeasurementList = true }) {
                HStack {
                    Image(systemName: "list.bullet")
                    Text("\(measurementService.measurements.count)")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .foregroundStyle(.white)
        }
        .padding()
    }

    private var currentMeasurementPreview: some View {
        VStack(spacing: 8) {
            // Points indicator
            HStack {
                ForEach(0..<measurementService.currentPoints.count, id: \.self) { index in
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 12, height: 12)
                }

                if pointsNeeded > 0 {
                    ForEach(0..<pointsNeeded, id: \.self) { _ in
                        Circle()
                            .strokeBorder(Color.cyan.opacity(0.5), lineWidth: 2)
                            .frame(width: 12, height: 12)
                    }
                }
            }

            // Live measurement value
            if let previewValue = measurementService.previewValue {
                Text(previewValue)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            // Instructions
            Text(measurementInstructions)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 20)
    }

    private var measurementControls: some View {
        VStack(spacing: 12) {
            // Mode selector
            HStack(spacing: 8) {
                ForEach(MeasurementService.MeasurementMode.allCases, id: \.self) { mode in
                    MeasurementModeButton(
                        mode: mode,
                        isSelected: selectedMeasurementMode == mode
                    ) {
                        selectedMeasurementMode = mode
                        measurementService.setMode(mode)
                    }
                }
            }
            .padding(.horizontal)

            // Action buttons
            HStack(spacing: 20) {
                // Undo last point
                Button(action: { measurementService.removeLastPoint() }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .disabled(measurementService.currentPoints.isEmpty)
                .opacity(measurementService.currentPoints.isEmpty ? 0.5 : 1)

                // Complete measurement (for area/volume)
                if selectedMeasurementMode == .area || selectedMeasurementMode == .volume {
                    Button(action: { measurementService.completeMeasurement() }) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                            .frame(width: 70, height: 70)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .disabled(measurementService.currentPoints.count < 3)
                    .opacity(measurementService.currentPoints.count < 3 ? 0.5 : 1)
                }

                // Clear current
                Button(action: { measurementService.clearCurrentPoints() }) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .disabled(measurementService.currentPoints.isEmpty)
                .opacity(measurementService.currentPoints.isEmpty ? 0.5 : 1)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }

    private var pointsNeeded: Int {
        switch selectedMeasurementMode {
        case .distance:
            return max(0, 2 - measurementService.currentPoints.count)
        case .angle:
            return max(0, 3 - measurementService.currentPoints.count)
        case .area, .volume:
            return max(0, 3 - measurementService.currentPoints.count)
        }
    }

    private var measurementInstructions: String {
        switch selectedMeasurementMode {
        case .distance:
            if measurementService.currentPoints.isEmpty {
                return "Klepněte na první bod"
            } else {
                return "Klepněte na druhý bod"
            }
        case .area:
            if measurementService.currentPoints.count < 3 {
                return "Přidejte alespoň 3 body polygonu"
            } else {
                return "Přidejte další bod nebo potvrďte"
            }
        case .volume:
            if measurementService.currentPoints.count < 4 {
                return "Přidejte alespoň 4 body pro objem"
            } else {
                return "Přidejte další bod nebo potvrďte"
            }
        case .angle:
            switch measurementService.currentPoints.count {
            case 0: return "Klepněte na první bod"
            case 1: return "Klepněte na vrchol úhlu"
            default: return "Klepněte na třetí bod"
            }
        }
    }
}

// MARK: - Measurement Mode Button

struct MeasurementModeButton: View {
    let mode: MeasurementService.MeasurementMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.title2)
                Text(mode.rawValue)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue : Color.clear)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Measurement Scene View

struct MeasurementSceneView: UIViewRepresentable {
    let session: ScanSession
    var measurementService: MeasurementServiceWrapper
    let selectedMode: MeasurementService.MeasurementMode

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1)
        scnView.allowsCameraControl = true
        scnView.showsStatistics = false
        scnView.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        scnView.scene = scene

        // Setup camera
        setupCamera(scene: scene)

        // Setup lighting
        setupLighting(scene: scene)

        // Add tap gesture for measurement
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)

        context.coordinator.scnView = scnView

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        guard let scene = scnView.scene else { return }

        // Update model content
        updateModelContent(scene: scene)

        // Update measurement visualization
        updateMeasurementVisualization(scene: scene)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(measurementService: measurementService, session: session)
    }

    private func setupCamera(scene: SCNScene) {
        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true

        if let bbox = session.pointCloud?.boundingBox {
            let center = bbox.center
            let distance = max(bbox.diagonal * 1.5, 3.0)
            cameraNode.position = SCNVector3(center.x, center.y + distance * 0.3, center.z + distance)
            cameraNode.look(at: SCNVector3(center.x, center.y, center.z))
        } else {
            cameraNode.position = SCNVector3(0, 2, 5)
            cameraNode.look(at: SCNVector3(0, 0, 0))
        }

        scene.rootNode.addChildNode(cameraNode)
    }

    private func setupLighting(scene: SCNScene) {
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 400
        scene.rootNode.addChildNode(ambientLight)

        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.intensity = 800
        directionalLight.position = SCNVector3(5, 10, 5)
        directionalLight.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(directionalLight)
    }

    private func updateModelContent(scene: SCNScene) {
        // Remove old model
        scene.rootNode.childNodes
            .filter { $0.name == "model" }
            .forEach { $0.removeFromParentNode() }

        let modelNode = SCNNode()
        modelNode.name = "model"

        // Add point cloud
        if let pointCloud = session.pointCloud {
            let pcNode = createPointCloudNode(from: pointCloud)
            modelNode.addChildNode(pcNode)
        }

        // Add meshes
        for mesh in session.combinedMesh.meshes.values {
            let meshNode = createMeshNode(from: mesh)
            modelNode.addChildNode(meshNode)
        }

        scene.rootNode.addChildNode(modelNode)
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
                colors.append(SCNVector4(0.7, 0.7, 0.8, 1.0))
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
        elements.pointSize = 2
        elements.minimumPointScreenSpaceRadius = 1
        elements.maximumPointScreenSpaceRadius = 4

        let geometry = SCNGeometry(sources: [pointSource, colorSource], elements: [elements])
        node.geometry = geometry

        return node
    }

    private func createMeshNode(from mesh: MeshData) -> SCNNode {
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
        material.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.5)
        material.isDoubleSided = true
        geometry.materials = [material]

        return SCNNode(geometry: geometry)
    }

    private func updateMeasurementVisualization(scene: SCNScene) {
        // Remove old measurement visualization
        scene.rootNode.childNodes
            .filter { $0.name?.starts(with: "measurement") ?? false }
            .forEach { $0.removeFromParentNode() }

        // Add current measurement points
        for (index, point) in measurementService.currentPoints.enumerated() {
            let sphere = SCNSphere(radius: 0.02)
            sphere.firstMaterial?.diffuse.contents = UIColor.cyan
            sphere.firstMaterial?.emission.contents = UIColor.cyan
            let node = SCNNode(geometry: sphere)
            node.name = "measurement_point_\(index)"
            node.position = SCNVector3(point.x, point.y, point.z)
            scene.rootNode.addChildNode(node)
        }

        // Add lines between points
        if measurementService.currentPoints.count >= 2 {
            for i in 0..<(measurementService.currentPoints.count - 1) {
                let lineNode = createLineNode(
                    from: measurementService.currentPoints[i],
                    to: measurementService.currentPoints[i + 1],
                    color: .cyan
                )
                lineNode.name = "measurement_line_\(i)"
                scene.rootNode.addChildNode(lineNode)
            }

            // Close polygon for area measurement
            if selectedMode == .area && measurementService.currentPoints.count >= 3 {
                let lineNode = createLineNode(
                    from: measurementService.currentPoints.last!,
                    to: measurementService.currentPoints.first!,
                    color: .cyan.withAlphaComponent(0.5)
                )
                lineNode.name = "measurement_line_close"
                scene.rootNode.addChildNode(lineNode)
            }
        }

        // Add saved measurements
        for (index, measurement) in measurementService.measurements.enumerated() {
            addMeasurementVisualization(measurement, index: index, to: scene)
        }
    }

    private func addMeasurementVisualization(
        _ measurement: MeasurementService.MeasurementResult,
        index: Int,
        to scene: SCNScene
    ) {
        let color: UIColor = {
            switch measurement.type {
            case .distance: return .green
            case .area: return .orange
            case .volume: return .purple
            case .angle: return .yellow
            }
        }()

        // Add points
        for (pointIndex, point) in measurement.points.enumerated() {
            let sphere = SCNSphere(radius: 0.015)
            sphere.firstMaterial?.diffuse.contents = color
            let node = SCNNode(geometry: sphere)
            node.name = "measurement_saved_\(index)_point_\(pointIndex)"
            node.position = SCNVector3(point.x, point.y, point.z)
            scene.rootNode.addChildNode(node)
        }

        // Add lines
        if measurement.points.count >= 2 {
            for i in 0..<(measurement.points.count - 1) {
                let lineNode = createLineNode(
                    from: measurement.points[i],
                    to: measurement.points[i + 1],
                    color: color
                )
                lineNode.name = "measurement_saved_\(index)_line_\(i)"
                scene.rootNode.addChildNode(lineNode)
            }
        }

        // Add label at centroid
        let centroid = measurement.points.reduce(simd_float3.zero, +) / Float(measurement.points.count)
        let labelNode = createLabelNode(text: measurement.formattedValue, color: color)
        labelNode.name = "measurement_saved_\(index)_label"
        labelNode.position = SCNVector3(centroid.x, centroid.y + 0.1, centroid.z)
        scene.rootNode.addChildNode(labelNode)
    }

    private func createLineNode(from start: simd_float3, to end: simd_float3, color: UIColor) -> SCNNode {
        let vertices: [SCNVector3] = [
            SCNVector3(start.x, start.y, start.z),
            SCNVector3(end.x, end.y, end.z)
        ]

        let source = SCNGeometrySource(vertices: vertices)
        let indices: [Int32] = [0, 1]
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)

        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        geometry.materials = [material]

        return SCNNode(geometry: geometry)
    }

    private func createLabelNode(text: String, color: UIColor) -> SCNNode {
        let textGeometry = SCNText(string: text, extrusionDepth: 0.01)
        textGeometry.font = UIFont.systemFont(ofSize: 0.1, weight: .bold)
        textGeometry.firstMaterial?.diffuse.contents = color
        textGeometry.firstMaterial?.emission.contents = color

        let node = SCNNode(geometry: textGeometry)
        node.scale = SCNVector3(0.3, 0.3, 0.3)

        // Center the text
        let (min, max) = textGeometry.boundingBox
        node.pivot = SCNMatrix4MakeTranslation(
            (max.x - min.x) / 2 + min.x,
            (max.y - min.y) / 2 + min.y,
            0
        )

        // Make it always face the camera
        node.constraints = [SCNBillboardConstraint()]

        return node
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        weak var scnView: SCNView?
        let measurementService: MeasurementServiceWrapper
        let session: ScanSession
        private let distanceCalculator = DistanceCalculator()

        init(measurementService: MeasurementServiceWrapper, session: ScanSession) {
            self.measurementService = measurementService
            self.session = session
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = scnView else { return }

            let location = gesture.location(in: scnView)

            // Hit test against the model
            let hitResults = scnView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue
            ])

            if let hit = hitResults.first(where: { $0.node.name != "camera" && !($0.node.name?.starts(with: "measurement") ?? false) }) {
                let worldPosition = hit.worldCoordinates
                let point = simd_float3(Float(worldPosition.x), Float(worldPosition.y), Float(worldPosition.z))

                // Snap to mesh if available
                let snappedPoint = snapToMesh(point)

                Task { @MainActor in
                    measurementService.addPoint(snappedPoint)
                }
            }
        }

        private func snapToMesh(_ point: simd_float3) -> simd_float3 {
            // Try to snap to the nearest mesh vertex/surface
            for mesh in session.combinedMesh.meshes.values {
                if let closest = distanceCalculator.closestPointOnMesh(point: point, mesh: mesh) {
                    if closest.distance < 0.05 {  // 5cm threshold
                        return closest.point
                    }
                }
            }
            return point
        }
    }
}

// MARK: - Measurement Service Wrapper

@MainActor
@Observable
class MeasurementServiceWrapper {
    private let service = MeasurementService()

    var currentPoints: [simd_float3] = []
    var measurements: [MeasurementService.MeasurementResult] = []
    var previewValue: String?

    func setMode(_ mode: MeasurementService.MeasurementMode) {
        service.setMode(mode)
        updateState()
    }

    func addPoint(_ point: simd_float3) {
        service.addPoint(point)
        updateState()
    }

    func removeLastPoint() {
        service.removeLastPoint()
        updateState()
    }

    func clearCurrentPoints() {
        service.clearCurrentPoints()
        updateState()
    }

    func completeMeasurement() {
        service.completeMeasurement()
        updateState()
    }

    func deleteMeasurement(_ id: UUID) {
        service.deleteMeasurement(id)
        updateState()
    }

    private func updateState() {
        currentPoints = service.currentPoints
        measurements = service.measurements

        // Calculate preview value
        if currentPoints.count >= 2, service.currentMode == .distance {
            let distance = simd_distance(currentPoints[0], currentPoints[1])
            previewValue = String(format: "%.2f m", distance)
        } else if currentPoints.count >= 3, service.currentMode == .area {
            if let preview = service.previewArea(with: currentPoints.last!) {
                previewValue = String(format: "%.2f m²", preview)
            }
        } else {
            previewValue = nil
        }
    }
}

// MARK: - Measurement List View

struct MeasurementListView: View {
    let measurements: [MeasurementService.MeasurementResult]
    let onDelete: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if measurements.isEmpty {
                    ContentUnavailableView {
                        Label("Žádná měření", systemImage: "ruler")
                    } description: {
                        Text("Klepnutím na model přidejte body měření")
                    }
                } else {
                    ForEach(measurements) { measurement in
                        MeasurementRow(measurement: measurement)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            onDelete(measurements[index].id)
                        }
                    }
                }
            }
            .navigationTitle("Měření")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hotovo") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct MeasurementRow: View {
    let measurement: MeasurementService.MeasurementResult

    var body: some View {
        HStack {
            Image(systemName: measurement.type.icon)
                .foregroundStyle(iconColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(measurement.formattedValue)
                    .font(.headline)

                HStack {
                    Text(measurement.type.rawValue)
                    if let confidence = measurement.confidence as Float?, confidence < 1.0 {
                        Text("(\(Int(confidence * 100))%)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(measurement.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var iconColor: Color {
        switch measurement.type {
        case .distance: return .green
        case .area: return .orange
        case .volume: return .purple
        case .angle: return .yellow
        }
    }
}

// MARK: - Preview

#Preview {
    InteractiveMeasurementView(session: MockDataProvider.shared.createMockScanSession())
}
