// Pigeon definition for the Flutter <-> Kotlin bridge.
// Regenerate with: dart run pigeon --input pigeons/gatekeeper_api.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/platform/gatekeeper_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/app/src/main/kotlin/com/gatekeeper/app/bridge/GateKeeperApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.gatekeeper.app.bridge'),
    dartPackageName: 'gatekeeper',
  ),
)
class SettingsMessage {
  SettingsMessage({
    this.gateNumber,
    this.simSubscriptionId,
    this.simLabel,
    this.latitude,
    this.longitude,
    required this.radiusMeters,
    required this.delaySeconds,
    required this.cooldownMinutes,
    required this.immediateTrigger,
    required this.androidAutoEnabled,
    required this.activityRecognitionEnabled,
    required this.carBluetoothEnabled,
    required this.testMode,
    this.carDeviceName,
    required this.carDeviceAssociated,
    required this.onboardingComplete,
  });

  String? gateNumber;
  int? simSubscriptionId;

  /// Human label of the selected SIM at selection time (slot + carrier), for "SIM missing" messages.
  String? simLabel;
  double? latitude;
  double? longitude;
  int radiusMeters;
  int delaySeconds;
  int cooldownMinutes;
  bool immediateTrigger;
  bool androidAutoEnabled;
  bool activityRecognitionEnabled;

  /// Being connected to the chosen car's Bluetooth counts as a vehicle signal (only with a car chosen).
  bool carBluetoothEnabled;
  bool testMode;

  /// Read-only on save: the car is chosen with selectCar/clearCar. True when a car is selected.
  String? carDeviceName;
  bool carDeviceAssociated;
  bool onboardingComplete;
}

class SimCardMessage {
  SimCardMessage({
    required this.subscriptionId,
    required this.slotIndex,
    this.carrierName,
    this.displayName,
    required this.callCapable,
  });

  int subscriptionId;
  int slotIndex;
  String? carrierName;
  String? displayName;

  /// True when Telecom exposes a call-capable PhoneAccount for this subscription.
  bool callCapable;
}

class StatusMessage {
  StatusMessage({
    required this.monitoring,
    required this.phase,
    required this.geofence,
    required this.vehicle,
    required this.androidAuto,
    required this.carBluetoothConnected,
    this.androidAutoObservedAt,
    this.lastTriggerAt,
    this.lastTriggerSource,
    this.lastTriggerDecision,
    this.lastCallAt,
    this.lastCallOutcome,
    this.pendingDeadline,
    required this.testMode,
    required this.problems,
  });

  bool monitoring;
  String phase;
  String geofence;
  String vehicle;
  String androidAuto;
  bool carBluetoothConnected;
  int? androidAutoObservedAt;
  int? lastTriggerAt;
  String? lastTriggerSource;
  String? lastTriggerDecision;
  int? lastCallAt;
  String? lastCallOutcome;
  int? pendingDeadline;
  bool testMode;

  /// Machine-readable problem codes (e.g. "SIM_UNAVAILABLE", "LOCATION_NOT_SET").
  List<String> problems;
}

class LogEntryMessage {
  LogEntryMessage({
    required this.timestamp,
    required this.category,
    required this.message,
  });

  int timestamp;
  String category;
  String message;
}

class LocationMessage {
  LocationMessage({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });

  double latitude;
  double longitude;
  double? accuracyMeters;
}

class BluetoothDeviceMessage {
  BluetoothDeviceMessage({
    required this.name,
    required this.address,
    required this.carLike,
    required this.selected,
  });

  /// User-visible name (the alias set in Bluetooth settings, or the device name).
  String name;
  String address;

  /// Bluetooth class says car audio / hands-free (likely a car head unit).
  bool carLike;
  bool selected;
}

class PlaceMessage {
  PlaceMessage({required this.label, required this.latitude, required this.longitude});

  String label;
  double latitude;
  double longitude;
}

class StartResult {
  StartResult({required this.started, required this.problems});

  bool started;
  List<String> problems;
}

class AppInfoMessage {
  AppInfoMessage({
    required this.versionName,
    required this.versionCode,
    required this.supportedAbis,
    required this.canInstallPackages,
  });

  String versionName;
  int versionCode;

  /// Device ABIs in preference order (Build.SUPPORTED_ABIS).
  List<String> supportedAbis;

  /// Whether the user allowed GateKeeper to install apps (needed for self-update).
  bool canInstallPackages;
}

@HostApi()
abstract class GateKeeperHostApi {
  SettingsMessage loadSettings();

  /// Persists settings. Throws a FlutterError with code "invalid" when native validation fails.
  void saveSettings(SettingsMessage settings);

  List<SimCardMessage> listSims();

  StatusMessage getStatus();

  /// Re-reads permissions / SIM / number and feeds the engine (call after returning from settings).
  StatusMessage refresh();

  @async
  StartResult startMonitoring();

  void stopMonitoring();

  List<LogEntryMessage> getLogs(int limit);

  void clearLogs();

  @async
  LocationMessage? getCurrentLocation();

  /// Address / place search using Android's built-in Geocoder. Empty list if nothing found or
  /// no geocoder is available on the device.
  @async
  List<PlaceMessage> searchPlaces(String query);

  /// Bluetooth devices paired with this phone, cars first. Throws FlutterError "permission"
  /// (Nearby devices not granted) or "bluetooth_off".
  List<BluetoothDeviceMessage> listPairedDevices();

  /// Chooses the car whose Bluetooth connection wakes GateKeeper.
  void selectCar(String address, String name);

  /// Forgets the chosen car.
  void clearCar();

  void openBluetoothSettings();

  /// Test mode only: injects a synthetic event ("enter", "exit", "vehicle_on", "vehicle_off",
  /// "aa_on", "aa_off", "bt_on", "bt_off"). Rejected when test mode is off.
  void simulateEvent(String event);

  /// Normalises and validates a phone number with Android's PhoneNumberUtils. Returns null if invalid.
  String? validatePhoneNumber(String number);

  /// Starts/stops observing Android Auto while the UI is visible.
  void setUiVisible(bool visible);

  AppInfoMessage getAppInfo();

  /// Downloads a release APK from this app's GitHub releases, verifies SHA-256 (if given), package name,
  /// signing certificate and version, then opens the system installer.
  /// Returns "installer_opened" or "needs_permission". Throws on download/verification failure.
  @async
  String downloadAndInstallUpdate(String url, String fileName, String? sha256);

  /// Opens "Install unknown apps" settings for GateKeeper.
  void openInstallPermissionSettings();
}

@FlutterApi()
abstract class GateKeeperFlutterApi {
  void onStatusChanged(StatusMessage status);

  /// Update download progress; total is -1 when unknown.
  void onUpdateProgress(int received, int total);
}
