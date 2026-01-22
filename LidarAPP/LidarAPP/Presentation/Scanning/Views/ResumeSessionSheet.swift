import SwiftUI

/// Sheet for choosing between new scan or resuming existing sessions
struct ResumeSessionSheet: View {
    let sessions: [ScanSessionPersistence.PersistedSession]
    let onResume: (UUID) -> Void
    let onNewScan: () -> Void
    let onDelete: ((UUID) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var sessionToDelete: ScanSessionPersistence.PersistedSession?
    @State private var isLoading = false
    @State private var loadingSessionId: UUID?

    init(
        sessions: [ScanSessionPersistence.PersistedSession],
        onResume: @escaping (UUID) -> Void,
        onNewScan: @escaping () -> Void,
        onDelete: ((UUID) -> Void)? = nil
    ) {
        self.sessions = sessions
        self.onResume = onResume
        self.onNewScan = onNewScan
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            List {
                // New Scan Section
                Section {
                    Button(action: {
                        onNewScan()
                        dismiss()
                    }) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.gradient)
                                    .frame(width: 44, height: 44)

                                Image(systemName: "plus")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Novy sken")
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text("Zacit skenovat od zacatku")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Resumable Sessions Section
                if !sessions.isEmpty {
                    Section {
                        ForEach(sessions) { session in
                            ResumeSessionRow(
                                session: session,
                                isLoading: loadingSessionId == session.id,
                                onTap: {
                                    guard !isLoading else { return }
                                    isLoading = true
                                    loadingSessionId = session.id
                                    onResume(session.id)
                                    // Note: dismiss happens after resume completes in ViewModel
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        dismiss()
                                    }
                                }
                            )
                            .disabled(isLoading && loadingSessionId != session.id)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if onDelete != nil && !isLoading {
                                    Button(role: .destructive) {
                                        sessionToDelete = session
                                    } label: {
                                        Label("Smazat", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Pokracovat v rozpracovanem")
                    } footer: {
                        Text("Tyto skeny maji ulozenou mapu prostredi a lze v nich pokracovat")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Skenovani")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrusit") {
                        dismiss()
                    }
                }
            }
            .alert("Smazat sken?", isPresented: .init(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            )) {
                Button("Zrusit", role: .cancel) {
                    sessionToDelete = nil
                }
                Button("Smazat", role: .destructive) {
                    if let session = sessionToDelete {
                        onDelete?(session.id)
                        sessionToDelete = nil
                    }
                }
            } message: {
                if let session = sessionToDelete {
                    Text("Opravdu chcete smazat sken \"\(session.name)\"? Tuto akci nelze vratit.")
                }
            }
        }
    }
}

// MARK: - Session Row

struct ResumeSessionRow: View {
    let session: ScanSessionPersistence.PersistedSession
    var isLoading: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail or placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Image(systemName: "cube.transparent")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(session.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if session.worldMapFile != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    HStack(spacing: 8) {
                        // Date
                        Label(formattedDate, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Stats
                        Label(formattedStats, systemImage: "cube")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Progress indicator
                    if session.state == "scanning" || session.state == "paused" {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(session.state == "scanning" ? Color.orange : Color.yellow)
                                .frame(width: 6, height: 6)

                            Text(session.state == "scanning" ? "Probiha sken" : "Pozastaveno")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .opacity(isLoading ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: session.updatedAt, relativeTo: Date())
    }

    private var formattedStats: String {
        let vertices = session.totalVertices
        if vertices >= 1_000_000 {
            return String(format: "%.1fM bodu", Double(vertices) / 1_000_000)
        } else if vertices >= 1_000 {
            return String(format: "%.1fK bodu", Double(vertices) / 1_000)
        } else {
            return "\(vertices) bodu"
        }
    }
}

// MARK: - Empty State

struct NoResumableSessionsView: View {
    let onNewScan: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Zadne rozpracovane skeny")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Zacnete novy sken a moznost pokracovat bude dostupna po prvnim ulozeni")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: onNewScan) {
                Label("Zacit novy sken", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 10)
        }
    }
}

// MARK: - Session Storage Info

struct SessionStorageInfo: View {
    let totalStorageMB: Int
    let sessionCount: Int

    var body: some View {
        HStack {
            Image(systemName: "externaldrive.fill")
                .foregroundStyle(.secondary)

            Text("\(sessionCount) skenu")
                .foregroundStyle(.secondary)

            Text("•")
                .foregroundStyle(.quaternary)

            Text(formattedStorage)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var formattedStorage: String {
        if totalStorageMB >= 1024 {
            return String(format: "%.1f GB", Double(totalStorageMB) / 1024)
        } else {
            return "\(totalStorageMB) MB"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ResumeSessionSheet_Previews: PreviewProvider {
    static var previews: some View {
        ResumeSessionSheet(
            sessions: [
                ScanSessionPersistence.PersistedSession(
                    id: UUID(),
                    name: "Obyvak",
                    createdAt: Date().addingTimeInterval(-3600),
                    updatedAt: Date().addingTimeInterval(-1800),
                    state: "paused",
                    deviceModel: "iPhone15,2",
                    appVersion: "1.0",
                    meshChunkFiles: [],
                    pointCloudChunkFiles: [],
                    textureFrameFiles: [],
                    worldMapFile: "worldmap.arworldmap",
                    trajectoryFile: nil,
                    coverageDataFile: nil,
                    scanDuration: 120,
                    totalVertices: 250000,
                    totalFaces: 80000,
                    areaScanned: 25.5,
                    thumbnailFile: nil
                ),
                ScanSessionPersistence.PersistedSession(
                    id: UUID(),
                    name: "Garaz",
                    createdAt: Date().addingTimeInterval(-86400),
                    updatedAt: Date().addingTimeInterval(-86400),
                    state: "scanning",
                    deviceModel: "iPhone15,2",
                    appVersion: "1.0",
                    meshChunkFiles: [],
                    pointCloudChunkFiles: [],
                    textureFrameFiles: [],
                    worldMapFile: "worldmap.arworldmap",
                    trajectoryFile: nil,
                    coverageDataFile: nil,
                    scanDuration: 300,
                    totalVertices: 1500000,
                    totalFaces: 500000,
                    areaScanned: 45.0,
                    thumbnailFile: nil
                )
            ],
            onResume: { _ in },
            onNewScan: { },
            onDelete: { _ in }
        )
    }
}
#endif
