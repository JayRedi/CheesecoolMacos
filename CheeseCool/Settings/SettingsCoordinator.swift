import AppKit
import SwiftUI

@MainActor
public final class SettingsCoordinator {
    private let model: SettingsViewModel
    private var window: NSWindow?

    public init(model: SettingsViewModel) {
        self.model = model
    }

    public func show() {
        show(initialTab: .general)
    }

    func show(initialTab: SettingsTab) {
        if window == nil {
            let rootView = SettingsView(model: model, initialTab: initialTab)
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "CheeseCool 设置"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 720, height: 620))
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
