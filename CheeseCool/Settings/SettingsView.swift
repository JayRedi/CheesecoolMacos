import Foundation
import SwiftUI
import CheeseCoolCore

public struct SettingsView: View {
    @ObservedObject private var model: SettingsViewModel

    public init(model: SettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gear") }
            menuBar
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            fan
                .tabItem { Label("Fan", systemImage: "fan") }
            advanced
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            about
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 430)
    }

    private var general: some View {
        Form {
            Toggle("Launch at Login", isOn: $model.configuration.launchAtLogin)
            Picker("Default Mode", selection: $model.configuration.operatingMode) {
                ForEach(OperatingMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Toggle("Restore previous mode", isOn: $model.configuration.restorePreviousMode)
            HStack {
                Text("Refresh interval")
                Slider(value: $model.configuration.refreshInterval, in: 0.5...10, step: 0.5)
                Text("\(model.configuration.refreshInterval, specifier: "%.1f") s")
                    .monospacedDigit()
            }
            HStack {
                Button("Reload Configuration") { model.reload() }
                Button("Reset Defaults") { model.reset() }
                Spacer()
                Button("Save") { model.save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var menuBar: some View {
        Form {
            Toggle(
                "Show main CheeseCool icon when metrics are visible",
                isOn: $model.configuration.menuBar.mainIconPreferredVisible
            )
            Section("Metrics") {
                ForEach(MetricIdentifier.allCases, id: \.self) { metric in
                    Toggle(metricTitle(metric), isOn: metricBinding(metric))
                }
            }
            Section("Order") {
                ForEach(Array(model.configuration.menuBar.metricOrder.enumerated()), id: \.element) {
                    Text("\($0.offset + 1). \(metricTitle($0.element))")
                }
            }
            Text("CheeseCool always keeps at least one interactive menu-bar entry visible.")
                .foregroundStyle(.secondary)
        }
    }

    private var fan: some View {
        Form {
            HStack {
                Text("Manual duty")
                Slider(
                    value: Binding(
                        get: { Double(model.configuration.manualDuty) },
                        set: { model.configuration.manualDuty = Int($0.rounded()) }
                    ),
                    in: 0...100,
                    step: 1
                )
                Text("\(model.configuration.manualDuty)%").monospacedDigit()
            }
            Text("0% means minimum speed, not fan off.")
                .foregroundStyle(.secondary)
            LabeledContent("Deadband (%)") {
                TextField("Deadband", value: $model.configuration.deadband, format: .number)
                    .frame(width: 90)
            }
            LabeledContent("Ramp up (%/s)") {
                TextField("Ramp up", value: $model.configuration.rampUpPerSecond, format: .number)
                    .frame(width: 90)
            }
            LabeledContent("Ramp down (%/s)") {
                TextField("Ramp down", value: $model.configuration.rampDownPerSecond, format: .number)
                    .frame(width: 90)
            }
            Section("AUTO curve") {
                ForEach(model.configuration.autoCurve.indices, id: \.self) { index in
                    HStack {
                        Text("Point \(index + 1)")
                        Spacer()
                        TextField(
                            "Temperature",
                            value: curveTemperatureBinding(index),
                            format: .number
                        )
                        .frame(width: 70)
                        Text("°C")
                        TextField("Duty", value: curveDutyBinding(index), format: .number)
                            .frame(width: 70)
                        Text("%")
                    }
                }
            }
        }
    }

    private var advanced: some View {
        Form {
            LabeledContent("Configuration path") {
                Text(model.configurationURL.path).textSelection(.enabled)
            }
            HStack {
                Button("Reload Configuration") { model.reload() }
                Button("Open Configuration Folder") { model.openConfigurationFolder() }
                Button("Clear Logs") { model.clearLogs() }
            }
        }
    }

    private var about: some View {
        VStack(spacing: 12) {
            Image(systemName: "fan.fill").font(.system(size: 48))
            Text("CheeseCool").font(.title)
            Text("Version 0.1.0")
            Text("Architecture: arm64")
            Text("Firmware transport: deferred to Phase 2")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metricBinding(_ metric: MetricIdentifier) -> Binding<Bool> {
        Binding(
            get: { model.configuration.menuBar.visibleMetrics.contains(metric) },
            set: { visible in
                model.configuration.menuBar.visibleMetrics.removeAll { $0 == metric }
                if visible { model.configuration.menuBar.visibleMetrics.append(metric) }
            }
        )
    }

    private func metricTitle(_ metric: MetricIdentifier) -> String {
        switch metric {
        case .fanRPM: return "Fan RPM"
        case .fanDuty: return "Fan Duty"
        case .socTemperature: return "SoC Temperature"
        case .cpuLoad: return "CPU Load"
        case .socPower: return "SoC Power"
        case .gpuLoad: return "GPU Load"
        }
    }

    private func curveTemperatureBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { model.configuration.autoCurve[index].temperatureCelsius },
            set: { value in
                let point = model.configuration.autoCurve[index]
                model.configuration.autoCurve[index] = AutoCurvePoint(
                    temperatureCelsius: value,
                    duty: point.duty
                )
            }
        )
    }

    private func curveDutyBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { model.configuration.autoCurve[index].duty },
            set: { value in
                let point = model.configuration.autoCurve[index]
                model.configuration.autoCurve[index] = AutoCurvePoint(
                    temperatureCelsius: point.temperatureCelsius,
                    duty: value
                )
            }
        )
    }
}
