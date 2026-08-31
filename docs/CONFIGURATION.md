# Configuration

Production configuration is UTF-8 JSON at:

```text
~/Library/Application Support/CheeseCool/config.json
```

Tests inject a temporary file URL and never access the user's real Library configuration. `ConfigStore` writes atomically, reloads on request, resets to complete safe defaults, and retains a structured error when corrupt input requires fallback.

Schema version 1 includes selected mode, manual duty, AUTO curve, deadband, ramp rates, critical behavior, temperature grace/staleness, keepalive/control intervals, reconnect policy, fixed physical-fan-off support, menu-bar visibility/order, refresh interval, login-at-startup, and previous-mode restoration.

Decoding is strict. The root, reconnect policy, menu-bar object, and every curve point must have exactly the supported keys. Unknown/missing keys, unsupported schema versions/enums, non-finite values, invalid ranges/order, duplicate metrics, and `physicalFanOffSupported=true` are rejected.

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
