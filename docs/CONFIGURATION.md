# Settings persistence

CheeseCool owns an internal UTF-8 settings store at:

```text
~/Library/Application Support/CheeseCool/settings.json
```

This location is an implementation detail and is not exposed in menus or Settings. UI changes are validated, applied immediately, and atomically auto-saved after a short debounce. Tests inject temporary file URLs and never access the user's Library. Corrupt data falls back to complete safe defaults, retains a structured diagnostic, and can be reset from the product UI.

One-time Phase 1 migration runs only when `settings.json` is absent and the former internal `config.json` exists. CheeseCool strictly decodes and validates the old data, atomically creates `settings.json`, preserves all valid values, and then reads only the new store. A corrupt legacy file produces and persists safe defaults so migration is not retried every launch; the old file is not deleted.

The launch-at-login field is persisted for continuity, but `SMAppService.mainApp.status` is authoritative in production. Loading settings updates the UI from the actual system state. Tests use `FakeLoginItemManager` and never modify the developer machine's login items.

Schema version 1 includes selected mode, manual duty, AUTO curve, deadband, ramp rates, critical behavior, temperature grace/staleness, keepalive/control intervals, reconnect policy, fixed physical-fan-off support, menu-bar visibility/order, refresh interval, login-at-startup, and previous-mode restoration.

Decoding is strict. The root, reconnect policy, menu-bar object, and every curve point must have exactly the supported keys. Unknown/missing keys, unsupported schema versions/enums, non-finite values, invalid ranges/order, duplicate metrics, refresh intervals other than 1/2/5 seconds, and `physicalFanOffSupported=true` are rejected.

Representative defaults:

```json
{
  "version": 1,
  "operatingMode": "AUTO",
  "manualDuty": 50,
  "autoCurve": [
    {"temperatureCelsius": 40, "duty": 0},
    {"temperatureCelsius": 50, "duty": 25},
    {"temperatureCelsius": 60, "duty": 40},
    {"temperatureCelsius": 70, "duty": 60},
    {"temperatureCelsius": 80, "duty": 80},
    {"temperatureCelsius": 90, "duty": 100}
  ],
  "deadband": 2,
  "rampUpPerSecond": 20,
  "rampDownPerSecond": 8,
  "criticalBehavior": "IMMEDIATE_100",
  "temperatureGrace": 3,
  "temperatureStaleAfter": 5,
  "keepaliveInterval": 5,
  "controlTickInterval": 1,
  "reconnectPolicy": {
    "maxAttempts": 3,
    "initialDelay": 2,
    "backoffMultiplier": 2,
    "maxDelay": 30
  },
  "physicalFanOffSupported": false,
  "menuBar": {
    "mainIconPreferredVisible": true,
    "visibleMetrics": ["fanRPM"],
    "metricOrder": ["fanRPM", "fanDuty", "socTemperature", "cpuLoad", "socPower", "gpuLoad"]
  },
  "refreshInterval": 1,
  "launchAtLogin": true,
  "restorePreviousMode": true
}
```
