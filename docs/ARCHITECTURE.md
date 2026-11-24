# GateKeeper architecture

## Overview

```
┌──────────────── Flutter (lib/) ────────────────┐       ┌──────────────── Kotlin (android/app/src/main/kotlin/com/gatekeeper/app) ───────────────┐
│ UI: onboarding, home, settings, map picker,    │Pigeon │ bridge/HostApiImpl ──► EngineRuntime (process singleton, one HandlerThread)          │
│     activity log, test-mode simulator          │◄─────►│                         │  1. reconcile prerequisites (perms, number, SIM)           │
│ AppController (ChangeNotifier)                 │       │                         │  2. TriggerEngine.reduce(state, event, config)  [pure]     │
│ SettingsRepository + Validators                │       │                         │  3. EngineStateStore.save(state)  [commit(), write-ahead]  │
│ PermissionService (permission_handler)         │       │                         │  4. execute effects                                        │
└────────────────────────────────────────────────┘       │ Receivers (run with the process dead):                                               │
                                                         │   GeofenceReceiver · ActivityTransitionReceiver · CarBluetoothReceiver · BootReceiver  │
                                                         │ DecisionWindowService (short FGS) · CarConnectionObserver · GateCaller · CallActivity  │
                                                         └───────────────────────────────────────────────────────────────────────────────────────┘
```

**Why the engine is native.** Every trigger has to be decided while the Flutter UI is closed, inside BroadcastReceivers with a roughly 10 s budget. Booting a headless Flutter engine for each geofence or activity event would add latency (bad for the "immediate" arrival trigger) and memory pressure. So the engine is a **pure Kotlin** state machine with no `android.*` imports, unit tested on the JVM with a fake clock. Flutter handles the UI, onboarding, validation, settings editing and log display.

**Persistence.** Settings are edited and validated in Dart and stored by the native `ConfigStore` (SharedPreferences) through Pigeon, because receivers have to read them without Flutter. Engine state (`EngineStateStore`) and the event log (`EventLog`, capped JSONL file) are also native.

## Repository layout

| Path | Contents |
|---|---|
| `lib/main.dart`, `lib/app.dart` | Entry point, Material 3 theme, onboarding gate, bottom-navigation shell |
| `lib/src/platform/` | Pigeon-generated API + `GateKeeperPlatform` interface (faked in tests) |
| `lib/src/settings/` | `GateSettings` model, `Validators`, `SettingsRepository`, problem-code descriptions |
| `lib/src/features/` | `home`, `settings` (+ simulator), `location_picker` (flutter_map/OSM), `logs`, `onboarding`, `permissions` |
| `pigeons/gatekeeper_api.dart` | Bridge definition |
| `android/.../core/` | `Model.kt`, `TriggerEngine.kt`: the pure state machine |
| `android/.../store/` | `ConfigStore`, `EngineStateStore`, `EventLog` |
| `android/.../geofence/`, `activity/` | Play services registration managers + receivers |
| `android/.../car/` | `CarConnectionObserver` (Android Auto), `CarBluetoothReceiver`, `CarAssociation` (cleans up companion associations from 1.0.0/1.0.1) |
| `android/.../telephony/` | `SimRepository`, `GateCaller`, `CallStateWatcher`, `CallActivity`, `PhoneNumbers` |
| `android/.../service/` | `DecisionWindowService` |
| `android/.../system/` | `PermissionMonitor`, `Notifications`, `BootReceiver`, `StopMonitoringReceiver` |
| `android/app/src/test/` | JVM unit tests for the engine (`EngineHarness` = fake clock, timers, call executor) |
| `android/app/src/androidTest/` | Device tests (stores, registration, SIM enumeration, receiver injection) |

## Signals and wake-ups

| Signal | Source | Wakes a dead process? | Qualifies as a vehicle signal? |
|---|---|---|---|
| Geofence ENTER/EXIT | `GeofencingClient`, PendingIntent → `GeofenceReceiver` | Yes | n/a (location) |
| IN_VEHICLE ENTER/EXIT | Activity Recognition Transition API → `ActivityTransitionReceiver` | Yes | Yes |
| Android Auto | `CarConnection` LiveData (public API) | **No**: dynamic receiver only | Yes |
| Car Bluetooth ACL connect | `ACTION_ACL_CONNECTED` (implicit-broadcast exception) → `CarBluetoothReceiver` | Yes | **No**, wake only |
| Boot / app update | `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED` | Yes | n/a (re-registers) |

**Decision window.** No service runs while you are parked and idle. A wake event that matters (genuine geofence ENTER, car Bluetooth connect while inside, IN_VEHICLE while inside, a pending trigger) starts `DecisionWindowService`. This is a `connectedDevice` foreground service that lasts at most 150 s and shows a low-importance notification with a **Stop monitoring** action. It observes Android Auto, keeps the process alive for the delay timer and hosts the call. Starting it from the background relies on documented exemptions: geofence and activity-transition events and, for the car Bluetooth wake-up, the app's battery-optimisation exemption (the app prompts for it with `CAR_WAKE_BLOCKED`). The car itself is chosen from the phone's bonded-device list (`BluetoothAdapter.getBondedDevices()`, names via `BLUETOOTH_CONNECT`).

