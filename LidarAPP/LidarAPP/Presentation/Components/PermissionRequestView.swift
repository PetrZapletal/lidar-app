import SwiftUI

// MARK: - Permission Request View

/// Reusable permission request card.
/// Displays a card with icon, title, description, and a grant/granted state.
struct PermissionRequestView: View {
    let icon: String // SF Symbol name
    let title: String
    let description: String
    let isGranted: Bool
    let requestAction: () async -> Void

    @State private var isRequesting = false

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isGranted ? .green : .accentColor)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(isGranted ? Color.green.opacity(0.12) : Color.accentColor.opacity(0.12))
                )
                .accessibilityHidden(true)

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("permission.\(icon).title")

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("permission.\(icon).description")
            }

            Spacer()

            // Status / Action
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Povoleno")
                    .accessibilityIdentifier("permission.\(icon).granted")
            } else {
                Button {
                    isRequesting = true
                    Task {
                        await requestAction()
                        isRequesting = false
                    }
                } label: {
                    if isRequesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Povolit")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRequesting)
                .accessibilityIdentifier("permission.\(icon).allowButton")
                .accessibilityLabel("Povolit \(title)")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isGranted ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("permission.\(icon).card")
    }
}

// MARK: - Preview

#Preview("Not Granted") {
    VStack(spacing: 12) {
        PermissionRequestView(
            icon: "camera.fill",
            title: "Kamera",
            description: "Pristup ke kamere je nutny pro 3D skenovani.",
            isGranted: false,
            requestAction: {}
        )
        PermissionRequestView(
            icon: "location.fill",
            title: "Poloha",
            description: "Pristup k poloze pro georeferencovani skenu.",
            isGranted: false,
            requestAction: {}
        )
    }
    .padding()
}

#Preview("Granted") {
    VStack(spacing: 12) {
        PermissionRequestView(
            icon: "camera.fill",
            title: "Kamera",
            description: "Pristup ke kamere je nutny pro 3D skenovani.",
            isGranted: true,
            requestAction: {}
        )
        PermissionRequestView(
            icon: "location.fill",
            title: "Poloha",
            description: "Pristup k poloze pro georeferencovani skenu.",
            isGranted: true,
            requestAction: {}
        )
    }
    .padding()
}
