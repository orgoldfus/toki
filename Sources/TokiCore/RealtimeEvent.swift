import Foundation

public enum RealtimeEventType: String, Codable, Equatable, Sendable {
    case roomJoin = "room.join"
    case roomLeave = "room.leave"
    case presenceSet = "presence.set"
    case roomSnapshot = "room.snapshot"
    case presenceUpdated = "presence.updated"
    case signalOffer = "signal.offer"
    case signalAnswer = "signal.answer"
    case signalIceCandidate = "signal.iceCandidate"
    case signalForwarded = "signal.forwarded"
    case error
    case reconnectRequired = "reconnect.required"
}

public struct RealtimeEventEnvelope<Payload: Codable & Sendable>: Codable, Equatable, Sendable where Payload: Equatable {
    public let type: RealtimeEventType
    public let id: String
    public let conversationID: ConversationID?
    public let sentAt: Date
    public let payload: Payload

    public init(
        type: RealtimeEventType,
        id: String,
        conversationID: ConversationID?,
        sentAt: Date,
        payload: Payload
    ) {
        self.type = type
        self.id = id
        self.conversationID = conversationID
        self.sentAt = sentAt
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case conversationID = "conversationId"
        case sentAt
        case payload
    }
}

public struct RoomJoinPayload: Codable, Equatable, Sendable {
    public let active: Bool

    public init(active: Bool) {
        self.active = active
    }
}

public struct AnyRealtimeEventEnvelope: Codable, Equatable, Sendable {
    public let type: RealtimeEventType
    public let id: String
    public let conversationID: ConversationID?
    public let sentAt: Date
    public let payload: JSONValue

    public init(
        type: RealtimeEventType,
        id: String,
        conversationID: ConversationID?,
        sentAt: Date,
        payload: JSONValue
    ) {
        self.type = type
        self.id = id
        self.conversationID = conversationID
        self.sentAt = sentAt
        self.payload = payload
    }

    public init(_ envelope: RealtimeEventEnvelope<RoomJoinPayload>) {
        self.init(
            type: envelope.type,
            id: envelope.id,
            conversationID: envelope.conversationID,
            sentAt: envelope.sentAt,
            payload: .object(["active": .bool(envelope.payload.active)])
        )
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case conversationID = "conversationId"
        case sentAt
        case payload
    }
}

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public extension JSONEncoder {
    static var tokiRealtime: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public extension JSONDecoder {
    static var tokiRealtime: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
