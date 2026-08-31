# 登录时启动

产品唯一使用 `SMAppService`，不写 LaunchAgent、shell 配置或持久环境变量。首次从 `/Applications/CheeseCool.app` 正常启动且尚无设置时，默认尝试启用登录时启动，并立即以系统实际状态回写设置。

用户关闭开关会注销，重新开启会注册。只有状态变化时才调用系统 API；JSON 中的值从不覆盖真实 ServiceManagement 状态。完整卸载在主应用仍存活时先注销登录项。测试使用 `FakeLoginItemManager`，不改变开发机状态。
