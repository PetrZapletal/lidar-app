import SwiftUI

struct UserStatusBanner: View {
    let user: User

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Vítejte, \(user.name)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Image(systemName: "camera.viewfinder")
                        .font(.caption2)
                    Text("\(user.scanCredits) skenů zbývá")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(user.subscription.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(subscriptionColor.opacity(0.15))
                .foregroundStyle(subscriptionColor)
                .clipShape(Capsule())
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var subscriptionColor: Color {
        switch user.subscription {
        case .free: return .gray
        case .pro: return .orange
        case .enterprise: return .purple
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
