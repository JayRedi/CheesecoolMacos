import AppKit
import CheeseCoolCore

enum MenuMetricFormatter {
    static func title(for metric: MetricIdentifier, value: Double?) -> String {
        switch (metric, value) {
        case (.fanRPM, .some(let value)): return "\(Int(value.rounded())) RPM"
        case (.fanRPM, .none): return "-- RPM"
        case (.fanDuty, .some(let value)): return "\(Int(value.rounded()))%"
        case (.fanDuty, .none): return "--%"
        case (.socTemperature, .some(let value)): return String(format: "%.0f°C", value)
        case (.socTemperature, .none): return "--°C"
        case (.cpuLoad, .some(let value)), (.gpuLoad, .some(let value)):
            return String(format: "%.0f%%", value)
        case (.cpuLoad, .none), (.gpuLoad, .none): return "--%"
        case (.socPower, .some(let value)): return String(format: "%.1f W", value)
        case (.socPower, .none): return "-- W"
        }
    }
}

@MainActor
final class MetricStatusItemController {
    let metric: MetricIdentifier
    private let statusBar: NSStatusBar
    private var statusItem: NSStatusItem?

    init(metric: MetricIdentifier, statusBar: NSStatusBar) {
        self.metric = metric
        self.statusBar = statusBar
    }

    var isVisible: Bool { statusItem != nil }

    func show(title: String, menu: NSMenu) {
        if statusItem == nil {
            statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        }
        statusItem?.button?.title = title
        statusItem?.button?.toolTip = metric.displayName
        statusItem?.menu = menu
        statusItem?.isVisible = true
    }

    func update(title: String) {
        statusItem?.button?.title = title
    }

    func hide() {
        if let statusItem { statusBar.removeStatusItem(statusItem) }
        statusItem = nil
    }
}
