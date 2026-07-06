import Foundation

public struct RoomPeer: Codable, Equatable, Sendable {
    public let connectionID: String
    public let userID: UserID
    public let deviceID: DeviceID
    public let active: Bool

    public init(connectionID: String, userID: UserID, deviceID: DeviceID, active: Bool) {
        self.connectionID = connectionID
        self.userID = userID
        self.deviceID = deviceID
        self.active = active
    }

    private enum CodingKeys: String, CodingKey {
        case connectionID = "connectionId"
        case userID = "userId"
        case deviceID = "deviceId"
        case active
    }
}

public struct RoomSnapshot: Codable, Equatable, Sendable {
    public let conversationID: ConversationID
    public let peers: [RoomPeer]

    public init(conversationID: ConversationID, peers: [RoomPeer]) {
        self.conversationID = conversationID
        self.peers = peers
    }

    private enum CodingKeys: String, CodingKey {
        case conversationID = "conversationId"
        case peers
    }
}

public enum PeerConnectionState: Equatable, Sendable {
    case connecting
    case connected
    case disconnected
    case failed
    case closed
}

public protocol PeerConnectionControlling: Sendable {
    func makeOffer() async throws -> String
    func setPublishingEnabled(_ enabled: Bool) async throws
    func close() async
}

public protocol PeerConnectionCreating: Sendable {
    func makePeerConnection(peer: RoomPeer, iceConfig: ICEConfigResponse) throws -> PeerConnectionControlling
}

public final class PeerConnectionManager<EventID: RealtimeEventIDGenerating>: @unchecked Sendable {
    public private(set) var peerStates: [DeviceID: PeerConnectionState] = [:]
    public private(set) var isPublishing = false

    private let localDeviceID: DeviceID
    private let iceConfig: ICEConfigResponse
    private let transport: RealtimeTransporting
    private let peerConnectionFactory: PeerConnectionCreating
    private let clock: RealtimeClock
    private var eventID: EventID
    private var activeConversationID: ConversationID?
    private var connections: [DeviceID: PeerConnectionControlling] = [:]

    public init(
        localDeviceID: DeviceID,
        iceConfig: ICEConfigResponse,
        transport: RealtimeTransporting,
        peerConnectionFactory: PeerConnectionCreating,
        eventID: EventID,
        clock: RealtimeClock = SystemRealtimeClock()
    ) {
        self.localDeviceID = localDeviceID
        self.iceConfig = iceConfig
        self.transport = transport
        self.peerConnectionFactory = peerConnectionFactory
        self.eventID = eventID
        self.clock = clock
    }

    public func joinRoom(_ snapshot: RoomSnapshot) async throws {
        try StrictP2PICEPolicy.validate(iceConfig)
        if activeConversationID != nil && activeConversationID != snapshot.conversationID {
            await closeConnections()
        }

        activeConversationID = snapshot.conversationID
        for peer in snapshot.peers where peer.deviceID != localDeviceID && connections[peer.deviceID] == nil {
            let connection = try peerConnectionFactory.makePeerConnection(peer: peer, iceConfig: iceConfig)
            connections[peer.deviceID] = connection
            peerStates[peer.deviceID] = .connecting
            if shouldCreateInitialOffer(to: peer.deviceID) {
                let offer = try await connection.makeOffer()
                try await sendSignal(.signalOffer, targetDeviceID: peer.deviceID, body: ["sdp": .string(offer)])
            }
        }
    }

    public func sendAnswer(_ sdp: String, to targetDeviceID: DeviceID) async throws {
        try await sendSignal(.signalAnswer, targetDeviceID: targetDeviceID, body: ["sdp": .string(sdp)])
    }

    public func sendICECandidate(_ candidate: String, to targetDeviceID: DeviceID) async throws {
        try StrictP2PICEPolicy.validateCandidate(candidate)
        try await sendSignal(.signalIceCandidate, targetDeviceID: targetDeviceID, body: ["candidate": .string(candidate)])
    }

    public func setPublishingEnabled(_ enabled: Bool) async throws {
        for connection in connections.values {
            try await connection.setPublishingEnabled(enabled)
        }
        isPublishing = enabled
    }

    public func leaveRoom() async {
        await closeConnections()
        activeConversationID = nil
    }

    private func shouldCreateInitialOffer(to peerDeviceID: DeviceID) -> Bool {
        localDeviceID.rawValue < peerDeviceID.rawValue
    }

    private func sendSignal(
        _ type: RealtimeEventType,
        targetDeviceID: DeviceID,
        body: [String: JSONValue]
    ) async throws {
        guard let activeConversationID else {
            throw TokiAPIError.invalidResponse
        }

        var payload = body
        payload["targetDeviceId"] = .string(targetDeviceID.rawValue)
        let envelope = AnyRealtimeEventEnvelope(
            type: type,
            id: eventID.nextEventID(),
            conversationID: activeConversationID,
            sentAt: clock.now(),
            payload: .object(payload)
        )
        try await transport.send(envelope)
    }

    private func closeConnections() async {
        if isPublishing {
            for connection in connections.values {
                try? await connection.setPublishingEnabled(false)
            }
        }
        for (deviceID, connection) in connections {
            await connection.close()
            peerStates[deviceID] = .closed
        }
        connections.removeAll()
        peerStates.removeAll()
        isPublishing = false
    }
}
