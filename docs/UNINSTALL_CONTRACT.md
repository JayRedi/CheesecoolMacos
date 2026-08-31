# 卸载契约

`CheeseCool Uninstaller.app` 是独立的原生目标，并作为 `CheeseCool.app/Contents/Helpers/` 中的辅助应用随 DMG 一起交付。主应用在用户确认后先注销登录启动项，再将卸载器复制到受控临时目录、传递主进程 PID 并退出；卸载器只会在主进程退出（最长等待 8 秒）后执行清理。

最终清理边界由清单以及以下特定于 bundle 的标准位置组成：

- `/Applications/CheeseCool.app`
- `~/Library/Application Support/CheeseCool`
- `~/Library/Caches/org.cheesecool.CheeseCool`
- `~/Library/Logs/CheeseCool`
- `~/Library/Preferences/org.cheesecool.CheeseCool.plist`
- `~/Library/Saved Application State/org.cheesecool.CheeseCool.savedState`
- Application Support 下由 CheeseCool 所有的运行时诊断信息
- `org.cheesecool.CheeseCool` 登录项注册

清单仅跟踪由 CheeseCool 所有的资源。它绝不推断宽泛的父目录、使用通配符、删除任意 Library 内容或修改 Shell 初始化文件。预计 CheeseCool 创建的持久 Shell 环境变量始终保持为零。

清理引擎会先验证每一个解析后的目标：必须是清单中精确列出的绝对路径，且不能是根目录、用户目录、`/Applications`、`/tmp` 或任何 Library 父目录；现存符号链接同样会被拒绝。验证失败时保持失败关闭，不删除任何内容。

卸载器会在界面中展示清理计划。仅在从已验证的主应用移交、用户确认后才执行删除；直接启动卸载器时仅提供演练预览。删除完成后会复核每个目标是否已不存在，并在卸载器退出时仅移除其自身创建的临时副本目录。

未来任何破坏性实现及其测试都必须先解析精确的清单条目。测试必须使用临时沙箱根目录，绝不能以开发项目或已安装应用为目标。
