import SwiftUI

// MARK: - Shared Control Bar

struct SharedControlBar: View {
    let isScanning: Bool
    let isPaused: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void
    let onClose: () -> Void

    private var captureState: CaptureButtonState {
        if isScanning {
            return .recording
        } else if isPaused {
            return .paused
        } else {
            return .ready
        }
    }

    var body: some View {
        HStack(spacing: 40) {
            // Left - mesh/info placeholder
            if isScanning || isPaused {
                ControlAccessoryButton(
                    icon: "cube",
                    label: "Mesh",
                    action: {}
                )
                .frame(width: 50)
            } else {
                Color.clear
                    .frame(width: 50, height: 50)
            }

            // Center - main capture button
            CaptureButton(
                state: captureState,
                onTap: {
                    if isScanning {
                        onPause()
                    } else if isPaused {
                        onResume()
                    } else {
                        onStart()
                    }
                }
            )

            // Right - stop or close
            if isScanning || isPaused {
                ControlAccessoryButton(
                    icon: "stop.fill",
                    label: "Stop",
                    action: onStop
                )
                .frame(width: 50)
            } else {
                ControlAccessoryButton(
                    icon: "xmark",
                    label: "Zavrit",
                    action: onClose
                )
                .frame(width: 50)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 20)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Control Accessory Button

struct ControlAccessoryButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var isActive: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(isActive ? .white : .white.opacity(0.7))
        }
        .accessibilityLabel(label)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            SharedControlBar(
                isScanning: true,
                isPaused: false,
                onStart: {},
                onPause: {},
                onResume: {},
                onStop: {},
                onClose: {}
            )
        }
    }
}
