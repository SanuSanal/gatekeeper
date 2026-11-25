# Permissions and battery-optimisation guide

GateKeeper asks for each permission in context during onboarding, and again from **Settings → Permissions**. Each one can be skipped; the app then shows what is unavailable. Nothing bypasses Android's permission controls.

## Runtime permissions

| Permission | Why | Without it |
|---|---|---|
| Precise location (`ACCESS_FINE_LOCATION`) | Set the parking spot; geofencing | No parking detection |
| Location **"Allow all the time"** (`ACCESS_BACKGROUND_LOCATION`) | Geofence events are delivered to a closed app only with this. On Android 11+ Android opens a settings page: choose **Allow all the time** | Detection works only while the app is open (monitoring cannot start) |
| Physical activity (`ACTIVITY_RECOGNITION`) | IN_VEHICLE transitions, so walking in never calls | No in-vehicle detection (only car Bluetooth and Android Auto can trigger) |
| Phone (`CALL_PHONE`, `READ_PHONE_STATE`) | Place the call; list SIMs; map SIM → PhoneAccount; confirm dialling | No calls or SIM selection (test mode still works) |
| Notifications (`POST_NOTIFICATIONS`, Android 13+) | Call errors, tap-to-call fallback, decision-window notice | Problems are silent; the fallback cannot be shown |
| Nearby devices (`BLUETOOTH_CONNECT`, Android 12+) | Receive the car Bluetooth connect broadcast | Connecting to the car is not noticed; only IN_VEHICLE (and Android Auto while the app is open) can trigger |

## Install-time permissions (no prompt)

`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `CHANGE_NETWORK_STATE` (connectedDevice prerequisite on Android 14+), `REQUEST_COMPANION_START_FOREGROUND_SERVICES_FROM_BACKGROUND` (only for car associations made by 1.0.0/1.0.1), `WAKE_LOCK` (only while a delayed trigger is pending), `RECEIVE_BOOT_COMPLETED`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, and `INTERNET` (map tiles and address search in the location picker, and update checks).

## Choosing your car

**Settings → Car Bluetooth → Choose** lists the Bluetooth devices already paired with your phone, by name, with car head units (car-audio / hands-free class) first. Pick your car; if it isn't listed, pair it in Android's Bluetooth settings first. Listing names needs the **Nearby devices** permission.

GateKeeper then reacts only to that device connecting. When it connects while you're inside the geofence, GateKeeper starts a short foreground "car check". Android allows that from the background only for apps that are **exempt from battery optimisation**, so the app shows *Let your car wake GateKeeper → Allow* until the exemption is granted. (Versions 1.0.0/1.0.1 used Android's companion-device dialog instead; an association created by them still works and is removed when you change or remove the car.)

Change or remove the car from the same screen at any time.

## Battery optimisation (strongly recommended)

Android's Doze mode and OEM "battery savers" can delay or drop geofence and activity events.

1. **Settings → Permissions → Ignore battery optimisation → Grant**, or Android Settings → Apps → GateKeeper → Battery → **Unrestricted**.
2. OEM-specific settings (names vary by version):
   - **Xiaomi / Redmi / POCO (MIUI / HyperOS):** Settings → Apps → GateKeeper → *Autostart* ON; Battery saver → *No restrictions*; *Other permissions* → allow **"Display pop-up windows while running in the background"** and **"Start in background"** (both needed for background calls).
   - **Samsung (One UI):** Settings → Battery → Background usage limits → remove GateKeeper from *Sleeping/Deep sleeping apps*, or add it to *Never sleeping apps*.
   - **OnePlus / OPPO / realme (ColorOS / OxygenOS):** App info → Battery → *Allow background activity*; turn on *Auto launch*.
   - **Vivo (Funtouch / OriginOS):** i Manager → App manager → Autostart ON; Battery → High background power consumption → allow.
   - **Huawei / Honor:** Battery → App launch → GateKeeper → *Manage manually*, all three toggles on.
3. Keep **Location** on. If location is turned off, Android removes the geofence. GateKeeper notifies you and re-registers when you next open it.

See <https://dontkillmyapp.com> for up-to-date OEM instructions.

## Play Store note

`CALL_PHONE`, background location and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` are restricted under Google Play policy. GateKeeper is intended for personal, sideloaded use.
