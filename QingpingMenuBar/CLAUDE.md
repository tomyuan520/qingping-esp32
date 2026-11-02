# CLAUDE.md

## Project overview

QingpingMenuBar is a macOS menu bar app that monitors Qingping Air Monitor Lite (CGDN1) devices. It supports three data sources: passive BLE scanning (default, no cloud needed), the Cleargrass Cloud API (optional fallback), and a local ESPHome stream for devices reflashed with ESPHome firmware. Displays real-time CO2, PM2.5, PM10, temperature, humidity, and battery data with sparkline charts.

## Build & run

- Open `QingpingMenuBar.xcodeproj` in Xcode 26+
- Build target: macOS 26 (Tahoe)
- No SPM dependencies — pure SwiftUI + system frameworks
- App Sandbox and Hardened Runtime are enabled
- Entitlements: Bluetooth, outgoing network connections

## Architecture

- **SwiftUI** with `MenuBarExtra` (`.window` style) — no dock icon (`LSUIElement = YES`)
- **@Observable** pattern (not ObservableObject) for Swift 6.2 `MainActor` default isolation
- **Three data sources**: BLE (default), Cloud API and ESPHome, switchable at runtime
- **BLE scanner** (`QingpingBLEScanner`) — passive, parses advertisements on UUID `0xFDCD`, no pairing
- **ESPHome client** (`ESPHomeClient`) — streams the web_server's `/events` (SSE) over plain HTTP, basic/digest login, auto-reconnect; shares the BLE history store
- **Actor-isolated API client** (`QingpingAPIClient`) — separate from MainActor, handles OAuth2 + REST
- **All model types are `nonisolated` and `Sendable`** — they cross actor boundaries freely
- **History persistence** (`HistoryStore`) — BLE history saved as JSON in Application Support, pruned to 24h on load

## Key files

| File | Purpose |
|------|---------|
| `QingpingMenuBarApp.swift` | App entry point, Keychain migration |
| `AirQualityViewModel.swift` | Central state, BLE/API switching, polling, history |
| `QingpingBLEScanner.swift` | Passive BLE advertisement parser (CoreBluetooth) |
| `QingpingAPIClient.swift` | OAuth2 + REST API calls (actor) |
| `ESPHomeClient.swift` | ESPHome web_server SSE stream → readings |
| `Models.swift` | Codable types matching API JSON |
| `MenuBarPopoverView.swift` | Popover UI, charts, settings, supporting types |
| `MenuBarLabel.swift` | Menu bar icon and value display |
| `AirQualityThresholds.swift` | Quality level definitions and thresholds |
| `CredentialsStore.swift` | Keychain read/write/migrate |
| `HistoryStore.swift` | BLE history persistence to disk |

## BLE protocol

- Service UUID: `0xFDCD`
- Device types: `0x0E`, `0x24` (CGDN1 variants)
- Data format: 8-byte header + TLV blocks (type, length, value)
- TLV types: `0x01` (temp+humidity), `0x02` (battery), `0x12` (PM2.5+PM10), `0x13` (CO2)
- All values little-endian. Temperature is signed Int16 / 10. Humidity is UInt16 / 10. Others are direct UInt16.

## Conventions

- All types default to `MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)
- Data models must be marked `nonisolated` to be usable from `QingpingAPIClient` and `QingpingBLEScanner`
- Keychain service name must match the bundle ID (`com.andreugordillo.QingpingMenuBar`)
- No `print()` statements in release code — all debug logging has been removed
- History arrays are capped at 500 points per metric to limit memory
- BLE history appends are throttled to every 30 seconds
- Temperature thresholds evaluate in Celsius regardless of display unit
- A fresh `QingpingAPIClient` is created on data source switch and wake from sleep (avoids stale sockets)

## Common tasks

- **Adding a new sensor metric**: Add field to `DeviceData`, `AirQualityReading`, `HistoryDataPoint`. Add TLV parsing in `QingpingBLEScanner`. Add history array in viewmodel + `appendBLEHistory`/`loadBLEHistory`/`saveBLEHistory`. Add `SensorRow` in popover. Add threshold function in `AirQualityThresholds`.
- **Changing BLE history throttle**: Edit the `>= 30` check in `appendBLEHistory()`
- **Changing poll interval**: Edit `PollSettings.interval` in `MenuBarPopoverView.swift`
- **Changing history refresh interval**: Edit the `600` second check in `AirQualityViewModel.refresh()`
- **Changing default data source**: Edit the fallback in `DataSource.from(stored:)` and `DataSourceSetting.source` getter
