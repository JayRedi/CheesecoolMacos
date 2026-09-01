# Phase 4B 真机验证结果

本报告记录 macOS 客户端在真实 CheeseCool 正常运行设备上的最终验证结论。验证对象为 VID `0x1A86` / PID `0xFE01`、产品名 `CheeseCool USB HID`、序列号 `CC-USB-001` 的设备；验证使用产品 `NativeHIDTransport`、`HIDHostDevice` 与受限开发期 Harness，不包含 DFU、固件写入或 USB 重连以外的硬件修改。

## 设备与状态

- FE01 discovery：通过；原生 `IOHID` 发现并打开真实设备。
- `GET_STATUS`：通过；设备报告 `usbConfigured=true`、无 power fault，并返回 firmware `1.0.0`。
- 客户端重启与重新发现：通过；无需 USB 拔插或 MCU 重置即可重新接管。

## 控制模式与实测结果

`MANUAL` 模式已依次验证 0%、20%、40%、60%、80%、100% 的请求与回报占空比。实测 RPM 分别为约 330、570、1320、1860、2340、2760 RPM；0% 保持最低安全转速，不代表风扇停转。

`MAX` 模式已验证为 100% duty，实测约 2730 RPM。`AUTO` 预检查读取到有效 SoC 温度并产生预期 duty；10 分钟 AUTO soak 完成，期间未观察到连接或温度有效性错误。

## 安全与生命周期

- MCU failsafe：主机控制停止超过 30 秒后，设备回退为约 50% duty；观察到约 1620 RPM。后续主机控制可恢复。
- 正常应用退出：真实 Release `CheeseCool.app` 通过 `NSRunningApplication.terminate()` 正常退出，终止请求被接受且进程在约 0.094 秒内消失。静默 34 秒后观察到 50% failsafe duty；重启应用后设备恢复健康控制。
- 物理重连：`reconnect-watch 5` 自动观察到 5/5 次设备移除和重新发现；每次均成功完成 `PING` 与 `GET_STATUS`。

读取 failsafe 后的第一个 `PING` 会刷新 MCU host activity，因此 `GET_STATUS` 读取时 `failsafe` 标志可能已清除。验收以静默窗口后的固定 50% duty 和对应风扇行为为准。

## 构建与测试

- 核心 XCTest：通过。
- 应用 XCTest：通过。
- Release `CheeseCool.app`：构建通过。
- Release `CheeseCool Uninstaller.app`：构建通过。
- 本地未签名 DMG：构建与完整性校验通过；内容审计确认包含主应用和内嵌卸载器，且不包含 `HardwareValidationHarness`。

这些结论适用于当时的验证硬件与本地开发环境；DMG 为未签名开发包，不构成 Apple 签名、公证或正式发布声明。
