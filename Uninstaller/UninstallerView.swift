import SwiftUI

struct UninstallerView: View {
    @StateObject private var model = CleanupViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            Text("完全卸载 CheeseCool").font(.title2.weight(.semibold))
            Text(model.statusText).foregroundStyle(.secondary)
            List(model.plan.resources, id: \.self) { resource in
                VStack(alignment: .leading, spacing: 3) {
                    Text(resource.kind.rawValue)
                    Text(resource.path ?? resource.bundleIdentifier ?? "").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let result = model.result {
                Text(result.hasFailures ? "部分内容未能删除" : "所有 CheeseCool 拥有的项目均已清理")
                    .foregroundStyle(result.hasFailures ? .orange : .green)
            }
            HStack {
                Button("取消") { model.cancel() }.disabled(model.screen == .processing)
                Spacer()
                if model.screen == .review {
                    Button("继续") { model.begin() }.keyboardShortcut(.defaultAction)
                } else if model.screen == .processing {
                    ProgressView()
                } else {
                    Button("完成") { model.cancel() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(minWidth: 620, minHeight: 470)
    }
}
