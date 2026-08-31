# CheeseCool for macOS

CheeseCool is a native menu-bar client for Apple Silicon Macs. Phase 1 establishes the product core, deterministic fake device/sensors, AppKit menu-bar shell, SwiftUI settings shell, and a dry-run uninstaller foundation.

## Platform and safety boundary

- Apple Silicon (`arm64`) only; minimum application deployment target is macOS 13.0.
- Swift 6, AppKit, and SwiftUI. There is no Python runtime, daemon, privileged helper, LaunchAgent, or shell-environment mutation.
- `0%` duty means `MINIMUM_SPEED` (approximately 345 RPM in the fake device), never physical fan off.
- The hardware transport and real Apple sensor providers are deliberately deferred. Phase 1 performs no USB, HID, DFU, flash, OpenOCD, WCH-LinkE, or other hardware operation.

## Products

| Xcode target | Product | Bundle identifier |
| --- | --- | --- |
| `CheeseCool` | `CheeseCool.app` | `org.cheesecool.CheeseCool` |
| `CheeseCoolCore` | Native Swift framework | `org.cheesecool.CheeseCoolCore` |
| `CheeseCoolTests` | App unit tests | `org.cheesecool.CheeseCoolTests` |
| `CheeseCoolCoreTests` | Core unit tests | `org.cheesecool.CheeseCoolCoreTests` |
| `CheeseCool Uninstaller` | `CheeseCool Uninstaller.app` | `org.cheesecool.CheeseCoolUninstaller` |

No Apple Developer Team ID is stored. Local CLI gates disable code signing.

## Build and test

```sh
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCoolCore -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test
xcodebuild -project CheeseCool.xcodeproj -scheme 'CheeseCool Uninstaller' -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

The `CheeseCool` test scheme runs both test targets. Its core suite includes the deterministic 86,400-tick simulation.

## Environment audited for Phase 1

- macOS 26.6.2 (25G83)
- Architecture: arm64
- Xcode 26.6 (17F113)
- Swift 6.3.3
- xcodebuild: `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild`
- Git 2.55.0

The actual project workspace was empty and safe to initialize at the start of Phase 1. The read-only Python oracle was inspected from local firmware commit `50beb2500937bd86aee1478bc1c295fc673b9efb`; the firmware worktree was not modified.

## Documentation

- [macOS client architecture](docs/MACOS_CLIENT_ARCHITECTURE.md)
- [Swift Product Core contract](docs/SWIFT_PRODUCT_CORE_CONTRACT.md)
- [menu-bar contract](docs/MENU_BAR_CONTRACT.md)
- [configuration](docs/CONFIGURATION.md)
- [uninstall contract](docs/UNINSTALL_CONTRACT.md)
