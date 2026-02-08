import SwiftUI

// MARK: - Statistics Grid

/// Grid view for displaying scan statistics
/// Used above the control bar in all scanning modes
struct StatisticsGrid: View {
    let items: [StatItem]
    var columns: Int = 3

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                        .frame(height: 40)
                        .background(Color.white.opacity(0.3))
                }

                StatItemView(item: item)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Stat Item

/// Single statistic item
struct StatItem: Identifiable {
    let id = UUID()
    let icon: String
    let value: String
    let label: String
    var iconColor: Color = .white
    var valueColor: Color = .white
}

/// View for displaying a single stat item
struct StatItemView: View {
    let item: StatItem

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundStyle(item.iconColor)

            Text(item.value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(item.valueColor)

            Text(item.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
    }
}

// MARK: - Horizontal Stats Bar

/// Horizontal stats bar (alternative layout)
struct HorizontalStatsBar: View {
    let items: [(label: String, value: String)]

    var body: some View {
        HStack {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.caption)
                        .fontWeight(.medium)
                }

                if item.label != items.last?.label {
                    Spacer()
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview("Statistics Grid - 3 Items") {
    ZStack {
        Color.black.ignoresSafeArea()

        StatisticsGrid(items: [
            StatItem(icon: "photo.stack", value: "42", label: "Snímky"),
            StatItem(icon: "rotate.3d", value: "85%", label: "Orbita"),
            StatItem(icon: "checkmark.circle.fill", value: "Dobrá", label: "Kvalita", iconColor: .green)
        ])
    }
}

#Preview("Statistics Grid - 4 Items (RoomPlan)") {
    ZStack {
        Color.black.ignoresSafeArea()

        StatisticsGrid(items: [
            StatItem(icon: "square.3.layers.3d", value: "2", label: "Místnosti"),
            StatItem(icon: "rectangle.portrait", value: "8", label: "Stěny"),
            StatItem(icon: "door.left.hand.open", value: "3", label: "Dveře"),
            StatItem(icon: "window.ceiling", value: "4", label: "Okna")
        ])
    }
}

#Preview("Horizontal Stats Bar") {
    ZStack {
        Color.black.ignoresSafeArea()

        HorizontalStatsBar(items: [
            ("Tracking", "Normal"),
            ("Body", "125K"),
            ("Plochy", "42K")
        ])
    }
}
