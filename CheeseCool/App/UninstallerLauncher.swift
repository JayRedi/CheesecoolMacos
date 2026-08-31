import AppKit
import Foundation
import CheeseCoolCore

@MainActor
public protocol UninstallerLaunching {
    func launch(mainApplicationURL: URL) throws
}

enum UninstallerLaunchError: LocalizedError {
    case invalidMainBundle
    case missingEmbeddedUninstaller
    case invalidCopiedUninstaller

    var errorDescription: String? {
        switch self {
        case .invalidMainBundle: return "无法确认当前 CheeseCool 应用包身份"
        case .missingEmbeddedUninstaller: return "应用内未找到完整卸载器"
        case .invalidCopiedUninstaller: return "临时卸载器身份验证失败"
        }
    }
}

/// The embedded helper is copied before launch so its executable is not removed from beneath it.
@MainActor
final class EmbeddedUninstallerLauncher: UninstallerLaunching {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    func launch(mainApplicationURL: URL) throws {
        guard Bundle(url: mainApplicationURL)?.bundleIdentifier == InstallManifest.mainBundleIdentifier else {
            throw UninstallerLaunchError.invalidMainBundle
        }
        let embedded = mainApplicationURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent("CheeseCool Uninstaller.app", isDirectory: true)
        guard fileManager.fileExists(atPath: embedded.path) else { throw UninstallerLaunchError.missingEmbeddedUninstaller }

        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CheeseCool-Uninstall-\(UUID().uuidString)", isDirectory: true)
        let copied = temporaryRoot.appendingPathComponent("CheeseCool Uninstaller.app", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try fileManager.copyItem(at: embedded, to: copied)
        guard Bundle(url: copied)?.bundleIdentifier == InstallManifest.uninstallerBundleIdentifier else {
            try? fileManager.removeItem(at: temporaryRoot)
            throw UninstallerLaunchError.invalidCopiedUninstaller
        }
        let executable = copied.appendingPathComponent("Contents/MacOS/CheeseCool Uninstaller", isDirectory: false)
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--main-app=\(mainApplicationURL.path)", "--parent-pid=\(ProcessInfo.processInfo.processIdentifier)", "--self-cleanup-root=\(temporaryRoot.path)"]
        try process.run()
    }
}
