import AppKit
import CheeseCoolCore

@MainActor
public final class MenuBarManager: NSObject {
    private let statusBar: NSStatusBar
    private var mainStatusItem: NSStatusItem?
    private var metricControllers: [MetricIdentifier: MetricStatusItemController] = [:]
    private var preferences: MenuBarPreferences = .init()

    public var onModeSelected: ((OperatingMode) -> Void)?
    public var onSettings: (() -> Void)?
    public var onReloadConfiguration: (() -> Void)?
    public var onQuit: (() -> Void)?
    public var onPreferencesChanged: ((MenuBarPreferences) -> Void)?

    public override init() {
        self.statusBar = .system
        super.init()
    }

    public init(statusBar: NSStatusBar) {
        self.statusBar = statusBar
        super.init()
    }

    public func apply(preferences: MenuBarPreferences) {
        self.preferences = preferences
        let visibility = MenuBarVisibilityPolicy.resolve(
            preferredMainIconVisible: preferences.mainIconPreferredVisible,
            visibleMetrics: Set(preferences.visibleMetrics)
        )
        rebuildMetricItems(visibility: visibility)
        setMainIconVisible(visibility.mainIconVisible)
    }

    public func update(telemetry: TelemetrySnapshot, metrics: MetricsSnapshot?) {
        metricControllers[.fanRPM]?.update(title: telemetry.rpm.map { "\($0) RPM" } ?? "— RPM")
        metricControllers[.fanDuty]?.update(
            title: telemetry.deviceActualDuty.map { "\($0)%" } ?? "—%"
        )
        metricControllers[.socTemperature]?.update(
            title: metrics?.socTemperatureCelsius.map { String(format: "%.0f°C", $0) } ?? "—°C"
        )
        metricControllers[.cpuLoad]?.update(
            title: metrics?.cpuLoadPercent.map { String(format: "CPU %.0f%%", $0) } ?? "CPU —%"
        )
        metricControllers[.socPower]?.update(
            title: metrics?.socPowerWatts.map { String(format: "%.1f W", $0) } ?? "— W"
        )
        metricControllers[.gpuLoad]?.update(
            title: metrics?.gpuLoadPercent.map { String(format: "GPU %.0f%%", $0) } ?? "GPU —%"
        )
    }

    private func rebuildMetricItems(visibility: MenuBarVisibility) {
        for controller in metricControllers.values { controller.hide() }
        metricControllers.removeAll()
        for metric in preferences.metricOrder where visibility.visibleMetrics.contains(metric) {
            let controller = MetricStatusItemController(metric: metric, statusBar: statusBar)
            controller.show(title: placeholder(for: metric), menu: makeMenu(for: metric))
            metricControllers[metric] = controller
        }
    }

    private func setMainIconVisible(_ visible: Bool) {
        if visible, mainStatusItem == nil {
            let item = statusBar.statusItem(withLength: NSStatusItem.squareLength)
            if let image = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: "CheeseCool") {
                image.isTemplate = true
                item.button?.image = image
            } else {
                item.button?.title = "C"
            }
            item.button?.toolTip = "CheeseCool"
            item.menu = makeMenu(for: nil)
            mainStatusItem = item
        } else if !visible, let mainStatusItem {
            statusBar.removeStatusItem(mainStatusItem)
            self.mainStatusItem = nil
        } else if visible {
            mainStatusItem?.menu = makeMenu(for: nil)
        }
    }

    private func makeMenu(for metric: MetricIdentifier?) -> NSMenu {
        let menu = NSMenu(title: "CheeseCool")
        menu.addItem(modeItem(title: "AUTO", mode: .auto))
        menu.addItem(modeItem(title: "MANUAL", mode: .manual))
        menu.addItem(modeItem(title: "MAX", mode: .max))
        menu.addItem(.separator())
        if let metric {
            let item = NSMenuItem(
                title: "Hide \(metric.displayName)",
                action: #selector(toggleMetric(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = metric.rawValue
            menu.addItem(item)
        } else {
            for availableMetric in preferences.metricOrder {
                let visible = preferences.visibleMetrics.contains(availableMetric)
                let item = NSMenuItem(
                    title: "\(visible ? "Hide" : "Show") \(availableMetric.displayName)",
                    action: #selector(toggleMetric(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = availableMetric.rawValue
                menu.addItem(item)
            }
        }
        menu.addItem(actionItem(title: "Settings…", action: #selector(openSettings)))
        menu.addItem(actionItem(title: "Reload Configuration", action: #selector(reloadConfiguration)))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit CheeseCool", action: #selector(quit)))
        return menu
    }

    private func modeItem(title: String, mode: OperatingMode) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(selectMode(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = mode.rawValue
        return item
    }

    private func actionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func placeholder(for metric: MetricIdentifier) -> String {
        switch metric {
        case .fanRPM: return "— RPM"
        case .fanDuty: return "—%"
        case .socTemperature: return "—°C"
        case .cpuLoad: return "CPU —%"
        case .socPower: return "— W"
        case .gpuLoad: return "GPU —%"
        }
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = OperatingMode(rawValue: rawValue) else { return }
        onModeSelected?(mode)
    }

    @objc private func toggleMetric(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let metric = MetricIdentifier(rawValue: rawValue) else { return }
        if preferences.visibleMetrics.contains(metric) {
            preferences.visibleMetrics.removeAll { $0 == metric }
        } else {
            preferences.visibleMetrics.append(metric)
        }
        apply(preferences: preferences)
        onPreferencesChanged?(preferences)
    }

    @objc private func openSettings() { onSettings?() }
    @objc private func reloadConfiguration() { onReloadConfiguration?() }
    @objc private func quit() { onQuit?() }
}
