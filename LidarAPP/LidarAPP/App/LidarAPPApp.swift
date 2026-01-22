import SwiftUI
import SceneKit

@main
struct LidarAPPApp: App {
    @State private var authService = AuthService()
    @State private var scanStore = ScanStore()

    init() {
        // Start crash reporting with MetricKit
        CrashReporter.shared.start()

        // Start debug streaming if raw data mode is enabled
        #if DEBUG
        if DebugSettings.shared.rawDataModeEnabled {
            DebugSettings.shared.debugStreamEnabled = true
            DebugStreamService.shared.startStreaming()
            print("Debug: Auto-started debug streaming (rawDataModeEnabled)")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(authService: authService, scanStore: scanStore)
                .task {
                    await authService.restoreSession()
                    await scanStore.loadScans()
                }
        }
    }
}

// MARK: - Main Tab View

/// Scan mode selection per LUMISCAN specification
enum ScanMode: String, CaseIterable {
    case exterior   // Buildings, facades, outdoor - ARKit with gravityAndHeading
    case interior   // Rooms - RoomPlan API
    case object     // Standalone objects - ObjectCaptureSession

    var displayName: String {
        switch self {
        case .exterior: return "Exteriér"
        case .interior: return "Interiér"
        case .object: return "Objekt"
        }
    }

    var icon: String {
        switch self {
        case .exterior: return "building.2"
        case .interior: return "house.fill"
        case .object: return "cube.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .exterior: return "Budovy a fasády"
        case .interior: return "Místnosti (RoomPlan)"
        case .object: return "Samostatné předměty"
        }
    }

    var description: String {
        switch self {
        case .exterior:
            return "Skenování exteriérů, budov a fasád. Využívá GPS pro přesné umístění."
        case .interior:
            return "Automatická detekce stěn, dveří a oken. Optimalizované pro interiéry."
        case .object:
            return "Skenování objektů na stole nebo vozu. Chodíte kolem objektu dokola."
        }
    }

    var color: Color {
        switch self {
        case .exterior: return .green
        case .interior: return .blue
        case .object: return .orange
        }
    }
}

struct MainTabView: View {
    let authService: AuthService
    let scanStore: ScanStore
    @State private var selectedTab: Tab = .gallery
    @State private var showScanning = false
    @State private var showActiveScan = false
    @State private var selectedScanMode: ScanMode = .exterior

    enum Tab: Int {
        case gallery
        case capture
        case profile
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                // Gallery Tab
                GalleryView(scanStore: scanStore)
                    .tag(Tab.gallery)
                    .toolbar(.hidden, for: .tabBar)

                // Capture placeholder (hidden, accessed via FAB)
                Color.clear
                    .tag(Tab.capture)
                    .toolbar(.hidden, for: .tabBar)

                // Profile Tab
                ProfileTabView(authService: authService)
                    .tag(Tab.profile)
                    .toolbar(.hidden, for: .tabBar)
            }

            // Custom Tab Bar with floating capture button
            CustomTabBar(
                selectedTab: $selectedTab,
                onCaptureTap: {
                    // Allow scanning with real LiDAR or in mock mode (for simulator testing)
                    if DeviceCapabilities.hasLiDAR || MockDataProvider.isMockModeEnabled {
                        showScanning = true
                    }
                }
            )
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showScanning) {
            ScanModeSelector { mode in
                showScanning = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    selectedScanMode = mode
                    showActiveScan = true
                }
            }
            .presentationDetents([.height(400)])
        }
        .fullScreenCover(isPresented: $showActiveScan) {
            switch selectedScanMode {
            case .exterior:
                // Exterior uses LiDAR scanning with GPS/heading alignment
                ScanningView(mode: .exterior) { savedScan, session in
                    scanStore.addScan(savedScan, session: session)
                }
            case .interior:
                // Interior uses RoomPlan API
                RoomPlanScanningView { savedScan, session in
                    scanStore.addScan(savedScan, session: session)
                }
            case .object:
                // Object uses ObjectCaptureSession API
                ObjectCaptureScanningView { savedScan, session in
                    scanStore.addScan(savedScan, session: session)
                }
            }
        }
    }
}

