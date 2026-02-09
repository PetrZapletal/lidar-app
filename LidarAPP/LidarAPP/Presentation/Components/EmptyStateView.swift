import SwiftUI

// MARK: - Empty State View

/// Reusable empty state placeholder with icon, title, message, and optional action button.
/// Used when a list or collection has no items to display.
struct EmptyStateView: View {
    let icon: String // SF Symbol name
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(.secondary.opacity(0.6))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            // Title
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("emptyState.title")

            // Message
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("emptyState.message")

            // Optional action button
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.body)
                        .fontWeight(.medium)
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
                .accessibilityIdentifier("emptyState.actionButton")
                .accessibilityLabel(actionTitle)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("emptyState.container")
    }
}

// MARK: - Preview

#Preview("With Action") {
    EmptyStateView(
        icon: "cube.transparent",
        title: "Zadne modely",
        message: "Vytvorte svuj prvni 3D sken pomoci tlacitka skenovani.",
        actionTitle: "Zahajit skenovani",
        action: {}
    )
}

#Preview("Without Action") {
    EmptyStateView(
        icon: "magnifyingglass",
        title: "Zadne vysledky",
        message: "Zkuste upravit vyhledavaci dotaz."
    )
}
