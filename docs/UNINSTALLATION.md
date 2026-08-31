# 完整卸载

入口：`CheeseCool → 设置 → 关于 → 完全卸载 CheeseCool`。确认后，主应用先停止控制会话、保存设置并注销登录时启动；内嵌卸载器会复制到 CheeseCool 专属临时目录，等待主应用退出后再执行清理。

清理仅使用显式 `InstallManifest`：应用包、`Application Support/CheeseCool`（含 `settings.json` 与旧 `config.json`）、bundle-ID 缓存、日志、偏好、保存状态、诊断数据和登录项。不会搜索磁盘、使用通配符或删除用户导出的诊断文件。

卸载器先标准化并验证每个路径，拒绝 `/`、`/Applications`、`~/Library`、相对路径和符号链接。无法删除时会显示“部分内容未能删除”，不会误报成功。临时卸载器在退出时尝试用原生 `FileManager` 删除其受限临时根；不会安装常驻服务。
