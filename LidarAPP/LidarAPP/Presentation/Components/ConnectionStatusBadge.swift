import SwiftUI

// MARK: - Connection Status Badge

/// Small badge showing server connection status.
/// Displays a colored dot, connection label, and optional latency.
struct ConnectionStatusBadge: View {
    let isConnected: Bool
    let latencyMs: Double?

    var body: some View {
        HStack(spacing: 6) {
            // Status dot
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            // Status label
            Text(isConnected ? "Pripojeno" : "Odpojeno")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(isConnected ? Color.primary : Color.red)
                .accessibilityIdentifier("connectionStatus.label")

            // Latency (when connected and available)
            if isConnected, let latencyMs {
                Text("\(Int(latencyMs)) ms")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(latencyColor(latencyMs))
                    .accessibilityIdentifier("connectionStatus.latency")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .stroke(isConnected ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityIdentifier("connectionStatus.badge")
    }

    // MARK: - Helpers

    /// Color the latency value based on response time thresholds.
    private func latencyColor(_ ms: Double) -> Color {
        switch ms {
        case ..<100:
            return .green
        case 100..<300:
            return .orange
        default:
            return .red
        }
    }

    private var accessibilityDescription: String {
        if isConnected {
            if let latencyMs {
                return "Pripojeno, latence \(Int(latencyMs)) milisekund"
            }
            return "Pripojeno"
        }
        return "Odpojeno"
    }
}

// MARK: - Preview

#Preview("Connected") {
    VStack(spacing: 12) {
        ConnectionStatusBadge(isConnected: true, latencyMs: 42)
        ConnectionStatusBadge(isConnected: true, latencyMs: 180)
        ConnectionStatusBadge(isConnected: true, latencyMs: 520)
        ConnectionStatusBadge(isConnected: true, latencyMs: nil)
    }
    .padding()
}

#Preview("Disconnected") {
    ConnectionStatusBadge(isConnected: false, latencyMs: nil)
        .padding()
}
