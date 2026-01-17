import SwiftUI

@main
struct LidarAPPApp: App {
    @State private var authService = AuthService()

    var body: some Scene {
        WindowGroup {
            ContentView(authService: authService)
                .task {
                    await authService.restoreSession()
                }
        }
    }
}

struct ContentView: View {
    let authService: AuthService
    @State private var showScanning = false
    @State private var showDeviceError = false
    @State private var showAuth = false
    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header with profile button
                HStack {
                    Spacer()
                    Button(action: {
                        if authService.isLoggedIn {
                            showProfile = true
                        } else {
                            showAuth = true
                        }
                    }) {
                        if let user = authService.currentUser {
                            // User avatar
                            ZStack {
                                Circle()
                                    .fill(.blue.gradient)
                                    .frame(width: 40, height: 40)
                                Text(user.initials)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                            }
                        } else {
                            Image(systemName: "person.circle")
                                .font(.title)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .padding(.horizontal)

                // Logo
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue.gradient)

                    Text("LiDAR 3D Scanner")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Ultra-precise 3D mapping")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // User status banner
                if let user = authService.currentUser {
                    UserStatusBanner(user: user)
                        .padding(.horizontal)
                }

                Spacer()

                // Features
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "camera.metering.spot", title: "LiDAR Scanning", description: "High-precision depth capture")
                    FeatureRow(icon: "ruler", title: "Offline Measurement", description: "Distance, area, volume")
                    FeatureRow(icon: "wand.and.stars", title: "AI Processing", description: "Neural mesh optimization")
                    FeatureRow(icon: "square.and.arrow.up", title: "Export", description: "USDZ, GLTF, OBJ formats")
                }
                .padding(.horizontal, 32)

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    // Start Scanning button
                    Button(action: startScanning) {
                        HStack {
                            Image(systemName: "record.circle")
                            Text("Start Scanning")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    // Login prompt for guests
                    if !authService.isLoggedIn {
                        Button(action: { showAuth = true }) {
                            Text("Log in for cloud processing & more")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .fullScreenCover(isPresented: $showScanning) {
                ScanningView()
            }
            .sheet(isPresented: $showAuth) {
                AuthView(authService: authService)
            }
            .sheet(isPresented: $showProfile) {
                if let user = authService.currentUser {
                    ProfileView(user: user, authService: authService)
                }
            }
            .alert("LiDAR Required", isPresented: $showDeviceError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("This app requires a device with LiDAR sensor (iPhone 12 Pro or later, iPad Pro 2020 or later).")
            }
        }
    }

    private func startScanning() {
        if DeviceCapabilities.hasLiDAR {
            showScanning = true
        } else {
            showDeviceError = true
        }
    }
}

// MARK: - User Status Banner

struct UserStatusBanner: View {
    let user: User

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome, \(user.name)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Image(systemName: "camera.viewfinder")
                        .font(.caption2)
                    Text("\(user.scanCredits) scans remaining")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Subscription badge
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
    ContentView(authService: AuthService())
}
