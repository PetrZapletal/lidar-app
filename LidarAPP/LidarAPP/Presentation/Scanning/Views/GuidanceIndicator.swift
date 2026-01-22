import SwiftUI
import simd

/// Visual guidance indicator showing optimal camera movement direction
struct GuidanceIndicator: View {
    let gap: CoverageAnalyzer.Gap
    let cameraTransform: simd_float4x4
    let viewSize: CGSize

    @State private var pulseAnimation = false

    var body: some View {
        let screenPosition = calculateScreenPosition()

        ZStack {
            // Outer pulsing ring
            Circle()
                .stroke(Color.orange.opacity(0.6), lineWidth: 3)
                .frame(width: 70, height: 70)
                .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                .opacity(pulseAnimation ? 0.3 : 0.8)

            // Inner solid circle
            Circle()
                .fill(Color.orange.opacity(0.3))
                .frame(width: 60, height: 60)

            // Arrow pointing toward gap
            ArrowShape()
                .fill(Color.orange.gradient)
                .frame(width: 30, height: 30)
                .rotationEffect(arrowRotation)

            // Distance label below
            VStack(spacing: 4) {
                Spacer()
                    .frame(height: 45)

                Text(distanceText)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .clipShape(Capsule())

                Text("Move here")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .position(clampedPosition(screenPosition))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }

    // MARK: - Calculations

    private var cameraPosition: simd_float3 {
        simd_float3(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
    }

    private var cameraForward: simd_float3 {
        -simd_float3(
            cameraTransform.columns.2.x,
            cameraTransform.columns.2.y,
            cameraTransform.columns.2.z
        )
    }

    private var cameraRight: simd_float3 {
        simd_float3(
            cameraTransform.columns.0.x,
            cameraTransform.columns.0.y,
            cameraTransform.columns.0.z
        )
    }

    private var cameraUp: simd_float3 {
        simd_float3(
            cameraTransform.columns.1.x,
            cameraTransform.columns.1.y,
            cameraTransform.columns.1.z
        )
    }

    private var distanceToGap: Float {
        simd_length(gap.center - cameraPosition)
    }

    private var distanceText: String {
        String(format: "%.1fm", distanceToGap)
    }

    private var directionToGap: simd_float3 {
        simd_normalize(gap.center - cameraPosition)
    }

    private var arrowRotation: Angle {
        // Calculate angle between camera forward and direction to gap
        // Project to camera's XZ plane (horizontal)
        let toGapProjected = simd_normalize(simd_float3(
            simd_dot(directionToGap, cameraRight),
            simd_dot(directionToGap, cameraUp),
            simd_dot(directionToGap, cameraForward)
        ))

        let angle = atan2(toGapProjected.x, toGapProjected.z)
        return Angle(radians: Double(angle))
    }

    private func calculateScreenPosition() -> CGPoint {
        // Simple projection based on direction relative to camera
        let toGap = gap.center - cameraPosition

        // Project onto camera's view plane
        let rightComponent = simd_dot(toGap, cameraRight)
        let upComponent = simd_dot(toGap, cameraUp)
        let forwardComponent = simd_dot(toGap, cameraForward)

        // If gap is behind camera, show at edge
        if forwardComponent < 0 {
            // Gap is behind - show arrow at edge pointing back
            let edgeX = rightComponent > 0 ? viewSize.width - 50 : 50
            return CGPoint(x: edgeX, y: viewSize.height / 2)
        }

        // Perspective projection
        let perspectiveFactor = max(0.5, forwardComponent)
        let screenX = viewSize.width / 2 + CGFloat(rightComponent / perspectiveFactor) * viewSize.width * 0.3
        let screenY = viewSize.height / 2 - CGFloat(upComponent / perspectiveFactor) * viewSize.height * 0.3

        return CGPoint(x: screenX, y: screenY)
    }

    private func clampedPosition(_ position: CGPoint) -> CGPoint {
        let margin: CGFloat = 50
        return CGPoint(
            x: min(max(position.x, margin), viewSize.width - margin),
            y: min(max(position.y, margin + 100), viewSize.height - margin - 100)
        )
    }
}

// MARK: - Arrow Shape

struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let width = rect.width
        let height = rect.height

        // Arrow pointing up
        path.move(to: CGPoint(x: width / 2, y: 0))
        path.addLine(to: CGPoint(x: width, y: height * 0.5))
        path.addLine(to: CGPoint(x: width * 0.65, y: height * 0.5))
        path.addLine(to: CGPoint(x: width * 0.65, y: height))
        path.addLine(to: CGPoint(x: width * 0.35, y: height))
        path.addLine(to: CGPoint(x: width * 0.35, y: height * 0.5))
        path.addLine(to: CGPoint(x: 0, y: height * 0.5))
        path.closeSubpath()

        return path
    }
}

// MARK: - Multiple Gap Indicators Container

struct GuidanceIndicatorsOverlay: View {
    let gaps: [CoverageAnalyzer.Gap]
    let cameraTransform: simd_float4x4

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(gaps.prefix(3).enumerated()), id: \.element.id) { index, gap in
                GuidanceIndicator(
                    gap: gap,
                    cameraTransform: cameraTransform,
                    viewSize: geometry.size
                )
                .opacity(index == 0 ? 1.0 : 0.6) // Primary gap is more visible
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Edge Direction Indicator

/// Shows direction arrow at screen edge when gap is off-screen
struct EdgeDirectionIndicator: View {
    let direction: Angle
    let edge: Edge
    let distance: Float

    @State private var pulseOpacity = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.orange)
                .rotationEffect(direction)

            Text(String(format: "%.1fm", distance))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.7))
        .clipShape(Capsule())
        .opacity(pulseOpacity ? 1.0 : 0.7)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseOpacity = true
            }
        }
    }
}

