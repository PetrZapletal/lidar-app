import SwiftUI

// MARK: - Statistics Grid

struct StatisticsGrid: View {
    let items: [StatItem]

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

struct StatItem: Identifiable {
    let id = UUID()
    let icon: String
    let value: String
    let label: String
    var iconColor: Color = .white
}

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

            Text(item.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        StatisticsGrid(items: [
            StatItem(icon: "point.3.filled.connected.trianglepath.dotted", value: "125K", label: "Body"),
            StatItem(icon: "square.stack.3d.up", value: "42K", label: "Plochy"),
            StatItem(icon: "timer", value: "2:35", label: "Cas"),
            StatItem(icon: "checkmark.circle.fill", value: "Good", label: "Kvalita", iconColor: .green)
        ])
    }
}
