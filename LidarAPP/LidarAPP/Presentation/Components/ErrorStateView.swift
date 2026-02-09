import SwiftUI

// MARK: - Error State View

/// Reusable error state component with optional retry and dismiss actions.
/// Displays an SF Symbol icon, error message, and action buttons.
struct ErrorStateView: View {
    let error: String
    let icon: String // SF Symbol name
    var retryAction: (() -> Void)?
    var dismissAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            // Error icon
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.red.opacity(0.8))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            // Error message
            Text(error)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("errorState.message")

            // Action buttons
            VStack(spacing: 12) {
                if let retryAction {
                    Button(action: retryAction) {
                        Label("Zkusit znovu", systemImage: "arrow.clockwise")
                            .font(.body)
                            .fontWeight(.medium)
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("errorState.retryButton")
                    .accessibilityLabel("Zkusit znovu")
                }

                if let dismissAction {
                    Button(action: dismissAction) {
                        Text("Zavrit")
                            .font(.body)
                            .fontWeight(.medium)
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("errorState.dismissButton")
                    .accessibilityLabel("Zavrit")
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("errorState.container")
    }
}

// MARK: - Preview

#Preview("With Both Actions") {
    ErrorStateView(
        error: "Nelze se pripojit k serveru. Zkontrolujte pripojeni k internetu.",
        icon: "wifi.exclamationmark",
        retryAction: {},
        dismissAction: {}
    )
}

#Preview("Retry Only") {
    ErrorStateView(
        error: "Skenovani selhalo.",
        icon: "exclamationmark.triangle.fill",
        retryAction: {}
    )
}

#Preview("Dismiss Only") {
    ErrorStateView(
        error: "Neocekavana chyba.",
        icon: "xmark.octagon.fill",
        dismissAction: {}
    )
}
