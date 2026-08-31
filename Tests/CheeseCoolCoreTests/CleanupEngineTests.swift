import XCTest
@testable import CheeseCoolCore

final class CleanupEngineTests: XCTestCase {
    func testProductionPlanDeletesOnlyOwnedItemsInInjectedTemporaryRoot() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let app = root.appendingPathComponent("Applications/CheeseCool.app", isDirectory: true)
        let manifest = InstallManifest.standard(homeDirectory: home, applicationBundleURL: app)
        let support = home.appendingPathComponent("Library/Application Support/CheeseCool", isDirectory: true)
        try write("settings", to: support.appendingPathComponent("settings.json"))
        try write("legacy", to: support.appendingPathComponent("config.json"))
        try write("app", to: app.appendingPathComponent("Contents/MacOS/CheeseCool"))
        let neighbor = home.appendingPathComponent("Library/Application Support/Unrelated/keep.txt")
        try write("keep", to: neighbor)

        let engine = CleanupEngine()
        let plan = engine.plan(manifest: manifest, dryRun: false)
        let execution = engine.execute(plan: plan, manifest: manifest)
        XCTAssertTrue(execution.isComplete)
        XCTAssertFalse(execution.hasFailures)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: neighbor.path))
        XCTAssertTrue(engine.verify(plan: plan, manifest: manifest).isComplete)
    }

    func testDryRunUsesTheSamePlanWithoutMutation() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Applications/CheeseCool.app")
        let manifest = InstallManifest.standard(homeDirectory: root.appendingPathComponent("home"), applicationBundleURL: app)
        try write("app", to: app.appendingPathComponent("Contents/MacOS/CheeseCool"))
        let engine = CleanupEngine()
        let plan = engine.plan(manifest: manifest, dryRun: true)
        let result = engine.execute(plan: plan, manifest: manifest)
        XCTAssertTrue(result.dryRun)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
        XCTAssertTrue(result.items.allSatisfy { $0.state == .planned || $0.state == .skippedUnsafe })
    }

    func testUnsafeAndRelativeTargetsFailClosed() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let unsafe = InstallManifest(ownedResources: [
            OwnedResource(kind: .applicationBundle, path: "/"),
            OwnedResource(kind: .cache, path: "../relative"),
            OwnedResource(kind: .log, path: "/Applications")
        ])
        let engine = CleanupEngine()
        let plan = engine.plan(manifest: unsafe, dryRun: false)
        let result = engine.execute(plan: plan, manifest: unsafe)
        XCTAssertTrue(result.hasFailures)
        XCTAssertTrue(result.items.allSatisfy { $0.state == .skippedUnsafe })
    }

    func testSymlinkAndDuplicateEntriesAreRejectedOrDeduplicated() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("home/Library/Caches/org.cheesecool.CheeseCool")
        let external = root.appendingPathComponent("unrelated")
        try write("keep", to: external.appendingPathComponent("keep.txt"))
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: external)
        let manifest = InstallManifest(ownedResources: [
            OwnedResource(kind: .cache, path: target.path),
            OwnedResource(kind: .cache, path: target.path)
        ])
        let engine = CleanupEngine()
        let plan = engine.plan(manifest: manifest, dryRun: false)
        XCTAssertEqual(plan.resources.count, 1)
        let result = engine.execute(plan: plan, manifest: manifest)
        XCTAssertEqual(result.items.first?.state, .skippedUnsafe)
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.appendingPathComponent("keep.txt").path))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CheeseCool-CleanupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
    }
}
