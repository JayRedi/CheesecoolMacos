# 菜单栏契约

每个指标都是独立的原生 `NSStatusItem`；字体排印、基线和尺寸由 macOS 控制。第一阶段为主 CheeseCool 项使用原生文本和临时 SF Symbol。

类型化指标标识符如下：

- `fanRPM`
- `fanDuty`
- `socTemperature`
- `cpuLoad`
- `socPower`
- `gpuLoad`

可见性和排序会分别持久化。主图标具有用户偏好，但可访问性优先级更高：

```text
if visibleMetricCount == 0:
    effectiveMainIconVisible = true
else:
    effectiveMainIconVisible = preferredMainIconVisible
```

因此，无法应用“隐藏主图标且隐藏全部指标”的组合。隐藏最后一个指标会立即显示主项目。该不变量以纯策略实现，并由应用单元测试覆盖。

第二阶段中，暂时不可用但受支持的指标仍会显示，并使用简洁占位符（`--°C`、`--%` 或 `-- W`）。永久不受支持的指标会从菜单栏移除，并在其禁用的“设置”开关旁说明原因。不受支持的指标不计入可访问性不变量；若它们是唯一被请求显示的项目，则会显示主 CheeseCool 项。

真实指标的格式为 `42°C`、`18%` 和 `6.8 W`，不会应用自定义字体。风扇 RPM 和占空比来自连接后的 Protocol V1 `GET_STATUS`；未检测到设备时，界面明确显示真实 CheeseCool 设备不可用，不会把模拟数值伪装为硬件遥测。

主 CheeseCool 状态栏项目使用已冻结的 17 pt 模板 `fan.fill` 图标。其精简原生菜单依次显示当前状态摘要、带勾选状态的 AUTO/MANUAL/MAX、 “设置…”和“退出 CheeseCool”。不包含重载配置、配置路径或其他实现细节。

每个指标项目提供自己的简洁上下文菜单：指标名称、“隐藏该指标”、“设置…”和“退出 CheeseCool”。运行模式、指标可见性和排序仍以“设置”窗口为主要配置入口。每个可见的 CheeseCool 入口始终可以打开“设置”。
