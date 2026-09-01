# 真机验证 Harness（仅开发用途）

`Tools/HardwareValidationHarness/main.swift` 由 `scripts/run-hardware-validation.sh` 临时编译到 `.build/HardwareValidation/HardwareValidationHarness`。它不是 Xcode App target 的成员，也不是打包脚本的输入，因此不会随 `CheeseCool.app` 或 DMG 发布。

Harness 仅调用产品实现：`HIDDeviceDiscovery`、`NativeHIDTransport`、`HIDHostDevice`、`ControlSession`、`AutoController` 和 `AppleSiliconTemperatureProvider`。它没有原始命令发送接口；`0x08` 与 `0x0D` 仍无法构造为 `ProtocolV1Command`。

可用受限命令：

```sh
scripts/run-hardware-validation.sh discover
scripts/run-hardware-validation.sh status
scripts/run-hardware-validation.sh manual 20
scripts/run-hardware-validation.sh max
scripts/run-hardware-validation.sh auto-soak 600
scripts/run-hardware-validation.sh failsafe-test
scripts/run-hardware-validation.sh reconnect-watch 5
```

`reconnect-watch` 在每轮明确要求物理拔插，并自动检查设备移除、重新发现、`PING` 和 `GET_STATUS`。`failsafe-test` 在设为 20% 后关闭生产控制会话，等待 31 秒且不产生任何 Protocol V1 流量，再用新的 `HIDHostDevice` 读取状态并验证回收控制权。重新连接的 `PING` 本身会刷新 MCU host activity，可能在 `GET_STATUS` 前清除 failsafe 标志；因此该流程以固件的固定 50% failsafe duty 作为可观察断言。

## 正常退出 failsafe 门禁

`Tools/GracefulAppTerminator/main.swift` 与 `scripts/gracefully-terminate-cheesecool.sh` 是独立的开发辅助工具。它通过 `NSRunningApplication.terminate()` 向 bundle identifier `org.cheesecool.CheeseCool` 发出正常 macOS 退出请求，轮询应用消失并输出 PID、方法和耗时；它不使用 UI 自动化、强制终止或信号杀进程。

为在不改动用户原设置的前提下建立临时的 `MANUAL / 20%` 运行状态，`Tools/Phase4BSettings/main.swift` 与 `scripts/phase4b-settings.sh` 会先备份 `~/Library/Application Support/CheeseCool/settings.json`，并在观察 failsafe 后从备份恢复。它们同样不属于任何发布 target。正常退出后，必须至少 31 秒不打开 HID 或发送 Protocol V1；首个状态读取会发送 `PING`，因此以报告的固定 50% duty（而不是读取时的 `failsafe` 标志）确认 MCU 已超时回退。
