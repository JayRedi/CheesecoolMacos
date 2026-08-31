# Phase 1 Verification

Verified on 2026-08-31 with macOS 26.6.2 (25G83), arm64, Xcode 26.6 (17F113), Swift 6.3.3, and Git 2.55.0.

## Build gates

The following command shapes completed successfully with a fresh temporary DerivedData directory and `CODE_SIGNING_ALLOWED=NO`:

```sh
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath <temporary-derived-data> CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath <temporary-derived-data> CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CheeseCool.xcodeproj -scheme 'CheeseCool Uninstaller' -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath <temporary-derived-data> CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath <temporary-derived-data> CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -project CheeseCool.xcodeproj -scheme CheeseCool -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath <temporary-derived-data> CODE_SIGNING_ALLOWED=NO test-without-building
```

Result: Debug PASS, Release PASS, Uninstaller Release PASS. Both application executables are arm64 Mach-O files. The app Info.plist resolves to `LSMinimumSystemVersion=13.0` and `LSUIElement=true`. The embedded `CheeseCoolCore.framework` install name and consumer linkage both resolve through `@rpath`.

## Tests

The final xcresult summary reported:

- total: 37
- passed: 37
- failed: 0
- skipped: 0
- expected failures: 0

The `CheeseCool` scheme includes both `CheeseCoolCoreTests` and `CheeseCoolTests`, so the result covers core behavior and the AppKit menu-bar visibility policy.

## Deterministic 24-hour simulation

```json
{
  "durationSeconds": 86400,
  "ticks": 86400,
  "totalDeviceCommands": 17641,
  "connectAttempts": 19,
  "maxEventLogSize": 67,
  "maxDeviceLogSize": 512,
  "invalidDutyCount": 0,
  "unhandledErrorCount": 0,
  "finalControlState": "AUTO_ACTIVE",
  "finalConnectionState": "CONNECTED",
  "commandFlood": false,
  "deadlock": false,
  "endlessReconnect": false,
  "passed": true
}
```

The simulation used `ManualClock`; it did not wait for 24 real hours. It covered temperature variation and failure, AUTO/MANUAL/MAX transitions, disconnect/reconnect, MCU failsafe, power-fault recovery, sleep/wake, reboot, command failure, and configuration load/save behavior.

## Hardware and external effects

Counts for HID/USB device access, DFU, firmware flash, OpenOCD, WCH-LinkE, and hardware sleep operations are all zero. The firmware repository was read only. No remote was created, no push occurred, no developer login item was changed by tests, and no persistent shell environment variable was created.
