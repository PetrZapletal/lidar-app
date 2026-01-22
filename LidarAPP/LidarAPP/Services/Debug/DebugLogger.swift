import Foundation
import os.log

#if DEBUG

// MARK: - Log Level

enum LogLevel: String, Codable, CaseIterable, Comparable {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }

    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .warning, .error]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

// MARK: - Log Entry

struct LogEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
    let file: String
    let function: String
    let line: Int
    let category: String?
    let metadata: [String: String]?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        message: String,
        file: String,
        function: String,
        line: Int,
        category: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.file = file
        self.function = function
        self.line = line
        self.category = category
        self.metadata = metadata
    }

    var formattedMessage: String {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: timestamp)
        return "[\(timestamp)] [\(level.rawValue.uppercased())] \(fileName):\(line) - \(message)"
    }

    var shortMessage: String {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        return "\(level.emoji) \(fileName):\(line) \(message)"
    }
}

// MARK: - Debug Logger

/// Centralized logging system for debug builds
/// Stores logs in memory buffer and forwards to os.log
@MainActor
final class DebugLogger {
    static let shared = DebugLogger()

    // MARK: - Properties

    private var buffer: [LogEntry] = []
    private let maxBufferSize: Int
    private let minimumLevel: LogLevel

    private let osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.lidarapp", category: "Debug")

    /// Callback for forwarding logs to debug stream
    var onLogEntry: ((LogEntry) -> Void)?

    // MARK: - Initialization

    private init(maxBufferSize: Int = 2000, minimumLevel: LogLevel = .debug) {
        self.maxBufferSize = maxBufferSize
        self.minimumLevel = minimumLevel
    }

    // MARK: - Logging Methods

    func log(
        _ level: LogLevel,
        _ message: String,
        category: String? = nil,
        metadata: [String: String]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level >= minimumLevel else { return }

        let entry = LogEntry(
            level: level,
            message: message,
            file: file,
            function: function,
            line: line,
            category: category,
            metadata: metadata
        )

        // Add to buffer
        buffer.append(entry)

        // Trim buffer if needed
        if buffer.count > maxBufferSize {
            buffer.removeFirst(buffer.count - maxBufferSize)
        }

        // Log to os.log
        os_log("%{public}@", log: osLog, type: level.osLogType, entry.formattedMessage)

        // Also print to console for Xcode debugging
        print(entry.shortMessage)

        // Forward to debug stream if configured
        onLogEntry?(entry)
    }

    // MARK: - Convenience Methods

    func debug(
        _ message: String,
        category: String? = nil,
        metadata: [String: String]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.debug, message, category: category, metadata: metadata, file: file, function: function, line: line)
    }

    func info(
        _ message: String,
        category: String? = nil,
        metadata: [String: String]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.info, message, category: category, metadata: metadata, file: file, function: function, line: line)
    }

    func warning(
        _ message: String,
        category: String? = nil,
        metadata: [String: String]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.warning, message, category: category, metadata: metadata, file: file, function: function, line: line)
    }

    func error(
        _ message: String,
        category: String? = nil,
        metadata: [String: String]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.error, message, category: category, metadata: metadata, file: file, function: function, line: line)
    }

    // MARK: - Buffer Access

    func getRecentLogs(count: Int = 100) -> [LogEntry] {
        Array(buffer.suffix(count))
    }

    func getLogs(since date: Date) -> [LogEntry] {
        buffer.filter { $0.timestamp >= date }
    }

    func getLogs(level: LogLevel) -> [LogEntry] {
        buffer.filter { $0.level >= level }
    }

    func getLogs(category: String) -> [LogEntry] {
        buffer.filter { $0.category == category }
    }

    func clearBuffer() {
        buffer.removeAll()
    }

    var logCount: Int {
        buffer.count
    }

    // MARK: - Export

    func exportLogs() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(buffer)
    }

    func exportLogsAsText() -> String {
        buffer.map(\.formattedMessage).joined(separator: "\n")
    }

    func saveLogsToFile() -> URL? {
        guard let data = exportLogs() else { return nil }

        let fileName = "debug_logs_\(ISO8601DateFormatter().string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Global Convenience Functions

/// Log debug message
func debugLog(
    _ message: String,
    category: String? = nil,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task { @MainActor in
        DebugLogger.shared.debug(message, category: category, file: file, function: function, line: line)
    }
}

/// Log info message
func infoLog(
    _ message: String,
    category: String? = nil,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task { @MainActor in
        DebugLogger.shared.info(message, category: category, file: file, function: function, line: line)
    }
}

/// Log warning message
func warningLog(
    _ message: String,
    category: String? = nil,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task { @MainActor in
        DebugLogger.shared.warning(message, category: category, file: file, function: function, line: line)
    }
}

/// Log error message
func errorLog(
    _ message: String,
    category: String? = nil,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task { @MainActor in
        DebugLogger.shared.error(message, category: category, file: file, function: function, line: line)
    }
}

// MARK: - Log Categories

extension String {
    static let logCategoryAR = "AR"
    static let logCategoryScanning = "Scanning"
    static let logCategoryProcessing = "Processing"
    static let logCategoryNetwork = "Network"
    static let logCategoryUI = "UI"
    static let logCategoryML = "ML"
    static let logCategoryStorage = "Storage"
}

#endif

// MARK: - Release Build Stubs

#if !DEBUG
/// No-op logging functions for release builds
func debugLog(_ message: String, category: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {}
func infoLog(_ message: String, category: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {}
func warningLog(_ message: String, category: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {}
func errorLog(_ message: String, category: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {}
#endif
