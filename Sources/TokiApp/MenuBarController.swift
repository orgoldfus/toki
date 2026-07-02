import AppKit
import Combine
import Foundation

@MainActor
final class MenuBarController {
    private let model: AppShellModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppShellModel) {
        self.model = model
        bind()
        rebuildMenu()
    }

    private func bind() {
        model.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.rebuildMenu()
                }
            }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: model.menuBarStatus.symbolName,
                accessibilityDescription: model.menuBarStatus.label
            )
            button.imagePosition = .imageLeading
            button.title = " \(model.menuBarStatus.label)"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: model.activityLabel, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Toki", action: #selector(openToki), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let muteItem = NSMenuItem(title: model.isOutputMuted ? "Unmute Output" : "Mute Output", action: #selector(toggleMute), keyEquivalent: "")
        muteItem.target = self
        menu.addItem(muteItem)

        let roomItem = NSMenuItem(title: "Switch Active Room", action: nil, keyEquivalent: "")
        let roomMenu = NSMenu()
        for (index, room) in model.rooms.enumerated() {
            let item = NSMenuItem(title: room.title, action: #selector(selectRoom(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = index
            item.state = model.activeConversationID == room.id ? .on : .off
            roomMenu.addItem(item)
        }
        roomItem.submenu = roomMenu
        menu.addItem(roomItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc
    private func openToki() {
        model.openMainWindow()
    }

    @objc
    private func toggleMute() {
        model.isOutputMuted.toggle()
    }

    @objc
    private func selectRoom(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, model.rooms.indices.contains(index) else { return }
        model.selectRoom(model.rooms[index].id)
        model.openMainWindow()
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}
