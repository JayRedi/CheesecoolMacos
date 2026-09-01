# 第三方组件声明

截至本文件编写时，CheeseCool 工程未声明 Swift Package 依赖，也未包含 CocoaPods、Carthage 或 vendored 第三方源码。

| 名称 | 来源 | 许可证 | 是否随 App 分发 | 原始许可证位置 |
| --- | --- | --- | --- | --- |
| AppKit、SwiftUI、Foundation、IOKit、OSLog、ServiceManagement、XCTest | Apple macOS SDK / Xcode SDK | Apple 平台 SDK 条款 | 系统提供；不作为独立第三方源码随 App 分发 | Apple SDK 与 Xcode 附带条款 |

CheeseCoolCore 是本仓库自身的 Swift framework，不是第三方组件。本文件不将任何 Apple SDK 或未来加入的第三方代码重新授权为 MIT；新增依赖时必须同步更新本文件及其原始许可证信息。
