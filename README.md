<p align="center">
  <img src="docs/assets/icon.svg" width="96" alt="GateKeeper icon">
</p>

<h1 align="center">GateKeeper</h1>

<p align="center">
  <b>Your phone calls the gate when you drive up, so you don't have to.</b><br>
  An Android app that dials your gate-opener number automatically when you arrive at, or leave, your parking spot.
</p>

<p align="center">
  <a href="https://github.com/SanuSanal/gatekeeper/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/SanuSanal/gatekeeper?label=download&color=1f6b5c"></a>
  <a href="https://github.com/SanuSanal/gatekeeper/actions/workflows/release.yml"><img alt="Release build" src="https://github.com/SanuSanal/gatekeeper/actions/workflows/release.yml/badge.svg"></a>
  <img alt="Android 11+" src="https://img.shields.io/badge/Android-11%2B-3ddc84">
  <img alt="No tracking" src="https://img.shields.io/badge/tracking-none-555">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue"></a>
</p>

<p align="center">
  <a href="https://sanusanal.github.io/gatekeeper/">Website</a> ·
  <a href="https://github.com/SanuSanal/gatekeeper/releases/latest">Download APK</a> ·
  <a href="docs/ARCHITECTURE.md">Architecture</a> ·
  <a href="docs/LIMITATIONS.md">Limitations</a>
</p>

---

