import Foundation

public struct PushToTalkShortcut: Codable, Equatable, Sendable {
    public struct Modifiers: OptionSet, Codable, Equatable, Sendable {
        public let rawValue: Int

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    public let keyCode: Int
    public let modifiers: Modifiers

    public init(keyCode: Int, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public struct DevicePreferences: Codable, Equatable, Sendable {
    public let selectedInputDeviceID: String?
    public let selectedOutputDeviceID: String?
    public let pushToTalkShortcut: PushToTalkShortcut?
    public let launchAtLogin: Bool
    public let diagnosticsOptIn: Bool

    public init(
        selectedInputDeviceID: String?,
        selectedOutputDeviceID: String?,
        pushToTalkShortcut: PushToTalkShortcut?,
        launchAtLogin: Bool,
        diagnosticsOptIn: Bool
    ) {
        self.selectedInputDeviceID = selectedInputDeviceID
        self.selectedOutputDeviceID = selectedOutputDeviceID
        self.pushToTalkShortcut = pushToTalkShortcut
        self.launchAtLogin = launchAtLogin
        self.diagnosticsOptIn = diagnosticsOptIn
    }

    public static let `default` = DevicePreferences(
        selectedInputDeviceID: nil,
        selectedOutputDeviceID: nil,
        pushToTalkShortcut: PushToTalkShortcut(keyCode: 49, modifiers: [.command, .shift]),
        launchAtLogin: false,
        diagnosticsOptIn: false
    )
}

public protocol SettingsStoring: Sendable {
    func load() -> DevicePreferences?
    func save(_ preferences: DevicePreferences)
}

public final class LocalSettingsStore: SettingsStoring, @unchecked Sendable {
    private enum Keys {
        static let devicePreferences = "devicePreferences"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> DevicePreferences? {
        guard let data = defaults.data(forKey: Keys.devicePreferences) else {
            return nil
        }

        return try? decoder.decode(DevicePreferences.self, from: data)
    }

    public func save(_ preferences: DevicePreferences) {
        guard let data = try? encoder.encode(preferences) else {
            defaults.removeObject(forKey: Keys.devicePreferences)
            return
        }

        defaults.set(data, forKey: Keys.devicePreferences)
    }
}
