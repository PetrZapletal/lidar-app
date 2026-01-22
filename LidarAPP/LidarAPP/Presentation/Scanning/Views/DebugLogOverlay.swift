import SwiftUI

// MARK: - Debug Log Types

struct DebugLog: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: DebugLogLevel
    let tag: String
    let message: String
}

enum DebugLogLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
    case network

    var color: Color {
        switch self {
        case .debug: return .cyan
        case .info: return .white
        case .warning: return .orange
        case .error: return .red
        case .network: return .green
        }
    }

    var icon: String {
        switch self {
        case .debug: return "ant"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .network: return "network"
        }
    }
}

// MARK: - Debug Log Overlay View

struct DebugLogOverlay: View {
    let logs: [DebugLog]
    let maxVisible: Int

    init(logs: [DebugLog], maxVisible: Int = 10) {
        self.logs = logs
        self.maxVisible = maxVisible
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(logs.suffix(maxVisible).reversed()) { log in
                HStack(spacing: 4) {
                    Text(log.timestamp, format: .dateTime.hour().minute().second())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.gray)

                    Image(systemName: log.level.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(log.level.color)

                    Text(log.tag)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(log.level.color)
                        .frame(width: 45, alignment: .leading)

                    Text(log.message)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            HStack {
                Spacer()
                DebugLogOverlay(logs: [
                    DebugLog(timestamp: Date(), level: .info, tag: "Scan", message: "Scan started: Test Scan"),
                    DebugLog(timestamp: Date(), level: .network, tag: "Stream", message: "Debug stream started"),
                    DebugLog(timestamp: Date(), level: .debug, tag: "AR", message: "Frame 30, pts: 12500"),
                    DebugLog(timestamp: Date(), level: .debug, tag: "Depth", message: "Depth frame captured: 256x192"),
                    DebugLog(timestamp: Date(), level: .warning, tag: "Memory", message: "Memory pressure warning"),
                ])
                .frame(maxWidth: 350)
            }
            .padding()
        }
    }
}
