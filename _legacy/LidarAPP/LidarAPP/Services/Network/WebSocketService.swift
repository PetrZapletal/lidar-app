import Foundation
import Combine

/// WebSocket service for real-time processing status updates
@MainActor
@Observable
final class WebSocketService: NSObject {

    // MARK: - Connection State

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case failed(error: String)
    }

    // MARK: - Message Types

    enum ServerMessage {
        case processingUpdate(ProcessingUpdate)
        case error(ErrorMessage)
        case ping
        case unknown(String)
    }

    struct ProcessingUpdate: Decodable {
        let scanId: String
        let status: ProcessingStatus
        let progress: Float
        let stage: String?
        let message: String?
        let estimatedTimeRemaining: TimeInterval?
        let resultURLs: [String: String]?

        enum ProcessingStatus: String, Decodable {
            case queued
            case processing
            case completed
            case failed
        }
    }

    struct ErrorMessage: Decodable {
        let code: String
        let message: String
        let scanId: String?
    }

    // MARK: - Configuration

    struct Configuration {
        var baseURL: URL
        var pingInterval: TimeInterval = 30
        var reconnectDelay: TimeInterval = 2
        var maxReconnectAttempts: Int = 5
        var reconnectBackoffMultiplier: Double = 1.5
    }

    // MARK: - Properties

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var lastMessage: ServerMessage?

    private let configuration: Configuration
    nonisolated(unsafe) private var webSocketTask: URLSessionWebSocketTask?
    nonisolated(unsafe) private var session: URLSession!
    private var authToken: String?

    nonisolated(unsafe) private var pingTask: Task<Void, Never>?
    nonisolated(unsafe) private var receiveTask: Task<Void, Never>?
    private var reconnectAttempt: Int = 0

    // Callbacks
    var onProcessingUpdate: ((ProcessingUpdate) -> Void)?
    var onError: ((ErrorMessage) -> Void)?
    var onConnectionStateChanged: ((ConnectionState) -> Void)?

    // Active subscriptions
    private var subscribedScanIds: Set<String> = []

    // MARK: - Initialization

    init(configuration: Configuration) {
        self.configuration = configuration
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    convenience init(baseURL: URL) {
        self.init(configuration: Configuration(baseURL: baseURL))
    }

    static func withDefaultURL() -> WebSocketService {
        #if DEBUG
        // Use Tailscale IP for device testing (Docker maps 8444 -> 8443)
        let defaultURL = URL(string: "wss://100.96.188.18:8444/ws")!
        #else
        let defaultURL = URL(string: "wss://api.lidarapp.com/ws")!
        #endif
        return WebSocketService(configuration: Configuration(baseURL: defaultURL))
    }

    deinit {
        // Clean up directly without calling MainActor-isolated method
        pingTask?.cancel()
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    // MARK: - Authentication

    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    // MARK: - Connection Management

    func connect() {
        guard connectionState == .disconnected || connectionState == .failed(error: "") else {
            return
        }

        connectionState = .connecting
        onConnectionStateChanged?(.connecting)

        var request = URLRequest(url: configuration.baseURL)

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        startReceiving()
        startPinging()
    }

    func disconnect() {
        pingTask?.cancel()
        receiveTask?.cancel()

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        connectionState = .disconnected
        onConnectionStateChanged?(.disconnected)
        subscribedScanIds.removeAll()
    }

    // MARK: - Subscription Management

    func subscribeTo(scanId: String) async throws {
        guard connectionState == .connected else {
            throw WebSocketError.notConnected
        }

        let message = ClientMessage.subscribe(scanId: scanId)
        try await send(message)

        subscribedScanIds.insert(scanId)
    }

    func unsubscribeFrom(scanId: String) async throws {
        guard connectionState == .connected else {
            throw WebSocketError.notConnected
        }

        let message = ClientMessage.unsubscribe(scanId: scanId)
        try await send(message)

        subscribedScanIds.remove(scanId)
    }

    // MARK: - Sending Messages

    private func send(_ message: ClientMessage) async throws {
        guard let task = webSocketTask else {
            throw WebSocketError.notConnected
        }

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let string = String(data: data, encoding: .utf8)!

        try await task.send(.string(string))
    }

    // MARK: - Receiving Messages

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self,
                      let task = self.webSocketTask else {
                    break
                }

                do {
                    let message = try await task.receive()
                    await self.handleMessage(message)
                } catch {
                    await self.handleReceiveError(error)
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            parseMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseMessage(text)
            }
        @unknown default:
            break
        }
    }

    private func parseMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Try to decode as processing update
        if let update = try? decoder.decode(ProcessingUpdateWrapper.self, from: data),
           update.type == "processing_update" {
            let processingUpdate = update.data
            lastMessage = .processingUpdate(processingUpdate)
            onProcessingUpdate?(processingUpdate)
            return
        }

        // Try to decode as error
        if let errorWrapper = try? decoder.decode(ErrorWrapper.self, from: data),
           errorWrapper.type == "error" {
            let error = errorWrapper.data
            lastMessage = .error(error)
            onError?(error)
            return
        }

        // Try ping/pong
        if text == "ping" || text == "{\"type\":\"ping\"}" {
            lastMessage = .ping
            Task {
                try? await send(.pong)
            }
            return
        }

        lastMessage = .unknown(text)
    }

    private func handleReceiveError(_ error: Error) async {
        if (error as NSError).code == 57 {  // Socket closed
            await attemptReconnect()
        } else {
            connectionState = .failed(error: error.localizedDescription)
            onConnectionStateChanged?(connectionState)
        }
    }

    // MARK: - Ping/Pong

    private func startPinging() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self?.configuration.pingInterval ?? 30) * 1_000_000_000)

                guard !Task.isCancelled,
                      let self = self,
                      self.connectionState == .connected else {
                    break
                }

                self.webSocketTask?.sendPing { error in
                    if let error = error {
                        Task { @MainActor in
                            self.connectionState = .failed(error: error.localizedDescription)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reconnection

    private func attemptReconnect() async {
        guard reconnectAttempt < configuration.maxReconnectAttempts else {
            connectionState = .failed(error: "Max reconnection attempts reached")
            onConnectionStateChanged?(connectionState)
            return
        }

        reconnectAttempt += 1
        connectionState = .reconnecting(attempt: reconnectAttempt)
        onConnectionStateChanged?(connectionState)

        let delay = configuration.reconnectDelay * pow(configuration.reconnectBackoffMultiplier, Double(reconnectAttempt - 1))

        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        guard !Task.isCancelled else { return }

        // Reconnect
        webSocketTask?.cancel()

        var request = URLRequest(url: configuration.baseURL)
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        startReceiving()

        // Resubscribe to previous scan IDs
        for scanId in subscribedScanIds {
            try? await subscribeTo(scanId: scanId)
        }
    }

    // MARK: - State

    var isConnected: Bool {
        connectionState == .connected
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketService: URLSessionWebSocketDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            self.connectionState = .connected
            self.reconnectAttempt = 0
            self.onConnectionStateChanged?(.connected)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            if closeCode != .normalClosure {
                await self.attemptReconnect()
            } else {
                self.connectionState = .disconnected
                self.onConnectionStateChanged?(.disconnected)
            }
        }
    }
}

// MARK: - Client Messages

private enum ClientMessage: Encodable {
    case subscribe(scanId: String)
    case unsubscribe(scanId: String)
    case pong

    private enum CodingKeys: String, CodingKey {
        case type
        case scanId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .subscribe(let scanId):
            try container.encode("subscribe", forKey: .type)
            try container.encode(scanId, forKey: .scanId)
        case .unsubscribe(let scanId):
            try container.encode("unsubscribe", forKey: .type)
            try container.encode(scanId, forKey: .scanId)
        case .pong:
            try container.encode("pong", forKey: .type)
        }
    }
}

// MARK: - Message Wrappers

private struct ProcessingUpdateWrapper: Decodable {
    let type: String
    let data: WebSocketService.ProcessingUpdate
}

private struct ErrorWrapper: Decodable {
    let type: String
    let data: WebSocketService.ErrorMessage
}

// MARK: - Errors

enum WebSocketError: LocalizedError {
    case notConnected
    case sendFailed
    case invalidMessage

    var errorDescription: String? {
        switch self {
        case .notConnected: return "WebSocket not connected"
        case .sendFailed: return "Failed to send message"
        case .invalidMessage: return "Invalid message format"
        }
    }
}

// MARK: - URLSessionTaskDelegate (Certificate Handling)

extension WebSocketService: URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Accept self-signed certificates for debug server
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
