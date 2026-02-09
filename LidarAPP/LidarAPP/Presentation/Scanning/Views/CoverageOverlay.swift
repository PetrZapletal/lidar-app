import SwiftUI

// MARK: - Coverage Overlay

struct CoverageOverlay: View {
    let coveragePercentage: Float
    let pointCount: String
    let faceCount: String
    let scanQuality: ScanQuality

    var body: some View {
        VStack {
            HStack {
                Spacer()

                // Coverage progress ring
                CoverageProgressRing(
                    coveragePercentage: coveragePercentage,
                    quality: scanQuality
                )
                .frame(width: 60, height: 60)
            }
            .padding(.horizontal, 16)
            .padding(.top, 80)

            Spacer()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Coverage Progress Ring

struct CoverageProgressRing: View {
    let coveragePercentage: Float
    let quality: ScanQuality

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 6)

            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(min(coveragePercentage, 100) / 100))
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center text
            VStack(spacing: 1) {
                Text("\(Int(coveragePercentage))%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(quality.displayName)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(quality.color)
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

// MARK: - Scan Quality Indicator

struct ScanQualityIndicator: View {
    let quality: ScanQuality

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < quality.level ? quality.color : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 16 + CGFloat(index * 4))
            }

            Text(quality.displayName)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        CoverageOverlay(
            coveragePercentage: 65,
            pointCount: "125K",
            faceCount: "42K",
            scanQuality: .good
        )
    }
}
