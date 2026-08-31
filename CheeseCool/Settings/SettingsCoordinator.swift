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
        if window == nil {
            let hostingController = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: hostingController)
            window.title = "CheeseCool Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 680, height: 500))
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
