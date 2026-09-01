import AppKit
import Foundation

@main
struct GracefulAppTerminator {
    static func main() {
        let bundleIdentifier = CommandLine.arguments.dropFirst().first ?? "org.cheesecool.CheeseCool"
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            fputs("No running application for bundle identifier: \(bundleIdentifier)\n", stderr)
            exit(EXIT_FAILURE)
        }

        let pid = application.processIdentifier
        let startedAt = Date()
        guard application.terminate() else {
            fputs("NSRunningApplication.terminate() was not accepted for PID \(pid).\n", stderr)
            exit(EXIT_FAILURE)
        }

        let deadline = Date().addingTimeInterval(15)
        while !application.isTerminated && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard application.isTerminated else {
            fputs("Termination request accepted but PID \(pid) did not exit within 15 seconds.\n", stderr)
            exit(EXIT_FAILURE)
        }

        let payload: [String: Any] = [
            "bundleIdentifier": bundleIdentifier,
            "pid": pid,
            "method": "NSRunningApplication.terminate",
            "exited": true,
            "elapsedSeconds": Date().timeIntervalSince(startedAt)
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
