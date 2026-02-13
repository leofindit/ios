<!-- Short Copilot instructions tailored for LEOFindIt_iOS -->
# LEOFindIt_iOS — Copilot Instructions

Purpose: quickly orient AI coding agents to the app structure, native BLE contract, developer workflows, and project-specific conventions.

1) Big picture
- Flutter app with a small native iOS BLE bridge. UI + business logic live in `lib/` (entry: [lib/main.dart](lib/main.dart)).
- Native iOS scanning + classification implemented in `ios/Runner/BluetoothManager.swift` and wired via a Flutter `MethodChannel` in `ios/Runner/AppDelegate.swift`.

2) Key integration points & contract
- MethodChannel name: `leo_find_it/scanner` (see [lib/ble_bridge.dart](lib/ble_bridge.dart) and [ios/Runner/AppDelegate.swift](ios/Runner/AppDelegate.swift)).
- Methods from Flutter -> native: `startScan`, `stopScan` (AppDelegate forwards to `BluetoothManager`).
- Native -> Flutter events: native calls `channel.invokeMethod("onDevice", arguments: payload)` where `payload` includes keys used by the app:
  - `signature`, `kind`, `rssi`, `distanceMeters`, `firstSeenMs`, `lastSeenMs`, `sightings`, `rawFrame` (see `BluetoothManager.swift` for full payload).
- Important: iOS does not expose MAC/address. Code relies on `signature` (constructed from `peripheral.identifier.uuidString`) and `firstSeenMs` for stable ordering.

3) BLE behavior & heuristics (source-of-truth)
- Distance estimation constants: `TX_POWER = -59.0`, `PATH_LOSS_N = 2.0` (see `BluetoothManager.estimateDistanceMeters`).
- TTL eviction for trackers: `TRACKER_TTL_MS = 30_000` (prevents stale entries).
- Start-request throttling: `START_REQUEST_TTL_MS = 10_000` and `pendingStart` logic — native may remember a start request until Bluetooth powers on.
- Classification heuristics are in `classifyKind(...)` (manufacturer IDs, localName, service UUIDs) — modify here when adding new device signatures.

4) Flutter-side expectations & patterns
- Use `BleBridge.detections` Stream (see [lib/ble_bridge.dart](lib/ble_bridge.dart)) — the app listens and merges with `TrackerDevice.fromNative(...)`.
- UI ordering: `main.dart` sorts by `firstSeenMs` to keep card positions stable (avoid reordering on RSSI updates).
- Scanning lifecycle: UI toggles `BleBridge.startScan()` / `stopScan()`; app auto-stops after 5 minutes and uses motion detection (`sensors_plus`) as a complementary heuristic.

5) Developer workflows & commands
- General Flutter dev: `flutter pub get`, `flutter run -d <device>`.
- iOS native changes: open `ios/Runner.xcworkspace` in Xcode, build on a physical device (Bluetooth requires device). After native edits run:
  - `cd ios && pod install`
  - `cd .. && flutter clean && flutter run -d <device>`
- Debugging native logs: run from Xcode to view `print(...)` messages in `BluetoothManager.swift` or tail device logs in Console.

6) Conventions & gotchas specific to this repo
- Do not assume MAC addresses on iOS — rely on `signature` field (constructed in iOS code). See `BluetoothManager.swift` where `signature` uses `peripheral.identifier.uuidString`.
- Keep classification changes in `classifyKind(...)` — tests and UI expect `kind` values like `TILE`, `AIRTAG`, `SAMSUNG_SMARTTAG`, `APPLE_DEVICE`, `UNKNOWN`.
- Avoid changing the `onDevice` payload keys; the Dart models parse these directly (`models.dart`).

7) Where to change things (quick pointers)
- Add/adjust native heuristics: [ios/Runner/BluetoothManager.swift](ios/Runner/BluetoothManager.swift).
- Change channel contract or add native methods: [ios/Runner/AppDelegate.swift](ios/Runner/AppDelegate.swift) and [lib/ble_bridge.dart](lib/ble_bridge.dart).
- UI and merging logic: [lib/main.dart](lib/main.dart) and `models.dart`.

If any section is unclear or you want more examples (small patches), tell me which area to expand (native heuristics, MethodChannel tests, or UI/device-model examples).
