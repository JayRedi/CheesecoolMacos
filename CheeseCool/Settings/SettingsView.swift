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

    public init(model: SettingsViewModel) {
        self.model = model
        self._selectedTab = State(initialValue: .general)
    }

    init(model: SettingsViewModel, initialTab: SettingsTab) {
        self.model = model
        self._selectedTab = State(initialValue: initialTab)
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                general
                    .tabItem { Label("常规", systemImage: "gear") }
                    .tag(SettingsTab.general)
                menuBar
                    .tabItem { Label("菜单栏", systemImage: "menubar.rectangle") }
                    .tag(SettingsTab.menuBar)
                fan
                    .tabItem { Label("风扇", systemImage: "fan") }
                    .tag(SettingsTab.fan)
                advanced
                    .tabItem { Label("高级", systemImage: "slider.horizontal.3") }
                    .tag(SettingsTab.advanced)
                about
                    .tabItem { Label("关于", systemImage: "info.circle") }
                    .tag(SettingsTab.about)
            }
            .padding(16)

            Divider()

            HStack {
                Button("恢复默认值") { model.reset() }
                Spacer()
                Text("更改会自动保存")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .frame(minWidth: 680, minHeight: 540)
    }

    private var general: some View {
        Form {
            Toggle("登录时启动", isOn: $model.configuration.launchAtLogin)
            Picker("运行模式", selection: $model.configuration.operatingMode) {
                ForEach(OperatingMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Toggle("恢复上次模式", isOn: $model.configuration.restorePreviousMode)
            Picker("刷新间隔", selection: $model.configuration.refreshInterval) {
                Text("1 秒").tag(TimeInterval(1))
                Text("2 秒").tag(TimeInterval(2))
                Text("5 秒").tag(TimeInterval(5))
            }
        }
    }

    private var menuBar: some View {
        Form {
            Toggle(
                "指标可见时显示 CheeseCool 主图标",
                isOn: $model.configuration.menuBar.mainIconPreferredVisible
            )
            Section("指标") {
                ForEach(MetricIdentifier.allCases, id: \.self) { metric in
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(metricTitle(metric), isOn: metricBinding(metric))
                            .disabled(model.isPermanentlyUnsupported(metric))
                        if let sample = model.sample(for: metric),
                           sample.sourceStatus == .unsupported {
                            Text(sample.errorReason ?? "当前系统不支持此指标")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("排列顺序") {
                ForEach(Array(model.configuration.menuBar.metricOrder.enumerated()), id: \.element) {
                    Text("\($0.offset + 1). \(metricTitle($0.element))")
                }
            }
            Text("CheeseCool 始终至少保留一个可交互的菜单栏入口。")
                .foregroundStyle(.secondary)
        }
    }

    private var fan: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("手动控制") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text("占空比")
                                .frame(width: 76, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { Double(model.configuration.manualDuty) },
                                    set: { model.configuration.manualDuty = Int($0.rounded()) }
                                ),
                                in: 0...100,
                                step: 1
                            )
                            Text("\(model.configuration.manualDuty)%")
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                        Text("0% 表示最低转速，不代表关闭风扇。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("调节参数") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        parameterRow(
                            title: "控制回差",
                            value: $model.configuration.deadband,
                            unit: "%"
                        )
                        parameterRow(
                            title: "上升速率",
                            value: $model.configuration.rampUpPerSecond,
                            unit: "%/秒"
                        )
                        parameterRow(
                            title: "下降速率",
                            value: $model.configuration.rampDownPerSecond,
                            unit: "%/秒"
                        )
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("自动模式曲线") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("节点")
                            Text("温度")
                            Text("占空比")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Divider()
                            .gridCellUnsizedAxes(.horizontal)

                        ForEach(model.configuration.autoCurve.indices, id: \.self) { index in
                            GridRow {
                                Text("\(index + 1)")
                                    .frame(width: 44, alignment: .leading)
                                HStack(spacing: 6) {
                                    TextField(
                                        "温度",
                                        value: curveTemperatureBinding(index),
                                        format: .number
                                    )
                                    .labelsHidden()
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 72)
                                    Text("°C")
                                }
                                HStack(spacing: 6) {
                                    TextField(
                                        "占空比",
                                        value: curveDutyBinding(index),
                                        format: .number
                                    )
                                    .labelsHidden()
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 72)
                                    Text("%")
                                }
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var advanced: some View {
        Form {
            Section("传感器状态") {
                diagnosticRow("SoC 温度", sample: model.metrics?.socTemperature)
                diagnosticRow("CPU 负载", sample: model.metrics?.cpuLoad)
                diagnosticRow("SoC 功耗", sample: model.metrics?.socPower)
                diagnosticRow("GPU 负载", sample: model.metrics?.gpuLoad)
            }
            if let metrics = model.metrics, metrics.temperatureSensorCount > 0 {
                LabeledContent("温度来源") {
                    Text("\(metrics.temperatureSensorCount) 个 PMU/PMU2 tdie 传感器")
                }
            }
            Button("清除日志") { model.clearLogs() }
        }
    }

    private var about: some View {
        VStack(spacing: 12) {
            Image(systemName: "fan.fill").font(.system(size: 48))
            Text("CheeseCool").font(.title)
            Text("版本 0.1.0")
            Text("架构：arm64")
            Text("硬件通信：将在后续 HID 阶段实现")
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
        metric.displayName
    }

    @ViewBuilder
    private func diagnosticRow(_ title: String, sample: MetricSample?) -> some View {
        LabeledContent(title) {
            if let sample {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(statusTitle(sample.sourceStatus))
                    Text(sample.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("等待首次采样")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusTitle(_ status: SensorSourceStatus) -> String {
        switch status {
        case .ok: return "正常"
        case .unavailable: return "暂时不可用"
        case .unsupported: return "不支持"
        case .empty: return "无有效数据"
        case .error: return "错误"
        case .timeout: return "超时"
        case .stale: return "数据已过期"
        }
    }

    private func parameterRow(
        title: String,
        value: Binding<Double>,
        unit: String
    ) -> some View {
        GridRow {
            Text(title)
                .frame(width: 92, alignment: .leading)
            TextField(title, value: value, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit)
                .foregroundStyle(.secondary)
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
