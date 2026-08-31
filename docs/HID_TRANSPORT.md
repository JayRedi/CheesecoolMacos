# HID 传输

## 发现范围

`HIDDeviceDiscovery` 使用 macOS 原生 `IOHIDManager` 被动监听设备，只匹配：

- Vendor ID：`0x1A86`
- Product ID：`0xFE01`

DFU Product ID `0x8035` 不在匹配条件内。因此本客户端不会因为发现逻辑而连接 DFU 设备，更不会执行 DFU、刷写或固件更新。多个匹配设备按 location ID、序列号、registry ID 的稳定顺序选择；诊断快照会提供完整匹配列表与已选设备。

## 报告语义

Protocol V1 的帧恒为 64 字节。`NativeHIDTransport` 直接调用：

```text
IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID: 0, frame, 64)
```

所以传给 IOHID 的是协议自身的 64 字节，不会添加 hidapi 常见的第 0 字节 report-ID 占位符。输入回调同样只接受 input report ID `0` 且长度恰为 64 的报告。这一选择是 macOS IOHID API 语义，而不是 hidapi 缓冲区约定。

## 并发、超时与错误

一次 HID 传输只有一个在途事务：底层传输以锁保护 pending continuation，`HIDHostDevice` 又以 actor 串行化命令。单次读写的默认超时为 750 ms；超时、校验失败、序列不匹配、短帧和设备断开都会向上抛出，并在诊断中记录。

传输层不自行重试，也不建立隐式保活。`ControlSession` 是唯一控制命令频率、停止通信和有界恢复策略的组件。

## 本阶段验证边界

本阶段以 `MockHIDTransport` 测试帧、超时、错误帧、设备移除及控制会话行为，未接触任何物理设备。工作区相邻目录中未找到可作为字节向量来源的 CheeseCool 固件项目；实现依据本阶段冻结的 Protocol V1 帧定义。真实设备字节抓包与硬件互操作验证属于后续 Phase 4B。
