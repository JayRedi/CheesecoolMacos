# macOS Client Architecture

## Runtime shape

`CheeseCool.app` is an `LSUIElement` accessory application backed by a native `NSStatusItem`. It has no normal Dock icon. Opening Settings creates a conventional AppKit `NSWindow` hosting SwiftUI. There is no background daemon, privileged helper, Python interpreter, LaunchAgent, or persistent shell configuration.

The product is divided into a UI/application target and a platform-neutral Swift framework:

```text
AppCoordinator (@MainActor)
├── MenuBarManager (@MainActor, AppKit)
├── SettingsCoordinator (@MainActor, SwiftUI in NSWindow)
├── TelemetryStore (@MainActor)
├── SensorEngine (actor)
├── LifecycleManager (actor)
└── ControlSession (actor)
    ├── TemperatureSource
    ├── AutoController (pure deterministic value state)
    ├── HostDevice (async protocol)
    ├── MonotonicClock
    └── EventLog (actor, bounded)
```

`AppCoordinator` composes dependencies; no product-core singleton or mutable global state is used. UI-bound state is main-actor isolated. Stateful background components use actors, and their cross-boundary models conform to `Sendable` where meaningful.

## Source layout

```text
CheeseCool/
├── App/            application entry point and composition
├── Core/           domain models, AUTO policy, session, simulation, manifests
├── Device/         HostDevice and deterministic FakeHostDevice
├── Sensors/        provider protocols, SensorEngine, fake providers
├── MenuBar/        NSStatusItem controllers and visibility invariant
├── Settings/       SwiftUI model/view and AppKit window coordinator
├── Persistence/    ConfigStore and TelemetryStore
├── Lifecycle/      sleep/wake/stop and login-item abstraction
├── Diagnostics/    bounded structured EventLog
└── Resources/      future native resources
```

## Clock and scheduling

All control decisions use an injected monotonic clock. `SystemMonotonicClock` reads system uptime; `ManualClock` advances only when a test or simulation requests it. Keepalive age, fake MCU watchdog, temperature grace/staleness, reconnect backoff, event timestamps, and the long simulation all derive from that clock. No test sleeps to advance product state.

The application loop only schedules when to call `tick()`; it does not determine whether keepalive or recovery work is due.

## Lifecycle

- `prepareForSleep()` disconnects and stops all host traffic so MCU ownership can take over.
- `resumeFromSleep()` resets bounded reconnect state and marks the selected mode for synchronized restoration.
- `stop()` closes the device and permanently transitions the session to `STOPPED`.
- Normal quit cancels the app loop, awaits `stop()`, and then terminates.

Production sleep/wake notification wiring and real transport/sensor implementations are Phase 2 work.

## Login item

`LoginItemManaging` isolates login registration. `SMAppServiceLoginItemManager` is used only by the running application; tests use `FakeLoginItemManager` and never change developer-machine login items. No LaunchAgent plist or shell command is used.
