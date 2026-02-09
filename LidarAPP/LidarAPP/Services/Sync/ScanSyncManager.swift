import Foundation

// MARK: - Scan Sync Manager

/// Offline-first scan synchronization manager.
///
/// Queues scans for upload locally, persists the queue to disk,
/// and uploads when network connectivity is available. Supports
/// automatic periodic syncing and basic conflict resolution.
@MainActor
@Observable
final class ScanSyncManager {

    // MARK: - Sync State

    enum SyncState: Sendable {
        case idle
        case syncing(progress: Float)
        case completed(synced: Int)
        case failed(String)
    }

    // MARK: - Configuration

    /// Maximum number of retry attempts before an item is marked as permanently failed.
    private static let maxRetryAttempts = 3

    /// Upload endpoint path.
    private static let uploadEndpoint = "/api/v1/scans/upload"

    /// Remote scan metadata endpoint.
    private static let scanMetadataEndpoint = "/api/v1/scans"

    // MARK: - Observable Properties

    private(set) var state: SyncState = .idle
    private(set) var pendingUploads: Int = 0
    private(set) var lastSyncDate: Date?

    // MARK: - Dependencies

    private let services: ServiceContainer
    private let syncQueue: SyncQueue

    // MARK: - Auto-Sync

    private var autoSyncTask: Task<Void, Never>?
    private var autoSyncInterval: TimeInterval = 60

    // MARK: - Initialization

    init(services: ServiceContainer) {
        self.services = services
        self.syncQueue = SyncQueue()
        updatePendingCount()
        infoLog("ScanSyncManager initialized with \(pendingUploads) pending uploads", category: .logCategoryNetwork)
    }

    // MARK: - Queue Management

    /// Add a scan to the upload queue.
    ///
    /// The scan file will be uploaded the next time `syncPendingItems()`
    /// runs or during the auto-sync cycle.
    func queueForUpload(scanId: UUID, fileURL: URL, metadata: SyncMetadata) {
        let item = SyncQueueItem(
            id: UUID(),
            scanId: scanId,
            fileURL: fileURL,
            metadata: metadata,
            addedAt: Date(),
            attempts: 0,
            lastAttempt: nil,
            status: .pending
        )

        syncQueue.add(item)
        updatePendingCount()
        infoLog("Scan \(scanId) queued for upload (\(metadata.scanName))", category: .logCategoryNetwork)
    }

    /// Remove a scan from the upload queue.
    func removeFromQueue(scanId: UUID) {
        syncQueue.remove(scanId: scanId)
        updatePendingCount()
        debugLog("Scan \(scanId) removed from sync queue", category: .logCategoryNetwork)
    }

    /// Returns all items currently in the sync queue.
    func getQueueStatus() -> [SyncQueueItem] {
        syncQueue.getAll()
    }

    // MARK: - Sync Operations

    /// Attempts to upload all pending items in the queue.
    ///
    /// Checks network connectivity first. Each item is uploaded
    /// sequentially; progress is reported through `state`.
    func syncPendingItems() async {
        let pendingItems = syncQueue.getPending()

        guard !pendingItems.isEmpty else {
            debugLog("No pending items to sync", category: .logCategoryNetwork)
            state = .idle
            return
        }

        // Check connectivity
        var isConnected = services.network.isConnected
        if !isConnected {
            isConnected = await services.network.checkConnectivity()
        }

        guard isConnected else {
            warningLog("Cannot sync - no network connection", category: .logCategoryNetwork)
            state = .failed("No network connection")
            return
        }

        infoLog("Starting sync of \(pendingItems.count) pending items", category: .logCategoryNetwork)
        state = .syncing(progress: 0)

        var successCount = 0
        let totalItems = Float(pendingItems.count)

        for (index, item) in pendingItems.enumerated() {
            let progress = Float(index) / totalItems
            state = .syncing(progress: progress)

            let success = await uploadItem(item)

            if success {
                successCount += 1
            }

            // Update progress
            let updatedProgress = Float(index + 1) / totalItems
            state = .syncing(progress: updatedProgress)
        }

        // Final state
        lastSyncDate = Date()
        updatePendingCount()

        if successCount == pendingItems.count {
            state = .completed(synced: successCount)
            infoLog("Sync completed: \(successCount)/\(pendingItems.count) items uploaded", category: .logCategoryNetwork)
        } else if successCount > 0 {
            state = .completed(synced: successCount)
            warningLog("Sync partially completed: \(successCount)/\(pendingItems.count) items uploaded", category: .logCategoryNetwork)
        } else {
            state = .failed("All uploads failed")
            errorLog("Sync failed: 0/\(pendingItems.count) items uploaded", category: .logCategoryNetwork)
        }
    }

    /// Starts a periodic auto-sync cycle.
    ///
    /// Every `interval` seconds the manager checks connectivity and
    /// uploads any pending items.
    func startAutoSync(interval: TimeInterval = 60) {
        stopAutoSync()
        autoSyncInterval = interval

        autoSyncTask = Task { [weak self] in
            guard let self else { return }

            infoLog("Auto-sync started with interval \(interval)s", category: .logCategoryNetwork)

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(autoSyncInterval))
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }

