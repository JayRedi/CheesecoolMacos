# 卸载契约

`CheeseCool Uninstaller.app` 是独立的原生目标。第一阶段实现了确认界面外壳、清理清单、精确清理路径计算和必需的演练预览；它不执行删除操作。

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

未来任何破坏性实现及其测试都必须先解析精确的清单条目。测试必须使用临时沙箱根目录，绝不能以开发项目或已安装应用为目标。
