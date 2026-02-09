import SwiftUI

// MARK: - Loading State View

/// Reusable loading state component with optional progress indicator.
/// Supports both indeterminate spinner and determinate progress display.
struct LoadingStateView: View {
    let message: String
    var progress: Float? // nil = indeterminate spinner

    var body: some View {
        VStack(spacing: 16) {
            if let progress {
                ProgressView(value: Double(progress))
                    .progressViewStyle(.circular)
                    .tint(.accentColor)
                    .accessibilityIdentifier("loadingState.progressIndicator")

                Text("\(Int(progress * 100))%")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("loadingState.progressLabel")
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.accentColor)
                    .accessibilityIdentifier("loadingState.spinner")
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("loadingState.message")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityIdentifier("loadingState.container")
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        if let progress {
            return "\(message), \(Int(progress * 100)) procent"
        }
        return message
    }
}

// MARK: - Preview

#Preview("Indeterminate") {
    LoadingStateView(message: "Nacitam data...")
}

#Preview("With Progress") {
    LoadingStateView(message: "Zpracovavam sken...", progress: 0.67)
}
