import AppKit
import SwiftUI

@main
struct CheeseCoolUninstallerApp: App {
    @NSApplicationDelegateAdaptor(UninstallerApplicationDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup { UninstallerView() }
            .windowResizability(.contentSize)
    }
}

final class UninstallerApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        let context = UninstallContext.fromArguments()
        guard let root = context.selfCleanupRoot?.standardizedFileURL,
              root.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path),
              root.lastPathComponent.hasPrefix("CheeseCool-Uninstall-") else { return }
        try? FileManager.default.removeItem(at: root)
    }
}
