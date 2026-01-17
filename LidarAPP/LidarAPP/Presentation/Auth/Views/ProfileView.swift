import SwiftUI

/// User profile and settings view
struct ProfileView: View {
    let user: User
    let authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var showLogoutConfirmation = false
    @State private var showSubscriptionInfo = false

    var body: some View {
        NavigationStack {
            List {
                // User Header
                Section {
                    HStack(spacing: 16) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(.blue.gradient)
                                .frame(width: 70, height: 70)

                            if let avatarURL = user.avatarURL {
                                AsyncImage(url: avatarURL) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Text(user.initials)
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 70, height: 70)
                                .clipShape(Circle())
                            } else {
                                Text(user.initials)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.name)
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text(user.email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 4) {
                                Image(systemName: subscriptionIcon)
                                    .foregroundStyle(subscriptionColor)
                                Text(user.subscription.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(subscriptionColor)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Subscription & Credits
                Section {
                    Button(action: { showSubscriptionInfo = true }) {
                        HStack {
                            Label("Subscription", systemImage: "crown")
                            Spacer()
                            Text(user.subscription.displayName)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)

                    HStack {
                        Label("Scan Credits", systemImage: "camera.viewfinder")
                        Spacer()
                        Text("\(user.scanCredits)")
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                    }

                    if user.subscription == .free {
                        Button(action: { showSubscriptionInfo = true }) {
                            HStack {
                                Spacer()
                                Label("Upgrade to Pro", systemImage: "star.fill")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Plan")
                }

                // Preferences
                Section {
                    NavigationLink {
                        PreferencesView(user: user, authService: authService)
                    } label: {
                        Label("Preferences", systemImage: "gearshape")
                    }

                    NavigationLink {
                        ScanHistoryPlaceholder()
                    } label: {
                        Label("Scan History", systemImage: "clock.arrow.circlepath")
                    }

                    NavigationLink {
                        ExportSettingsPlaceholder()
                    } label: {
                        Label("Export Settings", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Settings")
                }

                // Support
                Section {
                    Link(destination: URL(string: "https://lidarapp.com/help")!) {
                        Label("Help & Support", systemImage: "questionmark.circle")
                    }

                    Link(destination: URL(string: "https://lidarapp.com/feedback")!) {
                        Label("Send Feedback", systemImage: "envelope")
                    }

                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                } header: {
                    Text("Support")
                }

                // Logout
                Section {
                    Button(role: .destructive, action: { showLogoutConfirmation = true }) {
                        HStack {
                            Spacer()
                            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Log Out?", isPresented: $showLogoutConfirmation, titleVisibility: .visible) {
                Button("Log Out", role: .destructive) {
                    Task {
                        await authService.logout()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to log out?")
            }
            .sheet(isPresented: $showSubscriptionInfo) {
                SubscriptionInfoView(currentTier: user.subscription)
            }
        }
    }

    private var subscriptionIcon: String {
        switch user.subscription {
        case .free: return "person.circle"
        case .pro: return "star.circle.fill"
        case .enterprise: return "building.2.crop.circle.fill"
        }
    }

    private var subscriptionColor: Color {
        switch user.subscription {
        case .free: return .secondary
        case .pro: return .orange
        case .enterprise: return .purple
        }
    }
}

// MARK: - Preferences View

struct PreferencesView: View {
    let user: User
    let authService: AuthService
    @State private var preferences: UserPreferences
    @State private var isSaving = false

    init(user: User, authService: AuthService) {
        self.user = user
        self.authService = authService
        _preferences = State(initialValue: user.preferences)
    }

    var body: some View {
        List {
            Section {
                Picker("Measurement Unit", selection: $preferences.measurementUnit) {
                    ForEach(MeasurementUnit.allCases, id: \.self) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }

                Picker("Default Export Format", selection: $preferences.defaultExportFormat) {
                    ForEach(UserPreferences.ExportFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                Picker("Scan Quality", selection: $preferences.scanQuality) {
                    ForEach(UserPreferences.ScanQualityPreference.allCases, id: \.self) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
            } header: {
                Text("Scanning")
            }

            Section {
                Toggle("Auto-upload Scans", isOn: $preferences.autoUpload)
                Toggle("Haptic Feedback", isOn: $preferences.hapticFeedback)
                Toggle("Show Tutorials", isOn: $preferences.showTutorials)
            } header: {
                Text("General")
            }
        }
        .navigationTitle("Preferences")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task {
                            isSaving = true
                            try? await authService.updateUserPreferences(preferences)
                            isSaving = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Subscription Info View

struct SubscriptionInfoView: View {
    let currentTier: SubscriptionTier
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(SubscriptionTier.allCases, id: \.self) { tier in
                        SubscriptionCard(tier: tier, isCurrentTier: tier == currentTier)
                    }
                }
                .padding()
            }
            .navigationTitle("Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct SubscriptionCard: View {
    let tier: SubscriptionTier
    let isCurrentTier: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tier.displayName)
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if isCurrentTier {
                    Text("Current")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }

            ForEach(tier.features, id: \.self) { feature in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(feature)
                        .font(.subheadline)
                }
            }

            if !isCurrentTier && tier != .free {
                Button(action: {
                    // Open subscription purchase
                }) {
                    Text("Upgrade")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(tier == .pro ? .orange : .purple)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCurrentTier ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Placeholder Views

struct ScanHistoryPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "No Scans Yet",
            systemImage: "cube.transparent",
            description: Text("Your scan history will appear here")
        )
        .navigationTitle("Scan History")
    }
}

struct ExportSettingsPlaceholder: View {
    var body: some View {
        Text("Export Settings")
            .navigationTitle("Export Settings")
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.appVersion)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.buildNumber)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Link("Terms of Service", destination: URL(string: "https://lidarapp.com/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://lidarapp.com/privacy")!)
                Link("Open Source Licenses", destination: URL(string: "https://lidarapp.com/licenses")!)
            }
        }
        .navigationTitle("About")
    }
}

#Preview {
    ProfileView(
        user: User(
            id: "1",
            email: "user@example.com",
            displayName: "John Doe",
            subscription: .pro,
            scanCredits: 42
        ),
        authService: AuthService()
    )
}
