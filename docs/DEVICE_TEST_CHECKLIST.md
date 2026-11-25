# Real-device test checklist

Use a **dual-SIM** Android 11+ phone with Google Play services. Do runs 1–6 in **test mode** first (no calls), then repeat the key ones with test mode off, using a number you control instead of the real gate.

Record for each: device model, Android version, OEM skin, pass/fail, and the relevant lines from the activity log (**Settings → Test & diagnostics → Activity log**).

## 0. Setup

- [ ] `flutter run --release` installs. Onboarding shows every permission with its rationale.
- [ ] Background location: the settings hand-off works and "Allow all the time" is shown as granted.
- [ ] Skipping a permission shows its consequence in Settings → Permissions and on the Status tab.
- [ ] Both SIMs are listed with slot and carrier. Choosing SIM 2 persists across an app restart.
- [ ] Map picker: tap places the marker and the radius circle; "Use my current location" works; typed coordinates apply.
- [ ] Car choice: Settings → Car Bluetooth lists paired devices by name with the car first; after choosing, its name shows in Settings and on the Status tab. "Let your car wake GateKeeper → Allow" turns off battery optimisation and the warning disappears.
- [ ] `.\gradlew :app:connectedDebugAndroidTest` passes on the device.

## 1. Scenario B: arrive while driving (immediate)

- [ ] Drive into the geofence with IN_VEHICLE detected (log shows `IN_VEHICLE ENTER` before `ENTER geofence`) → call at ENTER with no delay.
- [ ] Note the ENTER latency relative to physically crossing the boundary.

## 2. Walk in (no call)

- [ ] Walk into the geofence → `ENTER geofence`, `waiting`, no call.

## 3. Scenario A: already inside, start driving

- [ ] Parked inside for more than 5 min, start driving → `IN_VEHICLE ENTER` → call after 5 s. Note how long IN_VEHICLE took.
- [ ] Same with the **screen off and phone locked**.

## 4. Scenario C: already inside, Android Auto connects

- [ ] Process killed (`adb shell am kill com.gatekeeper.app`), parked inside, get in the car → car Bluetooth connects → decision-window notification appears → Android Auto connects → call after 5 s.
- [ ] Wired AA and wireless AA (if available). Note the seconds between Bluetooth and AA.
- [ ] Opening the app while sitting in an already-connected car does **not** call.

## 4b. Car Bluetooth without Android Auto

- [ ] Android Auto off in Settings (or a car without it), car chosen, parked inside for more than 5 min, process killed → get in the car → `Car Bluetooth connected` → call after 5 s (`CAR_BLUETOOTH`).
- [ ] Drive home connected to the car → `ENTER geofence` → call after 5 s (`ENTER_WITH_CAR_BLUETOOTH`) if IN_VEHICLE hasn't already triggered an immediate call.
- [ ] Turn the car off and on again within 5 min → no second call.
- [ ] Restart the phone while connected to the car → log shows `Car Bluetooth state cleared (phone restarted)`.

## 5. Cancellation (Scenario D)

- [ ] During the 5 s delay (test mode makes this easy): Stop monitoring → cancelled.
- [ ] During the delay: unplug AA / stop the car → `vehicle signal no longer active`, cancelled.
- [ ] During the delay: revoke phone permission → cancelled, error shown.

## 6. Duplicates and cooldown

- [ ] AA and IN_VEHICLE both active → exactly one call.
- [ ] Leave and re-enter within 3 min → second call suppressed (cooldown in log).
- [ ] Leave, wait more than 3 min, re-enter driving → new call.
- [ ] Gate queue: stop and go near the gate for a few minutes after the arrival call → no second call.

## 7. Calling

- [ ] Call goes out on the **selected** SIM (check the dialler / call log) for SIM 1 and for SIM 2.
- [ ] Log shows `Dialling confirmed`.
- [ ] Phone locked + app closed → call still starts. If not, the "Tap to call the gate" notification appears and works.
- [ ] Remove the selected SIM (or disable the eSIM) → no call, "selected SIM is not available" notification. Confirm the other SIM was **not** used.
- [ ] Invalid number can't be saved; emergency numbers are refused.
- [ ] Test mode on → no call under any scenario; "Test mode: gate call simulated" notification.

## 8. Lifecycle

- [ ] Reboot while monitoring → log shows geofence and Activity Recognition re-registered and the initial state is synced without a call.
- [ ] Update the app (`flutter install` over it) while monitoring → registrations restored.
- [ ] Swipe the app from recents → triggers still work.
- [ ] Doze: `adb shell dumpsys deviceidle force-idle`, then simulate/drive → note any delay. `adb shell dumpsys deviceidle unforce` afterwards.
- [ ] Turn location off → "Parking detection paused" notification. Turn it on and open the app → re-registered.
- [ ] Revoke background location in system settings → the next event or app open shows the problem, and monitoring stops or flags it.

## 9. Battery

- [ ] 24 h idle at home while monitoring: battery usage for GateKeeper under 1–2 %. No persistent notification while parked.

## Results

| Date | Device / Android / skin | Section | Result | Notes |
|---|---|---|---|---|
| | | | | |
