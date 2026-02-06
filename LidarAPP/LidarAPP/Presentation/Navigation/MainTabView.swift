import SwiftUI

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
                GalleryView(scanStore: scanStore)
                    .tag(Tab.gallery)
                    .toolbar(.hidden, for: .tabBar)

                Color.clear
                    .tag(Tab.capture)
                    .toolbar(.hidden, for: .tabBar)

                ProfileTabView(authService: authService)
                    .tag(Tab.profile)
                    .toolbar(.hidden, for: .tabBar)
            }

            CustomTabBar(
                selectedTab: $selectedTab,
                onCaptureTap: {
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
                LiDARUnifiedScanningView(scanMode: .exterior) { savedScan, session in
                    scanStore.addScan(savedScan, session: session)
                }
            case .interior:
                UnifiedScanningView(mode: RoomPlanScanningModeAdapter()) { savedScan, session in
                    scanStore.addScan(savedScan, session: session)
                }
            case .object:
                UnifiedScanningView(mode: ObjectCaptureScanningModeAdapter()) { savedScan, session in
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

// MARK: - Scan Mode Card

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
            TabBarButton(
                icon: "cube.fill",
                title: "Galerie",
                isSelected: selectedTab == .gallery
            ) {
                selectedTab = .gallery
            }

            Spacer()

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

#Preview {
    MainTabView(authService: AuthService(), scanStore: ScanStore())
}
