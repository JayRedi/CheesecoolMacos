import Foundation
import CheeseCoolCore

@MainActor
final class CleanupViewModel: ObservableObject {
    @Published var dryRun = true
    @Published private(set) var plan: CleanupPlan
    @Published var confirmationPresented = false

    private let manifest: InstallManifest

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        manifest = .standard(homeDirectory: homeDirectory)
        plan = CleanupPlanner.plan(manifest: manifest, dryRun: true)
    }

    func prepare() {
        plan = CleanupPlanner.plan(manifest: manifest, dryRun: dryRun)
        confirmationPresented = true
    }

    func dismissConfirmation() {
        confirmationPresented = false
    }
}
