# macOS 开源分发说明

## 当前分发模式

GitHub 上的 macOS 二进制采用 whole-bundle ad-hoc 签名：

- 完成最终 bundle 组装后，按 inside-out 顺序签名嵌套 framework、helper 和 app。
- 使用 `codesign --force --sign - --timestamp=none`。
- 对最终 app、staging 副本、挂载 DMG 副本和安装等效副本执行 `codesign --verify --deep --strict`。
- 不使用 Developer ID Application，不执行 Apple notarization 或 stapler。

因此当前包是 **Ad-hoc signed、Not notarized、GitHub direct distribution**。ad-hoc 签名可以保证 bundle 内部签名一致性，但不代表 Apple trusted/notarized application。

## 验证门禁

`scripts/package-local-dmg.sh` 每次执行都会完成：

1. 构建 Release `CheeseCool.app` 与 `CheeseCool Uninstaller.app`。
2. 完成所有 bundle 复制后，使用 `scripts/sign-and-verify-app.sh` 进行最终 ad-hoc 签名。
3. 在 DMG staging、挂载后的 DMG 以及临时安装等效目录中进行 strict 验证。
4. 仅在所有签名门禁通过后生成 `dist/CheeseCool.dmg` 和 SHA-256 文件。

任一 `codesign --verify --deep --strict` 失败都会使脚本退出非零，并停止认可发布产物。`HardwareValidationHarness` 源码可以保留在仓库中，但其二进制不会进入 App 或 DMG。

## 首次打开

由于没有 Developer ID 和公证，首次打开时 macOS Gatekeeper 可能阻止启动。用户可在“系统设置 → 隐私与安全性”中查看提示并选择“仍要打开”。

不要将 `xattr -dr com.apple.quarantine` 作为正式安装步骤；本项目不会用删除 quarantine 的方式制造验证通过。

## 未来正式发布

如果未来需要 Apple 信任链分发，需要 Apple Developer Program、Developer ID Application 签名、notarytool 公证、staple 和 Gatekeeper 验证。这些不属于当前开源开发包，当前仓库也不保存签名证书或公证凭据。
