import SwiftUI
import simd

/// AR overlay showing coverage mini-map and statistics
struct CoverageOverlay: View {
    @Bindable var coverageAnalyzer: CoverageAnalyzer
    let cameraTransform: simd_float4x4
    let isScanning: Bool

    @State private var showDetailedStats = false

    var body: some View {
        VStack {
            HStack {
                // Mini-map in top-left corner
                MiniMapView(
                    coverageGrid: coverageAnalyzer.coverageGrid,
                    gaps: coverageAnalyzer.detectedGaps,
                    cameraPosition: cameraPosition,
                    cameraForward: cameraForward
                )
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(radius: 4)

                Spacer()

                // Coverage progress ring in top-right
                if let stats = coverageAnalyzer.statistics {
                    CoverageProgressRing(
                        coveragePercentage: stats.coveragePercentage,
                        gapCount: stats.gapCount
                    )
                    .frame(width: 60, height: 60)
                    .onTapGesture {
                        showDetailedStats.toggle()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60) // Below status bar

            Spacer()

            // Detailed statistics panel (when tapped)
            if showDetailedStats, let stats = coverageAnalyzer.statistics {
                DetailedStatsPanel(statistics: stats)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 100)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showDetailedStats)
    }

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
}

// MARK: - Mini Map View

struct MiniMapView: View {
    let coverageGrid: [Int: CoverageAnalyzer.CoverageCell]
    let gaps: [CoverageAnalyzer.Gap]
    let cameraPosition: simd_float3
    let cameraForward: simd_float3

    private let mapScale: Float = 0.05 // 1 meter = 5 pixels

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            // Draw coverage cells (top-down view, XZ plane)
            for (_, cell) in coverageGrid {
                let screenPos = worldToMiniMap(cell.worldPosition, center: center, size: size)

                let cellSize: CGFloat = 3
                let rect = CGRect(
                    x: screenPos.x - cellSize / 2,
                    y: screenPos.y - cellSize / 2,
                    width: cellSize,
                    height: cellSize
                )

                let color = colorForQuality(cell.quality)
                context.fill(Path(rect), with: .color(color))
            }

            // Draw gaps as red circles
            for gap in gaps {
                let screenPos = worldToMiniMap(gap.center, center: center, size: size)
                let gapSize: CGFloat = max(8, CGFloat(gap.cellCount) * 0.5)

                let gapRect = CGRect(
                    x: screenPos.x - gapSize / 2,
                    y: screenPos.y - gapSize / 2,
                    width: gapSize,
                    height: gapSize
                )

                context.stroke(
                    Path(ellipseIn: gapRect),
                    with: .color(.red),
                    lineWidth: 2
                )
            }

            // Draw camera position as blue triangle
            let camPos = worldToMiniMap(cameraPosition, center: center, size: size)
            drawCameraIndicator(context: context, position: camPos, forward: cameraForward)
        }
        .background(Color.black.opacity(0.6))
    }

    private func worldToMiniMap(_ worldPos: simd_float3, center: CGPoint, size: CGSize) -> CGPoint {
        // Relative to camera position (XZ plane for top-down)
        let relX = (worldPos.x - cameraPosition.x) * mapScale
        let relZ = (worldPos.z - cameraPosition.z) * mapScale

        // Convert to screen coordinates (Y is up in screen, Z is forward in world)
        return CGPoint(
            x: center.x + CGFloat(relX) * size.width / 2,
            y: center.y - CGFloat(relZ) * size.height / 2
        )
    }

    private func colorForQuality(_ quality: CoverageAnalyzer.QualityLevel) -> Color {
        switch quality {
        case .none: return .red.opacity(0.6)
        case .poor: return .orange.opacity(0.6)
        case .fair: return .yellow.opacity(0.6)
        case .good: return .green.opacity(0.6)
        case .excellent: return .blue.opacity(0.6)
        }
    }

    private func drawCameraIndicator(context: GraphicsContext, position: CGPoint, forward: simd_float3) {
        let triangleSize: CGFloat = 10

        // Calculate rotation angle from forward vector (XZ plane)
        let angle = atan2(Double(forward.x), Double(forward.z))

        var path = Path()

        // Triangle pointing up by default
        path.move(to: CGPoint(x: 0, y: -triangleSize))
        path.addLine(to: CGPoint(x: -triangleSize * 0.6, y: triangleSize * 0.5))
        path.addLine(to: CGPoint(x: triangleSize * 0.6, y: triangleSize * 0.5))
        path.closeSubpath()

        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: position.x, y: position.y)
        transform = transform.rotated(by: angle)

        context.fill(path.applying(transform), with: .color(.cyan))
        context.stroke(path.applying(transform), with: .color(.white), lineWidth: 1)
    }
}

// MARK: - Coverage Progress Ring

struct CoverageProgressRing: View {
    let coveragePercentage: Float
    let gapCount: Int

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 6)

            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(coveragePercentage / 100))
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center text
            VStack(spacing: 2) {
                Text("\(Int(coveragePercentage))%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if gapCount > 0 {
                    Text("\(gapCount) gaps")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .background(Color.black.opacity(0.5))
        .clipShape(Circle())
    }

    private var progressColor: Color {
        switch coveragePercentage {
        case 0..<30: return .red
        case 30..<60: return .orange
        case 60..<85: return .yellow
        default: return .green
        }
    }
}

// MARK: - Detailed Stats Panel

struct DetailedStatsPanel: View {
    let statistics: CoverageAnalyzer.CoverageStatistics

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Coverage Statistics")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                CoverageStatItem(title: "Covered", value: "\(statistics.coveredCells) cells")
                CoverageStatItem(title: "Area", value: String(format: "%.2f m2", statistics.scannedAreaM2))
                CoverageStatItem(title: "Quality", value: String(format: "%.1f/4", statistics.averageQuality))
                CoverageStatItem(title: "Gaps", value: "\(statistics.gapCount)")
            }

            // Quality bar
            HStack(spacing: 4) {
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(qualityColor(for: level))
                        .frame(height: 8)
                        .opacity(Float(level) < statistics.averageQuality ? 1 : 0.3)
                }
            }
            .frame(maxWidth: 200)
        }
        .padding(16)
        .background(Color.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    private func qualityColor(for level: Int) -> Color {
        switch level {
        case 0: return .red
        case 1: return .orange
        case 2: return .yellow
        case 3: return .green
        default: return .blue
        }
    }
}

struct CoverageStatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.gray)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Preview

#if DEBUG
struct CoverageOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            CoverageOverlay(
                coverageAnalyzer: CoverageAnalyzer(),
                cameraTransform: matrix_identity_float4x4,
                isScanning: true
            )
        }
    }
}
#endif
