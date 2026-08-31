import Foundation

public enum CleanupItemState: String, Codable, Equatable, Sendable {
    case planned, deleted, notPresent, failed, skippedUnsafe
}

public struct CleanupItemResult: Equatable, Sendable {
    public let resource: OwnedResource
    public let state: CleanupItemState
    public let detail: String

    public init(resource: OwnedResource, state: CleanupItemState, detail: String = "") {
        self.resource = resource
        self.state = state
        self.detail = detail
    }
}

public struct CleanupExecutionResult: Equatable, Sendable {
    public let dryRun: Bool
    public let items: [CleanupItemResult]

    public init(dryRun: Bool, items: [CleanupItemResult]) {
        self.dryRun = dryRun
        self.items = items
    }

    public var isComplete: Bool {
        items.allSatisfy { $0.state == .deleted || $0.state == .notPresent || $0.state == .planned }
    }

    public var hasFailures: Bool {
        items.contains { $0.state == .failed || $0.state == .skippedUnsafe }
    }
}

public enum CleanupPathError: Error, Equatable, LocalizedError, Sendable {
    case missingPath, relativePath, suspiciousParent(String), outsideManifest(String), symlink(String)

    public var errorDescription: String? {
        switch self {
        case .missingPath: return "清理路径为空"
        case .relativePath: return "清理路径必须是绝对路径"
        case .suspiciousParent(let path): return "拒绝删除危险父目录：\(path)"
        case .outsideManifest(let path): return "路径不在 CheeseCool 清单中：\(path)"
        case .symlink(let path): return "拒绝删除符号链接路径：\(path)"
        }
    }
}

/// A path must be an exact canonical manifest target. Parent directories, arbitrary input
/// and symbolic links are rejected before a deletion can be attempted.
public struct CleanupPathValidator: Sendable {
    private let allowedPaths: Set<String>
    private let forbiddenPaths: Set<String>

    public init(manifest: InstallManifest, fileManager: FileManager = .default) {
        allowedPaths = Set(manifest.ownedResources.compactMap { $0.path.map(Self.standardize) })
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        let library = home + "/Library"
        forbiddenPaths = ["/", "/Applications", "/tmp", home, library,
                          library + "/Application Support", library + "/Caches", library + "/Logs",
                          library + "/Preferences", library + "/Saved Application State"]
            .reduce(into: Set<String>()) { $0.insert(Self.standardize($1)) }
    }

    public func validate(_ rawPath: String?, fileManager: FileManager = .default) throws -> URL {
        guard let rawPath, !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CleanupPathError.missingPath
        }
        guard rawPath.hasPrefix("/") else { throw CleanupPathError.relativePath }
        let target = URL(fileURLWithPath: rawPath).standardizedFileURL
        let canonical = Self.standardize(target.path)
        guard !forbiddenPaths.contains(canonical) else { throw CleanupPathError.suspiciousParent(canonical) }
        guard allowedPaths.contains(canonical) else { throw CleanupPathError.outsideManifest(canonical) }
        if fileManager.fileExists(atPath: target.path),
           (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw CleanupPathError.symlink(target.path)
        }
        return target
    }

    private static func standardize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

public final class CleanupEngine: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func plan(manifest: InstallManifest, dryRun: Bool) -> CleanupPlan {
        CleanupPlanner.plan(manifest: manifest, dryRun: dryRun)
    }

    public func validate(plan: CleanupPlan, manifest: InstallManifest) -> [CleanupItemResult] {
        let validator = CleanupPathValidator(manifest: manifest, fileManager: fileManager)
        return plan.resources.map { resource in
            guard resource.path != nil else {
                return CleanupItemResult(resource: resource, state: .planned, detail: "登录项由原生 ServiceManagement 单独处理")
            }
            do {
                _ = try validator.validate(resource.path, fileManager: fileManager)
                return CleanupItemResult(resource: resource, state: .planned)
            } catch {
                return CleanupItemResult(resource: resource, state: .skippedUnsafe, detail: error.localizedDescription)
            }
        }
    }

    public func execute(plan: CleanupPlan, manifest: InstallManifest) -> CleanupExecutionResult {
        let validation = validate(plan: plan, manifest: manifest)
        guard !plan.dryRun else { return CleanupExecutionResult(dryRun: true, items: validation) }
        let validator = CleanupPathValidator(manifest: manifest, fileManager: fileManager)
        let results = plan.resources.map { resource -> CleanupItemResult in
            guard let path = resource.path else {
                return CleanupItemResult(resource: resource, state: .planned, detail: "登录项等待原生注销")
            }
            do {
                let target = try validator.validate(path, fileManager: fileManager)
                guard fileManager.fileExists(atPath: target.path) else {
                    return CleanupItemResult(resource: resource, state: .notPresent)
                }
                try fileManager.removeItem(at: target)
                return CleanupItemResult(resource: resource,
                                         state: fileManager.fileExists(atPath: target.path) ? .failed : .deleted,
                                         detail: fileManager.fileExists(atPath: target.path) ? "删除后路径仍存在" : "")
            } catch let error as CleanupPathError {
                return CleanupItemResult(resource: resource, state: .skippedUnsafe, detail: error.localizedDescription)
            } catch {
                return CleanupItemResult(resource: resource, state: .failed, detail: error.localizedDescription)
            }
        }
        return CleanupExecutionResult(dryRun: false, items: results)
    }

    public func verify(plan: CleanupPlan, manifest: InstallManifest) -> CleanupExecutionResult {
        let validator = CleanupPathValidator(manifest: manifest, fileManager: fileManager)
        let results = plan.resources.map { resource -> CleanupItemResult in
            guard let path = resource.path else {
                return CleanupItemResult(resource: resource, state: .planned, detail: "登录项由调用方验证")
            }
            do {
                let target = try validator.validate(path, fileManager: fileManager)
                return CleanupItemResult(resource: resource,
                                         state: fileManager.fileExists(atPath: target.path) ? .failed : .notPresent)
            } catch {
                return CleanupItemResult(resource: resource, state: .skippedUnsafe, detail: error.localizedDescription)
            }
        }
        return CleanupExecutionResult(dryRun: plan.dryRun, items: results)
    }
}
