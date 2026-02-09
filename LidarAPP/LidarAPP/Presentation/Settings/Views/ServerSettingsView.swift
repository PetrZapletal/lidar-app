import SwiftUI

/// Detailní nastavení připojení k serveru
struct ServerSettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var portText: String = ""
    @State private var showResetConfirmation = false

    var body: some View {
        List {
            connectionSection
            testConnectionSection
            resetSection
        }
        .navigationTitle("Server")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            portText = String(viewModel.serverPort)
        }
        .alert("Resetovat server", isPresented: $showResetConfirmation) {
            Button("Zrušit", role: .cancel) { }
            Button("Resetovat", role: .destructive) {
                resetToDefaults()
            }
        } message: {
            Text("Nastavení serveru bude obnoveno na výchozí hodnoty.")
        }
        .accessibilityIdentifier("serverSettings.view")
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("IP adresa (Tailscale)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("100.96.188.18", text: $viewModel.serverIP)
                    .keyboardType(.decimalPad)
                    .textContentType(.none)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("serverSettings.ipField")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Port")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("8444", text: $portText)
                    .keyboardType(.numberPad)
                    .onChange(of: portText) { _, newValue in
                        if let port = Int(newValue), port > 0, port <= 65535 {
                            viewModel.serverPort = port
                        }
                    }
                    .accessibilityIdentifier("serverSettings.portField")
            }

            HStack {
                Text("Plná URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("https://\(viewModel.serverIP):\(viewModel.serverPort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Připojení")
        } footer: {
            Text("Zadejte Tailscale IP adresu a port debug serveru. Výchozí port je 8444 (mapován na 8443 v Dockeru).")
        }
    }

    // MARK: - Test Connection Section

    private var testConnectionSection: some View {
        Section {
            Button {
                Task {
                    await viewModel.testServerConnection()
                }
            } label: {
                HStack {
                    Label("Otestovat připojení", systemImage: "network")
                    Spacer()
                    if viewModel.isTestingConnection {
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isTestingConnection)
            .accessibilityIdentifier("serverSettings.testConnectionButton")

            if !viewModel.connectionTestMessage.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: viewModel.isServerConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(viewModel.isServerConnected ? .green : .red)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.isServerConnected ? "Připojeno" : "Nepřipojeno")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(viewModel.isServerConnected ? .green : .red)

                        Text(viewModel.connectionTestMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let latency = viewModel.connectionLatencyMs {
                            Text(String(format: "Latence: %.0f ms", latency))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("serverSettings.connectionResult")
            }
        } header: {
            Text("Test připojení")
        }
    }

    // MARK: - Reset Section

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Obnovit výchozí hodnoty", systemImage: "arrow.counterclockwise")
            }
            .accessibilityIdentifier("serverSettings.resetButton")
        } footer: {
            Text("Obnoví IP adresu a port na výchozí hodnoty (100.96.188.18:8444).")
        }
    }

    // MARK: - Private

    private func resetToDefaults() {
        viewModel.serverIP = "100.96.188.18"
        viewModel.serverPort = 8444
        portText = "8444"
        viewModel.isServerConnected = false
        viewModel.connectionTestMessage = ""
        viewModel.connectionLatencyMs = nil
        infoLog("Server settings reset to defaults", category: .logCategoryUI)
    }
}
