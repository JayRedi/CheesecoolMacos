import CheeseCoolCore

extension OperatingMode {
    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .manual: return "手动"
        case .max: return "全速"
        }
    }
}

extension MetricIdentifier {
    var displayName: String {
        switch self {
        case .fanRPM: return "风扇转速"
        case .fanDuty: return "风扇占空比"
        case .socTemperature: return "芯片温度"
        case .cpuLoad: return "处理器负载"
        case .socPower: return "芯片功耗"
        case .gpuLoad: return "图形处理器负载"
        }
    }
}
