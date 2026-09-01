# 贡献指南

## 环境准备

请使用 Apple Silicon Mac、macOS 13 或更高版本与当前 Xcode。克隆仓库后按[构建说明](docs/BUILD.md)运行 Debug build 和 XCTest；不需要 Python、`hidapi`、后台 daemon 或特权 helper。

## 分支与编码

从当前主线创建描述明确的分支，例如 `fix/rpm-refresh`。保持 Swift 6 并发检查通过，优先修改现有产品层而非引入新运行时依赖。用户可见文本与项目说明应使用中文；类名、Apple API、协议命令和命令行参数保留技术英文名称。

Protocol V1 的 `0x08` 与 `0x0D` 是永久保留值，禁止重新使用、重新编号或新增任何软件 DFU UI/API。

## 测试与真机工具

提交前必须运行相关 XCTest；影响控制、HID、生命周期或配置的改动应运行完整应用测试。`Tools/HardwareValidationHarness` 及其脚本仅用于取得授权后的开发期真机验证，必须使用产品的受限传输接口，不能增加原始命令发送、DFU 或固件写入能力。其二进制输出不得提交或打包。

## Pull Request

PR 请说明问题、实现方式、测试命令和用户可见影响。不要将无关格式化、生成文件或个人环境修改混入同一 PR。涉及真实设备时，说明是否已使用模拟设备、真机及操作权限范围。

不要提交构建产物、`dist/` 内容、DerivedData、证书、私钥、provisioning profile、`.env` 或任何用户配置与日志。
