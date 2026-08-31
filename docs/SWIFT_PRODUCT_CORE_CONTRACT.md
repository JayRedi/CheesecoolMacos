# Swift 产品核心契约

## 行为基准

冻结的行为由分支 `product-core-simulation` 上本地 Python Product Core 的提交 `50beb2500937bd86aee1478bc1c295fc673b9efb` 移植而来。相关基准源码为 `tools/temperature_state`、`tools/auto_control`、`tools/cheesecool_core` 和 `docs/HOST_PRODUCT_CORE.md`。

Python 仅作为开发行为基准。`CheeseCool.app` 与 `CheeseCoolCore` 既不执行也不内嵌 Python。`PythonOracleV1.json` 捕获代表性的曲线、零占空比、看门狗和失效保护输出，Swift 测试会与其比较。

## 模式与设备语义

- `AUTO`：归一化的 `TemperatureSample` 经过 `AutoController`，产生整数占空比命令。
- `MANUAL`：精确恢复配置的 0 至 100 整数占空比。
- `MAX`：调用 `HostDevice.setMax()`，而非普通的 `setDuty(100)`。
- `0%`：表示 `MINIMUM_SPEED`；在 schema v1 中 `physicalFanOffSupported` 永远为 `false`。

`HostDevice` 仅拥有传输能力：连接、断开连接、连接查询、状态读取、主机控制模式、MAX 模式、精确占空比和关闭。它不包含 AUTO 曲线、温度策略或 UI 行为。

## AUTO 策略

| 温度 | 原始占空比 |
| --- | ---: |
| ≤40°C | 0% |
| 50°C | 25% |
| 60°C | 40% |
| 70°C | 60% |
| 80°C | 80% |
| ≥90°C | 100% |

中间值采用线性插值。控制回差为 2 个百分点，升速为每秒 20 个百分点，降速为每秒 8 个百分点。`CRITICAL` 样本会绕过控制回差和升降速限制，立即请求 100%。这些值是当前行为基线，而非最终物理调校。

## 温度丢失

此契约仅适用于 AUTO：

1. 最后一个有效样本后的 3 秒内（含 3 秒），状态为 `TEMPERATURE_GRACE`，并保持最后请求的占空比。
2. 3 秒后，状态为 `TEMPERATURE_UNAVAILABLE`，会话完全不执行 `HostDevice` 调用——包括状态、模式、占空比和保活。
3. 在没有通信流量的情况下，模拟 MCU 的 30 秒看门狗会自主选择 50% 的失效保护。
4. 恢复流程为：读取状态 → 主机控制模式 → 重新计算当前 AUTO 占空比 → 验证状态读取。

## 保活、失败与恢复

不会重复发送未改变的占空比。如果没有其他有效命令，每 5 秒应发送一次显式 `GET_STATUS` 保活。

传输失败会进入 `DEVICE_UNAVAILABLE`，仅断开一次，并使用有界指数重连。重连流程为：连接 → 读取状态 → 恢复所选模式 → 验证状态。AUTO 会重新计算当前占空比，MANUAL 恢复用户的精确占空比，MAX 恢复设备 MAX 模式。

报告的失效保护会使用同一套“状态/模式/占空比/验证”流程明确协调。电源故障会锁定为 `POWER_FAULT`，在显式确认前阻止常规设备通信；如果恢复期间状态仍报告故障，则再次锁定。

## FakeHostDevice

确定性的模拟设备在不使用 HID 或 IOKit 的情况下提供 Protocol V1 产品语义：

- 精确的 0–100 占空比，以及约 345–2500 RPM 映射；
- HOST_CONTROLLED 与专用 MAX 模式；
- 30 秒看门狗和 50% 自主失效保护；
- USB 丢失、连接/命令/读取失败、超时、重启、断开/重连和电源故障；
- 可配置的有界命令历史（默认 512 条）；
- 虚拟单调时间。

## 遥测与诊断

`TelemetrySnapshot` 保存温度/状态/有效性、所选模式、控制状态、原始 AUTO 占空比、请求/最后发送/设备占空比、RPM、失效保护、电源故障、连接状态、最后命令及其年龄、最后错误、原因和物理风扇停转支持。`EventLog` 默认保留 128 条记录，满时丢弃最旧记录。
