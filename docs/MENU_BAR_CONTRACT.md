# Menu-Bar Contract

Each metric is an independent native `NSStatusItem`; typography, baseline, and sizing are controlled by macOS. Phase 1 uses native text and a temporary SF Symbol for the main CheeseCool item.

Typed metric identifiers are:

- `fanRPM`
- `fanDuty`
- `socTemperature`
- `cpuLoad`
- `socPower`
- `gpuLoad`

Visibility and ordering are persisted independently. The main icon has a user preference, but accessibility has higher priority:

```text
if visibleMetricCount == 0:
    effectiveMainIconVisible = true
else:
    effectiveMainIconVisible = preferredMainIconVisible
```

Consequently, `main icon hidden + all metrics hidden` can never be applied. Hiding the final metric immediately materializes the main item. The invariant is implemented as a pure policy and covered by app unit tests.

Every status item exposes a native context menu. The menu contains AUTO, MANUAL, MAX, Settings, Reload Configuration, and Quit. Metric items can hide themselves; the main item can show or hide each metric. Settings remains reachable from every visible CheeseCool entry.
