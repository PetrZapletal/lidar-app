import SwiftUI

/// Hlavní navigační view s tab barem
struct MainTabView: View {
    let services: ServiceContainer
    @State private var showScanning = false

    var body: some View {
        TabView {
            ScanTabView(services: services, showScanning: $showScanning)
                .tabItem {
                    Label("Scan", systemImage: "viewfinder")
                }

            GalleryView(services: services)
                .tabItem {
                    Label("Galerie", systemImage: "photo.on.rectangle.angled")
                }

            SettingsView(services: services)
                .tabItem {
                    Label("Nastavení", systemImage: "gear")
                }
        }
        .onAppear {
            services.debugStream.trackViewAppeared("MainTabView")
        }
    }
}

// MARK: - Scan Tab (Sprint 1)

private struct ScanTabView: View {
    let services: ServiceContainer
    @Binding var showScanning: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "viewfinder")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue.gradient)

                Text("LiDAR Scanner")
                    .font(.title)
                    .fontWeight(.bold)

                Text("3D skenování prostoru pomocí LiDAR senzoru")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(action: { showScanning = true }) {
                    Label("Zahájit skenování", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 40)

                Spacer()
            }
            .navigationTitle("Scan")
            .fullScreenCover(isPresented: $showScanning) {
                ScanningView(services: services)
            }
        }
    }
}

