import Foundation
import Combine

// MARK: - WebSocket Message

/// Represents a message sent or received over the WebSocket connection.
struct WebSocketMessage: Codable {
    let type: String
    let data: [String: AnyCodableValue]?
    let timestamp: Date?

    enum CodingKeys: String, CodingKey {
        case type
        case data
        case timestamp
    }

    init(type: String, data: [String: AnyCodableValue]? = nil, timestamp: Date? = nil) {
        self.type = type
        self.data = data
        self.timestamp = timestamp ?? Date()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(String.self, forKey: .type)
        self.data = try container.decodeIfPresent([String: AnyCodableValue].self, forKey: .data)
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
    }
}

// MARK: - AnyCodableValue Convenience Accessors

/// Convenience accessors for extracting typed values from `AnyCodableValue`.
/// The `AnyCodableValue` type is defined in `DebugStreamService.swift` and stores `Any`.
extension AnyCodableValue {

    /// Extract String value if the underlying value is a String.
    var stringValue: String? {
        value as? String
    }

    /// Extract Int value if the underlying value is an Int.
    var intValue: Int? {
        value as? Int
    }

    /// Extract Double value, converting from Int if necessary.
    var doubleValue: Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    /// Extract Bool value if the underlying value is a Bool.
    var boolValue: Bool? {
        value as? Bool
    }

    /// Extract Float value, converting from Double or Int if necessary.
    var floatValue: Float? {
        if let d = value as? Double { return Float(d) }
        if let f = value as? Float { return f }
        if let i = value as? Int { return Float(i) }
        return nil
    }
}

// MARK: - WebSocket Service

/// Real-time WebSocket communication service for receiving scan processing updates.
/// Connects to `wss://<host>:<port>/ws/scans/{scanId}` and streams processing events.
/// Features auto-reconnect with exponential backoff and keepalive ping/pong.
@MainActor
@Observable
final class WebSocketService {

