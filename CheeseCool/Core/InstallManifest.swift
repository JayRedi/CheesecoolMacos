import Foundation

public enum OwnedResourceKind: String, Codable, Hashable, Sendable {
    case applicationBundle
    case applicationSupport
    case cache
    case log
    case preferences
    case savedApplicationState
    case runtimeDiagnostics
    case loginItemRegistration
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

public struct InstallManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let bundleIdentifier: String
    public let ownedResources: [OwnedResource]
    public let persistentShellEnvironmentVariableCount: Int

    public init(
        schemaVersion: Int = 1,
        bundleIdentifier: String = "org.cheesecool.CheeseCool",
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
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) -> InstallManifest {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        return InstallManifest(ownedResources: [
            OwnedResource(
                kind: .applicationBundle,
                path: applicationsDirectory.appendingPathComponent("CheeseCool.app").path
            ),
            OwnedResource(
                kind: .applicationSupport,
                path: library.appendingPathComponent("Application Support/CheeseCool").path
            ),
            OwnedResource(kind: .cache, path: library.appendingPathComponent("Caches/org.cheesecool.CheeseCool").path),
            OwnedResource(kind: .log, path: library.appendingPathComponent("Logs/CheeseCool").path),
            OwnedResource(
                kind: .preferences,
                path: library.appendingPathComponent("Preferences/org.cheesecool.CheeseCool.plist").path
            ),
            OwnedResource(
                kind: .savedApplicationState,
                path: library.appendingPathComponent("Saved Application State/org.cheesecool.CheeseCool.savedState").path
            ),
            OwnedResource(
                kind: .runtimeDiagnostics,
                path: library.appendingPathComponent("Application Support/CheeseCool/Diagnostics").path
            ),
            OwnedResource(kind: .loginItemRegistration, bundleIdentifier: "org.cheesecool.CheeseCool")
        ])
    }
}

public struct CleanupPlan: Equatable, Sendable {
    public let dryRun: Bool
    public let resources: [OwnedResource]
}

public enum CleanupPlanner {
    public static func plan(manifest: InstallManifest, dryRun: Bool = true) -> CleanupPlan {
        CleanupPlan(dryRun: dryRun, resources: manifest.ownedResources)
    }
}
