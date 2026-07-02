import Foundation

public struct TokiUserSummary: Codable, Equatable, Sendable {
    public let id: UserID
    public let email: String
    public let displayName: String

    public init(id: UserID, email: String, displayName: String) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }
}

public struct TokiTeamSummary: Codable, Equatable, Sendable {
    public let id: TeamID
    public let displayName: String

    public init(id: TeamID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct TokiTeamMembershipSummary: Codable, Equatable, Sendable {
    public let id: MembershipID
    public let team: TokiTeamSummary
    public let role: String

    public init(id: MembershipID, team: TokiTeamSummary, role: String) {
        self.id = id
        self.team = team
        self.role = role
    }
}

public struct TokiDeviceSummary: Codable, Equatable, Sendable {
    public let id: DeviceID
    public let name: String

    public init(id: DeviceID, name: String) {
        self.id = id
        self.name = name
    }
}

public enum ConversationKind: String, Codable, Equatable, Sendable {
    case direct
    case group
}

public struct ConversationMemberSummary: Codable, Equatable, Sendable {
    public let user: TokiUserSummary
    public let role: String

    public init(user: TokiUserSummary, role: String) {
        self.user = user
        self.role = role
    }
}

public struct ConversationPresenceSummary: Codable, Equatable, Sendable {
    public let onlineUserIDs: [UserID]
    public let activeSpeakerID: UserID?

    public init(onlineUserIDs: [UserID], activeSpeakerID: UserID?) {
        self.onlineUserIDs = onlineUserIDs
        self.activeSpeakerID = activeSpeakerID
    }

    private enum CodingKeys: String, CodingKey {
        case onlineUserIDs = "onlineUserIds"
        case activeSpeakerID = "activeSpeakerId"
    }
}

public struct ConversationSummary: Codable, Equatable, Sendable {
    public let id: ConversationID
    public let type: ConversationKind
    public let displayName: String?
    public let members: [ConversationMemberSummary]
    public let lastPresence: ConversationPresenceSummary

    public init(
        id: ConversationID,
        type: ConversationKind,
        displayName: String?,
        members: [ConversationMemberSummary],
        lastPresence: ConversationPresenceSummary
    ) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.members = members
        self.lastPresence = lastPresence
    }
}

