# macOS 构建说明

## 环境

- 硬件：Apple Silicon（`arm64`）Mac。
- 运行目标：macOS 13.0 或更高版本；该值来自工程的 `MACOSX_DEPLOYMENT_TARGET`。
- Swift：工程设置为 Swift 6.0。
- Xcode：本仓库已使用 Xcode 26.6（17F113）验证。工程未声明独立的最低 Xcode 版本；请使用能够构建 Swift 6 和 macOS 13 SDK target 的当前 Xcode。
- 工程：`CheeseCool.xcodeproj`。
- schemes：`CheeseCool`、`CheeseCoolCore`、`CheeseCool Uninstaller`。

项目只使用 macOS SDK 系统框架，不需要 Python runtime、`hidapi` runtime、后台 daemon 或 privileged helper。

## Debug 与 Release

以下命令均从仓库根目录执行。`CODE_SIGNING_ALLOWED=NO` 适用于本地未签名验证。

```sh
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

xcodebuild -project CheeseCool.xcodeproj -scheme 'CheeseCool Uninstaller' \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

主应用输出为 `.build/DerivedData/Build/Products/<Configuration>/CheeseCool.app`；卸载器输出为同目录的 `CheeseCool Uninstaller.app`。

## XCTest

```sh
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCoolCore \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test

xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test
```

第二条命令会运行应用与核心测试目标。测试结果位于 `.build/DerivedData/Logs/Test/`。

## 本地 DMG

```sh
scripts/package-local-dmg.sh
```

脚本会构建 Release 主应用和卸载器，将卸载器嵌入主应用后生成 `dist/CheeseCool.dmg` 与 `dist/CheeseCool.dmg.sha256`。这是本地、未签名、未公证的开发包，不应描述为正式 Apple 发布包。

## HardwareValidationHarness

```sh
scripts/run-hardware-validation.sh discover
scripts/run-hardware-validation.sh status
scripts/run-hardware-validation.sh reconnect-watch 5
```

该工具编译到 `.build/HardwareValidation/`，仅用于已获授权的开发期真机验证。它不属于 Xcode App target，不会进入 Release App 或 DMG。完整约束见[开发期硬件验证工具](HARDWARE_VALIDATION_HARNESS.md)。

## 常见问题

- **找不到设备**：确认系统中枚举到 VID `0x1A86` / PID `0xFE01` 的 `CheeseCool USB HID`；客户端不会连接 DFU 或恢复设备。
- **架构不匹配**：确认 destination 包含 `arch=arm64`，且在 Apple Silicon Mac 上构建。
- **测试服务无法连接**：关闭卡住的 Xcode/xctest 进程后重试；命令行测试需要 macOS 的测试服务可用。
- **本地 DMG 无法打开**：它未签名、未公证；这是本地开发验证限制，不是构建错误。
- **不应提交的输出**：`.build/`、`dist/`、DerivedData、测试日志与 Harness 二进制均由 `.gitignore` 排除。
