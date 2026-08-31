# 第二阶段验证

已于 2026-08-31 在 Apple Silicon arm64 上验证。基线：分支 `macos-client-foundation`，提交 `dd0106cc320fd43d4b1b63df242e97708546307a`；实现分支：`macos-client-metrics`。

## 自动化测试与构建

- XCTest：61 通过，0 失败（50 个 `CheeseCoolCoreTests`，11 个 `CheeseCoolTests`）。
- Debug `CheeseCool`：通过。
- Release `CheeseCool`：通过。
- Release `CheeseCool Uninstaller`：通过。
- 三个可执行文件均为仅 arm64 的 Mach-O 文件。
- Release 应用不包含 Python 工件/运行时、意外的 entitlement 或隐私用途描述键。`LSUIElement=true` 保持不变。

## 原生提供器审计

- IOKit 枚举在验证用 Mac 上找到 24 个仅匹配 `PMU/PMU2 tdie*` 的有效传感器。初始只读探测报告约 30.3–34.9°C。未接受 `tdev`、`tcal`、电池、NAND 或推断出的 CPU/GPU 映射。
- `powermetrics` 会报告估算的子系统功耗，并拒绝非 root 执行（`powermetrics must be invoked as the superuser`）。SDK 中不存在公开的 `IOReport.framework` 客户端 API，因此数值化 SoC 功耗不受支持。
- Metal 阶段计数器描述某个应用提交的工作，并非可靠的整机 GPU 利用率。其他系统范围计数器私有或风险过高，因此 GPU 负载不受支持。

## 五分钟真实演练

Debug 应用使用固定的 1 秒单调调度运行了 300.052 秒有界演练。在仅控制 `FakeHostDevice` 的情况下，它在 `/tmp/cheesecool-phase2-dry-run.json` 中生成了 300 条记录。

| 测量项 | 结果 |
| --- | --- |
| 温度有效 | 300 / 300 |
| 温度范围 | 32.851–37.969°C |
| 温度状态 | COOL 232；NORMAL 68 |
| 温度读取延迟 | 最小 17.035ms；平均 20.997ms；最大 27.263ms |
| CPU 有效 | 299 / 300（首个累积样本按设计不可用） |
| CPU 范围 | 11.677–33.534% |
| CPU 读取延迟 | 最小 0.006ms；平均 0.030ms；最大 0.318ms |
| AUTO 请求占空比 | 0–0% |
| 模拟设备占空比 | 0–0% |
| 模拟 RPM | 345–345 RPM |
| 模拟设备命令 | 共 58 条 |
| SoC 功耗 / GPU 数值 | 0 / 0，明确不支持 |
| 错误 / 传感器丢失 | 0 / 0 |

样本间隔为 0.938–1.064 秒，最后一个样本位于 299.081 秒。占空比没有振荡，没有数值离开 0–100% 范围，五分钟内 58 条命令符合初始同步加上固定保活的预期，不构成命令洪泛。

运行期间两次只读进程快照显示，Debug 应用的瞬时 CPU 均为 0.0%，RSS 分别约为 34MB 和 31MB；内存未随时间增长。提供器路径不会创建指标子进程。

## 权限与硬件结果

所需的面向用户 macOS 权限：无。不会请求屏幕录制、麦克风、摄像头、辅助功能、完全磁盘访问或定位权限。未引入辅助工具/root 设计。

真实 CheeseCool USB/PCB 操作、协议命令、DFU、刷写、OpenOCD、WCH-LinkE、固件变更和硬件睡眠操作：**0**。
