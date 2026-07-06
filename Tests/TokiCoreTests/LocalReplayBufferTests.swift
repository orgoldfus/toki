import XCTest
@testable import TokiCore

final class LocalReplayBufferTests: XCTestCase {
    func testKeepsOnlyMostRecentTwoMinutesOfReceivedAudio() {
        let buffer = LocalReplayBuffer(capacity: 120)

        buffer.append(segment: audioSegment(seconds: 80, speakerID: "alice", receivedAt: Date(timeIntervalSince1970: 0)))
        buffer.append(segment: audioSegment(seconds: 60, speakerID: "bob", receivedAt: Date(timeIntervalSince1970: 80)))
        buffer.append(segment: audioSegment(seconds: 60, speakerID: "carol", receivedAt: Date(timeIntervalSince1970: 140)))

        XCTAssertEqual(buffer.availableDuration, 120, accuracy: 0.001)
        XCTAssertEqual(buffer.segments.map(\.speakerID), [UserID("bob"), UserID("carol")])
    }

    func testClearRemovesBufferedAudioAndRecordsReason() {
        let buffer = LocalReplayBuffer(capacity: 120)
        buffer.append(segment: audioSegment(seconds: 20, speakerID: "alice", receivedAt: Date()))

        buffer.clear(reason: .roomSwitch)

        XCTAssertEqual(buffer.availableDuration, 0, accuracy: 0.001)
        XCTAssertTrue(buffer.segments.isEmpty)
        XCTAssertEqual(buffer.lastClearReason, .roomSwitch)
    }

    func testReplayRecentReturnsOnlyRequestedTailWithoutDiskPersistence() {
        let buffer = LocalReplayBuffer(capacity: 120)
        buffer.append(segment: audioSegment(seconds: 10, speakerID: "alice", receivedAt: Date(timeIntervalSince1970: 0)))
        buffer.append(segment: audioSegment(seconds: 15, speakerID: "bob", receivedAt: Date(timeIntervalSince1970: 10)))

        let player = ReplayPlayer(buffer: buffer)

        XCTAssertFalse(buffer.usesDurableStorage)
        XCTAssertEqual(player.playRecent(duration: 12).map(\.speakerID), [UserID("bob")])
        XCTAssertFalse(player.requestsFloorDuringPlayback)
        XCTAssertFalse(player.publishesMicrophoneDuringPlayback)
    }

    private func audioSegment(seconds: TimeInterval, speakerID: String, receivedAt: Date) -> LocalAudioSegment {
        LocalAudioSegment(
            speakerID: UserID(speakerID),
            receivedAt: receivedAt,
            duration: seconds,
            encodedAudio: Data(repeating: UInt8(seconds), count: Int(seconds))
        )
    }
}
