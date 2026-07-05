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
        // "record.circle" 在 macOS 14+ 上稳定存在，作为 Dynamic Island 的象征图标
        item.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Dynamic Island")
        item.button?.toolTip = "Dynamic Island"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置", action: #selector(toggleSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show Dynamic Island", action: #selector(showIsland), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Dynamic Island", action: #selector(hideIsland), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打开日志文件夹", action: #selector(openLogsFolder), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Dynamic Island", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu

        statusItem = item
    }

    @objc private func openLogsFolder() {
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DynamicIsland", isDirectory: true)
        // 如果目录不存在就先创建，确保 Finder 能打开
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(logsDirectory)
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