// MARK: - Scan Mode Selector

struct ScanModeSelector: View {
    let onModeSelected: (ScanMode) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Vyberte režim skenování")
                    .font(.headline)
                    .padding(.top)

                // Exterior Scanning
                ScanModeCard(
                    icon: ScanMode.exterior.icon,
                    title: ScanMode.exterior.displayName,
                    subtitle: ScanMode.exterior.subtitle,
                    description: ScanMode.exterior.description,
                    color: ScanMode.exterior.color,
                    isSupported: DeviceCapabilities.hasLiDAR || MockDataProvider.isMockModeEnabled
                ) {
                    onModeSelected(.exterior)
                }

                // Interior Scanning (RoomPlan)
                ScanModeCard(
                    icon: ScanMode.interior.icon,
                    title: ScanMode.interior.displayName,
                    subtitle: ScanMode.interior.subtitle,
                    description: ScanMode.interior.description,
                    color: ScanMode.interior.color,
                    isSupported: RoomPlanService.shared.isSupported || MockDataProvider.isMockModeEnabled
                ) {
                    onModeSelected(.interior)
                }

                // Object Scanning
                ScanModeCard(
                    icon: ScanMode.object.icon,
                    title: ScanMode.object.displayName,
                    subtitle: ScanMode.object.subtitle,
                    description: ScanMode.object.description,
                    color: ScanMode.object.color,
                    isSupported: ObjectCaptureService.isSupported || MockDataProvider.isMockModeEnabled
                ) {
                    onModeSelected(.object)
                }

                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zrušit") { dismiss() }
                }
            }
        }
    }
}

struct ScanModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let description: String
    let color: Color
    var isSupported: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(color)
                    .frame(width: 60)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.headline)
                        if !isSupported {
                            Text("Nepodporováno")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.red.opacity(0.2))
                                .foregroundStyle(.red)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!isSupported)
        .opacity(isSupported ? 1 : 0.5)
        .foregroundStyle(.primary)
    }
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: MainTabView.Tab
    let onCaptureTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Gallery button
            TabBarButton(
                icon: "cube.fill",
                title: "Galerie",
                isSelected: selectedTab == .gallery
            ) {
                selectedTab = .gallery
            }

            Spacer()

            // Central capture button
            Button(action: onCaptureTap) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)

                    Image(systemName: "viewfinder")
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
            .offset(y: -20)

            Spacer()

            // Profile button
            TabBarButton(
                icon: "person.fill",
                title: "Profil",
                isSelected: selectedTab == .profile
            ) {
                selectedTab = .profile
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        )
    }
}

struct TabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(isSelected ? .blue : .secondary)
        }
        .frame(width: 60)
    }
}

// MARK: - Gallery View

struct GalleryView: View {
    let scanStore: ScanStore
    @State private var searchText = ""
    @State private var selectedScan: ScanModel?
    @State private var sortOrder: SortOrder = .dateDescending
    @State private var viewMode: ViewMode = .grid

    enum SortOrder: String, CaseIterable {
        case dateDescending = "Nejnovější"
        case dateAscending = "Nejstarší"
        case nameAscending = "Název A-Z"
        case sizeDescending = "Největší"
    }

    enum ViewMode {
        case grid
        case list
    }

