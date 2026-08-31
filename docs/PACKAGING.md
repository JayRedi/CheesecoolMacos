# 本地 DMG 打包

执行：

```sh
scripts/package-local-dmg.sh
```

脚本使用 `xcodebuild` 构建 arm64 Release 主应用和卸载器，使用 `ditto` 将卸载器嵌入 `CheeseCool.app/Contents/Helpers/`，再使用 `hdiutil` 创建拖拽安装 DMG。产物位于被 Git 忽略的 `dist/`：Release 应用、`CheeseCool.dmg` 与 `.sha256`。

脚本会检查主/卸载器 bundle ID、arm64、AppIcon 和 Python runtime 缺失。签名顺序在 Phase 5B 为：嵌套 framework → 内嵌卸载器 → 主应用 → DMG 公证。
