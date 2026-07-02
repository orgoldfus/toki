import AppKit

@MainActor
final class GlobalShortcutController {
    private weak var model: AppShellModel?
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var globalKeyUpMonitor: Any?

    init(model: AppShellModel) {
        self.model = model
        installMonitors()
    }

    deinit {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }

        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
        }

        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
        }

        if let globalKeyUpMonitor {
            NSEvent.removeMonitor(globalKeyUpMonitor)
        }
    }

    private func installMonitors() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.matchesShortcut(event) == true else { return event }
            guard event.isARepeat == false else { return nil }
            _ = self?.model?.handleShortcutPressed()
            return nil
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard self?.matchesShortcut(event) == true else { return event }
            self?.model?.handleShortcutReleased()
            return nil
        }

        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.matchesShortcut(event) == true, event.isARepeat == false else { return }
            _ = self?.model?.handleShortcutPressed()
        }

        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard self?.matchesShortcut(event) == true else { return }
            self?.model?.handleShortcutReleased()
        }
    }

    private func matchesShortcut(_ event: NSEvent) -> Bool {
        event.keyCode == 49 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift]
    }
}
