import SwiftUI

struct UninstallerView: View {
    @StateObject private var model = CleanupViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CheeseCool Uninstaller").font(.title)
            Text("Phase 1 provides a manifest-driven cleanup preview. It does not delete files.")
                .foregroundStyle(.secondary)
            Toggle("Dry run", isOn: $model.dryRun)
                .disabled(true)
            List(model.plan.resources, id: \.self) { resource in
                VStack(alignment: .leading) {
                    Text(resource.kind.rawValue)
                    Text(resource.path ?? resource.bundleIdentifier ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Review Cleanup Plan") { model.prepare() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 440)
        .alert("Dry-run cleanup only", isPresented: $model.confirmationPresented) {
            Button("OK") { model.dismissConfirmation() }
        } message: {
            Text("No files will be removed in Phase 1.")
        }
    }
}
