import AppKit
import SwiftUI
import TokiCore

@main
struct TokiApp: App {
    @NSApplicationDelegateAdaptor(TokiApplicationDelegate.self) private var appDelegate
    @StateObject private var model = AppEnvironment.shared.model

    var body: some Scene {
        WindowGroup("Toki") {
            AppShellView(model: model)
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(model: model)
                .frame(width: 520, height: 340)
        }
    }
}

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let model = AppShellModel()

    private init() {}
}

final class TokiApplicationDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var globalShortcutController: GlobalShortcutController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppEnvironment.shared.model
        menuBarController = MenuBarController(model: model)
        globalShortcutController = GlobalShortcutController(model: model)
    }
}
