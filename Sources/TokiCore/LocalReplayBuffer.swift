import Foundation

public struct LocalAudioSegment: Equatable, Sendable {
    public let speakerID: UserID
    public let receivedAt: Date
    public let duration: TimeInterval
    public let encodedAudio: Data

    public init(speakerID: UserID, receivedAt: Date, duration: TimeInterval, encodedAudio: Data) {
        self.speakerID = speakerID
        self.receivedAt = receivedAt
        self.duration = max(0, duration)
        self.encodedAudio = encodedAudio
    }
}

public enum ReplayClearReason: Equatable, Sendable {
    case roomSwitch
    case signOut
    case appTermination
}

public final class LocalReplayBuffer: ObservableObject, @unchecked Sendable {
    @Published public private(set) var segments: [LocalAudioSegment] = []
    @Published public private(set) var lastClearReason: ReplayClearReason?

    public let capacity: TimeInterval
    public let usesDurableStorage = false

    public init(capacity: TimeInterval = 120) {
        self.capacity = capacity
    }

    public var availableDuration: TimeInterval {
        min(capacity, totalDuration)
    }

    public func append(segment: LocalAudioSegment) {
        guard segment.duration > 0 else {
            return
        }

        segments.append(segment)
        trimToCapacity()
    }

    public func clear(reason: ReplayClearReason) {
        segments.removeAll(keepingCapacity: false)
        lastClearReason = reason
    }

    public func recentSegments(duration requestedDuration: TimeInterval) -> [LocalAudioSegment] {
        guard requestedDuration > 0 else {
            return []
        }

        var collected: [LocalAudioSegment] = []
        var total: TimeInterval = 0

        for segment in segments.reversed() {
            collected.append(segment)
            total += segment.duration
            if total >= requestedDuration {
                break
            }
        }

        return collected.reversed()
    }

    private func trimToCapacity() {
        while totalDuration > capacity, segments.count > 1 {
            segments.removeFirst()
        }
    }

    private var totalDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }
}

public final class ReplayPlayer: @unchecked Sendable {
    private let buffer: LocalReplayBuffer

    public private(set) var requestsFloorDuringPlayback = false
    public private(set) var publishesMicrophoneDuringPlayback = false

    public init(buffer: LocalReplayBuffer) {
        self.buffer = buffer
    }

    public func playRecent(duration: TimeInterval) -> [LocalAudioSegment] {
        requestsFloorDuringPlayback = false
        publishesMicrophoneDuringPlayback = false
        return buffer.recentSegments(duration: duration)
    }
}
