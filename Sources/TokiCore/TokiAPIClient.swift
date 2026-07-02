import Foundation

public struct MagicLinkRequest: Codable, Equatable, Sendable {
    public let email: String

    public init(email: String) {
        self.email = email
    }
}

public struct MagicLinkResponse: Codable, Equatable, Sendable {
    public let token: String

    public init(token: String) {
        self.token = token
    }
}

public struct SessionRequest: Codable, Equatable, Sendable {
    public let token: String
    public let deviceName: String

    public init(token: String, deviceName: String) {
        self.token = token
        self.deviceName = deviceName
    }
}

public struct SessionResponse: Codable, Equatable, Sendable {
    public let sessionToken: String
    public let user: TokiUserSummary
    public let teamMemberships: [TokiTeamMembershipSummary]
    public let device: TokiDeviceSummary

    public init(
        sessionToken: String,
        user: TokiUserSummary,
        teamMemberships: [TokiTeamMembershipSummary],
        device: TokiDeviceSummary
    ) {
        self.sessionToken = sessionToken
        self.user = user
        self.teamMemberships = teamMemberships
        self.device = device
    }
}

public struct CurrentUserResponse: Codable, Equatable, Sendable {
    public let user: TokiUserSummary
    public let teamMemberships: [TokiTeamMembershipSummary]
    public let devices: [TokiDeviceSummary]

    public init(user: TokiUserSummary, teamMemberships: [TokiTeamMembershipSummary], devices: [TokiDeviceSummary]) {
        self.user = user
        self.teamMemberships = teamMemberships
        self.devices = devices
    }
}

public struct ConversationsResponse: Codable, Equatable, Sendable {
    public let conversations: [ConversationSummary]

    public init(conversations: [ConversationSummary]) {
        self.conversations = conversations
    }
}

public struct CreateConversationRequest: Codable, Equatable, Sendable {
    public let type: ConversationKind
    public let memberIDs: [UserID]
    public let displayName: String?

    public init(type: ConversationKind, memberIDs: [UserID], displayName: String?) {
        self.type = type
        self.memberIDs = memberIDs
        self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case memberIDs = "memberIds"
        case displayName
    }
}

public struct CreateConversationResponse: Codable, Equatable, Sendable {
    public let conversation: ConversationSummary

    public init(conversation: ConversationSummary) {
        self.conversation = conversation
    }
}

public struct AddConversationMembersRequest: Codable, Equatable, Sendable {
    public let memberIDs: [UserID]

    public init(memberIDs: [UserID]) {
        self.memberIDs = memberIDs
    }

    private enum CodingKeys: String, CodingKey {
        case memberIDs = "memberIds"
    }
}

public struct AddConversationMembersResponse: Codable, Equatable, Sendable {
    public let conversation: ConversationSummary

    public init(conversation: ConversationSummary) {
        self.conversation = conversation
    }
}

public enum TokiAPIError: Error, Equatable, Sendable {
    case invalidResponse
    case requestFailed(statusCode: Int)
}

public final class TokiAPIClient: @unchecked Sendable {
    private let baseURL: URL
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        urlSession: URLSession = .shared,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.encoder = encoder
        self.decoder = decoder
    }

    public func requestMagicLink(email: String) async throws -> MagicLinkResponse {
        try await send(
            path: "/v1/auth/magic-link",
            method: "POST",
            body: MagicLinkRequest(email: email),
            sessionToken: nil
        )
    }

    public func createSession(token: String, deviceName: String) async throws -> SessionResponse {
        try await send(
            path: "/v1/auth/session",
            method: "POST",
            body: SessionRequest(token: token, deviceName: deviceName),
            sessionToken: nil
        )
    }

    public func currentUser(sessionToken: String) async throws -> CurrentUserResponse {
        try await send(path: "/v1/me", method: "GET", body: EmptyRequest?.none, sessionToken: sessionToken)
    }

    public func conversations(sessionToken: String) async throws -> ConversationsResponse {
        try await send(path: "/v1/conversations", method: "GET", body: EmptyRequest?.none, sessionToken: sessionToken)
    }

    public func createConversation(
        type: ConversationKind,
        memberIDs: [UserID],
        displayName: String?,
        sessionToken: String
    ) async throws -> CreateConversationResponse {
        try await send(
            path: "/v1/conversations",
            method: "POST",
            body: CreateConversationRequest(type: type, memberIDs: memberIDs, displayName: displayName),
            sessionToken: sessionToken
        )
    }

    public func addConversationMembers(
        conversationID: ConversationID,
        memberIDs: [UserID],
        sessionToken: String
    ) async throws -> AddConversationMembersResponse {
        try await send(
            path: "/v1/conversations/\(conversationID.rawValue)/members",
            method: "POST",
            body: AddConversationMembersRequest(memberIDs: memberIDs),
            sessionToken: sessionToken
        )
    }

    private func send<Request: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Request?,
        sessionToken: String?
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if let sessionToken {
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokiAPIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw TokiAPIError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return try decoder.decode(Response.self, from: data)
    }
}

private struct EmptyRequest: Encodable {}
