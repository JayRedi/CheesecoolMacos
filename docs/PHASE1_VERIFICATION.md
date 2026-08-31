# 第一阶段验证

已于 2026-08-31 在 macOS 26.6.2 (25G83)、arm64、Xcode 26.6 (17F113)、Swift 6.3.3 和 Git 2.55.0 环境中验证。

## 构建关卡

下列命令形式均在全新的临时 DerivedData 目录中，以 `CODE_SIGNING_ALLOWED=NO` 成功完成：

```sh
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath <temporary-derived-data> CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath <temporary-derived-data> CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CheeseCool.xcodeproj -scheme 'CheeseCool Uninstaller' -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath <temporary-derived-data> CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath <temporary-derived-data> CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath <temporary-derived-data> CODE_SIGNING_ALLOWED=NO test-without-building
```

结果：Debug 通过、Release 通过、卸载器 Release 通过。两个应用可执行文件均为 arm64 Mach-O 文件。应用 Info.plist 解析为 `LSMinimumSystemVersion=13.0` 和 `LSUIElement=true`。嵌入的 `CheeseCoolCore.framework` 安装名称与使用方链接均通过 `@rpath` 解析。

## 测试

最终 xcresult 摘要报告：

- 总计：37
- 通过：37
- 失败：0
- 跳过：0
- 预期失败：0

`CheeseCool` scheme 包含 `CheeseCoolCoreTests` 和 `CheeseCoolTests`，因此结果覆盖核心行为以及 AppKit 菜单栏可见性策略。

## 确定性的 24 小时模拟

```json
{
  "durationSeconds": 86400,
  "ticks": 86400,
  "totalDeviceCommands": 17641,
  "connectAttempts": 19,
  "maxEventLogSize": 67,
  "maxDeviceLogSize": 512,
  "invalidDutyCount": 0,
  "unhandledErrorCount": 0,
  "finalControlState": "AUTO_ACTIVE",
  "finalConnectionState": "CONNECTED",
  "commandFlood": false,
  "deadlock": false,
  "endlessReconnect": false,
  "passed": true
}
```

该模拟使用 `ManualClock`，并未等待真实的 24 小时。它覆盖了温度变化与失效、AUTO/MANUAL/MAX 转换、断开/重连、MCU 失效保护、电源故障恢复、睡眠/唤醒、重启、命令失败以及配置加载/保存行为。

## 硬件与外部影响

HID/USB 设备访问、DFU、固件刷写、OpenOCD、WCH-LinkE 和硬件睡眠操作的计数均为零。固件仓库仅以只读方式访问。没有创建远程仓库、没有推送、测试没有更改开发者登录项，也没有创建持久 Shell 环境变量。
