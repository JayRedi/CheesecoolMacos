# macOS 客户端架构

## 运行时形态

`CheeseCool.app` 是由原生 `NSStatusItem` 支撑的 `LSUIElement` 配件型应用，没有常规的 Dock 图标。打开“设置”会创建承载 SwiftUI 的传统 AppKit `NSWindow`。系统中没有后台守护进程、特权辅助工具、Python 解释器、LaunchAgent 或持久 Shell 配置。

产品由 UI/应用目标和平台无关的 Swift 框架组成：

```text
AppCoordinator (@MainActor)
├── MenuBarManager (@MainActor, AppKit)
├── SettingsCoordinator (@MainActor, SwiftUI in NSWindow)
├── TelemetryStore (@MainActor)
├── SensorEngine (actor)
├── LifecycleManager (actor)
└── ControlSession (actor)
    ├── TemperatureSource
    ├── AutoController（纯确定性值状态）
    ├── HostDevice（异步协议）
    ├── MonotonicClock
    └── EventLog (actor, bounded)
```

`AppCoordinator` 负责组合依赖；不使用产品核心单例或可变全局状态。与 UI 绑定的状态由主 actor 隔离。有状态的后台组件使用 actor，并在有意义时让跨边界模型遵循 `Sendable`。

## 源码布局

```text
CheeseCool/
├── App/            应用入口与依赖组合
├── Core/           领域模型、AUTO 策略、会话、模拟、清单
├── Device/         HostDevice 与确定性的 FakeHostDevice
├── Sensors/        提供器协议、SensorEngine、模拟提供器
├── MenuBar/        NSStatusItem 控制器与可见性不变量
├── Settings/       SwiftUI 模型/视图与 AppKit 窗口协调器
├── Persistence/    ConfigStore 与 TelemetryStore
├── Lifecycle/      睡眠/唤醒/停止与登录项抽象
├── Diagnostics/    有界的结构化 EventLog
└── Resources/      未来的原生资源
```

## 时钟与调度

所有控制决策均使用注入的单调时钟。`SystemMonotonicClock` 读取系统运行时间；`ManualClock` 仅在测试或模拟显式要求时推进。保活年龄、模拟 MCU 看门狗、温度宽限期/过期时间、重连退避、事件时间戳和长时间模拟均源于该时钟。测试不会通过休眠来推进产品状态。

应用循环只负责安排何时调用 `tick()`；不会决定保活或恢复工作是否到期。

## 生命周期

- `prepareForSleep()` 会断开连接并停止所有主机通信，以便 MCU 接管控制权。
- `resumeFromSleep()` 会重置有界重连状态，并标记所选模式以同步恢复。
- `stop()` 会关闭设备，并永久将会话迁移到 `STOPPED`。
- 正常退出会取消应用循环、等待 `stop()` 完成，然后终止应用。

生产环境的睡眠/唤醒通知接线及真实传输/传感器实现属于第二阶段工作。

## 登录项

`LoginItemManaging` 隔离登录项注册。仅运行中的应用使用 `SMAppServiceLoginItemManager`；测试使用 `FakeLoginItemManager`，不会更改开发机登录项。不使用 LaunchAgent plist 或 Shell 命令。
