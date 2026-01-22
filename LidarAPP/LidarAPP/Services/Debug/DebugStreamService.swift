import Foundation
import ARKit

#if DEBUG

// MARK: - Debug Event

struct DebugEvent: Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let category: String
    let type: String
    let data: [String: AnyCodableValue]
    let deviceId: String
    let sessionId: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: DebugCategory,
        type: String,
        data: [String: Any],
        sessionId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category.rawValue
        self.type = type
        self.data = data.mapValues { AnyCodableValue($0) }
        self.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        self.sessionId = sessionId
    }

    // Factory methods
    static func appState(
        scanState: String,
        trackingState: String,
        pointCount: Int,
        meshFaceCount: Int,
        memoryMB: Int,
        sessionId: String? = nil
    ) -> DebugEvent {
        DebugEvent(
            category: .appState,
            type: "state_snapshot",
            data: [
                "scanState": scanState,
                "trackingState": trackingState,
                "pointCount": pointCount,
                "meshFaceCount": meshFaceCount,
                "memoryMB": memoryMB
            ],
            sessionId: sessionId
        )
    }

    static func performance(snapshot: PerformanceSnapshot, sessionId: String? = nil) -> DebugEvent {
        DebugEvent(
            category: .performance,
            type: "metrics",
            data: snapshot.dictionary,
            sessionId: sessionId
        )
    }

    static func arEvent(type: String, details: [String: Any], sessionId: String? = nil) -> DebugEvent {
        DebugEvent(
            category: .arSession,
            type: type,
            data: details,
            sessionId: sessionId
        )
    }

    static func processingTiming(
        stage: String,
        durationMs: Double,
        frameNumber: Int,
        sessionId: String? = nil
    ) -> DebugEvent {
        DebugEvent(
            category: .processing,
            type: "timing",
            data: [
                "stage": stage,
                "durationMs": durationMs,
                "frameNumber": frameNumber
            ],
            sessionId: sessionId
        )
    }

    static func networkEvent(
        endpoint: String,
        method: String,
        statusCode: Int?,
        durationMs: Double,
        bytesTransferred: Int,
        sessionId: String? = nil
    ) -> DebugEvent {
        var data: [String: Any] = [
            "endpoint": endpoint,
            "method": method,
            "durationMs": durationMs,
            "bytesTransferred": bytesTransferred
        ]
        if let code = statusCode {
            data["statusCode"] = code
        }

        return DebugEvent(
            category: .network,
            type: "request",
            data: data,
            sessionId: sessionId
        )
    }

    static func logEvent(entry: LogEntry, sessionId: String? = nil) -> DebugEvent {
        var data: [String: Any] = [
            "level": entry.level.rawValue,
            "message": entry.message,
            "file": entry.file,
            "line": entry.line
        ]
        if let category = entry.category {
            data["logCategory"] = category
        }

        return DebugEvent(
            category: .logs,
            type: "log",
            data: data,
            sessionId: sessionId
        )
    }

    // MARK: - UI Events

    static func uiEvent(
        action: String,
        screen: String,
        element: String? = nil,
        details: [String: Any]? = nil,
        sessionId: String? = nil
    ) -> DebugEvent {
        var data: [String: Any] = [
            "action": action,
            "screen": screen
        ]
        if let element = element {
            data["element"] = element
        }
        if let details = details {
            for (key, value) in details {
                data[key] = value
            }
        }

        return DebugEvent(
            category: .appState,
            type: "ui_event",
            data: data,
            sessionId: sessionId
        )
    }

    static func viewAppeared(_ viewName: String, details: [String: Any]? = nil, sessionId: String? = nil) -> DebugEvent {
        uiEvent(action: "view_appeared", screen: viewName, details: details, sessionId: sessionId)
    }

    static func viewDisappeared(_ viewName: String, sessionId: String? = nil) -> DebugEvent {
        uiEvent(action: "view_disappeared", screen: viewName, sessionId: sessionId)
    }

    static func buttonTapped(_ buttonName: String, screen: String, sessionId: String? = nil) -> DebugEvent {
        uiEvent(action: "button_tapped", screen: screen, element: buttonName, sessionId: sessionId)
    }

    static func error(_ message: String, screen: String, details: [String: Any]? = nil, sessionId: String? = nil) -> DebugEvent {
        var mergedDetails: [String: Any] = ["error_message": message]
        if let details = details {
            mergedDetails.merge(details) { _, new in new }
        }
        return uiEvent(action: "error", screen: screen, details: mergedDetails, sessionId: sessionId)
    }
}

// MARK: - Any Codable Value

