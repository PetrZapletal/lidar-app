import SwiftUI

@main
struct LidarAPPApp: App {
    @State private var authService = AuthService()
    @State private var scanStore = ScanStore()

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

struct MainTabView: View {
    let authService: AuthService
    let scanStore: ScanStore
    @State private var selectedTab: Tab = .gallery
    @State private var showScanning = false

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

                // Capture placeholder (hidden, accessed via FAB)
                Color.clear
                    .tag(Tab.capture)

                // Profile Tab
                ProfileTabView(authService: authService)
                    .tag(Tab.profile)
            }

            // Custom Tab Bar with floating capture button
            CustomTabBar(
                selectedTab: $selectedTab,
                onCaptureTap: {
                    if DeviceCapabilities.hasLiDAR {
                        showScanning = true
                    }
                }
            )
        }
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: $showScanning) {
            ScanningView()
        }
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // 3D Model Viewer
            Model3DViewer(scan: scan, measurementMode: showMeasurement)
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
                    Button(action: { /* rename */ }) {
                        Label("Přejmenovat", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: { /* delete */ }) {
                        Label("Smazat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showExport) {
            ExportOptionsSheet(scan: scan)
        }
        .fullScreenCover(isPresented: $showARPlacement) {
            ARPlacementView(scan: scan)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            // Measure button
            ActionButton(
                icon: "ruler",
                title: "Měřit",
                isActive: showMeasurement
            ) {
                showMeasurement.toggle()
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
        .padding()
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
    let measurementMode: Bool

    @State private var rotation: Angle = .zero
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color(.systemBackground)

                // 3D content would be rendered here with SceneKit/RealityKit
                // For now, placeholder
                VStack {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 120))
                        .foregroundStyle(.blue.opacity(0.3))
                        .rotationEffect(rotation)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                RotationGesture()
                                    .onChanged { value in
                                        rotation = value
                                    },
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = value
                                    }
                            )
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = value.translation
                                }
                        )

                    Text("Interaktivní 3D náhled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Measurement overlay
                if measurementMode {
                    MeasurementOverlayView()
                }
            }
        }
    }
}

// MARK: - Measurement Overlay

struct MeasurementOverlayView: View {
    @State private var measurementType: MeasurementType = .distance

    enum MeasurementType: String, CaseIterable {
        case distance = "Vzdálenost"
        case area = "Plocha"
        case volume = "Objem"

        var icon: String {
            switch self {
            case .distance: return "ruler"
            case .area: return "square.dashed"
            case .volume: return "cube"
            }
        }
    }

    var body: some View {
        VStack {
            // Top measurement type picker
            Picker("Typ měření", selection: $measurementType) {
                ForEach(MeasurementType.allCases, id: \.self) { type in
                    Label(type.rawValue, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .background(.ultraThinMaterial)

            Spacer()

            // Measurement result
            HStack {
                Image(systemName: measurementType.icon)
                Text("Klepněte na dva body pro měření")
            }
            .font(.subheadline)
            .padding()
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 100)
        }
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

// MARK: - Export Options Sheet

struct ExportOptionsSheet: View {
    let scan: ScanModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("3D formáty") {
                    ExportFormatRow(format: "USDZ", description: "Apple AR formát", icon: "arkit")
                    ExportFormatRow(format: "glTF", description: "Univerzální web formát", icon: "globe")
                    ExportFormatRow(format: "OBJ", description: "Wavefront 3D", icon: "cube")
                    ExportFormatRow(format: "STL", description: "3D tisk", icon: "printer")
                    ExportFormatRow(format: "PLY", description: "Point cloud", icon: "circle.dotted")
                }

                Section("Dokumenty") {
                    ExportFormatRow(format: "PDF", description: "Zpráva s měřeními", icon: "doc.text")
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

struct ExportFormatRow: View {
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
                        StatRow(title: "Celkem skenů", value: "\(user.scanCredits)")
                        StatRow(title: "Zpracováno AI", value: "0")
                        StatRow(title: "Exportováno", value: "0")
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

struct StatRow: View {
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
class ScanStore {
    var scans: [ScanModel] = []

    func loadScans() async {
        // Load from local storage
        // For now, empty
    }

    func addScan(_ scan: ScanModel) {
        scans.insert(scan, at: 0)
    }

    func deleteScan(_ scan: ScanModel) {
        scans.removeAll { $0.id == scan.id }
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

// MARK: - Bundle Extension

extension Bundle {
    var appVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

#Preview {
    MainTabView(authService: AuthService(), scanStore: ScanStore())
}
