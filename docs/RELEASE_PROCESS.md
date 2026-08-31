# 发布流程

版本来自标准 bundle metadata：`MARKETING_VERSION` 映射到 `CFBundleShortVersionString`，`CURRENT_PROJECT_VERSION` 映射到 `CFBundleVersion`；主应用与卸载器保持同一发布版本。关于页直接读取 bundle metadata，不维护独立硬编码版本。

Phase 5A：本地、未签名 DMG，仅用于开发验收。Phase 5B 前置条件：Apple Developer ID Application 证书、正确的 Team ID/签名配置、可用的 notarization 凭据、最终版本号、干净 Release 构建与签名后 bundle/DMG 审计。Phase 5B 再执行嵌套代码签名、`notarytool` 提交、staple 与 Gatekeeper 验证。
