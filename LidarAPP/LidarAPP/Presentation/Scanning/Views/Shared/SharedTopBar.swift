import SwiftUI

// MARK: - Shared Top Bar

/// Unified top bar for all scanning modes
/// - Left: Close button
/// - Center: Status indicator
/// - Right: Customizable action buttons
struct SharedTopBar<RightContent: View>: View {
    let status: UnifiedScanStatus
    var statusSubtitle: String?
    let onClose: () -> Void
    @ViewBuilder var rightContent: () -> RightContent

    var body: some View {
        HStack {
            // Close button (left)
            CircleButton(
                icon: "xmark",
                action: onClose,
                accessibilityLabel: "Zavřít"
            )

            Spacer()

            // Status indicator (center)
            StatusIndicator(
                status: status,
                subtitle: statusSubtitle
            )

            Spacer()

            // Right content (customizable)
            rightContent()
        }
        .padding()
    }
}

// MARK: - Circle Button

/// Reusable circular button with icon
struct CircleButton: View {
    let icon: String
    let action: () -> Void
    var isActive: Bool = false
    var activeColor: Color = .green
    var accessibilityLabel: String

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isActive ? activeColor : .white)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Simple Top Bar (no right content)

/// Simplified version with just close and status
struct SimpleTopBar: View {
    let status: UnifiedScanStatus
    var statusSubtitle: String?
    let onClose: () -> Void

    var body: some View {
        SharedTopBar(
            status: status,
            statusSubtitle: statusSubtitle,
            onClose: onClose
        ) {
            // Empty right content - add invisible spacer for balance
            Color.clear
                .frame(width: 44, height: 44)
        }
    }
}

// MARK: - Preview

#Preview("Shared Top Bar") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            // Simple with no right content
            SimpleTopBar(
                status: .scanning,
                statusSubtitle: "Pohybujte se pomalu",
                onClose: {}
            )

            // With single right button
            SharedTopBar(
                status: .scanning,
                statusSubtitle: "Obejděte objekt",
                onClose: {}
            ) {
                CircleButton(
                    icon: "questionmark.circle",
                    action: {},
                    accessibilityLabel: "Nápověda"
                )
            }

            // With multiple right buttons
            SharedTopBar(
                status: .scanning,
                statusSubtitle: nil,
                onClose: {}
            ) {
                HStack(spacing: 8) {
                    CircleButton(
                        icon: "map",
                        action: {},
                        isActive: true,
                        accessibilityLabel: "Mapa pokrytí"
                    )
                    CircleButton(
                        icon: "gearshape.fill",
                        action: {},
                        accessibilityLabel: "Nastavení"
                    )
                }
            }

            // Processing state
            SharedTopBar(
                status: .processing,
                onClose: {}
            ) {
                CircleButton(
                    icon: "info.circle",
                    action: {},
                    accessibilityLabel: "Informace"
                )
            }
        }
    }
}
