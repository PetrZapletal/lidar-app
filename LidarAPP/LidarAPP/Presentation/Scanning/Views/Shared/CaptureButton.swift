import SwiftUI

// MARK: - Capture Button State

/// State of the capture button
enum CaptureButtonState: Equatable {
    case ready           // White filled circle - ready to start
    case recording       // Red stop square - currently recording
    case processing      // Spinner - processing data
    case paused          // Orange pause icon - paused
    case disabled        // Dimmed - cannot interact

    var isInteractive: Bool {
        switch self {
        case .ready, .recording, .paused: return true
        case .processing, .disabled: return false
        }
    }
}

// MARK: - Capture Button

/// Main capture button used across all scanning modes
/// Adapts appearance based on current capture state
struct CaptureButton: View {
    let state: CaptureButtonState
    let onTap: () -> Void
    var onLongPress: (() -> Void)?
    var size: CGFloat = 80

    private var strokeWidth: CGFloat { size * 0.05 }
    private var innerSize: CGFloat { size * 0.8125 }
    private var stopSize: CGFloat { size * 0.4375 }

    var body: some View {
        Button(action: {
            guard state.isInteractive else { return }
            onTap()
        }) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.white, lineWidth: strokeWidth)
                    .frame(width: size, height: size)

                // Inner content based on state
                innerContent
            }
        }
        .disabled(!state.isInteractive)
        .opacity(state == .disabled ? 0.5 : 1.0)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    onLongPress?()
                }
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    @ViewBuilder
    private var innerContent: some View {
        switch state {
        case .ready:
            // White filled circle - ready to capture
            Circle()
                .fill(Color.white)
                .frame(width: innerSize, height: innerSize)

        case .recording:
            // Red stop square
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red)
                .frame(width: stopSize, height: stopSize)

        case .paused:
            // Orange pause icon
            Image(systemName: "pause.fill")
                .font(.system(size: size * 0.375))
                .foregroundStyle(.white)
                .frame(width: innerSize, height: innerSize)
                .background(Color.orange)
                .clipShape(Circle())

        case .processing:
            // Spinner
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

        case .disabled:
            // Dimmed circle
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: innerSize, height: innerSize)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .ready: return "Zahájit skenování"
        case .recording: return "Ukončit skenování"
        case .paused: return "Pokračovat ve skenování"
        case .processing: return "Zpracovávání"
        case .disabled: return "Skenování nedostupné"
        }
    }

    private var accessibilityHint: String {
        switch state {
        case .ready: return "Klepnutím zahájíte skenování"
        case .recording: return "Klepnutím ukončíte skenování"
        case .paused: return "Klepnutím budete pokračovat"
        case .processing: return "Čekejte na dokončení zpracování"
        case .disabled: return "AR session není připravena"
        }
    }
}

// MARK: - Preview

#Preview("Capture Button States") {
    HStack(spacing: 30) {
        VStack {
            CaptureButton(state: .ready, onTap: {})
            Text("Ready").font(.caption)
        }

        VStack {
            CaptureButton(state: .recording, onTap: {})
            Text("Recording").font(.caption)
        }

        VStack {
            CaptureButton(state: .paused, onTap: {})
            Text("Paused").font(.caption)
        }

        VStack {
            CaptureButton(state: .processing, onTap: {})
            Text("Processing").font(.caption)
        }

        VStack {
            CaptureButton(state: .disabled, onTap: {})
            Text("Disabled").font(.caption)
        }
    }
    .padding()
    .background(Color.black)
    .foregroundStyle(.white)
}

#Preview("Capture Button Sizes") {
    HStack(spacing: 20) {
        CaptureButton(state: .ready, onTap: {}, size: 60)
        CaptureButton(state: .recording, onTap: {}, size: 80)
        CaptureButton(state: .paused, onTap: {}, size: 100)
    }
    .padding()
    .background(Color.black)
}
