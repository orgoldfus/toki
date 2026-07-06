import Foundation

public enum ICERelayPolicy: String, Codable, Equatable, Sendable {
    case disabled
    case enabled
}

public struct ICEConfigServer: Codable, Equatable, Sendable {
    public let urls: [String]

    public init(urls: [String]) {
        self.urls = urls
    }
}

public struct ICEConfigResponse: Codable, Equatable, Sendable {
    public let iceServers: [ICEConfigServer]
    public let relayPolicy: ICERelayPolicy

    public init(iceServers: [ICEConfigServer], relayPolicy: ICERelayPolicy) {
        self.iceServers = iceServers
        self.relayPolicy = relayPolicy
    }

    public static func stunOnly(urls: [String]) -> ICEConfigResponse {
        ICEConfigResponse(iceServers: [ICEConfigServer(urls: urls)], relayPolicy: .disabled)
    }
}

public enum StrictP2PICEPolicyError: Error, Equatable, Sendable {
    case relayPolicyEnabled
    case missingStunServer
    case forbiddenRelayURL(String)
    case forbiddenRelayCandidate
}

public enum StrictP2PICEPolicy {
    public static func validate(_ config: ICEConfigResponse) throws {
        guard config.relayPolicy == .disabled else {
            throw StrictP2PICEPolicyError.relayPolicyEnabled
        }

        var hasStunServer = false
        for url in config.iceServers.flatMap(\.urls) {
            let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.hasPrefix("turn:") || normalized.hasPrefix("turns:") {
                throw StrictP2PICEPolicyError.forbiddenRelayURL(url)
            }
            if normalized.hasPrefix("stun:") || normalized.hasPrefix("stuns:") {
                hasStunServer = true
            }
        }

        guard hasStunServer else {
            throw StrictP2PICEPolicyError.missingStunServer
        }
    }

    public static func validateCandidate(_ candidate: String) throws {
        let fields = candidate.lowercased().split(whereSeparator: \.isWhitespace)
        let hasRelayType = fields.indices.contains { index in
            let nextIndex = fields.index(after: index)
            return fields[index] == "typ" && nextIndex < fields.endIndex && fields[nextIndex] == "relay"
        }
        if hasRelayType {
            throw StrictP2PICEPolicyError.forbiddenRelayCandidate
        }
    }
}
