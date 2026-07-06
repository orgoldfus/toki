import AVFoundation
import CoreAudio
import Foundation

public struct AudioDevice: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isSystemDefault: Bool

    public init(id: String, name: String, isSystemDefault: Bool) {
        self.id = id
        self.name = name
        self.isSystemDefault = isSystemDefault
    }
}

public enum AudioDeviceWarning: Equatable, Sendable {
    case selectedDevicesUnavailable(inputDeviceID: String?, outputDeviceID: String?)
}

public protocol AudioDeviceProviding: Sendable {
    func availableInputDevices() -> [AudioDevice]
    func availableOutputDevices() -> [AudioDevice]
}

public struct SystemAudioDeviceProvider: AudioDeviceProviding {
    public init() {}

    public func availableInputDevices() -> [AudioDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
        let devices = discovery.devices.map { device in
            AudioDevice(id: device.uniqueID, name: device.localizedName, isSystemDefault: device.uniqueID == defaultID)
        }

        if devices.isEmpty {
            return [AudioDevice(id: "system-input", name: "System Default Microphone", isSystemDefault: true)]
        }

        return devices
    }

    public func availableOutputDevices() -> [AudioDevice] {
        let defaultOutputID = defaultAudioObjectID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let devices = audioDeviceObjectIDs().compactMap { objectID -> AudioDevice? in
            guard hasOutputStreams(objectID), let name = audioDeviceName(objectID) else {
                return nil
            }

            return AudioDevice(
                id: String(objectID),
                name: name,
                isSystemDefault: objectID == defaultOutputID
            )
        }

        if devices.isEmpty {
            return [AudioDevice(id: "system-output", name: "System Default Output", isSystemDefault: true)]
        }

        return devices
    }

    private func defaultAudioObjectID(selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var objectID = AudioObjectID()
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &objectID
        ) == noErr else {
            return nil
        }

        return objectID
    }

    private func audioDeviceObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objectIDs = Array(repeating: AudioObjectID(), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &objectIDs
        ) == noErr else {
            return []
        }

        return objectIDs
    }

    private func hasOutputStreams(_ objectID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr else {
            return false
        }

        return size > 0
    }

    private func audioDeviceName(_ objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)

        let status = withUnsafeMutableBytes(of: &name) { buffer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, buffer.baseAddress!)
        }

        guard status == noErr else {
            return nil
        }

        return name as String
    }
}

public final class AudioDeviceManager: ObservableObject, @unchecked Sendable {
    @Published public private(set) var availableInputDevices: [AudioDevice]
    @Published public private(set) var availableOutputDevices: [AudioDevice]
    @Published public private(set) var selectedInputDeviceID: String
    @Published public private(set) var selectedOutputDeviceID: String
    @Published public private(set) var warning: AudioDeviceWarning?

    private let provider: AudioDeviceProviding
    private let settingsStore: SettingsStoring
    private var preferences: DevicePreferences

    public init(
        provider: AudioDeviceProviding = SystemAudioDeviceProvider(),
        settingsStore: SettingsStoring
    ) {
        self.provider = provider
        self.settingsStore = settingsStore
        self.preferences = settingsStore.load() ?? .default
        let inputDevices = provider.availableInputDevices()
        let outputDevices = provider.availableOutputDevices()
        self.availableInputDevices = inputDevices
        self.availableOutputDevices = outputDevices

        let resolvedInput = Self.resolveSelectedDeviceID(
            requestedID: preferences.selectedInputDeviceID,
            devices: inputDevices
        )
        let resolvedOutput = Self.resolveSelectedDeviceID(
            requestedID: preferences.selectedOutputDeviceID,
            devices: outputDevices
        )

        self.selectedInputDeviceID = resolvedInput
        self.selectedOutputDeviceID = resolvedOutput

        if preferences.selectedInputDeviceID != nil && preferences.selectedInputDeviceID != resolvedInput ||
            preferences.selectedOutputDeviceID != nil && preferences.selectedOutputDeviceID != resolvedOutput {
            self.warning = .selectedDevicesUnavailable(
                inputDeviceID: preferences.selectedInputDeviceID == resolvedInput ? nil : preferences.selectedInputDeviceID,
                outputDeviceID: preferences.selectedOutputDeviceID == resolvedOutput ? nil : preferences.selectedOutputDeviceID
            )
        }
    }

    public func refreshDevices() {
        availableInputDevices = provider.availableInputDevices()
        availableOutputDevices = provider.availableOutputDevices()
    }

    public func selectInputDevice(id: String) {
        guard availableInputDevices.contains(where: { $0.id == id }) else {
            return
        }

        selectedInputDeviceID = id
        savePreferences(inputDeviceID: id, outputDeviceID: selectedOutputDeviceID)
    }

    public func selectOutputDevice(id: String) {
        guard availableOutputDevices.contains(where: { $0.id == id }) else {
            return
        }

        selectedOutputDeviceID = id
        savePreferences(inputDeviceID: selectedInputDeviceID, outputDeviceID: id)
    }

    public func updateSettings(launchAtLogin: Bool, diagnosticsOptIn: Bool, shortcut: PushToTalkShortcut?) {
        preferences = DevicePreferences(
            selectedInputDeviceID: selectedInputDeviceID,
            selectedOutputDeviceID: selectedOutputDeviceID,
            pushToTalkShortcut: shortcut,
            launchAtLogin: launchAtLogin,
            diagnosticsOptIn: diagnosticsOptIn
        )
        settingsStore.save(preferences)
    }

    private func savePreferences(inputDeviceID: String, outputDeviceID: String) {
        preferences = DevicePreferences(
            selectedInputDeviceID: inputDeviceID,
            selectedOutputDeviceID: outputDeviceID,
            pushToTalkShortcut: preferences.pushToTalkShortcut,
            launchAtLogin: preferences.launchAtLogin,
            diagnosticsOptIn: preferences.diagnosticsOptIn
        )
        settingsStore.save(preferences)
    }

    private static func resolveSelectedDeviceID(requestedID: String?, devices: [AudioDevice]) -> String {
        if let requestedID, devices.contains(where: { $0.id == requestedID }) {
            return requestedID
        }

        return devices.first(where: \.isSystemDefault)?.id ?? devices.first?.id ?? ""
    }
}