> The plan proposed `shortService`. `connectedDevice` was used instead because `shortService` exists only on API 34+ while minSdk is 30. On Android 14+ its prerequisite is met by the normal `CHANGE_NETWORK_STATE` permission (or `BLUETOOTH_CONNECT`).

## Trigger state machine

Phases (derived from persisted state): `STOPPED`, `MONITORING_OUTSIDE`, `MONITORING_INSIDE`, `WAITING_FOR_VEHICLE_SIGNAL`, `PENDING_DELAYED_CALL`, `CALLING`, `COOLDOWN`.

```
                 genuine ENTER + IN_VEHICLE active ──────────────► attemptCall (Scenario B, immediate)
MONITORING_OUTSIDE ── genuine ENTER (no signal) ──► WAITING_FOR_VEHICLE_SIGNAL
                 genuine ENTER + AA connected ─┐                     │ rising edge: IN_VEHICLE enter / AA connect
                                               ▼                     ▼
                                   PENDING_DELAYED_CALL (delay, default 5 s; merges overlapping signals)
                                     │ EXIT / stop / signals lost / prerequisite lost → cancel
                                     ▼ TimerFired: revalidate inside + same session + signal + prereqs + not cooldown
                                   CALLING (write-ahead persisted) ─► COOLDOWN (default 3 min) ─► MONITORING_INSIDE (disarmed)
```

Rules (see `TriggerEngine.kt`):

1. **Genuine ENTER** starts a new inside-session with `armed = true`. If IN_VEHICLE is active (and the immediate trigger is enabled), call now (Scenario B, which takes priority). With immediate disabled, or with only Android Auto connected, use the delayed path: Android Auto is never proof of driving.
2. **Initial sync.** Transitions within 30 s of geofence or activity registration (start, reboot, settings change) only record state. They never fire Scenario B from possibly stale vehicle state.
3. **Rising edge while inside and armed** schedules one pending call. A second signal while pending is merged, not duplicated.
4. **Revalidation** after the delay re-checks everything, including a fresh SIM and permission reconcile. The runtime reconciles prerequisites before every external event and timer.
5. **One call per episode.** A call disarms the session. It re-arms on a genuine EXIT, or once every vehicle signal has been inactive for ≥ 5 min (so getting back into the car next morning works, but signal flapping at the gate does not call twice). The **cooldown** blocks all calls regardless.
6. **Ordering.** Each source (geofence, vehicle, AA, Bluetooth) is monotonic by event time. An older event delivered late is dropped, and an event repeating the current state is a no-op. Activity events carry `elapsedRealtimeNanos` and geofence events use the triggering fix time.
7. **Android Auto first reading.** When the observer starts, `UNKNOWN → ACTIVE` counts as a new connection only if the car's Bluetooth connected within the last 150 s. Otherwise it may be a car that has been connected for a long time (for example, the UI opened in a parked car).
8. **Write-ahead.** `calling = true` and `lastCallAt` are committed before `placeCall()` runs. If the process dies, `ProcessRestored` marks the result `UNKNOWN_PROCESS_DIED` and never retries. A restored pending timer more than 15 s past its deadline is discarded, and an earlier one is rescheduled.
9. **Test mode.** The engine emits `SimulateCall` instead of `PlaceCall`, and the runtime refuses to dial in test mode as a second guard.

## Calling

`GateCaller` reconciles right before dialling: `CALL_PHONE`, a valid non-emergency number, and the **exact** `PhoneAccountHandle` for the stored subscription (`TelecomManager.getCallCapablePhoneAccounts()` + `TelephonyManager.getSubscriptionId(handle)`, API 30). If that SIM is not present, no call is placed, an error notification is shown and the log says so. There is **never** a fallback to another SIM. The call uses `TelecomManager.placeCall(tel:…, EXTRA_PHONE_ACCOUNT_HANDLE)`.

After `placeCall()` returns, `CallStateWatcher` waits up to 10 s for `CALL_STATE_OFFHOOK`. If dialling is not confirmed (some OEMs silently block background calls), or `placeCall` throws `SecurityException`, a high-priority **"Tap to call the gate"** notification opens the transparent `CallActivity`. That call is user-initiated, so it is allowed, and it uses the same SIM check. Nothing is retried automatically.

## Threading

- One `HandlerThread` serializes all engine work. Receivers use `goAsync()` and finish when their event has been processed.
- Timers use `Handler.postDelayed` plus a bounded partial wake lock (delay + 10 s) so deep sleep cannot stall the 5 s revalidation.
- `CarConnection` is observed on the main thread and reference-counted between the decision window and the visible UI.