Many gated communities and parking lots use a **call-to-open** gate: you ring a number and the gate opens (the call is usually rejected, so it's free). GateKeeper places that call for you at the right moment, from the right SIM, exactly once.

> [!IMPORTANT]
> GateKeeper is new. The trigger logic is covered by unit tests, but background behaviour (geofencing, activity detection, car Bluetooth wake-up, background calling) differs between Android versions and phone makers. **Start in Test mode**, check the Activity log, and work through the [device test checklist](docs/DEVICE_TEST_CHECKLIST.md) before you depend on it.

## Contents

- [How it works](#how-it-works)
- [Features](#features)
- [Install](#install)
- [Setup](#setup)
- [Updating](#updating)
- [Permissions and privacy](#permissions-and-privacy)
- [Reliability tips](#reliability-tips)
- [Building from source](#building-from-source)
- [Releasing](#releasing)
- [Project structure](#project-structure)
- [Documentation](#documentation)
- [FAQ](#faq)
- [License](#license)

## How it works

GateKeeper calls only when **both** of these are true:

1. you are **inside** the parking geofence (a circle around your spot, 150 m by default), **and**
2. a **vehicle signal** is active: Android's activity detection says you are *in a vehicle*, or your phone is connected to **Android Auto**.

| Situation | What happens |
|---|---|
| **Arriving:** you drive into the geofence and you're already detected as driving | Calls **immediately** |
| **Leaving:** you're parked inside and you start driving, or Android Auto connects | Waits **5 s**, re-checks everything, then calls |
| **Walking** into the area | Never calls |
| Both signals fire at once, events arrive twice or out of order | Still exactly **one** call |
| You leave the area, stop monitoring, or the signal drops during the 5 s wait | Call **cancelled** |
| Another trigger within the **cooldown** (3 min by default) | Suppressed |

Under the hood it's a deterministic, persisted state machine (`STOPPED → MONITORING_OUTSIDE → WAITING_FOR_VEHICLE_SIGNAL → PENDING_DELAYED_CALL → CALLING → COOLDOWN`). It writes "a call is being placed" to disk *before* dialling, so a crash or restart can never cause a second call. Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

### No always-on service

GateKeeper doesn't keep a service running or show a permanent notification while you're parked at home, and it never polls GPS:

- **Geofence** and **in-vehicle** events are delivered by Google Play services, even when the app is closed.
- **Getting into the car** is detected through your car's **Bluetooth connection**. You choose your car once from the phone's paired Bluetooth devices.
- Only when something relevant happens does a short check run (up to 2.5 min, with a small notification) to look at Android Auto and place the call.

## Features

- Automatic gate call on arrival and departure, with delayed revalidation
- Exact **SIM selection** on dual-SIM phones. If the chosen SIM is missing, it does **not** call and tells you; it never silently switches SIM
- Easy location picker: drag the map under a fixed pin, search an address, use your current location, or paste coordinates or a Google Maps link
- Adjustable radius (100–1000 m), delay (1–30 s) and cooldown (1–30 min)
- Toggles for Android Auto detection, Activity Recognition and the immediate arrival trigger
- **Test mode** with an event simulator: same logic, never dials
- **Activity log** of every geofence, vehicle, Android Auto and Bluetooth event, every trigger decision and every call attempt
- **Tap-to-call fallback** if Android blocks the background call
- **In-app updates** from GitHub Releases, verified by checksum and signing certificate
- Material 3, light and dark theme, Android 11+

## Install

**Direct download:** use the buttons on the **[website](https://sanusanal.github.io/gatekeeper/#install)**; they always point at the latest APKs.

Or step by step:

1. On your phone, open the **[latest release](https://github.com/SanuSanal/gatekeeper/releases/latest)**.
2. Download the APK for your phone. If unsure, pick **arm64-v8a**: it covers almost every phone from 2017 onwards.

   | APK | For |
   |---|---|
   | `gatekeeper-X.Y.Z-arm64-v8a.apk` | Most phones (64-bit ARM) |
   | `gatekeeper-X.Y.Z-armeabi-v7a.apk` | Older 32-bit phones |
   | `gatekeeper-X.Y.Z-x86_64.apk` | Emulators, x86 devices |

3. Open it and allow your browser to "install unknown apps" when asked.
4. Optional: check the file against `SHA256SUMS.txt` from the same release.

Requirements: Android 11 or newer, Google Play services, a SIM that can make calls.

## Setup

1. **Onboarding:** grant permissions as each one is explained:
   - Location → then **"Allow all the time"** (required for detection while the app is closed)
   - Physical activity, Phone, Notifications
   - Nearby devices and battery-optimisation exemption (recommended)
2. **Settings → Gate phone number.** Emergency numbers are refused.
3. **Settings → SIM for gate calls.**
4. **Settings → Parking location:** tap *my location* (or search an address), then drag the map until the pin sits on your spot. You can also paste coordinates or a Google Maps link. Adjust the radius if needed.
5. **Settings → Car Bluetooth → Choose:** pick your car from the list of paired devices (shown by name, cars first). Pair it in Android's Bluetooth settings first if it isn't listed. If GateKeeper asks, tap **Allow** under *Let your car wake GateKeeper*: this turns off battery optimisation for the app, which Android requires before the car connection can start GateKeeper's short car check.
6. Turn on **Test mode**, press **Start monitoring**, and try a drive or the simulator buttons. Watch the **Activity** tab.
7. When it behaves as expected, turn Test mode **off**.

## Updating

GateKeeper checks GitHub Releases once a day (you can switch this off) and offers new versions. You can also use **Settings → Updates → Check**.

Before Android's installer opens, the update is checked:

- downloaded only from this repository's releases, over HTTPS
- SHA-256 matches the digest GitHub publishes
- same package, higher version, **same signing certificate** as the installed app

You confirm every install in Android's own dialog. The first time, Android asks you to allow GateKeeper to "install unknown apps".

## Permissions and privacy

| Permission | Used for |
|---|---|
| Location (all the time) | Parking geofence |
| Physical activity | Detecting that you're in a vehicle |
| Phone | Listing SIMs, placing the call, confirming it started |
| Notifications | Errors, tap-to-call fallback, the short "checking your car" notice |
| Nearby devices | Waking up when your car's Bluetooth connects |
| Install apps | Self-update (only after you tap Install) |

**Privacy:** no account, no backend, no analytics, no ads. Settings and logs never leave the phone. The only network requests are OpenStreetMap map tiles while the location picker is open, the text you type into its address search (sent to Android's built-in geocoder, usually Google), and an anonymous request to the GitHub Releases API for update checks. Phone numbers are masked in the UI and the log.

Full details: [docs/PERMISSIONS_AND_BATTERY.md](docs/PERMISSIONS_AND_BATTERY.md).

## Reliability tips

- Set GateKeeper's battery usage to **Unrestricted**.
- On Xiaomi/Redmi/POCO, also enable **Autostart**, **"Display pop-up windows while running in the background"** and **"Start in background"**.
- Keep Location on. If it's switched off, Android removes the geofence; GateKeeper tells you and restores it when you reopen the app.
- Keep a radius of at least 150 m.

See [docs/LIMITATIONS.md](docs/LIMITATIONS.md) for what Android does and doesn't guarantee.

## Building from source

Requirements: Flutter **3.47.5** (stable), JDK 17, Android SDK 36.

```powershell
git clone https://github.com/SanuSanal/gatekeeper.git
cd gatekeeper
flutter pub get
flutter run                     # debug build on a connected phone
flutter build apk --release --split-per-abi
```

Without `keys/key.properties`, release builds are signed with the debug key. They install fine, but they can't update (or be updated by) the official signed releases.

### Tests

```powershell
flutter test                                          # Dart: validators, settings, update logic, widgets
cd android; .\gradlew :app:testDebugUnitTest          # Kotlin: trigger state machine (fake clock, 40+ scenarios)
cd android; .\gradlew :app:connectedDebugAndroidTest  # on a device: stores, geofence/AR registration, SIM enumeration
```

### Platform bridge

The Flutter ↔ Kotlin API is generated by [Pigeon](https://pub.dev/packages/pigeon) from [pigeons/gatekeeper_api.dart](pigeons/gatekeeper_api.dart):

```powershell
dart run pigeon --input pigeons/gatekeeper_api.dart
```

## Releasing

Releases are built by [.github/workflows/release.yml](.github/workflows/release.yml) when a version tag is pushed:

```powershell
git tag v1.2.0
git push origin v1.2.0
```

The workflow:

1. checks the tag is `vMAJOR.MINOR.PATCH` (MINOR and PATCH 0–99) and that no release exists for it yet
2. runs the Dart and Kotlin unit tests (the signing key isn't on the runner yet)
3. restores the signing key and builds **signed per-ABI APKs** (`--split-per-abi`). The version name comes from the tag, and the build number is `MAJOR×10000 + MINOR×100 + PATCH`, so it always rises with the version (Flutter adds `ABI×1000` per APK)
4. verifies each APK is signed with exactly the GateKeeper release certificate (SHA-256 fingerprint pinned in the workflow)
5. publishes a GitHub Release with one APK per ABI (`gatekeeper-<version>-<abi>.apk`) and `SHA256SUMS.txt`

Keep `MINOR` and `PATCH` below 100 and never reuse or lower a version: installed apps only accept updates with a higher version code.

Signing uses four repository secrets (upload them from your local `keys/` folder with `.\tool\set-release-secrets.ps1`): `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`. Locally, the keystore lives in the gitignored `keys/` folder. **Back it up.** Losing it means existing installs can't be updated.

## Project structure

```
lib/                      Flutter UI, settings, validation, update checker
  src/features/           home · settings · location picker · activity log · onboarding · permissions
  src/update/             GitHub Releases update check + install flow
  src/platform/           Pigeon bridge (generated) + testable wrapper
android/app/src/main/kotlin/com/gatekeeper/app/
  core/                   Pure-Kotlin trigger state machine (no Android imports)
  geofence/ activity/     Play services geofencing & activity transitions
  car/                    Android Auto (CarConnection), car Bluetooth wake
  telephony/              SIM discovery, call placement, call-state confirmation
  service/                Short "decision window" foreground service
  update/                 Verified APK download + installer hand-off
  system/                 Permissions, notifications, boot restore
docs/                     Architecture, permissions, limitations, test checklist, website
```

## Documentation

| Document | What's in it |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Components, event flow, state machine rules, threading |
| [PERMISSIONS_AND_BATTERY.md](docs/PERMISSIONS_AND_BATTERY.md) | Every permission and why; battery and OEM settings |
| [LIMITATIONS.md](docs/LIMITATIONS.md) | Known Android limitations (Android Auto, Doze, OEM call blocking, …) |
| [DEVICE_TEST_CHECKLIST.md](docs/DEVICE_TEST_CHECKLIST.md) | Step-by-step real-device test plan |

## FAQ

**Does it work with the app closed?** Yes, that's the design: geofence, activity and car-Bluetooth events wake it. Some phone makers kill background apps aggressively; see [Reliability tips](#reliability-tips).

**Will it call when I walk home?** No. A vehicle signal is required, and walking into the geofence never calls.

**Why didn't it call when I left?** Activity detection needs the car moving and can take 30–90 s. Choose your car's Bluetooth in Settings so Android Auto can trigger it sooner. The Activity log shows why each trigger was or wasn't used.

**Can it call emergency numbers?** No. They are refused when saving and again before dialling.

**Is it on the Play Store?** No. Play Store policy restricts the permissions it needs (background calling and location), so it's distributed as signed APKs here.

**iPhone?** No. GateKeeper is Android-only.

## License

GateKeeper is released under the [MIT License](LICENSE). The name and logo identify this project; please don't use them for forks or derivative apps in a way that suggests they are the official GateKeeper.
