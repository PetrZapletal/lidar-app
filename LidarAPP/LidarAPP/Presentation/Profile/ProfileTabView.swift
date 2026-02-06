import SwiftUI

struct ProfileTabView: View {
    let authService: AuthService
    @State private var showSettings = false
    @State private var showAuth = false

    var body: some View {
        NavigationStack {
            List {
                if let user = authService.currentUser {
                    Section {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(.blue.gradient)
                                    .frame(width: 60, height: 60)
                                Text(user.initials)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(.headline)
                                Text(user.email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text(user.subscription.displayName)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    Section("Statistiky") {
                        ProfileStatRow(title: "Celkem skenů", value: "\(user.scanCredits)")
                        ProfileStatRow(title: "Zpracováno AI", value: "0")
                        ProfileStatRow(title: "Exportováno", value: "0")
                    }
                } else {
                    Section {
                        Button(action: { showAuth = true }) {
                            HStack {
                                Image(systemName: "person.circle")
                                    .font(.title)
                                VStack(alignment: .leading) {
                                    Text("Přihlásit se")
                                        .font(.headline)
                                    Text("Pro cloud zpracování a synchronizaci")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(action: { showSettings = true }) {
                        Label("Nastavení", systemImage: "gearshape")
                    }

                    NavigationLink {
                        Text("Nápověda")
                    } label: {
                        Label("Nápověda", systemImage: "questionmark.circle")
                    }

                    Link(destination: URL(string: "https://lidarscanner.app")!) {
                        Label("Webové stránky", systemImage: "globe")
                    }
                }

                Section {
                    HStack {
                        Text("Verze")
                        Spacer()
                        Text(Bundle.main.appVersion)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Profil")
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showAuth) {
                AuthView(authService: authService)
            }
        }
    }
}

struct ProfileStatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
        }
    }
}
