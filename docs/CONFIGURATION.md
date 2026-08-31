# 设置持久化

CheeseCool 在以下位置维护内部 UTF-8 设置存储：

```text
~/Library/Application Support/CheeseCool/settings.json
```

该位置属于实现细节，不会在菜单或“设置”中暴露。界面更改会先验证、立即应用，并在短暂防抖后以原子方式自动保存。测试会注入临时文件 URL，绝不访问用户的 Library。损坏的数据会回退到完整的安全默认值，同时保留结构化诊断信息，并可从产品界面重置。

仅当 `settings.json` 不存在、而旧的内部文件 `config.json` 存在时，才会执行一次第一阶段迁移。CheeseCool 会严格解码并验证旧数据，以原子方式创建 `settings.json`，保留所有有效值，之后只读取新存储。损坏的旧文件会生成并持久化安全默认值，避免每次启动都重试迁移；旧文件不会被删除。

“登录时启动”字段会持久化以保持连续性，但在生产环境中以 `SMAppService.mainApp.status` 为准。加载设置时，界面会根据真实系统状态更新。测试使用 `FakeLoginItemManager`，不会修改开发机的登录项。

版本 1 的架构包含：所选模式、手动占空比、AUTO 曲线、控制回差、升降速率、临界行为、温度宽限期/过期时间、保活/控制间隔、重连策略、物理风扇停转支持、菜单栏可见性/排序、刷新间隔、登录时启动以及前一模式恢复。

解码采用严格模式。根对象、重连策略、菜单栏对象和每个曲线点都必须恰好包含受支持的键。未知或缺失的键、不支持的架构版本或枚举、非有限数值、无效范围或顺序、重复指标、非 1/2/5 秒的刷新间隔，以及 `physicalFanOffSupported=true` 都会被拒绝。

代表性默认值：

```json
{
  "version": 1,
  "operatingMode": "AUTO",
  "manualDuty": 50,
  "autoCurve": [
    {"temperatureCelsius": 40, "duty": 0},
    {"temperatureCelsius": 50, "duty": 25},
    {"temperatureCelsius": 60, "duty": 40},
    {"temperatureCelsius": 70, "duty": 60},
    {"temperatureCelsius": 80, "duty": 80},
    {"temperatureCelsius": 90, "duty": 100}
  ],
  "deadband": 2,
  "rampUpPerSecond": 20,
  "rampDownPerSecond": 8,
  "criticalBehavior": "IMMEDIATE_100",
  "temperatureGrace": 3,
  "temperatureStaleAfter": 5,
  "keepaliveInterval": 5,
  "controlTickInterval": 1,
  "reconnectPolicy": {
    "maxAttempts": 3,
    "initialDelay": 2,
    "backoffMultiplier": 2,
    "maxDelay": 30
  },
  "physicalFanOffSupported": false,
  "menuBar": {
    "mainIconPreferredVisible": true,
    "visibleMetrics": ["fanRPM"],
    "metricOrder": ["fanRPM", "fanDuty", "socTemperature", "cpuLoad", "socPower", "gpuLoad"]
  },
  "refreshInterval": 1,
  "launchAtLogin": true,
  "restorePreviousMode": true
}
```

## 设置界面行为

设置窗口采用“通用、菜单栏、风扇、高级、关于”五个原生 macOS 页面。配置并不以用户可见文件形式提供，且不存在“重新载入配置”“打开配置文件夹”或配置路径界面。

“恢复默认设置”需要确认；确认后会验证、立即应用、自动保存，并立刻更新菜单栏，无需重启。AUTO 曲线使用受约束的步进编辑，始终保持严格递增温度和 0–100% 占空比，避免把部分无效编辑应用到控制会话。

风扇页在 Debug 构建中会明确标注 RPM 和占空比来自 `FakeHostDevice` 模拟设备。`0%` 一律表示最低转速，而不是关闭或停止风扇。SoC 功耗显示为“不可用”，GPU 负载显示为“当前系统不支持”，不会伪造 `0 W` 或 `0%`。
