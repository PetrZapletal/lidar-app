import SwiftUI

// MARK: - Scan Mode Card

/// Reusable card for scan mode selection.
/// Used in onboarding and scanning mode picker.
/// Displays mode icon, name, subtitle, and selection/availability state.
struct ScanModeCard: View {
    let mode: ScanMode
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            guard isAvailable else { return }
            HapticManager.shared.buttonTapped()
            action()
        }) {
            HStack(spacing: 14) {
                // Mode icon
                Image(systemName: mode.icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(iconBackgroundColor)
                    )
                    .accessibilityHidden(true)

                // Text content
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(isAvailable ? .primary : .secondary)

                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(mode.color)
                        .transition(.scale.combined(with: .opacity))
                }

                if !isAvailable {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? mode.color.opacity(0.08) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? mode.color.opacity(0.5) : Color.clear,
                        lineWidth: isSelected ? 2 : 0
                    )
            )
            .animation(.spring(duration: 0.3), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1.0 : 0.6)
        .scanModeAccessibility(mode: mode, isSelected: isSelected)
    }

    // MARK: - Computed Properties

    private var iconColor: Color {
        if !isAvailable {
            return .secondary
        }
        return isSelected ? .white : mode.color
    }

    private var iconBackgroundColor: Color {
        if !isAvailable {
            return Color.secondary.opacity(0.12)
        }
        return isSelected ? mode.color : mode.color.opacity(0.15)
    }
}

// MARK: - Preview

#Preview("All Modes") {
    VStack(spacing: 12) {
        ScanModeCard(
            mode: .exterior,
            isSelected: true,
            isAvailable: true,
            action: {}
        )
        ScanModeCard(
            mode: .interior,
            isSelected: false,
            isAvailable: true,
            action: {}
        )
        ScanModeCard(
            mode: .object,
            isSelected: false,
            isAvailable: false,
            action: {}
        )
    }
    .padding()
}

#Preview("Dark Mode") {
    VStack(spacing: 12) {
        ScanModeCard(
            mode: .exterior,
            isSelected: false,
            isAvailable: true,
            action: {}
        )
        ScanModeCard(
            mode: .interior,
            isSelected: true,
            isAvailable: true,
            action: {}
        )
    }
    .padding()
    .preferredColorScheme(.dark)
}
