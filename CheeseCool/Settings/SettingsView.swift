import AppKit
import Foundation
import SwiftUI
import CheeseCoolCore

enum SettingsTab: Hashable {
    case general
    case menuBar
    case fan
    case advanced
    case about
}

public struct SettingsView: View {
    @ObservedObject private var model: SettingsViewModel
    @State private var selectedTab: SettingsTab
    @State private var resetConfirmationPresented = false
    @State private var uninstallConfirmationPresented = false

    public init(model: SettingsViewModel) {
        self.model = model
        self._selectedTab = State(initialValue: .general)
    }

    init(model: SettingsViewModel, initialTab: SettingsTab) {
        self.model = model
        self._selectedTab = State(initialValue: initialTab)
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            general.tabItem { Label("通用", systemImage: "gearshape") }.tag(SettingsTab.general)
            menuBar.tabItem { Label("菜单栏", systemImage: "menubar.rectangle") }.tag(SettingsTab.menuBar)
            fan.tabItem { Label("风扇", systemImage: "fan") }.tag(SettingsTab.fan)
            advanced.tabItem { Label("高级", systemImage: "slider.horizontal.3") }.tag(SettingsTab.advanced)
            about.tabItem { Label("关于", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 560)
        .alert("恢复默认设置？", isPresented: $resetConfirmationPresented) {
            Button("恢复默认值", role: .destructive) { model.reset() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前设置会立即替换并自动保存，无需重新启动 CheeseCool。")
        }
        .alert("完全卸载 CheeseCool？", isPresented: $uninstallConfirmationPresented) {
            Button("取消", role: .cancel) {}
            Button("完全卸载", role: .destructive) { model.uninstall() }
        } message: {
            Text("这会删除 CheeseCool 应用、用户设置、风扇配置、缓存、运行日志、诊断数据和登录自启动配置。此操作无法撤销。")
        }
    }

    private var general: some View {
        Form {
            Section("启动") {
                Toggle("登录时自动启动", isOn: $model.configuration.launchAtLogin)
                Toggle("恢复上次使用模式", isOn: $model.configuration.restorePreviousMode)
            }
            Section("默认模式") {
                Picker("模式", selection: $model.configuration.operatingMode) {
                    ForEach(OperatingMode.allCases, id: \.self) { Text($0.productName).tag($0) }
                }
                .accessibilityLabel("默认模式")
            }
            Section("刷新") {
                Picker("刷新频率", selection: $model.configuration.refreshInterval) {
                    Text("1 秒").tag(TimeInterval(1))
                    Text("2 秒").tag(TimeInterval(2))
                    Text("5 秒").tag(TimeInterval(5))
                }
                Text("所有更改会立即应用，并在短暂延迟后自动保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("恢复默认设置", role: .destructive) { resetConfirmationPresented = true }
                    .accessibilityLabel("恢复默认设置")
            }
        }
        .formStyle(.grouped)
    }

    private var menuBar: some View {
        Form {
            Section("主图标") {
                Toggle("指标可见时显示 CheeseCool 主图标", isOn: $model.configuration.menuBar.mainIconPreferredVisible)
                    .accessibilityLabel("显示 CheeseCool 主图标")
                Text("隐藏全部指标时，主图标会自动显示，确保始终可从菜单栏访问 CheeseCool。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("显示的指标") {
                metricToggle(.fanRPM)
                metricToggle(.fanDuty)
                metricToggle(.socTemperature)
                metricToggle(.cpuLoad)
            }
            Section("当前不可显示") {
                unavailableMetric("SoC 功耗", detail: "当前系统没有稳定、免特权的公开功耗接口。")
                unavailableMetric("GPU 负载", detail: "当前系统不支持可靠的整机 GPU 利用率读取。")
            }
            Section("排列顺序") {
                ForEach(model.configuration.menuBar.metricOrder.filter { visibleConfigurableMetrics.contains($0) }, id: \.self) { metric in
                    HStack {
                        Text(metric.displayName)
                        Spacer()
                        Button { model.moveMetric(metric, by: -1) } label: { Image(systemName: "chevron.up") }
                            .accessibilityLabel("上移\(metric.displayName)")
                        Button { model.moveMetric(metric, by: 1) } label: { Image(systemName: "chevron.down") }
                            .accessibilityLabel("下移\(metric.displayName)")
                    }
                }
                Text("顺序会立即应用到菜单栏。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var fan: some View {
        Form {
            Section("当前控制") {
                Picker("模式", selection: $model.configuration.operatingMode) {
                    ForEach(OperatingMode.allCases, id: \.self) { Text($0.productName).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("风扇控制模式")
            }

            if model.configuration.operatingMode == .manual {
                Section("手动占空比") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(model.configuration.manualDuty) },
                                set: { model.setManualDuty(Int($0.rounded())) }
                            ),
                            in: 0...100,
                            step: 1
                        )
                        Text("\(model.configuration.manualDuty)%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                    .accessibilityLabel("手动占空比")
                    Text("0% 表示最低转速，不代表关闭、停止或物理停转。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if model.configuration.operatingMode == .auto {
                Section("自动温度曲线（临时值）") {
                    Text("以下曲线是当前临时策略，尚非最终硬件校准值。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(model.configuration.autoCurve.indices, id: \.self) { index in
                        autoCurveRow(index)
                    }
                }
            }

            if model.configuration.operatingMode == .max {
                Section("全速") {
                    Text("全速模式会请求设备进入 MAX 模式。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("当前状态") { liveStatus }
        }
        .formStyle(.grouped)
    }

    private var advanced: some View {
        Form {
            Section("高级自动控制") {
                stepperRow("控制回差", value: $model.configuration.deadband, range: 0...20, step: 1, unit: "%")
                stepperRow("上升速率", value: $model.configuration.rampUpPerSecond, range: 1...100, step: 1, unit: "%/秒")
                stepperRow("下降速率", value: $model.configuration.rampDownPerSecond, range: 1...100, step: 1, unit: "%/秒")
                Text("看门狗和失效保护为固定安全机制，不在此处修改。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("诊断") {
                diagnosticRow("SoC 温度", sample: model.metrics?.socTemperature)
                diagnosticRow("CPU 负载", sample: model.metrics?.cpuLoad)
                diagnosticRow("SoC 功耗", sample: model.metrics?.socPower)
                diagnosticRow("GPU 负载", sample: model.metrics?.gpuLoad)
                LabeledContent("设备") {
                    Text(model.simulationMode ? "模拟设备（FakeHostDevice）" : deviceDiagnosticText)
                }
                if let diagnostics = model.hidDiagnostics, !model.simulationMode {
                    LabeledContent("HID 匹配设备") { Text("\(diagnostics.matchingDevices.count) 个") }
                    LabeledContent("HID 已选设备") { Text(diagnostics.selectedDevice?.displayName ?? "未连接") }
                    LabeledContent("上次 HID 命令") { Text(diagnostics.lastCommand.map { String(format: "0x%02X", $0.rawValue) } ?? "--") }
                    LabeledContent("HID 序列") { Text(diagnostics.lastSequence.map(String.init) ?? "--") }
                    LabeledContent("HID 往返延迟") {
                        Text(diagnostics.lastRoundTripMilliseconds.map { String(format: "%.1f ms", $0) } ?? "--")
                    }
                    LabeledContent("HID 传输") { Text(diagnostics.lastError ?? "正常") }
                    LabeledContent("HID 断连/重连") { Text("\(diagnostics.disconnectCount) / \(diagnostics.reconnectCount)") }
                }
                Button("清除诊断日志") { model.clearLogs() }
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            Text("CheeseCool").font(.title2.weight(.semibold))
            Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知版本")")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text("Apple Silicon（arm64）")
                Text("最低支持 macOS 13")
                Text("原生菜单栏工具，使用真实 SoC 温度和 CPU 负载。")
            }
            .font(.callout)
            Link("GitHub 项目", destination: URL(string: "https://github.com/JayRedi/CheesecoolMacos")!)
            Button("完全卸载 CheeseCool", role: .destructive) {
                uninstallConfirmationPresented = true
            }
            .accessibilityLabel("完全卸载 CheeseCool")
            Text("开源项目。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var liveStatus: some View {
        Group {
            if let telemetry = model.telemetry {
                LabeledContent("当前模式") { Text(telemetry.operatingMode.productName) }
                LabeledContent("控制状态") {
                    Text(telemetry.controlState.displayName)
                        .foregroundStyle(telemetry.controlState.isCritical ? .red : .primary)
                }
                LabeledContent("连接") { Text(telemetry.connectionState.displayName) }
                LabeledContent("请求占空比") { Text(telemetry.requestedDuty.map { "\($0)%" } ?? "--") }
                LabeledContent("风扇转速") { Text(telemetry.rpm.map { "\($0) RPM" } ?? "-- RPM") }
                if model.simulationMode {
                    Text("风扇转速与占空比来自模拟设备，仅用于开发验证。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if telemetry.connectionState != .connected {
                    Text("未检测到真实 CheeseCool 设备；风扇控制当前不可用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("正在等待首次状态更新。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private let visibleConfigurableMetrics: Set<MetricIdentifier> = [.fanRPM, .fanDuty, .socTemperature, .cpuLoad]

    private var deviceDiagnosticText: String {
        guard let diagnostics = model.hidDiagnostics else { return "正在查找真实设备" }
        return diagnostics.connected ? "已连接" : "设备未连接"
    }

    @ViewBuilder
    private func metricToggle(_ metric: MetricIdentifier) -> some View {
        Toggle(metric.displayName, isOn: Binding(
            get: { model.configuration.menuBar.visibleMetrics.contains(metric) },
            set: { model.setMetric(metric, visible: $0) }
        ))
        .accessibilityLabel("显示\(metric.displayName)")
    }

    private func unavailableMetric(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func autoCurveRow(_ index: Int) -> some View {
        let point = model.configuration.autoCurve[index]
        return HStack {
            Stepper(
                "\(Int(point.temperatureCelsius))°C",
                onIncrement: { model.setAutoCurvePoint(at: index, temperature: point.temperatureCelsius + 1) },
                onDecrement: { model.setAutoCurvePoint(at: index, temperature: point.temperatureCelsius - 1) }
            )
            Spacer()
            Stepper(
                "\(Int(point.duty))%",
                onIncrement: { model.setAutoCurvePoint(at: index, duty: point.duty + 1) },
                onDecrement: { model.setAutoCurvePoint(at: index, duty: point.duty - 1) }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("自动曲线节点 \(index + 1)")
    }

    private func stepperRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))\(unit)").monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func diagnosticRow(_ title: String, sample: MetricSample?) -> some View {
        LabeledContent(title) {
            if let sample {
                Text(sample.sourceStatus.displayName)
            } else {
                Text("等待首次采样").foregroundStyle(.secondary)
            }
        }
    }
}
