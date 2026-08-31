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

At Phase 2, a transiently unavailable supported metric remains visible with a concise placeholder (`--°C`, `--%`, or `-- W`). A permanently unsupported metric is removed from the menu bar and explained beside its disabled Settings toggle. Unsupported metrics do not count toward the accessibility invariant, so the main CheeseCool item appears if they were the only requested items.

Real metric formatting is `42°C`, `18%`, and `6.8 W`. No custom font is applied. Fan RPM and duty continue to represent `FakeHostDevice`/not-connected development data until the later HID phase; they are not presented as real hardware telemetry.

Every status item exposes the same minimal native context menu containing only Settings and Quit. Operating mode and metric visibility are configured in the Settings window. Settings remains reachable from every visible CheeseCool entry.
