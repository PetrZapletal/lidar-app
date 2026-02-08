import SwiftUI

/// Hlavní navigační view s tab barem
struct MainTabView: View {
    let services: ServiceContainer

    var body: some View {
        TabView {
            ScanPlaceholderView()
                .tabItem {
                    Label("Scan", systemImage: "viewfinder")
                }

            GalleryPlaceholderView()
                .tabItem {
                    Label("Gallery", systemImage: "photo.on.rectangle.angled")
                }

            SettingsPlaceholderView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .onAppear {
            services.debugStream.trackViewAppeared("MainTabView")
        }
    }
}

// MARK: - Sprint 0 Placeholders

private struct ScanPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("Scanning")
                    .font(.title2)
                Text("Sprint 1: ARSessionService")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Scan")
        }
    }
}

private struct GalleryPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("Gallery")
                    .font(.title2)
                Text("Sprint 2: PersistenceService + Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Gallery")
        }
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "gear")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("Settings")
                    .font(.title2)
                Text("Sprint 5: SettingsView")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Settings")
        }
    }
}
