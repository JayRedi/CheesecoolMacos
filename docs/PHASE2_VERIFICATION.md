# Phase 2 Verification

Verified on 2026-08-31 on Apple Silicon arm64. Baseline: branch `macos-client-foundation`, commit `dd0106cc320fd43d4b1b63df242e97708546307a`; implementation branch: `macos-client-metrics`.

## Automated tests and builds

- XCTest: 61 passed, 0 failed (50 `CheeseCoolCoreTests`, 11 `CheeseCoolTests`).
- Debug `CheeseCool`: PASS.
- Release `CheeseCool`: PASS.
- Release `CheeseCool Uninstaller`: PASS.
- All three executables are arm64-only Mach-O files.
- The Release app has no Python artifact/runtime, unexpected entitlement, or privacy usage-description key. `LSUIElement=true` remains intact.

## Native provider audit

- IOKit enumeration found 24 valid sensors matching only `PMU/PMU2 tdie*` on the verification Mac. The initial read-only probe reported approximately 30.3–34.9°C. No `tdev`, `tcal`, battery, NAND, or inferred CPU/GPU mapping was accepted.
- `powermetrics` reports estimated subsystem power and refuses non-root execution (`powermetrics must be invoked as the superuser`). No public `IOReport.framework` client API is present in the SDK. Numeric SoC power is therefore unsupported.
- Metal stage counters describe work submitted by an application, not reliable whole-system GPU utilization. Other system-wide counters are private/high-risk. GPU load is therefore unsupported.

## Five-minute real dry-run

The Debug app ran its bounded dry-run for 300.052 seconds with a fixed 1-second monotonic schedule. It produced 300 records in `/tmp/cheesecool-phase2-dry-run.json` while controlling only `FakeHostDevice`.

| Measurement | Result |
| --- | --- |
| Temperature valid | 300 / 300 |
| Temperature range | 32.851–37.969°C |
| Temperature states | COOL 232; NORMAL 68 |
| Temperature read latency | min 17.035ms; avg 20.997ms; max 27.263ms |
| CPU valid | 299 / 300 (first cumulative sample intentionally unavailable) |
| CPU range | 11.677–33.534% |
| CPU read latency | min 0.006ms; avg 0.030ms; max 0.318ms |
| AUTO requested duty | 0–0% |
| Fake device duty | 0–0% |
| Fake RPM | 345–345 RPM |
| Fake device commands | 58 total |
| SoC power / GPU values | 0 / 0, explicitly unsupported |
| Errors / sensor loss | 0 / 0 |

Inter-sample deltas were 0.938–1.064 seconds, with the last sample at 299.081 seconds. Duty did not oscillate, no value left 0–100%, and 58 commands over five minutes is consistent with initial synchronization plus the frozen keepalive rather than command flooding.

Two read-only process snapshots during the run showed 0.0% instantaneous CPU and approximately 34MB then 31MB RSS for the Debug app; memory did not grow over time. The provider path creates no metric subprocess.

## Permission and hardware result

Required user-facing macOS permissions: none. Screen Recording, Microphone, Camera, Accessibility, Full Disk Access, and Location are not requested. No helper/root design was added.

Real CheeseCool USB/PCB operations, protocol commands, DFU, flash, OpenOCD, WCH-LinkE, firmware changes, and hardware sleep operations: **0**.
