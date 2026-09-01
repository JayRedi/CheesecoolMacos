# AUTO 自动调速

## 温度来源与控制温度

生产实现使用 `AppleSiliconTemperatureProvider`，通过 `IOHIDEventSystemClient` 读取 Apple 的 `AppleARMPMUTempSensor` 服务事件。实际参与控制的传感器名称必须匹配 `PMU tdie*` 或 `PMU2 tdie*`；名称、有限数值和 0–125°C 范围均会校验。

从全部有效传感器中取最高温度，作为 `control_temperature_c`。这使多个 SoC die 温度中最热的一个决定 AUTO 控制。

`TemperatureSample` 记录：

- `timestamp`：样本时间。
- `control_temperature_c`（代码字段 `controlTemperatureCelsius`）：有效传感器的最高温度。
- `state`：`cool`、`normal`、`warm`、`hot`、`critical` 或 `unknown`。
- `valid`：样本是否可用于控制。

温度状态阈值为：低于 35°C 为 cool，35–54°C 为 normal，55–69°C 为 warm，70–84°C 为 hot，85°C 及以上为 critical。

## 曲线与插值

当前生产默认曲线为：

| 温度 | duty |
| --- | ---: |
| ≤40°C | 0% |
| 50°C | 25% |
| 60°C | 40% |
| 70°C | 60% |
| 80°C | 80% |
| ≥90°C | 100% |

相邻节点之间使用线性插值。`critical` 温度状态会跳过曲线和 ramp，立即请求 100%。

## Deadband 与 Ramp

- duty deadband：2%。相对上次请求变化小于 2% 时保持上次值。
- ramp-up：20%/秒。
- ramp-down：8%/秒。

控制器以实际经过时间限制每次变化，因此不会因刷新间隔改变而放大或缩小单位时间升降速。

## 温度无效

新样本超过 5 秒、传感器为空、不可用或不合法时不可参与控制。若距离最后有效请求不超过 3 秒，AUTO 保持上次 duty（`HOST_TEMPERATURE_GRACE_HOLD`）；超过 grace 后进入 `HOST_TEMPERATURE_UNAVAILABLE`，客户端停止控制流量。

## macOS 与 MCU 的职责

macOS 负责采集温度、执行 AUTO 算法、计算 duty 并发送 Protocol V1 控制命令。MCU 负责 PWM 输出、RPM 测量和 30 秒 host timeout failsafe。温度失效时，客户端不尝试编造安全 duty，而是让 MCU 的独立 failsafe 接管。

曲线中的 0% 等于 `MINIMUM_SPEED`，不是 FAN OFF 或物理停转。