    var filteredScans: [ScanModel] {
        var scans = scanStore.scans
        if !searchText.isEmpty {
            scans = scans.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return scans.sorted(by: sortOrder)
    }

    var body: some View {
        NavigationStack {
            Group {
                if scanStore.scans.isEmpty {
                    emptyStateView
                } else {
                    scanGridView
                }
            }
            .navigationTitle("Moje 3D modely")
            .searchable(text: $searchText, prompt: "Hledat modely")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Řazení", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }

                        Divider()

                        Button(action: { viewMode = .grid }) {
                            Label("Mřížka", systemImage: "square.grid.2x2")
                        }
                        Button(action: { viewMode = .list }) {
                            Label("Seznam", systemImage: "list.bullet")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
            }
            .navigationDestination(item: $selectedScan) { scan in
                ModelDetailView(scan: scan, scanStore: scanStore)
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("Žádné modely", systemImage: "cube.transparent")
        } description: {
            Text("Vytvořte svůj první 3D sken pomocí tlačítka skenování")
        } actions: {
            Text("Stiskněte modré tlačítko dole")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var scanGridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(filteredScans) { scan in
                    ScanGridCard(scan: scan)
                        .onTapGesture {
                            selectedScan = scan
                        }
                }
            }
            .padding()
        }
    }
}

// MARK: - Scan Grid Card

struct ScanGridCard: View {
    let scan: ScanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 3D Preview thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .aspectRatio(1, contentMode: .fit)

