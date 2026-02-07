import Foundation
import QuartzCore
import UIKit

// MARK: - Performance Snapshot

struct PerformanceSnapshot: Codable, Sendable {
    let timestamp: Date
    let fps: Float
    let memoryUsageMB: Int
    let availableMemoryMB: Int
    let cpuUsage: Float
    let threadCount: Int
    let thermalState: String
    let batteryLevel: Float?
    let isLowPowerMode: Bool

    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "fps": fps,
            "memoryUsageMB": memoryUsageMB,
            "availableMemoryMB": availableMemoryMB,
            "cpuUsage": cpuUsage,
            "threadCount": threadCount,
            "thermalState": thermalState,
            "isLowPowerMode": isLowPowerMode
        ]
        if let battery = batteryLevel {
            dict["batteryLevel"] = battery
        }
        return dict
    }
}

// MARK: - Performance Monitor

/// Monitors app performance metrics in real-time
@MainActor
@Observable
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    // MARK: - Published Properties

    private(set) var currentFPS: Float = 0
    private(set) var memoryUsageMB: Int = 0
    private(set) var availableMemoryMB: Int = 0
    private(set) var cpuUsage: Float = 0
    private(set) var threadCount: Int = 0
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    private(set) var isMonitoring = false

    // MARK: - Private Properties

    private var displayLink: CADisplayLink?
    private var frameTimestamps: [CFTimeInterval] = []
    private let maxFrameSamples = 60

    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 0.5

    /// Callback for performance snapshots
    var onSnapshot: ((PerformanceSnapshot) -> Void)?

    // MARK: - Initialization

    private init() {
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    // MARK: - Start/Stop

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Start display link for FPS
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkTick))
        displayLink?.add(to: .main, forMode: .common)

        // Start timer for other metrics
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }

        debugLog("Performance monitoring started", category: .logCategoryProcessing)
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        displayLink?.invalidate()
        displayLink = nil

        updateTimer?.invalidate()
        updateTimer = nil

        frameTimestamps.removeAll()

        debugLog("Performance monitoring stopped", category: .logCategoryProcessing)
    }

    // MARK: - Display Link

    @objc private func displayLinkTick(_ displayLink: CADisplayLink) {
        let timestamp = displayLink.timestamp
        frameTimestamps.append(timestamp)

        // Keep only recent samples
        if frameTimestamps.count > maxFrameSamples {
            frameTimestamps.removeFirst()
        }

        // Calculate FPS
        if frameTimestamps.count >= 2 {
            let duration = frameTimestamps.last! - frameTimestamps.first!
            if duration > 0 {
                currentFPS = Float(frameTimestamps.count - 1) / Float(duration)
            }
        }
    }

    // MARK: - Metrics Update

    private func updateMetrics() {
        // Memory usage
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            memoryUsageMB = Int(info.resident_size / 1_000_000)
        }

        // Available memory (approximation)
        availableMemoryMB = Int(ProcessInfo.processInfo.physicalMemory / 1_000_000) - memoryUsageMB

        // CPU usage
        cpuUsage = getCPUUsage()

        // Thread count
        threadCount = getThreadCount()

        // Thermal state
        thermalState = ProcessInfo.processInfo.thermalState

        // Send snapshot
        let snapshot = collectSnapshot()
        onSnapshot?(snapshot)
    }

    // MARK: - CPU Usage

    private func getCPUUsage() -> Float {
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t()

        let result = task_threads(mach_task_self_, &threadsList, &threadsCount)
        guard result == KERN_SUCCESS, let threads = threadsList else {
            return 0
        }

        var totalCPU: Float = 0

        for i in 0..<Int(threadsCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)

            let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                }
            }

            if infoResult == KERN_SUCCESS {
                if threadInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalCPU += Float(threadInfo.cpu_usage) / Float(TH_USAGE_SCALE) * 100
                }
            }
        }

        // Deallocate
        let size = vm_size_t(MemoryLayout<thread_t>.size * Int(threadsCount))
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)

        return totalCPU
    }

    // MARK: - Thread Count

    private func getThreadCount() -> Int {
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t()

        let result = task_threads(mach_task_self_, &threadsList, &threadsCount)
        guard result == KERN_SUCCESS, let threads = threadsList else {
            return 0
        }

        let count = Int(threadsCount)

        // Deallocate
        let size = vm_size_t(MemoryLayout<thread_t>.size * count)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)

        return count
    }

    // MARK: - Snapshot

    func collectSnapshot() -> PerformanceSnapshot {
        let thermalStateString: String
        switch thermalState {
        case .nominal: thermalStateString = "nominal"
        case .fair: thermalStateString = "fair"
        case .serious: thermalStateString = "serious"
        case .critical: thermalStateString = "critical"
        @unknown default: thermalStateString = "unknown"
        }

        var batteryLevel: Float?
        if UIDevice.current.batteryState != .unknown {
            batteryLevel = UIDevice.current.batteryLevel
        }

        return PerformanceSnapshot(
            timestamp: Date(),
            fps: currentFPS,
            memoryUsageMB: memoryUsageMB,
            availableMemoryMB: availableMemoryMB,
            cpuUsage: cpuUsage,
            threadCount: threadCount,
            thermalState: thermalStateString,
            batteryLevel: batteryLevel,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    // MARK: - Processing Time Tracker

    /// Track processing duration for a named operation
    func trackProcessingTime<T>(
        operation: String,
        block: () async throws -> T
    ) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        debugLog("\(operation) completed in \(String(format: "%.2f", duration * 1000))ms", category: .logCategoryProcessing)

        return result
    }

    func trackProcessingTimeSync<T>(
        operation: String,
        block: () throws -> T
    ) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        debugLog("\(operation) completed in \(String(format: "%.2f", duration * 1000))ms", category: .logCategoryProcessing)

        return result
    }
}

// MARK: - Performance History

/// Stores historical performance data for analysis
@MainActor
@Observable
final class PerformanceHistory {
    static let shared = PerformanceHistory()

    private var snapshots: [PerformanceSnapshot] = []
    private let maxSnapshots = 1000

    private init() {}

    func addSnapshot(_ snapshot: PerformanceSnapshot) {
        snapshots.append(snapshot)
        if snapshots.count > maxSnapshots {
            snapshots.removeFirst()
        }
    }

    func getSnapshots(since date: Date) -> [PerformanceSnapshot] {
        snapshots.filter { $0.timestamp >= date }
    }

    func getSnapshots(last count: Int) -> [PerformanceSnapshot] {
        Array(snapshots.suffix(count))
    }

    func clear() {
        snapshots.removeAll()
    }

    // MARK: - Statistics

    var averageFPS: Float {
        guard !snapshots.isEmpty else { return 0 }
        return snapshots.map(\.fps).reduce(0, +) / Float(snapshots.count)
    }

    var averageMemoryMB: Int {
        guard !snapshots.isEmpty else { return 0 }
        return snapshots.map(\.memoryUsageMB).reduce(0, +) / snapshots.count
    }

    var peakMemoryMB: Int {
        snapshots.map(\.memoryUsageMB).max() ?? 0
    }

    var averageCPU: Float {
        guard !snapshots.isEmpty else { return 0 }
        return snapshots.map(\.cpuUsage).reduce(0, +) / Float(snapshots.count)
    }

    func exportAsJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try? encoder.encode(snapshots)
    }
}
