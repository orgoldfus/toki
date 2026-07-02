import XCTest
@testable import TokiCore

final class LocalSettingsStoreTests: XCTestCase {
    func testDeviceAndShortcutPreferencesRoundTripThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: "TokiCoreTests.\(UUID().uuidString)")!
        let store = LocalSettingsStore(defaults: defaults)
        let preferences = DevicePreferences(
            selectedInputDeviceID: "input-built-in",
            selectedOutputDeviceID: "output-airpods",
            pushToTalkShortcut: PushToTalkShortcut(keyCode: 49, modifiers: [.command, .shift]),
            launchAtLogin: true,
            diagnosticsOptIn: true
        )

        store.save(preferences)

        XCTAssertEqual(store.load(), preferences)
    }
}
