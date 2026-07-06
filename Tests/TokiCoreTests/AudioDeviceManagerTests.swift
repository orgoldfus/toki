import XCTest
@testable import TokiCore

final class AudioDeviceManagerTests: XCTestCase {
    func testEnumeratesInputAndOutputDevicesAndPersistsSelections() {
        let store = InMemorySettingsStore()
        let provider = FixedAudioDeviceProvider(
            inputDevices: [
                AudioDevice(id: "input-built-in", name: "Built-in Microphone", isSystemDefault: true),
                AudioDevice(id: "input-usb", name: "USB Microphone", isSystemDefault: false)
            ],
            outputDevices: [
                AudioDevice(id: "output-system", name: "System Output", isSystemDefault: true),
                AudioDevice(id: "output-headphones", name: "Headphones", isSystemDefault: false)
            ]
        )
        let manager = AudioDeviceManager(provider: provider, settingsStore: store)

        XCTAssertEqual(manager.availableInputDevices.map(\.id), ["input-built-in", "input-usb"])
        XCTAssertEqual(manager.availableOutputDevices.map(\.id), ["output-system", "output-headphones"])

        manager.selectInputDevice(id: "input-usb")
        manager.selectOutputDevice(id: "output-headphones")

        XCTAssertEqual(manager.selectedInputDeviceID, "input-usb")
        XCTAssertEqual(manager.selectedOutputDeviceID, "output-headphones")
        XCTAssertEqual(store.savedPreferences?.selectedInputDeviceID, "input-usb")
        XCTAssertEqual(store.savedPreferences?.selectedOutputDeviceID, "output-headphones")
    }

    func testMissingSelectedDeviceFallsBackToSystemDefaultWithWarning() {
        let store = InMemorySettingsStore(
            preferences: DevicePreferences(
                selectedInputDeviceID: "input-missing",
                selectedOutputDeviceID: "output-missing",
                pushToTalkShortcut: nil,
                launchAtLogin: false,
                diagnosticsOptIn: false
            )
        )
        let provider = FixedAudioDeviceProvider(
            inputDevices: [AudioDevice(id: "input-built-in", name: "Built-in Microphone", isSystemDefault: true)],
            outputDevices: [AudioDevice(id: "output-system", name: "System Output", isSystemDefault: true)]
        )

        let manager = AudioDeviceManager(provider: provider, settingsStore: store)

        XCTAssertEqual(manager.selectedInputDeviceID, "input-built-in")
        XCTAssertEqual(manager.selectedOutputDeviceID, "output-system")
        XCTAssertEqual(manager.warning, .selectedDevicesUnavailable(inputDeviceID: "input-missing", outputDeviceID: "output-missing"))
    }
}

private struct FixedAudioDeviceProvider: AudioDeviceProviding {
    let inputDevices: [AudioDevice]
    let outputDevices: [AudioDevice]

    func availableInputDevices() -> [AudioDevice] {
        inputDevices
    }

    func availableOutputDevices() -> [AudioDevice] {
        outputDevices
    }
}

private final class InMemorySettingsStore: SettingsStoring, @unchecked Sendable {
    private let preferences: DevicePreferences?
    private(set) var savedPreferences: DevicePreferences?

    init(preferences: DevicePreferences? = nil) {
        self.preferences = preferences
    }

    func load() -> DevicePreferences? {
        savedPreferences ?? preferences
    }

    func save(_ preferences: DevicePreferences) {
        savedPreferences = preferences
    }
}
