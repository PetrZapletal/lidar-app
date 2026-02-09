import SwiftUI

/// Hlavní obrazovka nastavení aplikace
struct SettingsView: View {
    let services: ServiceContainer
    @State private var viewModel: SettingsViewModel
    @State private var showResetConfirmation = false
    @State private var showClearCacheConfirmation = false
    @State private var showSignOutConfirmation = false
    @State private var showExportedLogsShare = false
    @State private var exportedLogsURL: URL?

    init(services: ServiceContainer) {
        self.services = services
        self._viewModel = State(initialValue: SettingsViewModel(services: services))
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                scanningSection
                exportSection
                serverSection
                debugSection
                aboutSection
                dangerZoneSection
            }
            .navigationTitle("Nastavení")
            .onAppear {
                services.debugStream.trackViewAppeared("SettingsView")
            }
            .alert("Resetovat nastavení", isPresented: $showResetConfirmation) {
                Button("Zrušit", role: .cancel) { }
                Button("Resetovat", role: .destructive) {
                    viewModel.resetSettings()
                }
            } message: {
                Text("Všechna nastavení budou obnovena na výchozí hodnoty. Tuto akci nelze vrátit zpět.")
            }
            .alert("Vymazat cache", isPresented: $showClearCacheConfirmation) {
                Button("Zrušit", role: .cancel) { }
                Button("Vymazat", role: .destructive) {
                    Task {
                        await viewModel.clearCache()
                    }
                }
            } message: {
                Text("Dočasné soubory a mezipaměť budou vymazány.")
            }
            .alert("Odhlásit se", isPresented: $showSignOutConfirmation) {
                Button("Zrušit", role: .cancel) { }
                Button("Odhlásit", role: .destructive) {
                    Task {
                        await viewModel.signOut()
                    }
                }
            } message: {
                Text("Budete odhlášeni z vašeho účtu.")
            }
            .sheet(isPresented: $showExportedLogsShare) {
                if let url = exportedLogsURL {
                    ShareSheet(items: [url])
                }
            }
        }
        .accessibilityIdentifier("settings.view")
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section {
            if viewModel.isSignedIn {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.userName)
                            .font(.headline)
                        Text(viewModel.userEmail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    Label("Odhlásit se", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityIdentifier("settings.signOutButton")
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nepřihlášen")
                            .font(.headline)
                        Text("Přihlaste se pro synchronizaci")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Button {
                    // Future: navigate to auth flow
                    debugLog("Sign in tapped - not yet implemented", category: .logCategoryUI)
                } label: {
                    Label("Přihlásit se", systemImage: "person.badge.plus")
                }
                .accessibilityIdentifier("settings.signInButton")
            }
        } header: {
            Text("Účet")
        }
    }

    // MARK: - Scanning Section

    private var scanningSection: some View {
        Section {
            Picker("Výchozí režim", selection: $viewModel.defaultScanMode) {
                ForEach(ScanMode.allCases, id: \.rawValue) { mode in
                    Label(mode.displayName, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .accessibilityIdentifier("settings.defaultScanModePicker")

            Toggle("Automatické ukládání", isOn: $viewModel.autoSaveEnabled)
                .accessibilityIdentifier("settings.autoSaveToggle")
        } header: {
            Text("Skenování")
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section {
            Picker("Výchozí formát", selection: $viewModel.defaultExportFormat) {
                ForEach(SettingsViewModel.availableExportFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }
            .accessibilityIdentifier("settings.exportFormatPicker")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Kvalita exportu")
                    Spacer()
                    Text("\(Int(viewModel.exportQuality * 100))%")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                Slider(value: $viewModel.exportQuality, in: 0.1...1.0, step: 0.05)
                    .accessibilityIdentifier("settings.exportQualitySlider")
            }
        } header: {
            Text("Export")
        }
    }

    // MARK: - Server Section

    private var serverSection: some View {
        Section {
            NavigationLink {
                ServerSettingsView(viewModel: viewModel)
            } label: {
                HStack {
                    Label("Konfigurace serveru", systemImage: "server.rack")
                    Spacer()
                    if viewModel.isServerConnected {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
            .accessibilityIdentifier("settings.serverSettingsLink")
        } header: {
            Text("Server")
        } footer: {
            if viewModel.isServerConnected {
                Text("Připojeno k \(viewModel.serverIP):\(viewModel.serverPort)")
            } else {
                Text("Nepřipojeno")
            }
        }
    }

    // MARK: - Debug Section

    private var debugSection: some View {
        Section {
            NavigationLink {
                DebugSettingsView(viewModel: viewModel, services: services)
            } label: {
                Label("Debug nastavení", systemImage: "ladybug")
            }
            .accessibilityIdentifier("settings.debugSettingsLink")

            Toggle("Performance overlay", isOn: $viewModel.showPerformanceOverlay)
                .accessibilityIdentifier("settings.performanceOverlayToggle")
        } header: {
            Text("Debug")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutView(viewModel: viewModel)
            } label: {
                Label("O aplikaci", systemImage: "info.circle")
            }
            .accessibilityIdentifier("settings.aboutLink")

            HStack {
                Text("Verze")
                Spacer()
                Text("\(viewModel.appVersion) (\(viewModel.buildNumber))")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("O aplikaci")
        }
    }

    // MARK: - Danger Zone Section

    private var dangerZoneSection: some View {
        Section {
            Button {
                showClearCacheConfirmation = true
            } label: {
                HStack {
                    Label("Vymazat cache", systemImage: "trash")
                    Spacer()
                    if viewModel.isClearingCache {
                        ProgressView()
                    } else if viewModel.cacheCleared {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .disabled(viewModel.isClearingCache)
            .accessibilityIdentifier("settings.clearCacheButton")

            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Resetovat nastavení", systemImage: "arrow.counterclockwise")
            }
            .accessibilityIdentifier("settings.resetButton")
        } header: {
            Text("Údržba")
        }
    }
}