    // MARK: - Connection State

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected): return true
            case (.connecting, .connecting): return true
            case (.connected, .connected): return true
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    // MARK: - Constants

    private enum Constants {
        static let pingIntervalSeconds: TimeInterval = 30.0
        static let maxReconnectAttempts = 5
        static let initialReconnectDelaySeconds: TimeInterval = 1.0
        static let maxReconnectDelaySeconds: TimeInterval = 60.0
    }

    // MARK: - Properties

    private(set) var state: ConnectionState = .disconnected

    @ObservationIgnored
    private var webSocketTask: URLSessionWebSocketTask?
    @ObservationIgnored
    private var pingTask: Task<Void, Never>?
    @ObservationIgnored
    private var receiveTask: Task<Void, Never>?
    @ObservationIgnored
    private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored
    private var reconnectAttempt = 0
    @ObservationIgnored
    private var currentScanId: String?
    @ObservationIgnored
    private var intentionalDisconnect = false

    @ObservationIgnored
    private let messageSubject = PassthroughSubject<WebSocketMessage, Never>()

    /// Publisher that emits incoming WebSocket messages.
    var messagePublisher: AnyPublisher<WebSocketMessage, Never> {
        messageSubject.eraseToAnyPublisher()
    }

    @ObservationIgnored
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    @ObservationIgnored
    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Initialization

    init() {}

    // MARK: - Connect

    /// Connect to the WebSocket endpoint for a specific scan's processing updates.
    /// - Parameter scanId: The scan identifier to subscribe to.
    func connect(scanId: String) async {
        // If already connected to the same scan, skip
        if case .connected = state, currentScanId == scanId {
            debugLog("WebSocket already connected to scan \(scanId)", category: .logCategoryNetwork)
            return
        }

        // Disconnect existing connection first
        disconnectInternal()

        intentionalDisconnect = false
        currentScanId = scanId
        reconnectAttempt = 0

        await performConnect(scanId: scanId)
    }

    /// Disconnect from the WebSocket.
    func disconnect() {
        intentionalDisconnect = true
        disconnectInternal()
        state = .disconnected
        infoLog("WebSocket disconnected intentionally", category: .logCategoryNetwork)
    }

    /// Send a message over the WebSocket connection.
    /// - Parameter message: The WebSocketMessage to send.
    func send(_ message: WebSocketMessage) async throws {
        guard let task = webSocketTask, case .connected = state else {
            throw NetworkError.notConnected
        }

        do {
            let data = try jsonEncoder.encode(message)
            try await task.send(.data(data))
            debugLog("WebSocket sent message: type=\(message.type)", category: .logCategoryNetwork)
        } catch let error as NetworkError {
            throw error
        } catch {
            errorLog("WebSocket send failed: \(error.localizedDescription)", category: .logCategoryNetwork)
            throw NetworkError.requestFailed(statusCode: 0, message: "WebSocket send failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private: Connection

    private func performConnect(scanId: String) async {
        state = .connecting

        let settings = DebugSettings.shared
        let urlString = "wss://\(settings.tailscaleIP):\(settings.serverPort)/ws/scans/\(scanId)"

        guard let url = URL(string: urlString) else {
            state = .failed("Invalid WebSocket URL: \(urlString)")
            errorLog("Invalid WebSocket URL: \(urlString)", category: .logCategoryNetwork)
            return
        }

        debugLog("WebSocket connecting to \(urlString)", category: .logCategoryNetwork)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0

        let session = URLSession(
            configuration: config,
            delegate: SelfSignedCertDelegate.shared,
            delegateQueue: nil
        )

        let task = session.webSocketTask(with: url)
        self.webSocketTask = task

        task.resume()

        // Send an initial ping to verify the connection
        do {
            try await task.sendPingAsync()
            state = .connected
            reconnectAttempt = 0
            infoLog("WebSocket connected to scan \(scanId)", category: .logCategoryNetwork)

            startReceiving()
            startPingTimer()
        } catch {
            state = .failed("Connection failed: \(error.localizedDescription)")
            errorLog("WebSocket connection failed: \(error.localizedDescription)", category: .logCategoryNetwork)
            scheduleReconnect()
        }
    }

    private func disconnectInternal() {
        pingTask?.cancel()
        pingTask = nil

        receiveTask?.cancel()
        receiveTask = nil

        reconnectTask?.cancel()
        reconnectTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Private: Message Receiving

    private func startReceiving() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                guard let task = await MainActor.run(body: { self.webSocketTask }) else {
                    break
                }

                do {
                    let wsMessage = try await task.receive()

                    switch wsMessage {
                    case .data(let data):
                        await MainActor.run {
                            self.handleReceivedData(data)
                        }
                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            await MainActor.run {
                                self.handleReceivedData(data)
                            }
                        } else {
                            await MainActor.run {
                                warningLog("WebSocket received non-UTF8 string message", category: .logCategoryNetwork)
                            }
                        }
                    @unknown default:
                        await MainActor.run {
                            warningLog("WebSocket received unknown message type", category: .logCategoryNetwork)
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            errorLog("WebSocket receive error: \(error.localizedDescription)", category: .logCategoryNetwork)
                            self.handleConnectionLost()
                        }
                    }
                    break
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        do {
            let message = try jsonDecoder.decode(WebSocketMessage.self, from: data)
            debugLog("WebSocket received message: type=\(message.type)", category: .logCategoryNetwork)
            messageSubject.send(message)
        } catch {
            // Try to at least extract the type field for debugging
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String {
                warningLog("WebSocket received partially decodable message: type=\(type), error=\(error.localizedDescription)", category: .logCategoryNetwork)
                // Create a minimal message with just the type
                let fallbackMessage = WebSocketMessage(type: type)
                messageSubject.send(fallbackMessage)
            } else {
                let preview = String(data: data.prefix(200), encoding: .utf8) ?? "non-UTF8"
                warningLog("WebSocket failed to decode message: \(error.localizedDescription). Preview: \(preview)", category: .logCategoryNetwork)
            }
        }
    }

    // MARK: - Private: Ping/Pong Keepalive

    private func startPingTimer() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(Constants.pingIntervalSeconds * 1_000_000_000))
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }

                guard let self = self else { break }
                let task = await MainActor.run { self.webSocketTask }

                guard let wsTask = task else { break }

                do {
                    try await wsTask.sendPingAsync()
                    await MainActor.run {
                        debugLog("WebSocket ping sent", category: .logCategoryNetwork)
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            warningLog("WebSocket ping failed: \(error.localizedDescription)", category: .logCategoryNetwork)
                            self.handleConnectionLost()
                        }
                    }
                    break
                }
            }
        }
    }

    // MARK: - Private: Reconnection

    private func handleConnectionLost() {
        guard !intentionalDisconnect else { return }

        state = .disconnected
        webSocketTask = nil
        pingTask?.cancel()
        receiveTask?.cancel()

        warningLog("WebSocket connection lost, scheduling reconnect", category: .logCategoryNetwork)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !intentionalDisconnect else { return }
        guard reconnectAttempt < Constants.maxReconnectAttempts else {
            state = .failed("Max reconnect attempts (\(Constants.maxReconnectAttempts)) exceeded")
            errorLog("WebSocket max reconnect attempts exceeded", category: .logCategoryNetwork)
            return
        }

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self = self else { return }

            let attempt = await MainActor.run { self.reconnectAttempt }
            let delay = min(
                Constants.initialReconnectDelaySeconds * pow(2.0, Double(attempt)),
                Constants.maxReconnectDelaySeconds
            )

            await MainActor.run {
                infoLog("WebSocket reconnecting in \(delay)s (attempt \(attempt + 1)/\(Constants.maxReconnectAttempts))", category: .logCategoryNetwork)
            }

            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return // Cancelled
            }

            guard !Task.isCancelled else { return }

            let scanId = await MainActor.run { () -> String? in
                self.reconnectAttempt += 1
                return self.currentScanId
            }

            guard let scanId = scanId else { return }
            await self.performConnect(scanId: scanId)
        }
    }
}

// MARK: - URLSessionWebSocketTask Async Ping

private extension URLSessionWebSocketTask {
    /// Async wrapper for sendPing with completion handler.
    func sendPingAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sendPing { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
