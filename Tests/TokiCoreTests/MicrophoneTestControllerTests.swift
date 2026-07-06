import XCTest
@testable import TokiCore

final class MicrophoneTestControllerTests: XCTestCase {
    func testMicTestReportsLevelWithoutPublishingAudio() {
        let controller = MicrophoneTestController()

        controller.start()
        controller.process(inputSamples: [0, 0.25, -0.5, 0.75])

        XCTAssertTrue(controller.isTesting)
        XCTAssertEqual(controller.inputLevel, 0.75, accuracy: 0.001)
        XCTAssertFalse(controller.shouldPublishMicrophone)
    }

    func testSpeakingLevelCanBeUpdatedFromInputSamples() {
        let controller = MicrophoneTestController()

        controller.processSpeakingInput(samples: [0, -0.2, 0.4])

        XCTAssertFalse(controller.isTesting)
        XCTAssertEqual(controller.inputLevel, 0.4, accuracy: 0.001)
        XCTAssertFalse(controller.shouldPublishMicrophone)
    }
}
