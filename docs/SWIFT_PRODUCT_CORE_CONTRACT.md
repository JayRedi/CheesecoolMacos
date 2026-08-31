# Swift Product Core Contract

## Behavioral oracle

The frozen behavior was ported from the local Python Product Core at commit `50beb2500937bd86aee1478bc1c295fc673b9efb` on branch `product-core-simulation`. Relevant oracle sources were `tools/temperature_state`, `tools/auto_control`, `tools/cheesecool_core`, and `docs/HOST_PRODUCT_CORE.md`.

Python is a development oracle only. `CheeseCool.app` and `CheeseCoolCore` neither execute nor embed Python. `PythonOracleV1.json` captures representative expected curve, zero-duty, watchdog, and failsafe outputs, and Swift tests compare against it.

## Modes and device semantics

- `AUTO`: a normalized `TemperatureSample` flows through `AutoController` to an integer duty command.
- `MANUAL`: exactly restores the configured integer duty from 0 through 100.
- `MAX`: calls `HostDevice.setMax()`. It is not represented as ordinary `setDuty(100)`.
- `0%`: `MINIMUM_SPEED`; `physicalFanOffSupported` is permanently `false` in schema v1.

`HostDevice` owns transport capabilities only: connect, disconnect, connection query, status read, host-controlled mode, MAX mode, exact duty, and close. It contains no AUTO curve, temperature policy, or UI behavior.

## AUTO policy

| Temperature | Raw duty |
| --- | ---: |
| ≤40°C | 0% |
| 50°C | 25% |
| 60°C | 40% |
| 70°C | 60% |
| 80°C | 80% |
| ≥90°C | 100% |

Intermediate values are linearly interpolated. Deadband is 2 percentage points, ramp up is 20 points/second, and ramp down is 8 points/second. A `CRITICAL` sample bypasses deadband and ramp limits and requests 100% immediately. These values are the current behavioral baseline, not final physical tuning.

## Temperature loss

This contract applies only to AUTO:

1. For up to and including 3 seconds after the last valid sample, state is `TEMPERATURE_GRACE` and the last requested duty is held.
2. After 3 seconds, state is `TEMPERATURE_UNAVAILABLE` and the session performs no `HostDevice` call at all—not status, mode, duty, or keepalive.
3. With traffic absent, the fake MCU's 30-second watchdog autonomously selects 50% failsafe.
4. Recovery performs status read → host-controlled mode → recomputed current AUTO duty → verification status read.

## Keepalive, failure, and restoration

An unchanged duty is not resent. If no other valid command occurred, an explicit `GET_STATUS` keepalive is due every 5 seconds.

Transport failures enter `DEVICE_UNAVAILABLE`, disconnect once, and use bounded exponential reconnect. A reconnect performs connect → status read → selected-mode restoration → status verification. AUTO recalculates its current duty, MANUAL restores the user's exact duty, and MAX restores device MAX mode.

A reported failsafe is explicitly reconciled using the same status/mode/duty/verification flow. A power fault latches `POWER_FAULT` and blocks ordinary device traffic until explicit acknowledgement; if status still reports the fault during recovery, it latches again.

## FakeHostDevice

The deterministic fake provides Protocol V1 product semantics without HID or IOKit:

- exact 0–100 duty and approximately 345–2500 RPM mapping;
- HOST_CONTROLLED and dedicated MAX mode;
- 30-second watchdog and 50% autonomous failsafe;
- USB loss, connect/command/read failure, timeout, reboot, disconnect/reconnect, and power fault;
- a configurable bounded command history (default 512);
- virtual monotonic time.

## Telemetry and diagnostics

`TelemetrySnapshot` preserves temperature/state/validity, selected mode, control state, raw AUTO duty, requested/last-sent/device duties, RPM, failsafe, power fault, connection, last command and age, last error, reason, and physical-fan-off support. `EventLog` defaults to 128 entries and discards oldest entries when full.
