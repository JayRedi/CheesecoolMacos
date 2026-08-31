# CheeseCool for macOS

CheeseCool 是一款面向 Apple Silicon Mac 的原生菜单栏客户端。当前包含产品核心、真实系统指标采样、原生菜单栏、SwiftUI 设置界面、原生 IOHID Protocol V1 传输层，以及仅演练的卸载器基础。

## 平台与安全边界

- 仅支持 Apple Silicon（`arm64`）；应用最低部署目标为 macOS 13.0。
- 使用 Swift 6、AppKit 与 SwiftUI；不包含 Python 运行时、守护进程、特权辅助工具、LaunchAgent 或 Shell 环境修改。
- `0%` 占空比表示 `MINIMUM_SPEED`（模拟设备中约为 345 RPM），绝不表示物理停转。
- 运行时仅被动匹配 CheeseCool 正常运行设备（VID `0x1A86` / PID `0xFE01`）；DFU PID `0x8035` 不会被发现、打开或写入。
- Release 默认使用原生 HID 路径。模拟设备只可通过 `--simulation` 或既有的阶段演练参数启用，界面会明确标为“模拟设备”。本阶段没有对实际硬件执行验证、刷写、DFU、OpenOCD 或 WCH-LinkE 操作。

## 产品

| Xcode 目标 | 产品 | 包标识符 |
| --- | --- | --- |
| `CheeseCool` | `CheeseCool.app` | `org.cheesecool.CheeseCool` |
| `CheeseCoolCore` | 原生 Swift 框架 | `org.cheesecool.CheeseCoolCore` |
| `CheeseCoolTests` | 应用单元测试 | `org.cheesecool.CheeseCoolTests` |
| `CheeseCoolCoreTests` | 核心单元测试 | `org.cheesecool.CheeseCoolCoreTests` |
| `CheeseCool Uninstaller` | `CheeseCool Uninstaller.app` | `org.cheesecool.CheeseCoolUninstaller` |

项目不存储 Apple Developer Team ID。本地 CLI 验证会禁用代码签名。

## 构建与测试

```sh
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCoolCore -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test
xcodebuild -project CheeseCool.xcodeproj -scheme 'CheeseCool Uninstaller' -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

`CheeseCool` 测试 scheme 会运行两个测试目标；其中核心测试套件包含确定性的 86,400 个时钟周期模拟和 Protocol V1 的帧、校验、异常、热插拔模拟测试。

## 第一阶段审计环境

- macOS 26.6.2 (25G83)
- 架构：arm64
- Xcode 26.6 (17F113)
- Swift 6.3.3
- xcodebuild：`/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild`
- Git 2.55.0

第一阶段开始时，实际项目工作区为空，可安全初始化。只读检查了本地固件提交 `50beb2500937bd86aee1478bc1c295fc673b9efb` 中的 Python 行为基准；没有修改固件工作区。

## 文档

- [macOS 客户端架构](docs/MACOS_CLIENT_ARCHITECTURE.md)
- [Swift 产品核心契约](docs/SWIFT_PRODUCT_CORE_CONTRACT.md)
- [菜单栏契约](docs/MENU_BAR_CONTRACT.md)
- [HID 传输](docs/HID_TRANSPORT.md)
- [Protocol V1 Swift 映射](docs/PROTOCOL_V1_SWIFT.md)
- [设备连接与模拟模式](docs/DEVICE_CONNECTION.md)
- [配置](docs/CONFIGURATION.md)
- [卸载契约](docs/UNINSTALL_CONTRACT.md)
- [Phase 3 UI 与产品打磨](docs/PHASE3_UI_PRODUCT_POLISH.md)
