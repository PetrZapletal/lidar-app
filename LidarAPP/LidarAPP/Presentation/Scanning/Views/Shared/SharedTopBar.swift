import SwiftUI

// MARK: - Shared Top Bar

struct SharedTopBar: View {
    let trackingState: String
    let pointCount: String
    let faceCount: String
    let scanDuration: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            // Left - tracking info
            VStack(alignment: .leading, spacing: 4) {
                Label(trackingState, systemImage: trackingStateIcon)
                    .font(.caption)
            }

            Spacer()

            // Center - duration
            Text(scanDuration)
                .font(.title2.monospacedDigit())
                .fontWeight(.semibold)

            Spacer()

            // Right - statistics
            VStack(alignment: .trailing, spacing: 4) {
                Text(pointCount + " pts")
                    .font(.caption)
                Text(faceCount + " faces")
                    .font(.caption)
            }

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Zavrit")
            .padding(.leading, 8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var trackingStateIcon: String {
        switch trackingState {
        case "Normal":
            return "checkmark.circle.fill"
        case _ where trackingState.contains("Limited"):
            return "exclamationmark.triangle.fill"
        case "Initializing", "Relocalizing":
            return "arrow.triangle.2.circlepath"
        default:
            return "xmark.circle.fill"
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            SharedTopBar(
                trackingState: "Normal",
                pointCount: "125K",
                faceCount: "42K",
                scanDuration: "2:35",
                onClose: {}
            )
            Spacer()
        }
    }
}
