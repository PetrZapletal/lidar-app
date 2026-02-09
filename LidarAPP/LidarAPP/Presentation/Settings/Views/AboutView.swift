import SwiftUI

/// O aplikaci - informace o verzi, zařízení, odkazy
struct AboutView: View {
    let viewModel: SettingsViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            appInfoSection
            deviceInfoSection
            memoryInfoSection
            linksSection
            footerSection
        }
        .navigationTitle("O aplikaci")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("about.view")
    }

    // MARK: - App Info Section

    private var appInfoSection: some View {
        Section {
            VStack(spacing: 16) {
                // App icon
                Image(systemName: "viewfinder")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue.gradient)
                    .frame(width: 80, height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.blue.opacity(0.1))
                    )

                // App name
                Text("LiDAR Scanner")
                    .font(.title2)
                    .fontWeight(.bold)

                // Version
                Text("Verze \(viewModel.appVersion) (Build \(viewModel.buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Device Info Section

    private var deviceInfoSection: some View {
        Section {
            infoRow(label: "Zařízení", value: viewModel.deviceModel)
            infoRow(label: "iOS verze", value: viewModel.iOSVersion)

            HStack {
                Text("LiDAR podpora")
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: viewModel.hasLiDAR ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(viewModel.hasLiDAR ? .green : .red)
                    Text(viewModel.hasLiDAR ? "Ano" : "Ne")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("about.lidarSupport")
        } header: {
            Text("Zařízení")
        }
    }

    // MARK: - Memory Info Section

    private var memoryInfoSection: some View {
        Section {
            infoRow(label: "Využitá paměť", value: "\(viewModel.memoryUsageMB) MB")
            infoRow(label: "Dostupná paměť", value: "\(viewModel.availableMemoryMB) MB")
        } header: {
            Text("Paměť")
        }
    }

    // MARK: - Links Section

    private var linksSection: some View {
        Section {
            Button {
                if let url = URL(string: "https://lidarscanner.app/privacy") {
                    openURL(url)
                }
            } label: {
                HStack {
                    Label("Zásady ochrany soukromí", systemImage: "hand.raised")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("about.privacyPolicyLink")

            Button {
                if let url = URL(string: "https://lidarscanner.app/terms") {
                    openURL(url)
                }
            } label: {
                HStack {
                    Label("Podmínky služby", systemImage: "doc.text")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("about.termsLink")
        } header: {
            Text("Odkazy")
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        Section {
            VStack(spacing: 8) {
                Text("Vytvořeno s \u{2764}\u{FE0F}")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("\u{00A9} 2024-2026 LiDAR Scanner")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
