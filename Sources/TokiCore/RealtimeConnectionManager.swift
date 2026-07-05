import Foundation

public enum ClientRealtimeState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case listening(conversationID: ConversationID)
    case reconnecting(attempt: Int)
}

public struct RealtimeDelay: Equatable, Sendable {
    public let seconds: Int

    public static func seconds(_ value: Int) -> RealtimeDelay {
        RealtimeDelay(seconds: value)
    }
}

public struct RealtimeBackoff: Equatable, Sendable {
    public let initial: RealtimeDelay
    public let maximum: RealtimeDelay

    public init(initial: RealtimeDelay = .seconds(1), maximum: RealtimeDelay = .seconds(30)) {
        self.initial = initial
        self.maximum = maximum
    }

    public func delay(forAttempt attempt: Int) -> RealtimeDelay {
        guard attempt > 1 else { return initial }
        let exponent = min(attempt - 1, 30)
        let seconds = min(maximum.seconds, initial.seconds * (1 << exponent))
        return .seconds(seconds)
    }
}

public protocol RealtimeTransporting: Sendable {
    func connect(sessionToken: String) async throws
    func send(_ envelope: AnyRealtimeEventEnvelope) async throws
    func close() async
}

public final class URLSessionRealtimeTransport: RealtimeTransporting, @unchecked Sendable {
    private let realtimeURL: URL
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private var task: URLSessionWebSocketTask?

    public init(
        realtimeURL: URL,
        urlSession: URLSession = .shared,
        encoder: JSONEncoder = .tokiRealtime
    ) {
        self.realtimeURL = realtimeURL
        self.urlSession = urlSession
        self.encoder = encoder
    }

    public func connect(sessionToken: String) async throws {
        var request = URLRequest(url: realtimeURL)
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        let task = urlSession.webSocketTask(with: request)
        self.task = task
        task.resume()
    }

    public func send(_ envelope: AnyRealtimeEventEnvelope) async throws {
        let data = try encoder.encode(envelope)
        guard let message = String(data: data, encoding: .utf8), let task else {
            throw TokiAPIError.invalidResponse
        }
        try await task.send(.string(message))
    }

    public func close() async {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
}

public protocol RealtimeEventIDGenerating: Sendable {
    mutating func nextEventID() -> String
}

public struct IncrementingRealtimeEventID: RealtimeEventIDGenerating {
    private let prefix: String
    private var value = 0

    public init(prefix: String = "client") {
        self.prefix = prefix
    }

    public mutating func nextEventID() -> String {
        value += 1
        return "\(prefix)-\(value)"
    }
}

public protocol RealtimeClock: Sendable {
    func now() -> Date
}

public struct SystemRealtimeClock: RealtimeClock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

public struct FixedRealtimeClock: RealtimeClock {
    private let fixedNow: Date

    public init(now: Date) {
        self.fixedNow = now
    }

    public func now() -> Date {
        fixedNow
    }
}

public final class RealtimeConnectionManager<EventID: RealtimeEventIDGenerating>: @unchecked Sendable {
    public private(set) var state: ClientRealtimeState = .disconnected
    public private(set) var needsPeerRenegotiation = false

    private let sessionToken: String
    private let transport: RealtimeTransporting
    private let backoff: RealtimeBackoff
    private let clock: RealtimeClock
    private var eventID: EventID
    private var activeConversationID: ConversationID?
    private var reconnectAttempt = 0

    public init(
        sessionToken: String,
        transport: RealtimeTransporting,
        backoff: RealtimeBackoff = RealtimeBackoff(),
        eventID: EventID = IncrementingRealtimeEventID(),
        clock: RealtimeClock = SystemRealtimeClock()
    ) where EventID == IncrementingRealtimeEventID {
        self.sessionToken = sessionToken
        self.transport = transport
        self.backoff = backoff
        self.eventID = eventID
        self.clock = clock
    }

    public init(
        sessionToken: String,
        transport: RealtimeTransporting,
        backoff: RealtimeBackoff = RealtimeBackoff(),
        eventID: EventID,
        clock: RealtimeClock = SystemRealtimeClock()
    ) {
        self.sessionToken = sessionToken
        self.transport = transport
        self.backoff = backoff
        self.eventID = eventID
        self.clock = clock
    }

    public func connect() async throws {
        state = .connecting
        try await transport.connect(sessionToken: sessionToken)
        state = .connected
        reconnectAttempt = 0
    }

    public func joinActiveRoom(_ conversationID: ConversationID) async throws {
        activeConversationID = conversationID
        try await sendJoin(conversationID: conversationID)
        state = .listening(conversationID: conversationID)
    }

    public func handleConnectionDropped() async {
        reconnectAttempt += 1
        state = .reconnecting(attempt: reconnectAttempt)
        await transport.close()
    }

    public func nextReconnectDelay() -> RealtimeDelay {
        backoff.delay(forAttempt: reconnectAttempt)
    }

    public func reconnectNow() async throws {
        state = .reconnecting(attempt: max(reconnectAttempt, 1))
        try await transport.connect(sessionToken: sessionToken)
        if let activeConversationID {
            try await sendJoin(conversationID: activeConversationID)
            needsPeerRenegotiation = true
            state = .listening(conversationID: activeConversationID)
        } else {
            state = .connected
        }
        reconnectAttempt = 0
    }

    private func sendJoin(conversationID: ConversationID) async throws {
        let envelope = RealtimeEventEnvelope(
            type: .roomJoin,
            id: eventID.nextEventID(),
            conversationID: conversationID,
            sentAt: clock.now(),
            payload: RoomJoinPayload(active: true)
        )
        try await transport.send(AnyRealtimeEventEnvelope(envelope))
    }
}
