import SwiftUI

// MARK: - Shared Control Bar

/// Unified bottom control bar for all scanning modes
/// - Left: Customizable accessory (mesh toggle, progress, etc.)
/// - Center: Main capture button
/// - Right: Customizable accessory (close, auto-capture, etc.)
struct SharedControlBar<LeftContent: View, RightContent: View>: View {
    let captureState: CaptureButtonState
    let onCaptureTap: () -> Void
    var onCaptureLongPress: (() -> Void)?
    @ViewBuilder var leftContent: () -> LeftContent
    @ViewBuilder var rightContent: () -> RightContent

    var body: some View {
        HStack(spacing: 40) {
            // Left accessory
            leftContent()
                .frame(width: 50)

            // Center capture button
            CaptureButton(
                state: captureState,
                onTap: onCaptureTap,
                onLongPress: onCaptureLongPress
            )

            // Right accessory
            rightContent()
                .frame(width: 50)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 30)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Control Accessory Views

/// Small accessory button for control bar
struct ControlAccessoryButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var isActive: Bool = false
    var activeColor: Color = .white

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(isActive ? activeColor : .white.opacity(0.7))
        }
        .accessibilityLabel(label)
    }
}

/// Progress accessory showing circular progress
struct ProgressAccessory: View {
    let progress: Float
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 4)
                    .frame(width: 36, height: 36)

                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))

                Text("\(Int(progress * 100))")
                    .font(.caption2.bold())
            }

            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(.white)
    }
}

/// Stats accessory showing icon, value, and label
struct StatsAccessory: View {
    let icon: String
    let value: String
    let label: String
    var iconColor: Color = .white

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Simple Control Bar

/// Simplified control bar with just capture button
struct SimpleCaptureControlBar: View {
    let captureState: CaptureButtonState
    let onCaptureTap: () -> Void
    var onCaptureLongPress: (() -> Void)?

    var body: some View {
        SharedControlBar(
            captureState: captureState,
            onCaptureTap: onCaptureTap,
            onCaptureLongPress: onCaptureLongPress
        ) {
            Color.clear
        } rightContent: {
            Color.clear
        }
    }
}

// MARK: - Preview

#Preview("Shared Control Bar - LiDAR Style") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()

            SharedControlBar(
                captureState: .recording,
                onCaptureTap: {},
                onCaptureLongPress: {}
            ) {
                ControlAccessoryButton(
                    icon: "cube.fill",
                    label: "Mesh",
                    action: {},
                    isActive: true
                )
            } rightContent: {
                ControlAccessoryButton(
                    icon: "stop.fill",
                    label: "Stop",
                    action: {}
                )
            }
        }
    }
}

#Preview("Shared Control Bar - RoomPlan Style") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()

            SharedControlBar(
                captureState: .recording,
                onCaptureTap: {}
            ) {
                ProgressAccessory(progress: 0.65, label: "Progress")
            } rightContent: {
                StatsAccessory(
                    icon: "square.dashed",
                    value: "12.5",
                    label: "m²"
                )
            }
        }
    }
}

#Preview("Shared Control Bar - Object Capture Style") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()

            SharedControlBar(
                captureState: .ready,
                onCaptureTap: {}
            ) {
                ControlAccessoryButton(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Flip",
                    action: {}
                )
            } rightContent: {
                ControlAccessoryButton(
                    icon: "a.circle.fill",
                    label: "Auto",
                    action: {},
                    isActive: true
                )
            }
        }
    }
}

#Preview("Simple Capture Control Bar") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            SimpleCaptureControlBar(
                captureState: .ready,
                onCaptureTap: {}
            )
        }
    }
}
