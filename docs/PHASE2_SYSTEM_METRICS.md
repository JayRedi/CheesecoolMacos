# Phase 2 Apple Silicon system metrics

## Sources and semantics

- SoC temperature uses the native IOKit HID event system. It accepts only product names matching `^(PMU|PMU2) tdie[0-9]+$`, rejects non-finite and out-of-range values, and selects the maximum valid 0–125°C reading. Battery, NAND, `tdev`, `tcal`, and unrelated device sensors are excluded. The IOKit event functions are exported by the system framework but are SPI rather than SDK-header API; they require no helper, root access, subprocess, daemon, or user-facing permission. Failure produces explicit unavailable/stale state rather than a numeric fallback.
- CPU load uses Mach `HOST_CPU_LOAD_INFO` cumulative ticks. The first sample is unavailable. Later samples use deltas for `user + system + nice` as busy and `busy + idle` as total, producing a clamped overall percentage. Counter reset, zero delta, and API errors are unavailable samples.
- Numeric package/SoC power is unsupported. The audited IOReport/powermetrics paths are private and/or privileged and are not acceptable for a permanent menu-bar utility. CheeseCool does not estimate power from CPU load or TDP.
- GPU utilization is unsupported. The available Apple Silicon counters do not provide a stable public, non-privileged application API. CheeseCool does not derive GPU load from CPU activity.

Every `MetricSample` includes a value, validity flag, monotonic timestamp, source health, source description, optional reason, and measured provider latency. Temperature also records the contributing sensor count and names. `SensorEngine` starts all providers concurrently, off the UI path, and preserves healthy samples when another provider fails.

## Sampling and display

The default period is 1 second, with product choices constrained to 1, 2, or 5 seconds. A single coordinator task drives control and metrics, and a short same-cycle temperature cache prevents duplicate HID enumeration when control and telemetry consume the shared temperature provider.

Transient unavailable values use concise menu-bar placeholders. Permanently unsupported metrics are explained in Settings and do not occupy a status item. The main-icon accessibility invariant is evaluated after unsupported metrics are removed.

## Development dry-run

The Debug app supports a bounded Phase 2 dry-run:

```text
CheeseCool --phase2-dry-run-seconds=300 --disable-login-item-management
```

The duration is clamped to at least 300 seconds. It samples at 1 Hz, controls only `FakeHostDevice`, writes all samples atomically to `/tmp/cheesecool-phase2-dry-run.json`, does not start normal settings/menu tasks, and exits. Each record includes temperature/state, AUTO raw and requested duty, fake duty/RPM, CPU, optional power/GPU, provider latency, and errors.

## Permissions and runtime audit

Required user-facing permissions: none. Screen Recording, Microphone, Camera, Accessibility, Full Disk Access, and Location are not requested. There is no privileged helper, persistent daemon, Python runtime, metric subprocess, new entitlement, or architecture other than arm64.
