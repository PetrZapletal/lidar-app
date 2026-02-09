import Foundation
import UIKit
import ARKit

/// ViewModel pro hlavní obrazovku nastavení
@MainActor
@Observable
final class SettingsViewModel {

    // MARK: - Account

    var isSignedIn: Bool = false
    var userName: String = ""
    var userEmail: String = ""

    // MARK: - Scanning

    var defaultScanMode: ScanMode = .exterior
    var autoSaveEnabled: Bool = true

    // MARK: - Export

    var defaultExportFormat: String = "USDZ"
    var exportQuality: Float = 0.9

    static let availableExportFormats = ["USDZ", "GLTF", "OBJ", "STL", "PLY"]

    // MARK: - Server

    var serverIP: String {
        didSet { DebugSettings.shared.tailscaleIP = serverIP }
    }

    var serverPort: Int {
        didSet { DebugSettings.shared.serverPort = serverPort }
    }

    var isServerConnected: Bool = false
    var isTestingConnection: Bool = false
    var connectionTestMessage: String = ""
    var connectionLatencyMs: Double?

    // MARK: - Debug

    var debugStreamEnabled: Bool {
        didSet { DebugSettings.shared.debugStreamEnabled = debugStreamEnabled }
    }

    var verboseLogging: Bool {
        didSet { DebugSettings.shared.verboseLogging = verboseLogging }
    }

    var showPerformanceOverlay: Bool = false

    var rawDataModeEnabled: Bool {
        didSet { DebugSettings.shared.rawDataModeEnabled = rawDataModeEnabled }
    }

    var textureQuality: Double {
        didSet { DebugSettings.shared.textureQuality = textureQuality }
    }

    var maxTextureFrames: Int {
        didSet { DebugSettings.shared.maxTextureFrames = maxTextureFrames }
    }

    // MARK: - About

    var appVersion: String
    var buildNumber: String
    var deviceModel: String
    var iOSVersion: String
    var hasLiDAR: Bool

    // MARK: - Cache

    var isClearingCache: Bool = false
    var cacheCleared: Bool = false

    // MARK: - Dependencies

    private let services: ServiceContainer

    // MARK: - Init

    init(services: ServiceContainer) {
        self.services = services

        let settings = DebugSettings.shared

        // Server
        self.serverIP = settings.tailscaleIP
        self.serverPort = settings.serverPort

        // Debug
        self.debugStreamEnabled = settings.debugStreamEnabled
        self.verboseLogging = settings.verboseLogging
        self.rawDataModeEnabled = settings.rawDataModeEnabled
        self.textureQuality = settings.textureQuality
        self.maxTextureFrames = settings.maxTextureFrames

        // About
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        self.buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        self.deviceModel = Self.deviceModelName()
        self.iOSVersion = UIDevice.current.systemVersion
        self.hasLiDAR = Self.checkLiDARSupport()

        infoLog("SettingsViewModel initialized", category: .logCategoryUI)
    }

    // MARK: - Server Connection

    func testServerConnection() async {
        isTestingConnection = true
        connectionTestMessage = ""
        connectionLatencyMs = nil

        debugLog("Testing server connection to \(serverIP):\(serverPort)", category: .logCategoryNetwork)

        let result = await DebugSettings.shared.testConnection()

        isServerConnected = result.success
        connectionTestMessage = result.message
        connectionLatencyMs = result.latencyMs

        if result.success {
            infoLog("Server connection successful: \(result.message)", category: .logCategoryNetwork)
        } else {
            warningLog("Server connection failed: \(result.message)", category: .logCategoryNetwork)
        }

        isTestingConnection = false
    }

    // MARK: - Account

    func signOut() async {
        debugLog("User signing out", category: .logCategoryUI)
        isSignedIn = false
        userName = ""
        userEmail = ""
        infoLog("User signed out", category: .logCategoryUI)
    }

    // MARK: - Reset

    func resetSettings() {
        DebugSettings.shared.resetToDefaults()

        // Re-read from DebugSettings
        let settings = DebugSettings.shared
        serverIP = settings.tailscaleIP
        serverPort = settings.serverPort
        debugStreamEnabled = settings.debugStreamEnabled
        verboseLogging = settings.verboseLogging
        rawDataModeEnabled = settings.rawDataModeEnabled
        textureQuality = settings.textureQuality
        maxTextureFrames = settings.maxTextureFrames

        // Reset local settings
        defaultScanMode = .exterior
        autoSaveEnabled = true
        defaultExportFormat = "USDZ"
        exportQuality = 0.9
        showPerformanceOverlay = false

        // Reset connection state
        isServerConnected = false
        connectionTestMessage = ""
        connectionLatencyMs = nil

        infoLog("All settings reset to defaults", category: .logCategoryUI)
    }

    // MARK: - Cache

    func clearCache() async {
        isClearingCache = true
        debugLog("Clearing cache...", category: .logCategoryStorage)

        // Clear temporary files
        let tmpDir = FileManager.default.temporaryDirectory
        do {
            let tmpContents = try FileManager.default.contentsOfDirectory(
                at: tmpDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            for fileURL in tmpContents {
                try? FileManager.default.removeItem(at: fileURL)
            }
            infoLog("Cache cleared: \(tmpContents.count) items removed", category: .logCategoryStorage)
        } catch {
            errorLog("Failed to clear cache: \(error.localizedDescription)", category: .logCategoryStorage)
        }

        // Clear log buffer
        services.logger.clearBuffer()

        cacheCleared = true
        isClearingCache = false

        // Reset indicator after 2 seconds
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        cacheCleared = false
    }

    // MARK: - Logs

    var recentLogs: [LogEntry] {
        services.logger.getRecentLogs(count: 50)
    }

    func exportLogs() -> URL? {
        services.logger.saveLogsToFile()
    }

    func clearLogs() {
        services.logger.clearBuffer()
        debugLog("Logs cleared by user", category: .logCategoryUI)
    }

    // MARK: - Memory Info

    var memoryUsageMB: Int {
        services.performanceMonitor.memoryUsageMB
    }

    var availableMemoryMB: Int {
        services.performanceMonitor.availableMemoryMB
    }

    // MARK: - Private Helpers

    private static func deviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    private static func checkLiDARSupport() -> Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
}
