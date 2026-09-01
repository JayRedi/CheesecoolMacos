# 安装

Phase 5A 的产物是 **LOCAL / DEVELOPMENT PACKAGE**，使用 ad-hoc 签名但未使用 Developer ID 或公证，不能宣称为 Apple trusted/notarized 公开发布包。首次打开若被 Gatekeeper 拦截，请在“系统设置 → 隐私与安全性”中选择“仍要打开”；不要使用 `xattr -dr com.apple.quarantine` 作为安装方式。

安装流程保持 macOS 原生习惯：打开 `CheeseCool-local-development.dmg`，将 `CheeseCool.app` 拖到 `Applications`，完成。DMG 中只含应用和指向 `/Applications` 的快捷方式；不使用 PKG、终端脚本、特权辅助工具或首次启动安装器。

应用可从任意位置运行。完整卸载会基于启动它的已验证应用包位置，不会把应用强制复制到 `/Applications`。
