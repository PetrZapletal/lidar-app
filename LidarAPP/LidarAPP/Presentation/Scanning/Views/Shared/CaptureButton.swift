import SwiftUI

// MARK: - Capture Button State

enum CaptureButtonState: Equatable {
    case ready
    case recording
    case processing
    case paused
    case disabled

    var isInteractive: Bool {
        switch self {
        case .ready, .recording, .paused: return true
        case .processing, .disabled: return false
        }
    }
}

// MARK: - Capture Button

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
                Circle()
                    .stroke(Color.white, lineWidth: strokeWidth)
                    .frame(width: size, height: size)

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
    }

    @ViewBuilder
    private var innerContent: some View {
        switch state {
        case .ready:
            Circle()
                .fill(Color.white)
                .frame(width: innerSize, height: innerSize)

        case .recording:
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red)
                .frame(width: stopSize, height: stopSize)

        case .paused:
            Image(systemName: "pause.fill")
                .font(.system(size: size * 0.375))
                .foregroundStyle(.white)
                .frame(width: innerSize, height: innerSize)
                .background(Color.orange)
                .clipShape(Circle())

        case .processing:
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

        case .disabled:
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: innerSize, height: innerSize)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .ready: return "Zahajit skenovani"
        case .recording: return "Ukoncit skenovani"
        case .paused: return "Pokracovat ve skenovani"
        case .processing: return "Zpracovavani"
        case .disabled: return "Skenovani nedostupne"
        }
    }
}

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
            CaptureButton(state: .disabled, onTap: {})
            Text("Disabled").font(.caption)
        }
    }
    .padding()
    .background(Color.black)
    .foregroundStyle(.white)
}
