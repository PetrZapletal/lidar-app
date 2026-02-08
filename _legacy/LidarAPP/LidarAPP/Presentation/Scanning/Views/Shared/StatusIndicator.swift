import SwiftUI

// MARK: - Unified Scan Status

/// Unified status type for all scanning modes
enum UnifiedScanStatus: Equatable {
    case idle
    case preparing
    case scanning
    case processing
    case completed
    case failed(String)

    var displayName: String {
        switch self {
        case .idle: return "Připraveno"
        case .preparing: return "Příprava"
        case .scanning: return "Skenování"
        case .processing: return "Zpracování"
        case .completed: return "Dokončeno"
        case .failed: return "Chyba"
        }
    }

    var color: Color {
        switch self {
        case .idle, .preparing: return .gray
        case .scanning: return .green
        case .processing: return .orange
        case .completed: return .blue
        case .failed: return .red
        }
    }

    var isActive: Bool {
        switch self {
        case .scanning, .processing: return true
        default: return false
        }
    }
}

// MARK: - Status Indicator

/// Shared status indicator pill used across all scanning modes
struct StatusIndicator: View {
    let status: UnifiedScanStatus
    var subtitle: String?
    var showPulse: Bool = true

    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                // Status dot with optional pulse animation
                ZStack {
                    if showPulse && status == .scanning {
                        Circle()
                            .fill(status.color.opacity(0.3))
                            .frame(width: 16, height: 16)
                            .scaleEffect(isPulsing ? 1.5 : 1.0)
                            .opacity(isPulsing ? 0 : 0.5)
                    }

                    Circle()
                        .fill(status.color)
                        .frame(width: 10, height: 10)
                }

                Text(status.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .onAppear {
            if showPulse && status == .scanning {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
        }
        .onChange(of: status) { _, newStatus in
            if showPulse && newStatus == .scanning {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            } else {
                isPulsing = false
            }
        }
    }
}

// MARK: - Preview

#Preview("Status Variants") {
    VStack(spacing: 20) {
        StatusIndicator(status: .idle)
        StatusIndicator(status: .preparing, subtitle: "Inicializace AR")
        StatusIndicator(status: .scanning, subtitle: "Pohybujte se pomalu")
        StatusIndicator(status: .processing)
        StatusIndicator(status: .completed)
        StatusIndicator(status: .failed("AR session selhala"))
    }
    .padding()
    .background(Color.black)
}
