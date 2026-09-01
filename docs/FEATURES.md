# 功能说明

## 菜单栏

CheeseCool 使用 `NSStatusItem` 作为菜单栏应用，并采用 accessory activation policy，因此不显示 Dock 图标。可独立开关的指标包括：

- Fan RPM
- Fan Duty
- SoC Temp
- CPU Load

SoC Power 与 GPU 指标会按系统实际能力显示 unsupported/unavailable，不伪造数值。所有指标关闭时，主图标会自动保留，确保仍可打开菜单与设置。

菜单栏状态与设置页的风扇 RPM/设备状态以 1 秒周期刷新；温度与其他系统指标的慢速读取不会阻塞 HID 状态刷新。

## 设备与协议

- 正常运行设备：VID `0x1A86` / PID `0xFE01`。
- USB 产品名：`CheeseCool USB HID`。
- 传输：原生 `IOHID`，不依赖 `hidapi`。
- 协议：64-byte Protocol V1 帧。

连接失败时，客户端会按照配置的有限重连策略处理 disconnect/reconnect；应用重启会重新发现 FE01 并恢复控制，不需要 USB 重新插拔。

## 控制模式

- `MANUAL`：发送 host-controlled 模式和用户设置的 0–100% duty。
- `MAX`：请求 MCU 进入全速模式。
- `AUTO`：由 macOS 采集 SoC 温度、计算目标 duty，并执行 deadband、ramp 与 critical override。

0% 是 `MINIMUM_SPEED`，不等同于 FAN OFF。设备的 RPM 由 MCU 实际测量后回报。

## 异常与安全边界

- **disconnect/reconnect**：传输失败会关闭连接，使用有限重试；重新连接后恢复已配置的模式和占空比。
- **客户端重启**：应用启动时重新发现设备并同步状态；在通信中断后，MCU 独立保障风扇安全。
- **MCU failsafe**：30 秒没有 host activity 时，MCU 回退至固定 50% duty。正常主机控制恢复后可重新接管。
- **温度不可用**：AUTO 先保持最近有效请求值一小段 grace 时间；超过阈值后停止主机流量，把安全控制交给 MCU failsafe。

## Software DFU

客户端不支持软件触发 DFU。`0x08` 和 `0x0D` 永久 `RESERVED`，不存在进入 DFU 的 UI、API、原始命令通道或固件写入功能。引导加载程序与固件恢复不属于 macOS 客户端职责。
