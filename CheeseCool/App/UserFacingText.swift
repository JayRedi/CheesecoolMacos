import CheeseCoolCore

extension OperatingMode {
    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .manual: return "手动"
        case .max: return "全速"
        }
    }

    var productName: String {
        switch self {
        case .auto: return "自动（AUTO）"
        case .manual: return "手动（MANUAL）"
        case .max: return "全速（MAX）"
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

extension ConnectionState {
    var displayName: String {
        switch self {
        case .connected: return "已连接"
        case .disconnected: return "设备未连接"
        case .connecting: return "正在连接"
        case .unavailable: return "设备暂不可用"
        }
    }
}

extension ControlState {
    var displayName: String {
        switch self {
        case .idle: return "正在准备"
        case .autoActive: return "自动控制中"
        case .manualActive: return "手动控制中"
        case .maxActive: return "全速运行中"
        case .temperatureGrace: return "温度暂不可用，保持当前转速"
        case .temperatureUnavailable: return "温度暂不可用，已进入安全保护"
        case .deviceUnavailable: return "设备暂不可用"
        case .failsafeHandoff: return "安全模式"
        case .recovering: return "正在恢复连接"
        case .powerFault: return "电源故障"
        case .sleeping: return "系统睡眠中"
        case .stopped: return "已停止"
        }
    }

    var isCritical: Bool { self == .powerFault }
}

extension SensorSourceStatus {
    var displayName: String {
        switch self {
        case .ok: return "正常"
        case .unavailable: return "暂时不可用"
        case .unsupported: return "当前系统不支持"
        case .empty: return "无有效数据"
        case .error: return "读取失败"
        case .timeout: return "读取超时"
        case .stale: return "数据已过期"
        }
    }
}
