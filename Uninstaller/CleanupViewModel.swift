import Foundation
import CheeseCoolCore
import Darwin
import AppKit

@MainActor
final class CleanupViewModel: ObservableObject {
    enum Screen { case review, processing, complete, partialFailure }

    @Published private(set) var screen: Screen = .review
    @Published private(set) var plan: CleanupPlan
    @Published private(set) var result: CleanupExecutionResult?
    @Published private(set) var statusText = "将只删除 CheeseCool 明确拥有的数据。"

    private let context: UninstallContext
    private let manifest: InstallManifest
    private let engine: CleanupEngine

    init(context: UninstallContext = .fromArguments(), homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, engine: CleanupEngine = CleanupEngine()) {
        self.context = context
        manifest = .standard(homeDirectory: homeDirectory, applicationBundleURL: context.mainApplicationURL)
        self.engine = engine
        plan = engine.plan(manifest: manifest, dryRun: context.mainApplicationURL == nil)
    }

    func cancel() { NSApplication.shared.terminate(nil) }

    func begin() {
        guard context.isValidatedMainApplication else {
            statusText = "无法确认要卸载的 CheeseCool 应用。直接打开的卸载器仅提供安全预览。"
            result = CleanupExecutionResult(dryRun: true, items: engine.validate(plan: plan, manifest: manifest))
            screen = .partialFailure
            return
        }
        screen = .processing
        statusText = "正在等待 CheeseCool 正常退出…"
        Task { [weak self] in await self?.perform() }
    }

    private func perform() async {
        if let parentPID = context.parentPID, !(await waitForExit(parentPID, timeout: 8)) {
            statusText = "CheeseCool 仍在运行。请关闭应用后重试；不会删除正在使用的应用。"
            screen = .partialFailure
            return
        }
        statusText = "正在清理 CheeseCool 拥有的数据…"
        let execution = engine.execute(plan: plan, manifest: manifest)
        let verification = engine.verify(plan: plan, manifest: manifest)
        let failedPaths = Set(verification.items.compactMap { $0.state == .failed ? $0.resource.path : nil })
        let final = CleanupExecutionResult(dryRun: false, items: execution.items.map { item in
            item.resource.path.map(failedPaths.contains) == true
                ? CleanupItemResult(resource: item.resource, state: .failed, detail: "验证发现路径仍存在")
                : item
        })
        result = final
        if final.hasFailures {
            statusText = "部分内容未能删除。请查看下方详情后重试。"
            screen = .partialFailure
        } else {
            statusText = "卸载完成。"
            screen = .complete
        }
    }

    private func waitForExit(_ pid: Int32, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return kill(pid, 0) != 0
    }
}