// MARK: - Quality Heatmap Overlay

struct QualityHeatmapOverlay: View {
    let coverageGrid: [Int: CoverageAnalyzer.CoverageCell]
    let cameraIntrinsics: simd_float3x3
    let cameraTransform: simd_float4x4

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for (_, cell) in coverageGrid {
                    guard let screenPos = projectToScreen(
                        worldPoint: cell.worldPosition,
                        intrinsics: cameraIntrinsics,
                        transform: cameraTransform,
                        viewSize: size
                    ) else { continue }

                    // Check if point is in front of camera
                    let cameraZ = simd_float3(
                        cameraTransform.columns.2.x,
                        cameraTransform.columns.2.y,
                        cameraTransform.columns.2.z
                    )
                    let cameraPos = simd_float3(
                        cameraTransform.columns.3.x,
                        cameraTransform.columns.3.y,
                        cameraTransform.columns.3.z
                    )

                    let toPoint = cell.worldPosition - cameraPos
                    if simd_dot(toPoint, -cameraZ) < 0 { continue }

                    let color = heatmapColor(for: cell.quality)
                    let radius: CGFloat = 6

                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: screenPos.x - radius,
                            y: screenPos.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )),
                        with: .color(color.opacity(0.4))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func projectToScreen(
        worldPoint: simd_float3,
        intrinsics: simd_float3x3,
        transform: simd_float4x4,
        viewSize: CGSize
    ) -> CGPoint? {
        // World to camera space
        let invTransform = transform.inverse
        let cameraPoint4 = invTransform * simd_float4(worldPoint, 1)
        let cameraPoint = simd_float3(cameraPoint4.x, cameraPoint4.y, cameraPoint4.z)

        // Check if behind camera
        guard cameraPoint.z > 0.1 else { return nil }

        // Project using intrinsics
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]

        let x = (cameraPoint.x * fx / cameraPoint.z) + cx
        let y = (cameraPoint.y * fy / cameraPoint.z) + cy

        // Convert to view coordinates (assuming intrinsics are for some reference resolution)
        let scaleX = viewSize.width / 1920 // Approximate scale
        let scaleY = viewSize.height / 1440

        return CGPoint(x: CGFloat(x) * scaleX, y: CGFloat(y) * scaleY)
    }

    private func heatmapColor(for quality: CoverageAnalyzer.QualityLevel) -> Color {
        switch quality {
        case .none: return .red
        case .poor: return .orange
        case .fair: return .yellow
        case .good: return .green
        case .excellent: return .blue
        }
    }
}

// MARK: - Preview

#if DEBUG
struct GuidanceIndicator_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            GuidanceIndicator(
                gap: CoverageAnalyzer.Gap(
                    id: UUID(),
                    center: simd_float3(1, 0, 2),
                    cellCount: 10,
                    estimatedArea: 0.5,
                    suggestedViewDirection: simd_float3(0, 0, 1),
                    suggestedCameraPosition: simd_float3(1, 0, 0),
                    priority: 5,
                    cellIds: []
                ),
                cameraTransform: matrix_identity_float4x4,
                viewSize: CGSize(width: 400, height: 800)
            )
        }
    }
}
#endif