                if let thumbnail = scan.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue.opacity(0.5))
                }

                // Status badges
                VStack {
                    HStack {
                        Spacer()
                        if scan.isProcessed {
                            Label("AI", systemImage: "wand.and.stars")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.green)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    Spacer()
                }
                .padding(8)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(scan.createdAt.formatted(date: .abbreviated, time: .omitted))
                    Text("•")
                    Text(formatFileSize(scan.fileSize))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Model Detail View

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
    @StateObject private var aiService = AIGeometryGenerationService()
    @Environment(\.dismiss) private var dismiss

    /// The scan session with actual 3D data
    private var session: ScanSession? {
        scanStore.getSession(for: scan.id)
    }

    var body: some View {
        ZStack {
            // 3D Model Viewer
            Model3DViewer(scan: scan, session: session)
                .ignoresSafeArea()

            // Overlay controls
            VStack {
                Spacer()

                // Bottom action bar
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
            // AI Processing indicator
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
                // AI Enhancement button
                ActionButton(
                    icon: "wand.and.stars",
                    title: "AI",
                    isActive: aiService.isProcessing
                ) {
                    Task {
                        await processWithAI()
                    }
                }
                .disabled(aiService.isProcessing)

                // Measure button
                ActionButton(
                    icon: "ruler",
                    title: "Měřit",
                    isActive: showMeasurement
                ) {
                    showMeasurement.toggle()
                }

                // Enhanced 3D View
                ActionButton(
                    icon: "cube.transparent",
                    title: "3D+",
                    isActive: showEnhanced3DViewer
                ) {
                    showEnhanced3DViewer = true
                }

                // AR View button
                ActionButton(
                    icon: "arkit",
                    title: "AR",
                    isActive: false
                ) {
                    showARPlacement = true
                }

                // Export button
                ActionButton(
                    icon: "square.and.arrow.up",
                    title: "Export",
                    isActive: false
                ) {
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
        // Get existing session or create mock one for testing
        let workingSession = scanStore.getOrCreateSession(for: scan)

        do {
            let options = AIGeometryGenerationService.GenerationOptions(
                mode: .hybrid,
                completionLevel: .medium,
                preserveDetails: true
            )

            let result = try await aiService.generateGeometry(from: workingSession, options: options)

            // Update session with enhanced mesh
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
                // Real 3D content using SceneKit
                SceneKitModelView(session: session)
            } else {
                // Fallback placeholder when no session data
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

        // Add camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.position = SCNVector3(0, 2, 5)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        // Add ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        scene.rootNode.addChildNode(ambientLight)

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        guard let scene = scnView.scene else { return }

        // Remove old geometry
        scene.rootNode.childNodes
            .filter { $0.name == "scanGeometry" }
            .forEach { $0.removeFromParentNode() }

        // Add point cloud if available
        if let pointCloud = session.pointCloud {
            let pointNode = createPointCloudNode(from: pointCloud)
            pointNode.name = "scanGeometry"
            scene.rootNode.addChildNode(pointNode)
        }

        // Add meshes
        for mesh in session.combinedMesh.meshes.values {
            let meshNode = createMeshNode(from: mesh)
            meshNode.name = "scanGeometry"
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
                // Default color based on height
                let normalizedY = (point.y + 1) / 3.0  // Normalize height
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

// MARK: - AR Placement View

struct ARPlacementView: View {
    let scan: ScanModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // AR content would go here
            Color.black

            VStack {
                // Instructions
                Text("Nasměrujte kameru na rovný povrch")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 60)

                Spacer()

                // Close button
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Gallery Export Sheet

struct GalleryExportSheet: View {
    let scan: ScanModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("3D formáty") {
                    GalleryExportFormatRow(format: "USDZ", description: "Apple AR formát", icon: "arkit")
                    GalleryExportFormatRow(format: "glTF", description: "Univerzální web formát", icon: "globe")
                    GalleryExportFormatRow(format: "OBJ", description: "Wavefront 3D", icon: "cube")
                    GalleryExportFormatRow(format: "STL", description: "3D tisk", icon: "printer")
                    GalleryExportFormatRow(format: "PLY", description: "Point cloud", icon: "circle.dotted")
                }

                Section("Dokumenty") {
                    GalleryExportFormatRow(format: "PDF", description: "Zpráva s měřeními", icon: "doc.text")
                }
            }
            .navigationTitle("Exportovat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hotovo") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct GalleryExportFormatRow: View {
    let format: String
    let description: String
    let icon: String

    var body: some View {
        Button(action: { /* export */ }) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 30)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading) {
                    Text(format)
                        .fontWeight(.medium)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.blue)
            }
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Profile Tab View

struct ProfileTabView: View {
    let authService: AuthService
    @State private var showSettings = false
    @State private var showAuth = false

    var body: some View {
        NavigationStack {
            List {
                if let user = authService.currentUser {
                    // User info section
                    Section {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(.blue.gradient)
                                    .frame(width: 60, height: 60)
                                Text(user.initials)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(.headline)
                                Text(user.email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text(user.subscription.displayName)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // Stats section
                    Section("Statistiky") {
                        ProfileStatRow(title: "Celkem skenů", value: "\(user.scanCredits)")
                        ProfileStatRow(title: "Zpracováno AI", value: "0")
                        ProfileStatRow(title: "Exportováno", value: "0")
                    }
                } else {
                    // Not logged in
                    Section {
                        Button(action: { showAuth = true }) {
                            HStack {
                                Image(systemName: "person.circle")
                                    .font(.title)
                                VStack(alignment: .leading) {
                                    Text("Přihlásit se")
                                        .font(.headline)
                                    Text("Pro cloud zpracování a synchronizaci")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Settings section
                Section {
                    Button(action: { showSettings = true }) {
                        Label("Nastavení", systemImage: "gearshape")
                    }

                    NavigationLink {
                        Text("Nápověda")
                    } label: {
                        Label("Nápověda", systemImage: "questionmark.circle")
                    }

                    Link(destination: URL(string: "https://lidarscanner.app")!) {
                        Label("Webové stránky", systemImage: "globe")
                    }
                }

                // App info
                Section {
                    HStack {
                        Text("Verze")
                        Spacer()
                        Text(Bundle.main.appVersion)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Profil")
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showAuth) {
                AuthView(authService: authService)
            }
        }
    }
}

struct ProfileStatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
        }
    }
}

// MARK: - Scan Model

struct ScanModel: Identifiable, Hashable {
    let id: String
    var name: String
    let createdAt: Date
    var thumbnail: UIImage?
    let pointCount: Int
    let faceCount: Int
    let fileSize: Int64
    let isProcessed: Bool
    let localURL: URL?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ScanModel, rhs: ScanModel) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Scan Store

@Observable
final class ScanStore {
    var scans: [ScanModel] = []

    /// Stores actual 3D data (point clouds, meshes) by scan ID
    private var scanSessions: [String: ScanSession] = [:]

    func loadScans() async {
        // Load from local storage
        // For now, create mock scans for testing in simulator
        if MockDataProvider.isMockModeEnabled && scans.isEmpty {
            loadMockScans()
        }
    }

    private func loadMockScans() {
        let mockProvider = MockDataProvider.shared

        // Create sample mock scans for testing
        let mockScan1 = ScanModel(
            id: UUID().uuidString,
            name: "Obyvaci pokoj",
            createdAt: Date().addingTimeInterval(-86400), // 1 day ago
            thumbnail: nil,
            pointCount: 125000,
            faceCount: 42000,
            fileSize: 15_000_000,
            isProcessed: true,
            localURL: nil
        )
        let session1 = mockProvider.createMockScanSession(name: "Obyvaci pokoj")
        addScan(mockScan1, session: session1)

        let mockScan2 = ScanModel(
            id: UUID().uuidString,
            name: "Kuchyn",
            createdAt: Date().addingTimeInterval(-172800), // 2 days ago
            thumbnail: nil,
            pointCount: 85000,
            faceCount: 28000,
            fileSize: 10_500_000,
            isProcessed: true,
            localURL: nil
        )
        let session2 = mockProvider.createMockScanSession(name: "Kuchyn")
        addScan(mockScan2, session: session2)

        let mockScan3 = ScanModel(
            id: UUID().uuidString,
            name: "Loznice",
            createdAt: Date().addingTimeInterval(-259200), // 3 days ago
            thumbnail: nil,
            pointCount: 95000,
            faceCount: 32000,
            fileSize: 12_000_000,
            isProcessed: false,
            localURL: nil
        )
        let session3 = mockProvider.createMockScanSession(name: "Loznice")
        addScan(mockScan3, session: session3)
    }

    func addScan(_ scan: ScanModel) {
        scans.insert(scan, at: 0)
    }

    func addScan(_ scan: ScanModel, session: ScanSession) {
        scans.insert(scan, at: 0)
        scanSessions[scan.id] = session
    }

    func getSession(for scanId: String) -> ScanSession? {
        scanSessions[scanId]
    }

    func deleteScan(_ scan: ScanModel) {
        scans.removeAll { $0.id == scan.id }
        scanSessions.removeValue(forKey: scan.id)
    }

    func renameScan(_ scan: ScanModel, to newName: String) {
        if let index = scans.firstIndex(where: { $0.id == scan.id }) {
            scans[index].name = newName
        }
    }

    /// Get existing session or create a mock one for testing
    func getOrCreateSession(for scan: ScanModel) -> ScanSession {
        if let existing = scanSessions[scan.id] {
            return existing
        }

        // Create mock session for testing
        let mockSession = MockDataProvider.shared.createMockScanSession(name: scan.name)
        scanSessions[scan.id] = mockSession
        return mockSession
    }
}

extension [ScanModel] {
    func sorted(by order: GalleryView.SortOrder) -> [ScanModel] {
        switch order {
        case .dateDescending:
            return sorted { $0.createdAt > $1.createdAt }
        case .dateAscending:
            return sorted { $0.createdAt < $1.createdAt }
        case .nameAscending:
            return sorted { $0.name < $1.name }
        case .sizeDescending:
            return sorted { $0.fileSize > $1.fileSize }
        }
    }
}

// MARK: - User Status Banner

struct UserStatusBanner: View {
    let user: User

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Vítejte, \(user.name)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Image(systemName: "camera.viewfinder")
                        .font(.caption2)
                    Text("\(user.scanCredits) skenů zbývá")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(user.subscription.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(subscriptionColor.opacity(0.15))
                .foregroundStyle(subscriptionColor)
                .clipShape(Capsule())
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var subscriptionColor: Color {
        switch user.subscription {
        case .free: return .gray
        case .pro: return .orange
        case .enterprise: return .purple
        }
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    MainTabView(authService: AuthService(), scanStore: ScanStore())
}
