# Known Android limitations

Everything below comes from reading the platform documentation and the library internals. **None of it has been verified on a real device yet.** Update this file with what you see during the device checklist.

## Android Auto (CarConnection)

- `androidx.car.app.connection.CarConnection` is a `LiveData` backed by a content-provider query to the Android Auto host plus a **dynamically registered** broadcast receiver (confirmed in `androidx.car.app:app:1.7.0`). It cannot wake a stopped app; it only reports while our process is alive and observing.
- GateKeeper therefore observes it only during a **decision window** (≤ 150 s) or while the UI is visible. At other times Android Auto is shown as *Not observed* and does not count as active.
- To catch "got into the car at home" without a service running all the time, the **car's Bluetooth connection** (an implicit-broadcast exception) wakes the app. If Android Auto connects more than about 150 s after Bluetooth, it is missed; IN_VEHICLE still covers that case once the car moves.
- No undocumented Android Auto broadcasts or internals are used.

## Activity Recognition

- IN_VEHICLE detection typically takes **30 s to a few minutes** and needs the car to be moving. In a parking lot the departure trigger may only fire near the gate.
- The Transition API reports *changes* only. A missed EXIT can leave IN_VEHICLE stale; a fresh registration (start, reboot, update) resets it to *Unknown*.
- Whether an initial ENTER is delivered right after registration varies. Events within 30 s of registration are treated as state sync, not new signals.

## Geofencing

- Typical ENTER/EXIT latency is **0–2 minutes**, longer in Doze or with poor GPS. Radii below 100 m are unreliable, so 100 m is the app's minimum.
- Geofences are removed on reboot, on app update, when location is switched off, and when Play services data is cleared. GateKeeper re-registers on boot and update, and on the next app launch after location was off.
- The initial ENTER/EXIT after registration is treated as state sync, so it never fires the immediate arrival call.

## Background calling

- `TelecomManager.placeCall()` with `CALL_PHONE` from a background or foreground-service context works on stock Android 11–16 as far as the documentation shows. It is **not guaranteed**: some OEMs (MIUI/HyperOS especially) block calls from background apps unless extra permissions are granted.
- GateKeeper confirms dialling by watching for `CALL_STATE_OFFHOOK` for 10 s. If dialling isn't seen, it posts a **Tap to call the gate** notification (a user-initiated call, always allowed). That fallback may fire spuriously if the call state can't be observed, and tapping it places a second, deliberate call.
- `placeCall()` gives no answered/failed result. The app records *initiated*, *dialling confirmed* or *not confirmed*, never "gate opened".

## Background execution

- Starting the decision window from the background relies on documented exemptions: geofence and activity-transition events, and, for the car Bluetooth wake-up, the app being exempt from battery optimisation. If Android refuses anyway (`ForegroundServiceStartNotAllowedException`), the event is still processed, the refusal is logged, and the 5 s timer runs only while the process stays alive.
- On Android 14+ users can swipe away foreground-service notifications. The service keeps running for its short window.
- Doze can delay geofence and activity broadcasts. A battery-optimisation exemption reduces this but cannot remove it.

## SIM handling

- Subscription IDs change when a SIM card is replaced. After a SIM swap the stored SIM shows as unavailable and **no call is placed** until you choose a SIM again. This is deliberate: there is no silent fallback.
- eSIM profiles that are disabled are not "active subscriptions" and show as unavailable.

## Platform scope

- Android 11+ only (minSdk 30), because of the exact SIM-to-PhoneAccount mapping API.
- Requires Google Play services (geofencing and Activity Recognition).
