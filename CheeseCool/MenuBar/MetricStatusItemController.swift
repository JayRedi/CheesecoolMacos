import AppKit
import CheeseCoolCore

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
    }

    func update(title: String) {
        statusItem?.button?.title = title
    }

    func hide() {
        if let statusItem { statusBar.removeStatusItem(statusItem) }
        statusItem = nil
    }
}

extension MetricIdentifier {
    var displayName: String {
        switch self {
        case .fanRPM: return "Fan RPM"
        case .fanDuty: return "Fan Duty"
        case .socTemperature: return "SoC Temperature"
        case .cpuLoad: return "CPU Load"
        case .socPower: return "SoC Power"
        case .gpuLoad: return "GPU Load"
        }
    }
}
