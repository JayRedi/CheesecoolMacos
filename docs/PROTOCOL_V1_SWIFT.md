# Protocol V1 的 Swift 映射

## 帧格式

每个请求和响应都是 64 字节：

| 字节 | 含义 |
| --- | --- |
| 0 | Protocol Version，当前为 `1` |
| 1 | Command |
| 2 | Sequence |
| 3 | Payload Length |
| 4... | 请求 payload；响应的 byte 4 为 status，payload 从 byte 5 开始 |
| 63 | bytes `0...62` 的 XOR 校验 |

请求 payload 最大为 59 字节。响应的 byte 4 保留 status，因此响应 payload 最大为 58 字节。`ProtocolV1Codec` 在编码、解码和状态映射时均验证长度、版本、命令、序列与 XOR。

## 命令表

| 命令 | 值 | Phase 4A 使用 |
| --- | ---: | --- |
| `PING` | `0x01` | 是，连接后确认链路 |
| `ENTER_DFU_LEGACY` | `0x08` | 否 |
| `GET_STATUS` | `0x09` | 是 |
| `SET_MODE` | `0x0A` | 是 |
| `SET_DUTY` | `0x0B` | 是 |
| `SET_CURVE` | `0x0C` | 否 |
| `ENTER_DFU` | `0x0D` | 否 |

Phase 4A 不会发出任何 DFU 或曲线设置命令。

`SET_MODE` 的 payload 为一个字节：`0` 表示 host-controlled，`1` 表示 max。`SET_DUTY` 的 payload 为 `0...100` 的精确整数百分比；`0` 的物理含义仍由设备的最小安全转速策略决定，并不被客户端解释为停转。

## GET_STATUS payload

成功响应的 status 为零，随后 payload 必须为 17 字节：

| 偏移 | 字段 | 编码 |
| --- | --- | --- |
| 0 | mode | 单字节 |
| 1 | target duty | 单字节百分比 |
| 2 | actual duty | 单字节百分比 |
| 3...6 | RPM | UInt32 little-endian |
| 7 | USB configured flag | `0` 或 `1` |
| 8 | failsafe flag | `0` 或 `1` |
| 9 | power-fault flag | `0` 或 `1` |
| 10...13 | uptime | UInt32 little-endian |
| 14...16 | firmware version | major/minor/patch |

无效长度、未知 mode、非法 flag 或非零 status 都会被拒绝，而不是转换成貌似正常的风扇状态。
