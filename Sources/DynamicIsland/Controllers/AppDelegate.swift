import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtimeSettings = IslandRuntimeSettings()
    private var panelController: IslandPanelController?
    private var statusItem: NSStatusItem?
    private var settingsPopover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panelController = IslandPanelController(runtimeSettings: runtimeSettings)
        self.panelController = panelController
        configureStatusItem()
        panelController.show()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "cx"
        item.button?.toolTip = "Dynamic Island MVP"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置", action: #selector(toggleSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show Dynamic Island", action: #selector(showIsland), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Dynamic Island", action: #selector(hideIsland), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Dynamic Island", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu

        statusItem = item
    }

    @objc private func toggleSettings() {
        if settingsPopover?.isShown == true {
            settingsPopover?.performClose(nil)
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 260, height: 266)
        popover.contentViewController = NSHostingController(
            rootView: IslandSettingsView(
                settings: runtimeSettings,
                onResetDisplay: { [weak self] in
                    self?.resetDisplayAdaptation()
                }
            )
        )
        settingsPopover = popover

        if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func showIsland() {
        panelController?.show()
    }

    @objc private func hideIsland() {
        panelController?.hide()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func resetDisplayAdaptation() {
        panelController?.resetDisplayAdaptation()
    }

    @objc private func screenConfigurationDidChange() {
        panelController?.refreshForCurrentScreen()
    }
}
