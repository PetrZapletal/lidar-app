import SwiftUI

// MARK: - Debug Log Overlay

struct DebugLogOverlay: View {
    let logs: [DebugLogEntry]
    let maxVisible: Int

    init(logs: [DebugLogEntry], maxVisible: Int = 10) {
        self.logs = logs
        self.maxVisible = maxVisible
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Header
            HStack {
                Image(systemName: "ant")
                    .font(.system(size: 10))
                Text("Debug Log")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Spacer()
                Text("\(logs.count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.gray)
            }
            .foregroundStyle(.green)
            .padding(.bottom, 2)

            // Log entries (most recent at bottom)
            ForEach(logs.suffix(maxVisible)) { log in
                HStack(spacing: 4) {
                    Text(log.timestamp, format: .dateTime.hour().minute().second())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.gray)

                    Image(systemName: log.level.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(log.level.color)

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

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            HStack {
                Spacer()
                DebugLogOverlay(logs: [
                    DebugLogEntry(timestamp: Date(), level: .info, message: "Scan started: Test Scan [exterior]"),
                    DebugLogEntry(timestamp: Date(), level: .debug, message: "AR session configured"),
                    DebugLogEntry(timestamp: Date(), level: .info, message: "Tracking: Normal"),
                    DebugLogEntry(timestamp: Date(), level: .warning, message: "Memory warning: 1024MB used"),
                    DebugLogEntry(timestamp: Date(), level: .error, message: "Mesh extraction failed"),
                ])
                .frame(maxWidth: 350)
            }
            .padding()
        }
    }
}
