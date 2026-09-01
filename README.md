# CheeseCool for macOS

CheeseCool 是面向 Apple Silicon Mac 的原生菜单栏风扇控制客户端。它通过 USB HID 与 CheeseCool 控制器通信，显示实时风扇状态，并提供手动、全速与基于 SoC 温度的自动调速。

## 支持平台

- Apple Silicon（`arm64`）Mac。
- 应用部署目标为 macOS 13.0。
- 使用 Swift 6、AppKit、SwiftUI 与系统 IOKit；不需要 Python、`hidapi`、后台 daemon、特权 helper 或 Shell 环境修改。

## 主要功能

- 原生 `NSStatusItem` 菜单栏应用，无 Dock 图标。
- 实时风扇 RPM、请求/实际占空比、设备连接状态；RPM 与设备状态正式刷新周期为 1 秒。
- `MANUAL`：设置 0–100% 请求占空比；`0%` 表示设备的最低安全转速（`MINIMUM_SPEED`），不是物理停转。
- `MAX`：请求控制器全速运行。
- `AUTO`：读取 Apple Silicon SoC 温度，按曲线、2% deadband 和升降速限制自动计算占空比。
- MCU 30 秒 host timeout failsafe：主机停止通信后，控制器回退到固定 50% 安全占空比。
- 原生 `IOHID` 通信，仅匹配 CheeseCool 正常运行设备 VID `0x1A86` / PID `0xFE01`（`CheeseCool USB HID`），使用 64-byte Protocol V1 帧。
- 内嵌完整卸载器，可删除应用、用户配置、日志和登录项。

软件触发 DFU 不受支持。Protocol V1 的 `0x08` 与 `0x0D` 永久保留；客户端没有进入 DFU 的 UI 或 API，也不负责引导加载程序和固件恢复。

## 安装

本仓库可生成本地、未签名的开发 DMG；它不是 Apple 签名或公证后的正式发行包。构建完成后打开 `dist/CheeseCool.dmg`，将 `CheeseCool.app` 拖入“应用程序”即可。

详细步骤见[安装说明](docs/INSTALLATION.md)与[构建说明](docs/BUILD.md)。

## 本地构建与测试

在仓库根目录执行：

```sh
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test

scripts/package-local-dmg.sh
```

更多命令、输出位置和常见问题见[构建说明](docs/BUILD.md)。

## 卸载

在应用的“关于”页选择“完全卸载”，或运行打包应用内的 `CheeseCool Uninstaller.app`。卸载器会先展示清理范围，须确认后才执行。详见[卸载说明](docs/UNINSTALLATION.md)。

## 项目状态

macOS 客户端已完成真实 FE01 HID 通信、控制模式、MCU failsafe、应用正常退出后的 failsafe、重连和本地开发 DMG 的验证。测试与构建结果见[硬件验证报告](docs/HARDWARE_VALIDATION.md)。本仓库当前不提供签名、公证或正式 Release 发布流程。

## 文档

- [构建环境与命令](docs/BUILD.md)
- [功能说明](docs/FEATURES.md)
- [AUTO 自动调速](docs/AUTO_CONTROL.md)
- [真机验证结果](docs/HARDWARE_VALIDATION.md)
- [HID 传输](docs/HID_TRANSPORT.md)
- [Protocol V1 映射](docs/PROTOCOL_V1_SWIFT.md)
- [开发期硬件验证工具](docs/HARDWARE_VALIDATION_HARNESS.md)
- [配置](docs/CONFIGURATION.md)
- [安装](docs/INSTALLATION.md)
- [完整卸载](docs/UNINSTALLATION.md)
- [贡献指南](CONTRIBUTING.md)
- [安全报告](SECURITY.md)

## 第三方依赖与许可证

当前工程没有 Swift Package、CocoaPods、Carthage 或 vendored 第三方源码；运行时依赖均为 macOS 系统框架。详见[第三方声明](THIRD_PARTY_NOTICES.md)。

本项目以 [MIT License](LICENSE) 开源；[中文参考](LICENSE.zh-CN.md)仅帮助理解，法律效力以根目录英文原文为准。
