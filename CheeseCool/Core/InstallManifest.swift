import Foundation

public enum OwnedResourceKind: String, Codable, Hashable, Sendable, CaseIterable {
    case applicationBundle
    case applicationSupport
    case settings
    case legacySettings
    case cache
    case log
    case preferences
    case savedApplicationState
    case runtimeDiagnostics
    case loginItemRegistration
    case temporaryProductData
}

public struct OwnedResource: Codable, Equatable, Hashable, Sendable {
    public let kind: OwnedResourceKind
    public let path: String?
    public let bundleIdentifier: String?

    public init(kind: OwnedResourceKind, path: String? = nil, bundleIdentifier: String? = nil) {
        self.kind = kind
        self.path = path
        self.bundleIdentifier = bundleIdentifier
    }
}

/// The explicit, bundle-scoped ownership ledger used by both dry-run and real uninstall.
/// It intentionally contains no glob, search or user-entered target.
public struct InstallManifest: Codable, Equatable, Sendable {
    public static let mainBundleIdentifier = "org.cheesecool.CheeseCool"
    public static let uninstallerBundleIdentifier = "org.cheesecool.CheeseCoolUninstaller"

    public let schemaVersion: Int
    public let bundleIdentifier: String
    public let ownedResources: [OwnedResource]
    public let persistentShellEnvironmentVariableCount: Int

    public init(
        schemaVersion: Int = 2,
        bundleIdentifier: String = InstallManifest.mainBundleIdentifier,
        ownedResources: [OwnedResource],
        persistentShellEnvironmentVariableCount: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.bundleIdentifier = bundleIdentifier
        self.ownedResources = ownedResources
        self.persistentShellEnvironmentVariableCount = persistentShellEnvironmentVariableCount
    }

    public static func standard(
        homeDirectory: URL,
        applicationBundleURL: URL? = nil,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) -> InstallManifest {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        let support = library.appendingPathComponent("Application Support/CheeseCool", isDirectory: true)
        let application = applicationBundleURL ?? applicationsDirectory.appendingPathComponent("CheeseCool.app", isDirectory: true)
        return InstallManifest(ownedResources: [
            OwnedResource(kind: .applicationBundle, path: application.path),
            OwnedResource(kind: .applicationSupport, path: support.path),
            OwnedResource(kind: .settings, path: support.appendingPathComponent("settings.json").path),
            OwnedResource(kind: .legacySettings, path: support.appendingPathComponent("config.json").path),
            OwnedResource(kind: .cache, path: library.appendingPathComponent("Caches/org.cheesecool.CheeseCool").path),
            OwnedResource(kind: .log, path: library.appendingPathComponent("Logs/CheeseCool").path),
            OwnedResource(kind: .preferences, path: library.appendingPathComponent("Preferences/org.cheesecool.CheeseCool.plist").path),
            OwnedResource(kind: .savedApplicationState, path: library.appendingPathComponent("Saved Application State/org.cheesecool.CheeseCool.savedState").path),
            OwnedResource(kind: .runtimeDiagnostics, path: support.appendingPathComponent("Diagnostics").path),
            OwnedResource(kind: .loginItemRegistration, bundleIdentifier: mainBundleIdentifier)
        ])
    }
}

public struct CleanupPlan: Equatable, Sendable {
    public let dryRun: Bool
    public let resources: [OwnedResource]

    public init(dryRun: Bool, resources: [OwnedResource]) {
        self.dryRun = dryRun
        self.resources = resources
    }
}

public enum CleanupPlanner {
    public static func plan(manifest: InstallManifest, dryRun: Bool = true) -> CleanupPlan {
        var seen = Set<OwnedResource>()
        return CleanupPlan(dryRun: dryRun, resources: manifest.ownedResources.filter { seen.insert($0).inserted })
    }
}
