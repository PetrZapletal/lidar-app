import Foundation

// MARK: - Sync Metadata

/// Metadata attached to a queued scan upload.
struct SyncMetadata: Codable, Sendable {
    let scanName: String
    let pointCount: Int
    let faceCount: Int
    let createdAt: Date
    let exportFormat: String
}

// MARK: - Sync Queue Item

/// Represents a single item in the persistent sync upload queue.
struct SyncQueueItem: Identifiable, Codable, Sendable {
    let id: UUID
    let scanId: UUID
    let fileURL: URL
    let metadata: SyncMetadata
    let addedAt: Date
    var attempts: Int
    var lastAttempt: Date?
    var status: SyncItemStatus
}

// MARK: - Sync Item Status

enum SyncItemStatus: String, Codable, Sendable {
    case pending
    case uploading
    case completed
    case failed
}

// MARK: - Sync Conflict

/// Describes a version conflict between a local scan and its remote counterpart.
struct SyncConflict: Sendable {
    let scanId: UUID
    let localVersion: Date
    let remoteVersion: Date
    let description: String
}

// MARK: - Conflict Resolution

enum ConflictResolution: Sendable {
    case keepLocal
    case keepRemote
    case merge
}

// MARK: - Sync Queue

/// Persistent queue backed by a JSON file in the app's Documents directory.
///
/// Items survive app restarts. The queue is loaded from disk on init and
/// saved after every mutation.
final class SyncQueue: @unchecked Sendable {

    // MARK: - Properties

    private let queueFileURL: URL

    /// In-memory queue protected by an NSLock for thread safety.
    private let lock = NSLock()
    private var _items: [SyncQueueItem] = []

    // MARK: - Initialization

    init() {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        self.queueFileURL = documentsDirectory.appendingPathComponent("sync_queue.json")
        loadQueue()
        debugLog("SyncQueue initialized with \(_items.count) items from \(queueFileURL.lastPathComponent)", category: .logCategoryStorage)
    }

    // MARK: - Public Methods

    /// Add a new item to the queue. If an item with the same `scanId`
    /// already exists it will be replaced.
    func add(_ item: SyncQueueItem) {
        lock.lock()
        defer { lock.unlock() }

        // Remove existing item for same scan to avoid duplicates
        _items.removeAll { $0.scanId == item.scanId }
        _items.append(item)
        saveQueue()

        debugLog("Added scan \(item.scanId) to sync queue (total: \(_items.count))", category: .logCategoryStorage)
    }

    /// Remove an item identified by its `scanId`.
    func remove(scanId: UUID) {
        lock.lock()
        defer { lock.unlock()  }

        let countBefore = _items.count
        _items.removeAll { $0.scanId == scanId }

        if _items.count < countBefore {
            saveQueue()
            debugLog("Removed scan \(scanId) from sync queue", category: .logCategoryStorage)
        }
    }

    /// Replace the item with matching `id`.
    func update(_ item: SyncQueueItem) {
        lock.lock()
        defer { lock.unlock() }

        if let index = _items.firstIndex(where: { $0.id == item.id }) {
            _items[index] = item
            saveQueue()
            debugLog("Updated queue item \(item.id) status: \(item.status.rawValue)", category: .logCategoryStorage)
        }
    }

    /// Returns all items that are pending or have failed and are
    /// eligible for retry.
    func getPending() -> [SyncQueueItem] {
        lock.lock()
        defer { lock.unlock() }

        return _items.filter { $0.status == .pending || $0.status == .failed }
    }

    /// Returns every item in the queue regardless of status.
    func getAll() -> [SyncQueueItem] {
        lock.lock()
        defer { lock.unlock() }

        return _items
    }

    // MARK: - Persistence

    /// Loads the queue from its JSON file on disk.
    private func loadQueue() {
        guard FileManager.default.fileExists(atPath: queueFileURL.path) else {
            debugLog("No existing sync queue file found", category: .logCategoryStorage)
            return
        }

        do {
            let data = try Data(contentsOf: queueFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            _items = try decoder.decode([SyncQueueItem].self, from: data)
            infoLog("Loaded \(_items.count) items from sync queue", category: .logCategoryStorage)
        } catch {
            errorLog("Failed to load sync queue: \(error.localizedDescription)", category: .logCategoryStorage)
            _items = []
        }
    }

    /// Writes the current queue to its JSON file on disk.
    private func saveQueue() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(_items)
            try data.write(to: queueFileURL, options: .atomic)
        } catch {
            errorLog("Failed to save sync queue: \(error.localizedDescription)", category: .logCategoryStorage)
        }
    }
}