                let hasPending = syncQueue.getPending().isEmpty == false
                if hasPending {
                    debugLog("Auto-sync: found pending items, starting sync", category: .logCategoryNetwork)
                    await syncPendingItems()
                } else {
                    debugLog("Auto-sync: no pending items", category: .logCategoryNetwork)
                }
            }

            debugLog("Auto-sync task ended", category: .logCategoryNetwork)
        }
    }

    /// Stops the periodic auto-sync cycle.
    func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
        debugLog("Auto-sync stopped", category: .logCategoryNetwork)
    }

    // MARK: - Conflict Resolution

    /// Checks for a version conflict between a local scan and its
    /// remote counterpart.
    ///
    /// Compares the local `createdAt` timestamp against the server's
    /// `updatedAt` value. Returns `nil` if no conflict exists or
    /// the server is unreachable.
    func checkConflicts(scanId: UUID) async -> SyncConflict? {
        debugLog("Checking conflicts for scan \(scanId)", category: .logCategoryNetwork)

        // Find local version
        let queueItems = syncQueue.getAll()
        guard let localItem = queueItems.first(where: { $0.scanId == scanId }) else {
            debugLog("Scan \(scanId) not found in local queue", category: .logCategoryNetwork)
            return nil
        }

        // Query remote version
        do {
            let endpoint = "\(Self.scanMetadataEndpoint)/\(scanId.uuidString)"
            let response: RemoteScanInfo = try await services.network.request(
                endpoint: endpoint,
                method: .get,
                body: nil
            )

            let localVersion = localItem.metadata.createdAt
            let remoteVersion = response.updatedAt

            // Conflict if remote was modified after local creation
            if remoteVersion > localVersion {
                let conflict = SyncConflict(
                    scanId: scanId,
                    localVersion: localVersion,
                    remoteVersion: remoteVersion,
                    description: "Remote version (\(formatDate(remoteVersion))) is newer than local (\(formatDate(localVersion)))"
                )
                warningLog("Conflict detected for scan \(scanId): \(conflict.description)", category: .logCategoryNetwork)
                return conflict
            }

            debugLog("No conflict for scan \(scanId)", category: .logCategoryNetwork)
            return nil
        } catch {
            debugLog("Could not check remote version for scan \(scanId): \(error.localizedDescription)", category: .logCategoryNetwork)
            return nil
        }
    }

    /// Resolves a sync conflict using the specified resolution strategy.
    func resolveConflict(_ conflict: SyncConflict, resolution: ConflictResolution) {
        infoLog("Resolving conflict for scan \(conflict.scanId) with strategy: \(resolution)", category: .logCategoryNetwork)

        switch resolution {
        case .keepLocal:
            // Re-queue the local version for upload (force overwrite)
            if let existingItem = syncQueue.getAll().first(where: { $0.scanId == conflict.scanId }) {
                var updated = existingItem
                updated.status = .pending
                updated.attempts = 0
                syncQueue.update(updated)
                infoLog("Conflict resolved: keeping local version for scan \(conflict.scanId)", category: .logCategoryNetwork)
            }

        case .keepRemote:
            // Remove local item from queue; the remote version is authoritative
            syncQueue.remove(scanId: conflict.scanId)
            infoLog("Conflict resolved: keeping remote version for scan \(conflict.scanId)", category: .logCategoryNetwork)

        case .merge:
            // For merge we re-queue with a fresh attempt count.
            // A real merge would involve diffing point clouds,
            // but for now we treat it the same as keepLocal.
            if let existingItem = syncQueue.getAll().first(where: { $0.scanId == conflict.scanId }) {
                var updated = existingItem
                updated.status = .pending
                updated.attempts = 0
                syncQueue.update(updated)
                infoLog("Conflict resolved: merge requested for scan \(conflict.scanId) (uploading local)", category: .logCategoryNetwork)
            }
        }

        updatePendingCount()
    }

    // MARK: - Private Helpers

    /// Uploads a single queue item and updates its status.
    private func uploadItem(_ item: SyncQueueItem) async -> Bool {
        // Check retry limit
        guard item.attempts < Self.maxRetryAttempts else {
            warningLog("Scan \(item.scanId) exceeded max retry attempts (\(Self.maxRetryAttempts))", category: .logCategoryNetwork)
            var failedItem = item
            failedItem.status = .failed
            syncQueue.update(failedItem)
            return false
        }

        // Verify file still exists
        guard FileManager.default.fileExists(atPath: item.fileURL.path) else {
            errorLog("File not found for scan \(item.scanId): \(item.fileURL.lastPathComponent)", category: .logCategoryNetwork)
            var failedItem = item
            failedItem.status = .failed
            syncQueue.update(failedItem)
            return false
        }

        // Mark as uploading
        var uploadingItem = item
        uploadingItem.status = .uploading
        uploadingItem.attempts += 1
        uploadingItem.lastAttempt = Date()
        syncQueue.update(uploadingItem)

        debugLog("Uploading scan \(item.scanId) (attempt \(uploadingItem.attempts))", category: .logCategoryNetwork)

        do {
            _ = try await services.network.uploadFile(
                endpoint: Self.uploadEndpoint,
                fileURL: item.fileURL
            ) { progress in
                debugLog("Upload progress for \(item.scanId): \(Int(progress * 100))%", category: .logCategoryNetwork)
            }

            // Mark as completed
            var completedItem = uploadingItem
            completedItem.status = .completed
            syncQueue.update(completedItem)
            infoLog("Upload completed for scan \(item.scanId)", category: .logCategoryNetwork)
            return true
        } catch {
            errorLog("Upload failed for scan \(item.scanId): \(error.localizedDescription)", category: .logCategoryNetwork)
            var failedItem = uploadingItem
            failedItem.status = .failed
            syncQueue.update(failedItem)
            return false
        }
    }

    /// Updates the `pendingUploads` count from the queue.
    private func updatePendingCount() {
        pendingUploads = syncQueue.getPending().count
    }

    /// Formats a date for human-readable conflict descriptions.
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Remote Scan Info

/// Lightweight model for decoding scan metadata from the server
/// during conflict checks.
private struct RemoteScanInfo: Decodable {
    let id: String
    let updatedAt: Date
}
