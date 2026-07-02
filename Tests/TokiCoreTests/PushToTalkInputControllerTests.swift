import Foundation
import XCTest
@testable import TokiCore

final class PushToTalkInputControllerTests: XCTestCase {
    func testControllerEmitsPressedAndReleasedEvents() {
        let controller = PushToTalkInputController()
        let recorder = EventRecorder()
        controller.onEvent = { recorder.record($0) }

        controller.press(source: .keyboard)
        controller.release()

        XCTAssertEqual(recorder.events, [.pressed(.keyboard), .released])
    }
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [PushToTalkInputEvent] = []

    var events: [PushToTalkInputEvent] {
        lock.withLock { recordedEvents }
    }

    func record(_ event: PushToTalkInputEvent) {
        lock.withLock {
            recordedEvents.append(event)
        }
    }
}
