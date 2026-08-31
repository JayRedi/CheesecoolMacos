import AppKit
import CheeseCoolCore
import OSLog

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "org.cheesecool.CheeseCool", category: "Application")
    private var coordinator: AppCoordinator?
    private var terminationInProgress = false

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSClassFromString("XCTestCase") == nil else {
            logger.notice("Skipping production startup in an XCTest host")
            return
        }
        NSApp.setActivationPolicy(.accessory)
        let arguments = ProcessInfo.processInfo.arguments
        let dryRunDuration = arguments.compactMap { argument -> TimeInterval? in
            guard argument.hasPrefix("--phase2-dry-run-seconds=") else { return nil }
            return TimeInterval(argument.split(separator: "=").last ?? "")
        }.first
        let loginItemManager: (any LoginItemManaging)?
        if arguments.contains("--disable-login-item-management") || dryRunDuration != nil {
            loginItemManager = FakeLoginItemManager()
        } else {
            loginItemManager = nil
        }
        let coordinator = AppCoordinator(loginItemManager: loginItemManager)
        self.coordinator = coordinator
        if let dryRunDuration {
            Task {
                let report = await coordinator.runDryRun(
                    duration: max(300, dryRunDuration),
                    interval: 1
                )
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(report)
                    let outputURL = URL(fileURLWithPath: "/tmp/cheesecool-phase2-dry-run.json")
                    try data.write(to: outputURL, options: .atomic)
                    logger.notice("Phase 2 dry run written to \(outputURL.path, privacy: .public)")
                    exit(EXIT_SUCCESS)
                } catch {
                    logger.error("Phase 2 dry run failed to write: \(error.localizedDescription, privacy: .public)")
                    exit(EXIT_FAILURE)
                }
            }
            return
        }
        coordinator.start()
#if DEBUG
        if arguments.contains("--show-settings-for-ui-testing") {
            coordinator.showSettingsForUITesting()
        }
#endif
        logger.notice("CheeseCool application coordinator started")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationInProgress, let coordinator else { return .terminateNow }
        terminationInProgress = true
        Task {
            await coordinator.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