struct AnyCodableValue: Codable, Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodableValue].self) {
            value = arrayValue.map(\.value)
        } else if let dictValue = try? container.decode([String: AnyCodableValue].self) {
            value = dictValue.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let floatValue as Float:
            try container.encode(Double(floatValue))
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let dateValue as Date:
            try container.encode(ISO8601DateFormatter().string(from: dateValue))
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodableValue($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodableValue($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Debug Stream Service

/// Service for streaming debug events to backend
@MainActor
@Observable
final class DebugStreamService {
    static let shared = DebugStreamService()

    // MARK: - State

    private(set) var isStreaming = false
    private(set) var isConnected = false
    private(set) var eventsBuffered = 0
    private(set) var eventsSent = 0
    private(set) var lastError: String?

    // MARK: - Private Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private var eventBuffer: [DebugEvent] = []
    private var batchTimer: Timer?
    private var settings: DebugSettings { DebugSettings.shared }

    private let maxBufferSize = 500
    private let encoder: JSONEncoder

    private var currentSessionId: String?

    // MARK: - Initialization

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Start/Stop

    func startStreaming(sessionId: String? = nil) {
        guard !isStreaming else { return }
        guard settings.debugStreamEnabled else { return }

        isStreaming = true
        currentSessionId = sessionId
        eventBuffer.removeAll()
        eventsBuffered = 0
        eventsSent = 0
        lastError = nil

        if settings.debugStreamMode == "realtime" {
            startWebSocket()
        } else {
            startBatchMode()
        }

        // Connect to performance monitor
        PerformanceMonitor.shared.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in
                self?.logPerformance(snapshot)
            }
        }
        PerformanceMonitor.shared.startMonitoring()

        // Connect to logger
        DebugLogger.shared.onLogEntry = { [weak self] entry in
            Task { @MainActor in
                self?.logEntry(entry)
            }
        }

        debugLog("Debug streaming started (mode: \(settings.debugStreamMode))", category: .logCategoryNetwork)
    }

    func stopStreaming() {
        guard isStreaming else { return }

        isStreaming = false

        // Flush remaining events
        if !eventBuffer.isEmpty {
            Task {
                await flushBuffer()
            }
        }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        batchTimer?.invalidate()
        batchTimer = nil

        PerformanceMonitor.shared.stopMonitoring()
        PerformanceMonitor.shared.onSnapshot = nil
        DebugLogger.shared.onLogEntry = nil

        isConnected = false

        debugLog("Debug streaming stopped", category: .logCategoryNetwork)
    }

    // MARK: - WebSocket Mode

    private func startWebSocket() {
        guard let url = settings.debugStreamWebSocketURL else {
            lastError = "Invalid WebSocket URL"
            return
        }

        let session = URLSession(configuration: .default, delegate: SelfSignedCertDelegate.shared, delegateQueue: nil)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        isConnected = true
        receiveWebSocketMessages()

        debugLog("WebSocket connected to \(url)", category: .logCategoryNetwork)
    }

    private func receiveWebSocketMessages() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    // Handle server messages if needed
                    if case .string(let text) = message {
                        debugLog("WS received: \(text)", category: .logCategoryNetwork)
                    }
                    self?.receiveWebSocketMessages()

                case .failure(let error):
                    self?.lastError = error.localizedDescription
                    self?.isConnected = false
                    debugLog("WS error: \(error)", category: .logCategoryNetwork)

                    // Reconnect after delay
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if self?.isStreaming == true {
                        self?.startWebSocket()
                    }
                }
            }
        }
    }

    private func sendViaWebSocket(_ event: DebugEvent) {
        guard let data = try? encoder.encode(event),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            Task { @MainActor in
                if let error = error {
                    self?.lastError = error.localizedDescription
                } else {
                    self?.eventsSent += 1
                }
            }
        }
    }

    // MARK: - Batch Mode

    private func startBatchMode() {
        let interval = settings.batchInterval
        batchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.flushBuffer()
            }
        }

        isConnected = true
    }

    private func flushBuffer() async {
        guard !eventBuffer.isEmpty else { return }

        let eventsToSend = eventBuffer
        eventBuffer.removeAll()

        guard let url = settings.debugBatchUploadURL else {
            lastError = "Invalid batch URL"
            eventBuffer.append(contentsOf: eventsToSend) // Re-add on failure
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let payload: [String: Any] = [
                "events": eventsToSend.map { try? encoder.encode($0) }.compactMap { $0 }
            ]

            request.httpBody = try encoder.encode(eventsToSend)

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                eventsSent += eventsToSend.count
                eventsBuffered = eventBuffer.count
            } else {
                lastError = "Server returned error"
                // Re-add failed events (up to buffer limit)
                let remaining = maxBufferSize - eventBuffer.count
                eventBuffer.append(contentsOf: eventsToSend.prefix(remaining))
            }
        } catch {
            lastError = error.localizedDescription
            // Re-add failed events
            let remaining = maxBufferSize - eventBuffer.count
            eventBuffer.append(contentsOf: eventsToSend.prefix(remaining))
        }

        eventsBuffered = eventBuffer.count
    }

    // MARK: - Event Logging

    func logEvent(_ event: DebugEvent) {
        guard isStreaming else { return }
        guard settings.isCategoryEnabled(DebugCategory(rawValue: event.category) ?? .logs) else { return }

        if settings.debugStreamMode == "realtime" {
            sendViaWebSocket(event)
        } else {
            eventBuffer.append(event)
            if eventBuffer.count > maxBufferSize {
                eventBuffer.removeFirst()
            }
            eventsBuffered = eventBuffer.count
        }
    }

    // Convenience methods
    func logAppState(
        scanState: String,
        trackingState: String,
        pointCount: Int,
        meshFaceCount: Int,
        memoryMB: Int
    ) {
        let event = DebugEvent.appState(
            scanState: scanState,
            trackingState: trackingState,
            pointCount: pointCount,
            meshFaceCount: meshFaceCount,
            memoryMB: memoryMB,
            sessionId: currentSessionId
        )
        logEvent(event)
    }

    func logPerformance(_ snapshot: PerformanceSnapshot) {
        let event = DebugEvent.performance(snapshot: snapshot, sessionId: currentSessionId)
        logEvent(event)
    }

    func logARTrackingChange(_ state: ARCamera.TrackingState) {
        let stateString: String
        let reason: String?

        switch state {
        case .normal:
            stateString = "normal"
            reason = nil
        case .limited(let limitedReason):
            stateString = "limited"
            switch limitedReason {
            case .initializing: reason = "initializing"
            case .relocalizing: reason = "relocalizing"
            case .excessiveMotion: reason = "excessiveMotion"
            case .insufficientFeatures: reason = "insufficientFeatures"
            @unknown default: reason = "unknown"
            }
        case .notAvailable:
            stateString = "notAvailable"
            reason = nil
        }

        var details: [String: Any] = ["state": stateString]
        if let r = reason {
            details["reason"] = r
        }

        let event = DebugEvent.arEvent(type: "trackingStateChanged", details: details, sessionId: currentSessionId)
        logEvent(event)
    }

    func logMeshAnchorEvent(_ anchor: ARMeshAnchor, type: String) {
        let event = DebugEvent.arEvent(
            type: "meshAnchor_\(type)",
            details: [
                "anchorId": anchor.identifier.uuidString,
                "vertexCount": anchor.geometry.vertices.count,
                "faceCount": anchor.geometry.faces.count
            ],
            sessionId: currentSessionId
        )
        logEvent(event)
    }

    func logProcessingTiming(stage: String, duration: TimeInterval, frameNumber: Int) {
        let event = DebugEvent.processingTiming(
            stage: stage,
            durationMs: duration * 1000,
            frameNumber: frameNumber,
            sessionId: currentSessionId
        )
        logEvent(event)
    }

    func logNetworkRequest(
        endpoint: String,
        method: String,
        statusCode: Int?,
        duration: TimeInterval,
        bytesTransferred: Int
    ) {
        let event = DebugEvent.networkEvent(
            endpoint: endpoint,
            method: method,
            statusCode: statusCode,
            durationMs: duration * 1000,
            bytesTransferred: bytesTransferred,
            sessionId: currentSessionId
        )
        logEvent(event)
    }

    private func logEntry(_ entry: LogEntry) {
        let event = DebugEvent.logEvent(entry: entry, sessionId: currentSessionId)
        logEvent(event)
    }

    // MARK: - UI Tracking

    /// Track view appearance
    func trackViewAppeared(_ viewName: String, details: [String: Any]? = nil) {
        let event = DebugEvent.viewAppeared(viewName, details: details, sessionId: currentSessionId)
        logEvent(event)
    }

    /// Track view disappearance
    func trackViewDisappeared(_ viewName: String) {
        let event = DebugEvent.viewDisappeared(viewName, sessionId: currentSessionId)
        logEvent(event)
    }

    /// Track button tap
    func trackButtonTap(_ buttonName: String, screen: String) {
        let event = DebugEvent.buttonTapped(buttonName, screen: screen, sessionId: currentSessionId)
        logEvent(event)
    }

    /// Track error
    func trackError(_ message: String, screen: String, details: [String: Any]? = nil) {
        let event = DebugEvent.error(message, screen: screen, details: details, sessionId: currentSessionId)
        logEvent(event)
    }

    /// Track custom UI event
    func trackUIEvent(action: String, screen: String, element: String? = nil, details: [String: Any]? = nil) {
        let event = DebugEvent.uiEvent(action: action, screen: screen, element: element, details: details, sessionId: currentSessionId)
        logEvent(event)
    }
}

#endif
