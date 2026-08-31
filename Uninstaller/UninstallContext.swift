import Foundation
import CheeseCoolCore

struct UninstallContext: Sendable {
    let mainApplicationURL: URL?
    let parentPID: Int32?
    let selfCleanupRoot: URL?

    static func fromArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> UninstallContext {
        func value(_ key: String) -> String? { arguments.first { $0.hasPrefix(key) }.map { String($0.dropFirst(key.count)) } }
        return UninstallContext(
            mainApplicationURL: value("--main-app=").map { URL(fileURLWithPath: $0) },
            parentPID: value("--parent-pid=").flatMap(Int32.init),
            selfCleanupRoot: value("--self-cleanup-root=").map { URL(fileURLWithPath: $0) }
        )
    }

    var isValidatedMainApplication: Bool {
        guard let mainApplicationURL,
              mainApplicationURL.lastPathComponent == "CheeseCool.app",
              mainApplicationURL.path.hasPrefix("/"),
              mainApplicationURL.path != "/Applications" else { return false }
        return Bundle(url: mainApplicationURL)?.bundleIdentifier == InstallManifest.mainBundleIdentifier
    }
}
